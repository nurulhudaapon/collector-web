const std = @import("std");
const Allocator = std.mem.Allocator;

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

const database = @import("database.zig");

const Card = @import("Card.zig");

const Owned = struct {
    id: u64,
    user_id: u64,
    variant_id: u64,
    owned: bool,
};

const InsertRes = struct {
    variants_count: usize,
};

fn insert(allocator: Allocator, session: *database.Session, brief: sdk.Card.Brief) !InsertRes {
    const url, const free = if (brief.image) |image|
        .{ try std.fmt.allocPrint(allocator, "{f}", .{image}), true }
    else
        .{ "", false }; // TODO: 404.png or something?
    defer if (free) allocator.free(url);

    // ignore TCG Pocket cards
    if (std.mem.indexOf(u8, url, "tcgp")) |_| {
        return .{ .variants_count = 0 };
    }

    try Card.insert(session, .{
        .card_id = brief.id,
        .name = brief.name,
        .image_url = url,
    });

    const card: sdk.Card = try .get(allocator, .{ .id = brief.id });
    defer card.deinit();

    const variants: []const ptz.VariantDetailed = switch (card) {
        inline else => |info| info.variant_detailed,
    } orelse return .{ .variants_count = 0 };

    for (variants) |variant| {
        try Card.Variant.insert(session, .{
            .card_id = brief.id,
            .type = variant.type,
            .subtype = variant.subtype,
            .size = variant.size,
            .stamps = variant.stamp,
            .foil = variant.foil,
        });
    }

    return .{ .variants_count = variants.len };
}

const FetchRes = struct {
    card_count: usize,
    ms_elapsed: usize,
};

pub fn fetch(allocator: Allocator, name: []const u8) !FetchRes {
    var timer: std.time.Timer = try .start();

    var session = try database.getSession(allocator);
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
            n_cards += res.variants_count;
        }
    }

    return .{
        .card_count = n_cards,
        .ms_elapsed = timer.read() / 1_000_000, // ns to ms
    };
}
