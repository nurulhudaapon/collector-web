const std = @import("std");

const zx = @import("zx");

const database = @import("database");

const routing = @import("routing.zig");

const ProxyState = @This();

token: ?[]const u8,
env: routing.Environment,

// TODO: use Authorization header?
pub fn init(ctx: *zx.ProxyContext, cookie_name: []const u8) ProxyState {
    return .{
        .token = ctx.request.cookies.get(cookie_name),
        .env = routing.getEnvironment(ctx.request),
    };
}

pub fn getUser(self: ProxyState, session: *database.Session) !?database.User {
    const token = self.token orelse return null;
    return .get(session, token);
}
