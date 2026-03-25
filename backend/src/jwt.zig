/// Minimal HS256 JWT implementation
/// No external dependencies — uses std.crypto.auth.hmac.sha2.HmacSha256
const std = @import("std");
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

pub const Claims = struct {
    sub: []const u8,    // user id
    role: []const u8,   // professional | calibrator | admin
    exp: i64,           // unix timestamp
};

const HEADER = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"; // base64url({"alg":"HS256","typ":"JWT"})

/// Sign and return a JWT token. Caller owns the returned slice.
pub fn sign(allocator: std.mem.Allocator, claims: Claims, secret: []const u8) ![]u8 {
    // Build payload JSON
    const payload_json = try std.fmt.allocPrint(
        allocator,
        "{{\"sub\":\"{s}\",\"role\":\"{s}\",\"exp\":{d}}}",
        .{ claims.sub, claims.role, claims.exp },
    );
    defer allocator.free(payload_json);

    // base64url encode payload
    const payload_b64 = try base64urlEncode(allocator, payload_json);
    defer allocator.free(payload_b64);

    // Create signing input: header.payload
    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ HEADER, payload_b64 });
    defer allocator.free(signing_input);

    // HMAC-SHA256 signature
    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    // base64url encode signature
    const sig_b64 = try base64urlEncode(allocator, &mac);
    defer allocator.free(sig_b64);

    return std.fmt.allocPrint(allocator, "{s}.{s}.{s}", .{ HEADER, payload_b64, sig_b64 });
}

/// Verify and parse a JWT token. Returns Claims if valid.
pub fn verify(allocator: std.mem.Allocator, token: []const u8, secret: []const u8) !Claims {
    // Split into 3 parts
    var parts = std.mem.splitScalar(u8, token, '.');
    const header_b64 = parts.next() orelse return error.InvalidToken;
    const payload_b64 = parts.next() orelse return error.InvalidToken;
    const sig_b64 = parts.next() orelse return error.InvalidToken;

    // Verify signature
    const signing_input = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ header_b64, payload_b64 });
    defer allocator.free(signing_input);

    var mac: [HmacSha256.mac_length]u8 = undefined;
    HmacSha256.create(&mac, signing_input, secret);

    const expected_sig = try base64urlEncode(allocator, &mac);
    defer allocator.free(expected_sig);

    if (!std.mem.eql(u8, sig_b64, expected_sig)) return error.InvalidSignature;

    // Decode payload
    const payload_json = try base64urlDecode(allocator, payload_b64);
    defer allocator.free(payload_json);

    // Parse JSON fields (minimal parser — no external deps)
    const sub = try extractJsonString(allocator, payload_json, "sub");
    const role = try extractJsonString(allocator, payload_json, "role");
    const exp = try extractJsonInt(payload_json, "exp");

    // Check expiry
    const now = std.time.timestamp();
    if (exp < now) return error.TokenExpired;

    return Claims{ .sub = sub, .role = role, .exp = exp };
}

fn base64urlEncode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const Encoder = std.base64.url_safe_no_pad.Encoder;
    const len = Encoder.calcSize(data.len);
    const buf = try allocator.alloc(u8, len);
    _ = Encoder.encode(buf, data);
    return buf;
}

fn base64urlDecode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const Decoder = std.base64.url_safe_no_pad.Decoder;
    const len = try Decoder.calcSizeForSlice(data);
    const buf = try allocator.alloc(u8, len);
    try Decoder.decode(buf, data);
    return buf;
}

/// Minimal JSON string extractor — no alloc version, returns allocated slice
fn extractJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const search = try std.fmt.allocPrint(allocator, "\"{s}\":\"", .{key});
    defer allocator.free(search);

    const start = std.mem.indexOf(u8, json, search) orelse return error.KeyNotFound;
    const val_start = start + search.len;
    const val_end = std.mem.indexOf(u8, json[val_start..], "\"") orelse return error.InvalidJson;
    return allocator.dupe(u8, json[val_start .. val_start + val_end]);
}

fn extractJsonInt(json: []const u8, key: []const u8) !i64 {
    // Find "key": followed by digits
    var buf: [64]u8 = undefined;
    const search = try std.fmt.bufPrint(&buf, "\"{s}\":", .{key});

    const start = std.mem.indexOf(u8, json, search) orelse return error.KeyNotFound;
    var i = start + search.len;
    // Skip whitespace
    while (i < json.len and json[i] == ' ') i += 1;
    // Read digits
    const num_start = i;
    while (i < json.len and json[i] >= '0' and json[i] <= '9') i += 1;
    return std.fmt.parseInt(i64, json[num_start..i], 10);
}
