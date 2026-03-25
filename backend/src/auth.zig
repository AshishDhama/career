const std = @import("std");
const db = @import("db.zig");
const jwt = @import("jwt.zig");

// JWT secret — in production, load from env var
const JWT_SECRET = "career-jwt-secret-change-in-production";
const JWT_EXPIRY_SECONDS: i64 = 7 * 24 * 60 * 60; // 7 days

pub const AuthHandler = struct {
    pool: *db.Pool,
    allocator: std.mem.Allocator,

    pub fn init(pool: *db.Pool, allocator: std.mem.Allocator) AuthHandler {
        return .{ .pool = pool, .allocator = allocator };
    }

    /// POST /api/auth/register
    /// Body: {"email":"...","password":"...","name":"...","role":"professional|calibrator"}
    pub fn register(self: *AuthHandler, body: []const u8) ![]u8 {
        const email = parseJsonString(self.allocator, body, "email") catch return jsonError(self.allocator, "missing email");
        defer self.allocator.free(email);
        const password = parseJsonString(self.allocator, body, "password") catch return jsonError(self.allocator, "missing password");
        defer self.allocator.free(password);
        const name = parseJsonString(self.allocator, body, "name") catch return jsonError(self.allocator, "missing name");
        defer self.allocator.free(name);
        const role = parseJsonString(self.allocator, body, "role") catch return jsonError(self.allocator, "missing role");
        defer self.allocator.free(role);

        // Validate role
        if (!std.mem.eql(u8, role, "professional") and !std.mem.eql(u8, role, "calibrator")) {
            return jsonError(self.allocator, "role must be professional or calibrator");
        }

        // Check if email already exists
        var check = self.pool.query(
            "SELECT id FROM users WHERE email = $1",
            &.{email},
        ) catch return jsonError(self.allocator, "database error");
        defer check.deinit();

        if (check.rowCount() > 0) {
            return jsonError(self.allocator, "email already registered");
        }

        // Hash password using Argon2id
        var hash_buf: [128]u8 = undefined;
        const hash = try hashPassword(password, &hash_buf);

        // Insert user
        var result = self.pool.query(
            "INSERT INTO users (email, password, name, role) VALUES ($1, $2, $3, $4) RETURNING id",
            &.{ email, hash, name, role },
        ) catch return jsonError(self.allocator, "failed to create user");
        defer result.deinit();

        const user_id = result.row(0).get(0) orelse return jsonError(self.allocator, "insert failed");

        // Generate JWT
        const token = try jwt.sign(self.allocator, .{
            .sub = user_id,
            .role = role,
            .exp = std.time.timestamp() + JWT_EXPIRY_SECONDS,
        }, JWT_SECRET);
        defer self.allocator.free(token);

        return std.fmt.allocPrint(self.allocator,
            "{{\"token\":\"{s}\",\"user\":{{\"id\":\"{s}\",\"name\":\"{s}\",\"role\":\"{s}\"}}}}",
            .{ token, user_id, name, role },
        );
    }

    /// POST /api/auth/login
    /// Body: {"email":"...","password":"..."}
    pub fn login(self: *AuthHandler, body: []const u8) ![]u8 {
        const email = parseJsonString(self.allocator, body, "email") catch return jsonError(self.allocator, "missing email");
        defer self.allocator.free(email);
        const password = parseJsonString(self.allocator, body, "password") catch return jsonError(self.allocator, "missing password");
        defer self.allocator.free(password);

        // Fetch user
        var result = self.pool.query(
            "SELECT id, name, role, password FROM users WHERE email = $1",
            &.{email},
        ) catch return jsonError(self.allocator, "database error");
        defer result.deinit();

        if (result.rowCount() == 0) {
            return jsonError(self.allocator, "invalid email or password");
        }

        const r = result.row(0);
        const user_id = r.get(0) orelse return jsonError(self.allocator, "error");
        const name = r.get(1) orelse return jsonError(self.allocator, "error");
        const role = r.get(2) orelse return jsonError(self.allocator, "error");
        const stored_hash = r.get(3) orelse return jsonError(self.allocator, "error");

        // Verify password
        if (!verifyPassword(password, stored_hash)) {
            return jsonError(self.allocator, "invalid email or password");
        }

        // Generate JWT
        const token = try jwt.sign(self.allocator, .{
            .sub = user_id,
            .role = role,
            .exp = std.time.timestamp() + JWT_EXPIRY_SECONDS,
        }, JWT_SECRET);
        defer self.allocator.free(token);

        return std.fmt.allocPrint(self.allocator,
            "{{\"token\":\"{s}\",\"user\":{{\"id\":\"{s}\",\"name\":\"{s}\",\"role\":\"{s}\"}}}}",
            .{ token, user_id, name, role },
        );
    }

    /// Middleware: extract and verify JWT from Authorization header
    pub fn verifyToken(self: *AuthHandler, authorization: []const u8) !jwt.Claims {
        const prefix = "Bearer ";
        if (!std.mem.startsWith(u8, authorization, prefix)) return error.InvalidToken;
        const token = authorization[prefix.len..];
        return jwt.verify(self.allocator, token, JWT_SECRET);
    }
};

// --- Password hashing using Argon2id (std.crypto) ---

fn hashPassword(password: []const u8, buf: []u8) ![]u8 {
    const params = std.crypto.pwhash.argon2.Params{
        .t = 2,
        .m = 65536,
        .p = 1,
    };
    try std.crypto.pwhash.argon2.strHash(password, .{
        .allocator = std.heap.page_allocator,
        .params = params,
        .mode = .argon2id,
    }, buf);
    return std.mem.sliceTo(buf, 0);
}

fn verifyPassword(password: []const u8, hash: []const u8) bool {
    std.crypto.pwhash.argon2.strVerify(hash, password, .{
        .allocator = std.heap.page_allocator,
    }) catch return false;
    return true;
}

// --- Minimal JSON helpers ---

fn parseJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const search = try std.fmt.allocPrint(allocator, "\"{s}\":\"", .{key});
    defer allocator.free(search);
    const start = std.mem.indexOf(u8, json, search) orelse return error.KeyNotFound;
    const val_start = start + search.len;
    const val_end = std.mem.indexOf(u8, json[val_start..], "\"") orelse return error.InvalidJson;
    return allocator.dupe(u8, json[val_start .. val_start + val_end]);
}

fn jsonError(allocator: std.mem.Allocator, msg: []const u8) []u8 {
    return std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{msg}) catch
        @constCast("{\"error\":\"unknown\"}");
}
