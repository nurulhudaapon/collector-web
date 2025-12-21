//! Functions used on frontend to interact with database
//!
//! Note that leaking resources is not a big deal since most times we will be using an arena
//! As such, everything will be free'd when the response is sent by client
//!
//! Regardless, those leaks are still a bad thing, lets try and not make any :)

const std = @import("std");
const Allocator = std.mem.Allocator;

const ptz = @import("ptz");
pub const sdk = ptz.Sdk(.en);

const sqlite = zmig.sqlite;

const zmig = @import("zmig");

const database = @import("database.zig");

const oom = "out of memory";
const env_key = "ZMIG_DB_PATH";

fn getDbConnection(allocator: Allocator) database.Connection {
    const env = std.process.getEnvVarOwned(allocator, env_key) catch |e| switch (e) {
        error.OutOfMemory => @panic(oom),
        error.EnvironmentVariableNotFound => std.debug.panic("${s} not set", .{env_key}),
        error.InvalidWtf8 => unreachable,
    };
    defer allocator.free(env);

    const path = allocator.dupeZ(u8, env) catch @panic(oom);
    defer allocator.free(path);

    var conn = database.Connection.init(.{
        .mode = .{
            .File = path,
        },
        .open_flags = .{
            .create = true,
            .write = true,
        },
    }) catch @panic("could not open database");

    // SAFETY: initialized by `zmig` on problems
    var diagnostics: zmig.Diagnostics = undefined;

    zmig.applyMigrations(
        &conn,
        allocator,
        .{ .diagnostics = &diagnostics },
    ) catch std.debug.panic("error with migrations: {f}", .{diagnostics});

    return conn;
}

pub fn getCards(allocator: Allocator, params: sdk.Card.Brief.Params) ![]const sdk.Card {
    var cards: std.ArrayList(sdk.Card) = if (params.page_size) |page_size|
        try .initCapacity(allocator, page_size)
    else
        .empty;
    errdefer cards.clearAndFree(allocator);

    var iterator = sdk.Card.all(allocator, params);

    const briefs = try iterator.next() orelse @panic("oops");
    for (briefs) |brief| {
        defer brief.deinit();

        const card: sdk.Card = try .get(allocator, .{
            .id = brief.id,
        });
        try cards.append(allocator, card);
    }

    return cards.toOwnedSlice(allocator);
}

pub fn updateOne(allocator: Allocator, connection: *database.Connection, card: sdk.Card) void {
    const id: []const u8, const name: []const u8, const image: ?ptz.Image = switch (card) {
        inline else => |c| .{ c.id, c.name, c.image },
    };

    var allocating: std.Io.Writer.Allocating = .init(allocator);
    defer allocating.deinit();

    if (image) |img| {
        allocating.clearRetainingCapacity();

        img.toUrl(&allocating.writer, .high, .jpg) catch {
            allocating.clearRetainingCapacity();
        };
    }

    const image_url: ?[]const u8 = if (allocating.writer.end > 0)
        allocating.toOwnedSlice() catch null
    else
        null;
    defer if (image_url) |url| allocator.free(url);

    // SAFETY: initialized by `sqlite` on problems
    var diagnostics: sqlite.Diagnostics = undefined;
    database.save(
        connection,
        .card,
        allocator,
        .{
            .id = id,
            .name = name,
            .image_url = image_url,
        },
        &diagnostics,
    ) catch std.log.err("db error: {f}", .{diagnostics});
}

pub fn updateAll(allocator: Allocator, query: ?[]const u8) void {
    var connection = getDbConnection(allocator);
    defer connection.deinit();

    var iterator = sdk.Card.all(allocator, .{
        .where = &.{
            .like(.name, query orelse ""),
        },
    });

    while (iterator.next() catch null) |briefs| {
        for (briefs) |brief| {
            defer brief.deinit();

            const card = sdk.Card.get(
                allocator,
                .{ .id = brief.id },
            ) catch continue;
            defer card.deinit();

            updateOne(allocator, &connection, card);
        }
    }
}

fn testConnection() !database.Connection {
    return .init(.{
        .open_flags = .{
            .write = true,
        },
    });
}

test "migrations into empty database" {
    const allocator = std.testing.allocator;

    var connection = try testConnection();
    defer connection.deinit();

    try zmig.applyMigrations(&connection, allocator, .default);
}

test updateOne {
    const allocator = std.testing.allocator;

    var connection = try testConnection();
    defer connection.deinit();

    const card: sdk.Card = try .get(allocator, .{
        .id = "base2-1",
    });
    defer card.deinit();

    updateOne(allocator, &connection, card);
}
