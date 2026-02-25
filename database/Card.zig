const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const fr = @import("fridge");

const database = @import("database.zig");

const Card = @This();

id: database.Id,
tcgdex_id: []const u8,
set_id: []const u8,
name: []const u8,
image_url: []const u8,
cardmarket_id: ?database.Int,
dex_ids: DexIds,

pub const DexIds = struct {
    items: []const Id,

    const Id = u64;
    pub const separator: u8 = '$';
    const empty_array: u8 = '^';

    pub const empty: DexIds = .{ .items = &.{} };

    fn idLessThan(_: void, lhs: Id, rhs: Id) bool {
        return lhs < rhs;
    }

    pub fn toValue(self: DexIds, allocator: std.mem.Allocator) !fr.Value {
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();

        const writer = &aw.writer;

        try writer.writeByte(separator);

        if (self.items.len == 0) {
            try writer.print("{c}", .{empty_array});
        } else {
            const sorted = try allocator.dupe(Id, self.items);
            defer allocator.free(sorted);

            std.mem.sort(Id, sorted, {}, idLessThan);

            for (sorted) |id| {
                try writer.print("{}{c}", .{ id, separator });
            }
        }

        return .{ .string = try aw.toOwnedSlice() };
    }

    pub fn fromValue(value: fr.Value, allocator: std.mem.Allocator) !DexIds {
        const string = switch (value) {
            .string => |string| string,
            else => return error.InvalidValueTag,
        };

        std.debug.assert(string[0] == separator);
        if (string[1] == empty_array) {
            std.debug.assert(string.len == 2);
            return .empty;
        }

        var ids: std.ArrayList(Id) = .empty;
        defer ids.deinit(allocator);

        var it = std.mem.splitScalar(u8, string, separator);
        while (it.next()) |raw| {
            if (raw.len == 0) continue;

            const id = try std.fmt.parseInt(Id, raw, 10);
            try ids.append(allocator, id);
        }

        return .{ .items = try ids.toOwnedSlice(allocator) };
    }
};

fn stringLessThan(lhs: []const u8, rhs: []const u8) bool {
    // foo-8 must be prior to foo-10, can't lexicographically sort on diff len
    if (lhs.len < rhs.len) return true;
    if (lhs.len > rhs.len) return false;

    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn cardLessThanInner(sets: []const database.Set, lhs: Card, rhs: Card) !bool {
    // compare tcgdex id, not great due to lack of leading '0' for padding
    if (std.mem.eql(u8, lhs.set_id, rhs.set_id)) {
        return stringLessThan(lhs.tcgdex_id, rhs.tcgdex_id);
    }

    const lhs_set = for (sets) |set| {
        if (std.mem.eql(u8, lhs.set_id, set.tcgdex_id)) break set;
    } else return error.SetNotFound;

    const rhs_set = for (sets) |set| {
        if (std.mem.eql(u8, rhs.set_id, set.tcgdex_id)) break set;
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

pub fn getVariants(self: Card, session: *database.Session) ![]const database.Variant {
    return session
        .query(database.Variant)
        .where("card_id", self.tcgdex_id)
        .findAll();
}

pub fn getSet(self: Card, session: *database.Session) !database.Set {
    return try session
        .query(database.Set)
        .where("tcgdex_id", self.set_id)
        .findFirst() orelse return error.SetNotFound;
}
