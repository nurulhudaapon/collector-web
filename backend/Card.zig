const std = @import("std");

const database = @import("database.zig");
const util = @import("util.zig");

const Card = @This();

id: u64,
card_id: []const u8,
name: []const u8,
image_url: []const u8,

pub const Variant = struct {
    id: u64,
    card_id: []const u8,
    type: []const u8,
    subtype: ?[]const u8 = null,
    size: ?[]const u8 = null,
    stamps: ?[]const []const u8 = null,
    foil: ?[]const u8 = null,

    pub fn insert(session: *database.Session, variant: util.Omit(Variant, .id)) !void {
        _ = try session.insert(Variant, variant);
    }
};

pub fn insert(session: *database.Session, card: util.Omit(Card, .id)) !void {
    _ = session.insert(Card, card) catch |err| switch (err) {
        // card existed in DB already, lets not error out
        error.UniqueViolation => {},
        else => return err,
    };
}

pub fn list(allocator: std.mem.Allocator, name: []const u8) ![]const Card {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const wildcard = try std.fmt.allocPrint(allocator, "%{s}%", .{name});
    defer allocator.free(wildcard);

    return session
        .query(Card)
        .whereRaw("name like ?", .{wildcard})
        .findAll();
}
