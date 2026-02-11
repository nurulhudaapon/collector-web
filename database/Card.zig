const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const database = @import("database.zig");

const Card = @This();

id: database.Id,
tcgdex_id: []const u8,
set_id: database.Id,
name: []const u8,
image_url: []const u8,
cardmarket_id: ?database.Int,

fn stringLessThan(lhs: []const u8, rhs: []const u8) bool {
    // foo-8 must be prior to foo-10, can't lexicographically sort on diff len
    if (lhs.len < rhs.len) return true;
    if (lhs.len > rhs.len) return false;

    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn cardLessThanInner(sets: []const database.Set, lhs: Card, rhs: Card) !bool {
    // compare tcgdex id, not great due to lack of leading '0' for padding
    if (lhs.set_id == rhs.set_id) {
        return stringLessThan(lhs.tcgdex_id, rhs.tcgdex_id);
    }

    const lhs_set = for (sets) |set| {
        if (lhs.set_id == set.id) break set;
    } else return error.SetNotFound;

    const rhs_set = for (sets) |set| {
        if (rhs.set_id == set.id) break set;
    } else return error.SetNotFound;

    return stringLessThan(lhs_set.release_date, rhs_set.release_date);
}

fn cardLessThan(sets: []const database.Set, lhs: Card, rhs: Card) bool {
    return cardLessThanInner(sets, lhs, rhs) catch true;
}

/// return a copy of the input, sorted by release date and id
/// caller owns the memory
pub fn sort(allocator: Allocator, cards: []const Card, sets: []const database.Set) ![]const Card {
    const sorted = try allocator.dupe(Card, cards);
    std.mem.sort(Card, sorted, sets, cardLessThan);

    return sorted;
}

pub fn variants(self: *const Card, session: *database.Session) ![]const database.Variant {
    return database.findAll(database.Variant, session, .{
        .card_id = self.id,
    });
}
