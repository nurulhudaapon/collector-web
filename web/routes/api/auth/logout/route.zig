const app = @import("app");
const database = @import("database");

pub fn GET(ctx: app.RouteCtx) !void {
    var session = try ctx.app.pool.getSession(ctx.arena);
    defer session.deinit();

    const user = try ctx.state.getUser(&session) orelse return;
    try user.logout(&session);

    ctx.response.setCookie("auth_token", "", .{
        .path = "/",
        .max_age = 0,
    });
}
