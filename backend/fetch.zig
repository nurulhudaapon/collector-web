//! Functions to update local database with API data

const std = @import("std");
const Allocator = std.mem.Allocator;

const sdk = @import("sdk");

const database = @import("database.zig");
const Omit = @import("utils.zig").Omit;
const Card = @import("Card.zig");

// numbers should never get bigger than u16 (65k years is far away)
// but we are using u64 to simplify the multiplication (u16 * value causes panic due to overflowing u16)
fn consume(it: *std.mem.SplitIterator(u8, .scalar)) !u64 {
    const buf = it.next() orelse return error.BadDateStr;
    return std.fmt.parseInt(u64, buf, 10);
}

fn dateToNum(release_date: []const u8) !u64 {
    var it = std.mem.splitScalar(u8, release_date, '-');

    const year = try consume(&it);
    const month = try consume(&it);
    const day = try consume(&it);

    return year * 366 + month * 31 + day;
}

pub fn run(allocator: Allocator, name: []const u8) !usize {
    var session = try database.getSession(allocator);
    defer session.deinit();

    // NOTE: sweet spot is somewhere 1900-1950, don't feel like digging exact value
    @setEvalBranchQuota(1950);

    const response = try sdk.graphql.run(
        allocator,
        "cards",
        .{
            .filters = .{
                .name = name,
            },
        },
        .{
            .id = true,
            .name = true,
            .image = true,
            .set = .{
                .logo = true,
                // .releaseDate = true,
            },
            .variants_detailed = .{
                .type = true,
                // .subtype = true,
                .size = true,
                .stamps = true,
                .foil = true,
            },
        },
    );
    defer response.deinit();

    const cards = try response.unwrap() orelse return error.NothingFound;

    var count: usize = 0;
    for (cards) |card| {
        // skip pocket cards
        if (card.set.logo) |logo| {
            if (std.mem.indexOf(u8, logo, "tcgp") != null) {
                continue;
            }
        }

        const image_url, const free = if (card.image) |url|
            .{ try std.fmt.allocPrint(allocator, "{s}/high.png", .{url}), true }
        else
            .{ "", false };
        defer if (free) allocator.free(image_url);

        const db_card: Omit(Card, "id") = .{
            .card_id = card.id,
            .name = card.name,
            .image_url = image_url,
            .release_date = 123, // FIXME: graphql returns null and crashes
            // .release_date = try dateToNum(card.set.releaseDate),
        };

        if (try session.query(Card).findBy("card_id", db_card.card_id)) |exists| {
            try session.update(Card, exists.id, db_card);
        } else {
            _ = try session.insert(Card, db_card);
        }

        count += 1;

        const variants = card.variants_detailed orelse continue;
        for (variants) |variant| {
            const data: Omit(Card.Variant, "id") = .{
                .card_id = card.id,
                .type = variant.type,
                // .subtype = variant.subtype, // FIXME: missing in graphql
                .size = variant.size,
                .stamps = variant.stamps,
                .foil = variant.foil,
            };

            const in_db = try database.findOne(Card.Variant, &session, data);
            if (in_db) |row| {
                try session.update(Card.Variant, row.id, data);
            } else {
                _ = try session.insert(Card.Variant, data);
            }

            count += 1;
        }
    }

    return count;
}
