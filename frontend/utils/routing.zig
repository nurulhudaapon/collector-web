const std = @import("std");

pub fn isApi(route: []const u8) bool {
    return std.mem.startsWith(u8, route, "/api/");
}
