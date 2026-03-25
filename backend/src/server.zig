const std = @import("std");
const db = @import("db.zig");
const auth = @import("auth.zig");
const signaling = @import("signaling.zig");

// Global DB pool — initialized once at startup
var global_pool: ?db.Pool = null;

const ConnContext = struct {
    allocator: std.mem.Allocator,
    conn: std.net.Server.Connection,
};

pub fn run(allocator: std.mem.Allocator, port: u16) !void {
    // Read DATABASE_URL from env (default to local dev)
    const db_url = std.posix.getenv("DATABASE_URL") orelse
        "postgres://career:career@localhost:5432/career";

    global_pool = db.Pool.init(allocator, db_url) catch |err| {
        std.debug.print("Warning: DB not available ({}) — running without database\n", .{err});
        null;
    };
    defer if (global_pool) |*pool| pool.deinit();

    // Init WebRTC signaling hub
    signaling.initHub(allocator);
    std.debug.print("Signaling hub initialized\n", .{});

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

const Request = struct {
    method: []const u8,
    path: []const u8,
    body: []const u8,
    authorization: ?[]const u8,
};

fn parseRequest(buf: []const u8) ?Request {
    const first_line_end = std.mem.indexOf(u8, buf, "\r\n") orelse return null;
    const first_line = buf[0..first_line_end];

    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return null;
    const path = parts.next() orelse return null;

    // Find body (after \r\n\r\n)
    const body_sep = "\r\n\r\n";
    const body = if (std.mem.indexOf(u8, buf, body_sep)) |idx|
        buf[idx + body_sep.len ..]
    else
        "";

    // Find Authorization header
    const auth_prefix = "Authorization: ";
    const authorization = if (std.mem.indexOf(u8, buf, auth_prefix)) |idx| blk: {
        const val_start = idx + auth_prefix.len;
        const val_end = std.mem.indexOf(u8, buf[val_start..], "\r\n") orelse break :blk null;
        break :blk buf[val_start .. val_start + val_end];
    } else null;

    return Request{
        .method = method,
        .path = path,
        .body = body,
        .authorization = authorization,
    };
}

fn handleHttp(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
    var buf: [8192]u8 = undefined;
    const n = try stream.read(&buf);
    if (n == 0) return;

    const req = parseRequest(buf[0..n]) orelse return;
    std.debug.print("{s} {s}\n", .{ req.method, req.path });

    // CORS preflight
    if (std.mem.eql(u8, req.method, "OPTIONS")) {
        _ = try stream.write(
            "HTTP/1.1 204 No Content\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n" ++
            "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" ++
            "\r\n"
        );
        return;
    }

    // Route
    if (std.mem.eql(u8, req.path, "/api/health")) {
        try sendJson(stream, 200, "{\"status\":\"ok\",\"service\":\"career\"}");

    } else if (std.mem.eql(u8, req.path, "/api/auth/register") and std.mem.eql(u8, req.method, "POST")) {
        try handleRegister(allocator, stream, req.body);

    } else if (std.mem.eql(u8, req.path, "/api/auth/login") and std.mem.eql(u8, req.method, "POST")) {
        try handleLogin(allocator, stream, req.body);

    } else if (std.mem.eql(u8, req.path, "/api/me") and std.mem.eql(u8, req.method, "GET")) {
        try handleMe(allocator, stream, req.authorization);

    } else if (std.mem.startsWith(u8, req.path, "/api/")) {
        try sendJson(stream, 404, "{\"error\":\"endpoint not found\"}");

    } else if (std.mem.startsWith(u8, req.path, "/ws/")) {
        try handleWebSocketUpgrade(allocator, stream, buf[0..n], req.path);

    } else {
        try serveStatic(allocator, stream, req.path);
    }
}

fn handleRegister(allocator: std.mem.Allocator, stream: std.net.Stream, body: []const u8) !void {
    if (global_pool == null) {
        try sendJson(stream, 503, "{\"error\":\"database not available\"}");
        return;
    }
    var handler = auth.AuthHandler.init(&global_pool.?, allocator);
    const response = try handler.register(body);
    defer allocator.free(response);
    try sendJson(stream, 200, response);
}

fn handleLogin(allocator: std.mem.Allocator, stream: std.net.Stream, body: []const u8) !void {
    if (global_pool == null) {
        try sendJson(stream, 503, "{\"error\":\"database not available\"}");
        return;
    }
    var handler = auth.AuthHandler.init(&global_pool.?, allocator);
    const response = try handler.login(body);
    defer allocator.free(response);
    try sendJson(stream, 200, response);
}

fn handleMe(allocator: std.mem.Allocator, stream: std.net.Stream, authorization: ?[]const u8) !void {
    if (authorization == null) {
        try sendJson(stream, 401, "{\"error\":\"unauthorized\"}");
        return;
    }
    if (global_pool == null) {
        try sendJson(stream, 503, "{\"error\":\"database not available\"}");
        return;
    }
    var handler = auth.AuthHandler.init(&global_pool.?, allocator);
    const claims = handler.verifyToken(authorization.?) catch {
        try sendJson(stream, 401, "{\"error\":\"invalid or expired token\"}");
        return;
    };
    defer allocator.free(claims.sub);
    defer allocator.free(claims.role);

    // Fetch user from DB
    var result = global_pool.?.query(
        "SELECT id, name, email, role FROM users WHERE id = $1",
        &.{claims.sub},
    ) catch {
        try sendJson(stream, 500, "{\"error\":\"database error\"}");
        return;
    };
    defer result.deinit();

    if (result.rowCount() == 0) {
        try sendJson(stream, 404, "{\"error\":\"user not found\"}");
        return;
    }

    const r = result.row(0);
    const id = r.get(0) orelse "";
    const name = r.get(1) orelse "";
    const email = r.get(2) orelse "";
    const role = r.get(3) orelse "";

    const body = try std.fmt.allocPrint(allocator,
        "{{\"id\":\"{s}\",\"name\":\"{s}\",\"email\":\"{s}\",\"role\":\"{s}\"}}",
        .{ id, name, email, role },
    );
    defer allocator.free(body);
    try sendJson(stream, 200, body);
}

fn sendJson(stream: std.net.Stream, status: u16, body: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        503 => "Service Unavailable",
        else => "Internal Server Error",
    };
    const response = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 {d} {s}\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "Access-Control-Allow-Headers: Content-Type, Authorization\r\n" ++
        "\r\n{s}",
        .{ status, status_text, body.len, body },
    );
    defer std.heap.page_allocator.free(response);
    _ = try stream.write(response);
}

fn serveStatic(allocator: std.mem.Allocator, stream: std.net.Stream, path: []const u8) !void {
    const clean_path = if (std.mem.indexOf(u8, path, "?")) |q| path[0..q] else path;

    var file_path_buf: [512]u8 = undefined;
    const file_path = if (std.mem.eql(u8, clean_path, "/"))
        "public/index.html"
    else
        try std.fmt.bufPrint(&file_path_buf, "public{s}", .{clean_path});

    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        return serveFile(allocator, stream, "public/index.html"); // SPA fallback
    };
    file.close();
    try serveFile(allocator, stream, file_path);
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
        "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: public, max-age=3600\r\n\r\n",
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
    if (std.mem.endsWith(u8, path, ".woff2")) return "font/woff2";
    return "application/octet-stream";
}

fn handleWebSocketUpgrade(allocator: std.mem.Allocator, stream: std.net.Stream, request: []const u8, path: []const u8) !void {
    const key_prefix = "Sec-WebSocket-Key: ";
    const key_start = std.mem.indexOf(u8, request, key_prefix) orelse {
        _ = try stream.write("HTTP/1.1 400 Bad Request\r\n\r\n");
        return;
    };
    const key_value_start = key_start + key_prefix.len;
    const key_end = std.mem.indexOf(u8, request[key_value_start..], "\r\n") orelse return;
    const client_key = request[key_value_start .. key_value_start + key_end];

    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    var combined: [128]u8 = undefined;
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

    std.debug.print("WebSocket connected: {s}\n", .{path});

    // Hand off to signaling hub
    signaling.handleSession(allocator, stream, path);
}
