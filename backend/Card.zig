const std = @import("std");
const Allocator = std.mem.Allocator;

const database = @import("database.zig");

const Card = @This();

id: u64,
card_id: []const u8,
name: []const u8,
image_url: []const u8,
release_date: u64, // used to display cards chronologically

pub const Variant = struct {
    id: u64,
    card_id: []const u8,
    type: []const u8,
    subtype: ?[]const u8 = null,
    size: ?[]const u8 = null,
    stamps: ?[]const []const u8 = null,
    foil: ?[]const u8 = null,

    pub const Owned = struct {
        id: u64,
        user_id: u64,
        variant_id: u64,
        owned: bool,
    };
};

pub fn all(session: *database.Session, pokemon_name: ?[]const u8) ![]const Card {
    var query = session.query(Card);

    if (pokemon_name) |name| {
        const wildcard = try std.fmt.allocPrint(session.arena, "%{s}%", .{name});
        query = query.whereRaw("name like ?", .{wildcard});
    }

    return query
        .orderBy(.release_date, .asc)
        .findAll();
}

pub fn variants(self: *const Card, session: *database.Session) ![]const Variant {
    return database.findAll(Variant, session, .{
        .card_id = self.card_id,
    });
}
