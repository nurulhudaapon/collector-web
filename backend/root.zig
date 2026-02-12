//! Functions used on frontend to interact with database
//!
//! Note that leaking resources is not a big deal since most times we will be using an arena
//! As such, everything will be free'd when the response is sent by client
//!
//! Regardless, those leaks are still a bad thing, lets try and not make any :)

const std = @import("std");
const Allocator = std.mem.Allocator;

const graphqlz = @import("graphqlz");

const database = @import("database");

const graphql = graphqlz.Client("https://tcgdex.elpekenin.dev/v3/graphql", @import("graphql-schema.zig"));

fn parseEnum(comptime T: type, str: []const u8) T {
    return std.meta.stringToEnum(T, str) orelse {
        std.log.warn("unknown value '{s}' for {}", .{ str, T });
        return .unknown;
    };
}

fn parseMaybeEnum(comptime T: type, str: ?[]const u8) ?T {
    return parseEnum(T, str orelse return null);
}

fn stampLessThan(_: void, lhs: database.Variant.Stamp, rhs: database.Variant.Stamp) bool {
    return @intFromEnum(lhs) < @intFromEnum(rhs);
}

fn fetchVariant(
    allocator: Allocator,
    session: *database.Session,
    card_id: database.Id,
    variant: anytype,
) !database.Id {
    const stamps: []database.Variant.Stamp, const free_stamps = if (variant.stamp) |raw_stamps| blk: {
        const stamps = try allocator.alloc(database.Variant.Stamp, raw_stamps.len);

        for (raw_stamps, stamps) |str, *stamp| {
            stamp.* = parseEnum(database.Variant.Stamp, str);
        }

        std.mem.sort(database.Variant.Stamp, stamps, {}, stampLessThan);

        break :blk .{ stamps, true };
    } else .{ &.{}, false };
    defer if (free_stamps) allocator.free(stamps);

    return database.save(database.Variant, session, .{
        .card_id = card_id,
        .type = parseEnum(database.Variant.Type, variant.type),
        .subtype = parseMaybeEnum(database.Variant.Subtype, variant.subtype),
        .size = parseMaybeEnum(database.Variant.Size, variant.size),
        .stamps = .init(stamps),
        .foil = parseMaybeEnum(database.Variant.Foil, variant.foil),
    });
}

fn fetchCard(allocator: Allocator, session: *database.Session, card: anytype) !usize {
    var count: usize = 0;

    const image_url, const free_image_url = if (card.image) |url|
        .{ try std.fmt.allocPrint(allocator, "{s}/high.png", .{url}), true }
    else
        .{ "/card-back.png", false };
    defer if (free_image_url) allocator.free(image_url);

    const set_id = try database.save(database.Set, session, .{
        .tcgdex_id = card.set.id,
        .name = card.set.name,
        .release_date = card.set.releaseDate orelse "0000-00-00",
    });

    const cardmarket_id: ?database.Int = blk: {
        if (card.pricing) |pricing| {
            if (pricing.cardmarket) |cardmarket| {
                if (cardmarket.idProduct) |id| {
                    break :blk @intCast(id);
                }
            }
        }

        std.log.warn("missing cardmarket_id (card_id: {s})", .{card.id});
        break :blk null;
    };

    const card_id = try database.save(database.Card, session, .{
        .tcgdex_id = card.id,
        .set_id = set_id,
        .name = card.name,
        .image_url = image_url,
        .cardmarket_id = cardmarket_id,
    });

    count += 1;

    const variants = card.variants_detailed orelse return count;
    for (variants) |variant| {
        _ = try fetchVariant(allocator, session, card_id, variant);
        count += 1;
    }

    return count;
}

pub fn fetch(session: *database.Session, name: []const u8) !usize {
    const allocator = session.arena;

    // NOTE: sweet spot is somewhere 1900-1950, don't feel like digging exact value
    @setEvalBranchQuota(1950);

    const response = try graphql.query(
        "cards",
        allocator,
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
                .id = true,
                .logo = true,
                .name = true,
                .releaseDate = true,
            },
            .variants_detailed = .{
                .type = true,
                .subtype = true,
                .size = true,
                .stamp = true,
                .foil = true,
            },
            .pricing = .{
                .cardmarket = .{
                    .idProduct = true,
                },
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

        count += try fetchCard(allocator, session, card);
    }

    return count;
}
