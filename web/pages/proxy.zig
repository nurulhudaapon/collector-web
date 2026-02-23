const std = @import("std");

const zx = @import("zx");

const app = @import("app");

const cookie_name = "auth_token";

pub fn setToken(response: *const zx.Response, token: []const u8) void {
    response.setCookie(cookie_name, token, .{
        .path = "/",
        // 10 days worth of login
        // TODO: extend duration when navigating web?
        .max_age = 60 * 60 * 24 * 10,
    });
}

const Redirect = struct {
    from: []const u8,
    to: []const u8,

    fn init(from: []const u8, to: []const u8) Redirect {
        return .{ .from = from, .to = to };
    }
};

const redirects: []const Redirect = &.{
    .init("/", "/collection/"),
};

pub fn Proxy(ctx: *zx.ProxyContext) !void {
    const state: app.ProxyState = .init(ctx, cookie_name);
    ctx.state(state);

    for (redirects) |redirect| {
        if (std.mem.eql(u8, ctx.request.pathname, redirect.from)) {
            ctx.response.setStatus(.moved_permanently);
            ctx.response.setHeader("Location", redirect.to);

            ctx.abort();
        }
    }

    ctx.next();
}
