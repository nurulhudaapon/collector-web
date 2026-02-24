const std = @import("std");

const api = @import("api");
const app = @import("app");
const database = @import("database");

comptime {
    std.debug.assert(database.Id == api.database.Id);
    std.debug.assert(database.Int == api.database.Int);
}

pub fn owned(ctx: app.RouteCtx, is_owned: bool) !void {
    const variant_id_str = ctx.request.searchParams.get("variant_id") orelse return error.MissingVariantId;
    const variant_id = try std.fmt.parseInt(api.database.Id, variant_id_str, 10);

    const js_ref_str = ctx.request.searchParams.get("js_ref") orelse return error.MissingJsRef;
    const js_ref = try std.fmt.parseInt(api.js.Ref, js_ref_str, 10);

    var session = try ctx.app.pool.getSession(ctx.arena);
    defer session.deinit();

    const user = try ctx.state.getUser(&session) orelse return;

    const maybe_row = try session
        .query(database.Owned)
        .where("user_id", user.id)
        .where("variant_id", variant_id)
        .findFirst();

    if (maybe_row) |row| {
        try session.update(database.Owned, row.id, .{
            .owned = is_owned,
        });
    } else {
        _ = try session.insert(database.Owned, .{
            .user_id = user.id,
            .variant_id = variant_id,
            .owned = is_owned,
        });
    }

    const response: api.Owned = .{
        .variant_id = variant_id,
        .owned = is_owned,
        .js_ref = js_ref,
    };

    try ctx.response.json(response, .{});
}

pub fn tracked(ctx: app.RouteCtx, is_tracked: bool) !void {
    const pokedex_str = ctx.request.searchParams.get("pokedex") orelse return error.MissingDex;
    const pokedex = try std.fmt.parseInt(api.database.Int, pokedex_str, 10);

    const js_ref_str = ctx.request.searchParams.get("js_ref") orelse return error.MissingJsRef;
    const js_ref = try std.fmt.parseInt(api.js.Ref, js_ref_str, 10);

    var session = try ctx.app.pool.getSession(ctx.arena);
    defer session.deinit();

    const user = try ctx.state.getUser(&session) orelse return;

    const maybe_row = try session
        .query(database.Tracked)
        .where("user_id", user.id)
        .where("species_dex", pokedex)
        .findFirst();

    if (maybe_row) |row| {
        try session.update(database.Tracked, row.id, .{
            .tracked = is_tracked,
        });
    } else {
        _ = try session.insert(database.Tracked, .{
            .user_id = user.id,
            .species_dex = pokedex,
            .tracked = is_tracked,
        });
    }

    const response: api.Tracked = .{
        .pokedex = pokedex,
        .tracked = is_tracked,
        .js_ref = js_ref,
    };

    try ctx.response.json(response, .{});
}
