const std = @import("std");

const fr = @import("fridge");

const database = @import("database.zig");

const Variant = @This();

id: database.Id,
card_id: database.Id,
type: Type,
subtype: ?Subtype = null,
size: ?Size = null,
stamps: Stamps = .empty,
foil: ?Foil = null,

const Stamps = struct {
    const separator: u8 = 255;
    const empty_array: u8 = 254;

    items: []const Stamp,

    pub fn init(items: []const Stamp) Stamps {
        return .{
            .items = items,
        };
    }

    pub const empty: Stamps = .init(&.{});

    pub fn toValue(self: Stamps, allocator: std.mem.Allocator) !fr.Value {
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();

        const writer = &aw.writer;

        if (self.items.len == 0) {
            try writer.print("{c}", .{empty_array});
        } else for (self.items) |stamp| {
            try writer.print("{t}{c}", .{ stamp, separator });
        }

        return .{
            .blob = try aw.toOwnedSlice(),
        };
    }

    pub fn fromValue(value: fr.Value, allocator: std.mem.Allocator) !Stamps {
        const blob = switch (value) {
            .blob => |blob| blob,
            else => return error.InvalidValueTag,
        };

        if (blob[0] == empty_array) {
            std.debug.assert(blob.len == 1);
            return .empty;
        }

        var stamps: std.ArrayList(Stamp) = .empty;
        defer stamps.deinit(allocator);

        var it = std.mem.splitScalar(u8, blob, separator);
        while (it.next()) |raw| {
            if (raw.len == 0) continue;

            const stamp = std.meta.stringToEnum(Stamp, raw) orelse return error.InvalidStampTag;
            try stamps.append(allocator, stamp);
        }

        return .{
            .items = try stamps.toOwnedSlice(allocator),
        };
    }
};

pub const Type = enum {
    unknown,

    normal,
    reverse,
    holo,
};

pub const Subtype = enum {
    unknown,

    unlimited,
    shadowless,
    @"1999-2000-copyright",
};

pub const Size = enum {
    unknown,

    standard,
    jumbo,
};

pub const Stamp = enum {
    unknown,

    staff,
    @"1st-edition",
    @"set-logo",
    @"city-championships",
    @"state-championships",
    @"regional-championships",
    @"national-championships",
    @"michael-pramawat",
    @"destiny-deoxys",
    @"pokemon-day",
    @"stadium-challenge",
};

pub const Foil = enum {
    unknown,

    energy,
    cosmos,
};

pub fn ownedBy(self: *const Variant, session: *database.Session, user_id: database.Id) !bool {
    const row = try database.findOne(database.Owned, session, .{
        .user_id = user_id,
        .variant_id = self.id,
    }) orelse return false;

    return row.owned;
}
