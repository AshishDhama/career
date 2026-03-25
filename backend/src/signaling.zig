/// WebRTC Signaling Server
///
/// Each assessment session has a "room" identified by its assessment UUID.
/// Two peers join: the professional and the calibrator.
/// The server relays signaling messages (offer, answer, ice-candidate) between them.
/// No media passes through the server — only signaling.
///
/// Message protocol (JSON over WebSocket):
///   { "type": "join",          "room": "<assessment_id>", "peer_id": "<user_id>", "role": "professional|calibrator" }
///   { "type": "offer",         "room": "<assessment_id>", "sdp": "..." }
///   { "type": "answer",        "room": "<assessment_id>", "sdp": "..." }
///   { "type": "ice-candidate", "room": "<assessment_id>", "candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0 }
///   { "type": "chat",          "room": "<assessment_id>", "text": "...", "sender": "<name>" }
///   { "type": "leave",         "room": "<assessment_id>" }
///
/// Server → client events:
///   { "type": "peer-joined",   "role": "professional|calibrator" }
///   { "type": "peer-left" }
///   { "type": "offer",         "sdp": "..." }
///   { "type": "answer",        "sdp": "..." }
///   { "type": "ice-candidate", "candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0 }
///   { "type": "chat",          "text": "...", "sender": "<name>" }
///   { "type": "error",         "message": "..." }

const std = @import("std");

pub const MAX_ROOMS = 256;
pub const MAX_PEERS_PER_ROOM = 2;
pub const MSG_BUF_SIZE = 65536;

pub const PeerRole = enum { professional, calibrator };

pub const Peer = struct {
    stream: std.net.Stream,
    role: PeerRole,
    peer_id: [64]u8,
    peer_id_len: usize,
    active: bool,
};

pub const Room = struct {
    id: [64]u8,
    id_len: usize,
    peers: [MAX_PEERS_PER_ROOM]?Peer,
    mutex: std.Thread.Mutex,
    active: bool,

    pub fn init(room_id: []const u8) Room {
        var r = Room{
            .id = undefined,
            .id_len = room_id.len,
            .peers = .{ null, null },
            .mutex = .{},
            .active = true,
        };
        @memcpy(r.id[0..room_id.len], room_id);
        return r;
    }

    /// Add a peer to the room. Returns index or error if full.
    pub fn addPeer(self: *Room, peer: Peer) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (&self.peers, 0..) |*slot, i| {
            if (slot.* == null) {
                slot.* = peer;
                return i;
            }
        }
        return error.RoomFull;
    }

    /// Remove a peer by stream fd
    pub fn removePeer(self: *Room, stream: std.net.Stream) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (&self.peers) |*slot| {
            if (slot.*) |p| {
                if (p.stream.handle == stream.handle) {
                    slot.* = null;
                    return;
                }
            }
        }
    }

    /// Send a message to all peers except the sender
    pub fn relay(self: *Room, sender_stream: std.net.Stream, msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (&self.peers) |*slot| {
            if (slot.*) |p| {
                if (p.stream.handle != sender_stream.handle and p.active) {
                    sendWsText(p.stream, msg) catch {};
                }
            }
        }
    }

    /// Send to all peers including sender
    pub fn broadcast(self: *Room, msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (&self.peers) |*slot| {
            if (slot.*) |p| {
                if (p.active) sendWsText(p.stream, msg) catch {};
            }
        }
    }

    pub fn peerCount(self: *Room) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        var count: usize = 0;
        for (self.peers) |slot| {
            if (slot != null) count += 1;
        }
        return count;
    }
};

pub const Hub = struct {
    rooms: [MAX_ROOMS]?Room,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Hub {
        return .{
            .rooms = [_]?Room{null} ** MAX_ROOMS,
            .mutex = .{},
            .allocator = allocator,
        };
    }

    /// Get or create a room by ID
    pub fn getOrCreateRoom(self: *Hub, room_id: []const u8) *Room {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find existing room
        for (&self.rooms) |*slot| {
            if (slot.*) |*r| {
                if (r.active and std.mem.eql(u8, r.id[0..r.id_len], room_id)) {
                    return r;
                }
            }
        }

        // Create new room in empty slot
        for (&self.rooms) |*slot| {
            if (slot.* == null) {
                slot.* = Room.init(room_id);
                return &slot.*.?;
            }
        }

        // Overwrite first inactive room
        for (&self.rooms) |*slot| {
            if (slot.*) |r| {
                if (!r.active) {
                    slot.* = Room.init(room_id);
                    return &slot.*.?;
                }
            }
        }

        // Fallback: overwrite slot 0
        self.rooms[0] = Room.init(room_id);
        return &self.rooms[0].?;
    }
};

// Global hub — one per server process
pub var global_hub: ?Hub = null;

pub fn initHub(allocator: std.mem.Allocator) void {
    global_hub = Hub.init(allocator);
}

/// Entry point: handle a WebSocket connection for a signaling session
pub fn handleSession(allocator: std.mem.Allocator, stream: std.net.Stream, path: []const u8) void {
    _ = path;
    var current_room: ?*Room = null;
    var buf: [MSG_BUF_SIZE]u8 = undefined;

    defer {
        if (current_room) |room| {
            room.removePeer(stream);
            // Notify the other peer
            const leave_msg = "{\"type\":\"peer-left\"}";
            room.relay(stream, leave_msg);
        }
        stream.close();
    }

    while (true) {
        // Read WebSocket frame
        const msg = readWsFrame(allocator, stream, &buf) catch break;
        if (msg.len == 0) break;

        // Parse message type
        const msg_type = extractJsonString(allocator, msg, "type") catch continue;
        defer allocator.free(msg_type);

        if (std.mem.eql(u8, msg_type, "join")) {
            const room_id = extractJsonString(allocator, msg, "room") catch continue;
            defer allocator.free(room_id);
            const peer_id = extractJsonString(allocator, msg, "peer_id") catch continue;
            defer allocator.free(peer_id);
            const role_str = extractJsonString(allocator, msg, "role") catch continue;
            defer allocator.free(role_str);

            const role: PeerRole = if (std.mem.eql(u8, role_str, "calibrator"))
                .calibrator
            else
                .professional;

            if (global_hub == null) {
                sendWsText(stream, "{\"type\":\"error\",\"message\":\"server not ready\"}") catch {};
                continue;
            }

            const room = global_hub.?.getOrCreateRoom(room_id);
            var peer = Peer{
                .stream = stream,
                .role = role,
                .peer_id = undefined,
                .peer_id_len = peer_id.len,
                .active = true,
            };
            @memcpy(peer.peer_id[0..peer_id.len], peer_id);

            _ = room.addPeer(peer) catch {
                sendWsText(stream, "{\"type\":\"error\",\"message\":\"room full\"}") catch {};
                continue;
            };
            current_room = room;

            // Notify the other peer that someone joined
            const role_name = if (role == .calibrator) "calibrator" else "professional";
            var notify_buf: [128]u8 = undefined;
            const notify = std.fmt.bufPrint(
                &notify_buf,
                "{{\"type\":\"peer-joined\",\"role\":\"{s}\"}}",
                .{role_name},
            ) catch continue;
            room.relay(stream, notify);

            // Confirm to the joining peer
            const peer_count = room.peerCount();
            var ack_buf: [128]u8 = undefined;
            const ack = std.fmt.bufPrint(
                &ack_buf,
                "{{\"type\":\"joined\",\"room\":\"{s}\",\"peers\":{d}}}",
                .{ room_id, peer_count },
            ) catch continue;
            sendWsText(stream, ack) catch {};

        } else if (std.mem.eql(u8, msg_type, "offer") or
            std.mem.eql(u8, msg_type, "answer") or
            std.mem.eql(u8, msg_type, "ice-candidate") or
            std.mem.eql(u8, msg_type, "chat"))
        {
            // Relay directly to the other peer
            if (current_room) |room| {
                room.relay(stream, msg);
            }
        } else if (std.mem.eql(u8, msg_type, "leave")) {
            break;
        }
    }
}

// --- WebSocket frame read/write ---

pub fn readWsFrame(allocator: std.mem.Allocator, stream: std.net.Stream, buf: []u8) ![]u8 {
    // Read first 2 bytes (header)
    var header: [2]u8 = undefined;
    const n = stream.read(&header) catch return error.Disconnected;
    if (n < 2) return error.Disconnected;

    const opcode = header[0] & 0x0F;
    const masked = (header[1] & 0x80) != 0;
    var payload_len: u64 = header[1] & 0x7F;

    if (opcode == 0x8) return error.Disconnected; // Close frame
    if (opcode == 0x9) { // Ping — send Pong
        _ = stream.write(&.{ 0x8A, 0x00 }) catch {};
        return buf[0..0];
    }

    // Extended payload length
    if (payload_len == 126) {
        var ext: [2]u8 = undefined;
        _ = try stream.readAll(&ext);
        payload_len = (@as(u64, ext[0]) << 8) | ext[1];
    } else if (payload_len == 127) {
        var ext: [8]u8 = undefined;
        _ = try stream.readAll(&ext);
        payload_len = 0;
        for (ext) |b| payload_len = (payload_len << 8) | b;
    }

    if (payload_len > buf.len) return error.MessageTooLarge;

    // Masking key (client → server is always masked)
    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) _ = try stream.readAll(&mask);

    // Payload
    const data = buf[0..payload_len];
    _ = try stream.readAll(data);

    // Unmask
    if (masked) {
        for (data, 0..) |*b, i| b.* ^= mask[i % 4];
    }

    _ = allocator;
    return data;
}

pub fn sendWsText(stream: std.net.Stream, msg: []const u8) !void {
    var header: [10]u8 = undefined;
    var header_len: usize = 2;

    header[0] = 0x81; // FIN + text opcode

    if (msg.len < 126) {
        header[1] = @intCast(msg.len);
    } else if (msg.len < 65536) {
        header[1] = 126;
        header[2] = @intCast((msg.len >> 8) & 0xFF);
        header[3] = @intCast(msg.len & 0xFF);
        header_len = 4;
    } else {
        header[1] = 127;
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            header[2 + i] = @intCast((msg.len >> @intCast((7 - i) * 8)) & 0xFF);
        }
        header_len = 10;
    }

    _ = try stream.write(header[0..header_len]);
    _ = try stream.write(msg);
}

// --- Minimal JSON string extractor ---
fn extractJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const search = try std.fmt.allocPrint(allocator, "\"{s}\":\"", .{key});
    defer allocator.free(search);
    const start = std.mem.indexOf(u8, json, search) orelse return error.KeyNotFound;
    const val_start = start + search.len;
    const val_end = std.mem.indexOf(u8, json[val_start..], "\"") orelse return error.InvalidJson;
    return allocator.dupe(u8, json[val_start .. val_start + val_end]);
}
