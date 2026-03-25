const std = @import("std");

pub fn run(allocator: std.mem.Allocator, port: u16) !void {
    const address = try std.net.Address.parseIp("0.0.0.0", port);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    std.debug.print("Listening on port {d}\n", .{port});

    while (true) {
        const conn = listener.accept() catch |err| {
            std.debug.print("Accept error: {}\n", .{err});
            continue;
        };

        const thread = try std.Thread.spawn(.{}, handleConnection, .{ allocator, conn });
        thread.detach();
    }
}

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    handleHttp(allocator, conn.stream) catch |err| {
        std.debug.print("HTTP error: {}\n", .{err});
    };
}

fn handleHttp(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
    var buf: [4096]u8 = undefined;
    const n = try stream.read(&buf);
    if (n == 0) return;

    const request = buf[0..n];
    const first_line_end = std.mem.indexOf(u8, request, "\r\n") orelse return;
    const first_line = request[0..first_line_end];

    // Parse method and path
    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return;
    const path = parts.next() orelse return;

    std.debug.print("{s} {s}\n", .{ method, path });

    // Route requests
    if (std.mem.startsWith(u8, path, "/api/health")) {
        try sendJson(stream, 200, "{\"status\":\"ok\",\"service\":\"career\"}");
    } else if (std.mem.startsWith(u8, path, "/api/")) {
        try sendJson(stream, 404, "{\"error\":\"not found\"}");
    } else if (std.mem.startsWith(u8, path, "/ws/")) {
        try handleWebSocketUpgrade(allocator, stream, request, path);
    } else {
        // Serve static files from public/
        try serveStatic(allocator, stream, path);
    }
}

fn sendJson(stream: std.net.Stream, status: u16, body: []const u8) !void {
    const status_text = if (status == 200) "OK" else if (status == 404) "Not Found" else "Error";
    const response = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\n\r\n{s}",
        .{ status, status_text, body.len, body },
    );
    defer std.heap.page_allocator.free(response);
    _ = try stream.write(response);
}

fn serveStatic(allocator: std.mem.Allocator, stream: std.net.Stream, path: []const u8) !void {
    const file_path = if (std.mem.eql(u8, path, "/")) "public/index.html" else blk: {
        const p = if (path[0] == '/') path[1..] else path;
        break :blk try std.fmt.allocPrint(allocator, "public/{s}", .{p});
    };
    defer if (!std.mem.eql(u8, file_path, "public/index.html")) allocator.free(file_path);

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        // SPA fallback: serve index.html for unknown routes
        return serveFile(allocator, stream, "public/index.html");
    };
    defer file.close();

    return serveFile(allocator, stream, file_path);
}

fn serveFile(allocator: std.mem.Allocator, stream: std.net.Stream, path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        _ = try stream.write("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found");
        return;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    const mime = getMime(path);
    const header = try std.fmt.allocPrint(
        allocator,
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n",
        .{ mime, content.len },
    );
    defer allocator.free(header);

    _ = try stream.write(header);
    _ = try stream.write(content);
}

fn getMime(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".ico")) return "image/x-icon";
    return "application/octet-stream";
}

fn handleWebSocketUpgrade(allocator: std.mem.Allocator, stream: std.net.Stream, request: []const u8, path: []const u8) !void {
    _ = allocator;
    _ = path;

    // Find Sec-WebSocket-Key header
    const key_prefix = "Sec-WebSocket-Key: ";
    const key_start = std.mem.indexOf(u8, request, key_prefix) orelse {
        _ = try stream.write("HTTP/1.1 400 Bad Request\r\n\r\n");
        return;
    };
    const key_value_start = key_start + key_prefix.len;
    const key_end = std.mem.indexOf(u8, request[key_value_start..], "\r\n") orelse return;
    const client_key = request[key_value_start .. key_value_start + key_end];

    // Compute accept key: SHA1(key + magic) base64
    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    var combined: [60 + 36]u8 = undefined;
    @memcpy(combined[0..client_key.len], client_key);
    @memcpy(combined[client_key.len .. client_key.len + magic.len], magic);

    var sha1_out: [20]u8 = undefined;
    std.crypto.hash.Sha1.hash(combined[0 .. client_key.len + magic.len], &sha1_out, .{});

    var accept_key: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&accept_key, &sha1_out);

    const response = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n",
        .{accept_key},
    );
    defer std.heap.page_allocator.free(response);
    _ = try stream.write(response);

    // TODO: WebSocket frame loop (assessment session handler)
    std.debug.print("WebSocket connected: {s}\n", .{path});
    handleWebSocketSession(stream) catch {};
}

fn handleWebSocketSession(stream: std.net.Stream) !void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = stream.read(&buf) catch break;
        if (n == 0) break;

        // Parse WebSocket frame (simplified)
        if (n < 2) continue;
        const opcode = buf[0] & 0x0F;
        if (opcode == 0x8) break; // Close frame

        // Echo back for now (TODO: route to session handler)
        _ = stream.write(buf[0..n]) catch break;
    }
}
