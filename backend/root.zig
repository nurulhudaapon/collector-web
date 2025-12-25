//! Functions used on frontend to interact with database
//!
//! Note that leaking resources is not a big deal since most times we will be using an arena
//! As such, everything will be free'd when the response is sent by client
//!
//! Regardless, those leaks are still a bad thing, lets try and not make any :)

const std = @import("std");
const Allocator = std.mem.Allocator;

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

pub const database = @import("database.zig");

pub fn init(allocator: Allocator) !void {
    try database.init(allocator);
}

pub fn allCards(allocator: Allocator, name: []const u8) ![]const database.Card {
    var session = try database.session(allocator);
    defer session.deinit();

    var allocating: std.Io.Writer.Allocating = .init(allocator);
    defer allocating.deinit();

    try allocating.writer.print("%{s}%", .{name});

    const wildcard = try allocating.toOwnedSlice();
    defer allocator.free(wildcard);

    return session
        .query(database.Card)
        .whereRaw("name like ?", .{wildcard})
        .findAll();
}

const InsertRes = struct {
    new_row: bool,
};

fn insert(allocator: Allocator, session: *database.Session, brief: sdk.Card.Brief) !InsertRes {
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    defer allocating.deinit();

    if (brief.image) |image| {
        allocating.clearRetainingCapacity();

        image.toUrl(&allocating.writer, .high, .jpg) catch {
            allocating.clearRetainingCapacity();
        };
    }

    const url, const free = if (allocating.toOwnedSlice()) |slice|
        .{ slice, true }
    else |_|
        .{ "", false };
    defer if (free) allocator.free(url);

    // ignore TCG Pocket cards
    if (std.mem.indexOf(u8, url, "tcgp")) |_| {
        return .{ .new_row = false };
    }

    _ = session.insert(database.Card, .{
        .card_id = brief.id,
        .name = brief.name,
        .image_url = url,
    }) catch |err| return switch (err) {
        // card existed, but let's not actually errors
        error.UniqueViolation => .{ .new_row = false },
        else => return err,
    };

    return .{ .new_row = true };
}

const FetchRes = struct {
    card_count: usize,
    ms_elapsed: usize,
};

pub fn fetch(allocator: Allocator, name: []const u8) !FetchRes {
    var timer: std.time.Timer = try .start();

    var session = try database.session(allocator);
    defer session.deinit();

    var iterator = sdk.Card.all(allocator, .{
        .page_size = 250,
        .where = &.{
            .like(.name, name),
        },
    });

    var n_cards: usize = 0;
    while (iterator.next() catch null) |briefs| {
        for (briefs) |brief| {
            defer brief.deinit();

            const res = try insert(allocator, &session, brief);
            if (res.new_row) n_cards += 1;
        }
    }

    return .{
        .card_count = n_cards,
        .ms_elapsed = timer.read() / 1_000_000, // ns to ms
    };
}
