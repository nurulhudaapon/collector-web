const std = @import("std");

const zx = @import("zx");

const database = @import("database");

const ProxyState = @This();

token: ?[]const u8,
env: Environment,

const Environment = enum {
    unknown,
    development,
    deployed,

    fn fromUrl(maybe_url: ?[]const u8) Environment {
        return if (maybe_url) |url|
            if (std.mem.indexOf(u8, url, "localhost") != null)
                .development
            else
                .deployed
        else
            .unknown;
    }
};

// TODO: use Authorization header?
pub fn init(ctx: *zx.ProxyContext, cookie_name: []const u8) ProxyState {
    return .{
        .token = ctx.request.cookies.get(cookie_name),
        .env = .fromUrl(ctx.request.headers.get("host")),
    };
}

pub fn getUser(self: *const ProxyState, session: *database.Session) !?database.User {
    const token = self.token orelse return null;
    return .get(session, token);
}
