const std = @import("std");

const zx = @import("zx");

const app = @import("app");

const cookie_name = "auth_token";

pub fn setToken(response: *const zx.Response, token: []const u8) void {
    response.setCookie(cookie_name, token, .{
        .path = "/",
        .max_age = 3600,
    });
}

pub fn rmToken(response: *const zx.Response) void {
    response.setCookie(cookie_name, "", .{
        .path = "/",
        .max_age = 0,
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
    .init("/", "/cards/all/"),
    .init("/cards", "/cards/all/"),
    .init("/cards/", "/cards/all/"),
};

pub fn Proxy(ctx: *zx.ProxyContext) !void {
    const state: app.ProxyState = .{
        .token = ctx.request.cookies.get(cookie_name),
    };

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
