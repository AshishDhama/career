const std = @import("std");
const server = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const port: u16 = 8080;
    std.debug.print("Career server starting on http://localhost:{d}\n", .{port});

    try server.run(allocator, port);
}
