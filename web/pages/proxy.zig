const std = @import("std");

const zx = @import("zx");

const app = @import("app");

const cookie_name = "auth_token";

pub fn setToken(response: *const zx.Response, token: []const u8) void {
    response.setCookie(cookie_name, token, .{
        .path = "/",
        .max_age = 60 * 60 * 12,
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

    // extend token duration
    if (state.token) |token| {
        setToken(&ctx.response, token);
    }

    for (redirects) |redirect| {
        if (std.mem.eql(u8, ctx.request.pathname, redirect.from)) {
            ctx.response.setStatus(.moved_permanently);
            ctx.response.setHeader("Location", redirect.to);

            ctx.abort();
        }
    }

    ctx.next();
}
