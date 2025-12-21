const std = @import("std");
const Allocator = std.mem.Allocator;

id: u64,
card_id: []const u8,
type: []const u8,
subtype: ?[]const u8 = null,
size: ?[]const u8 = null,
stamp: ?Stamp = null,
foil: ?[]const u8 = null,

const Stamp = struct {
    const separator = "||";
    pub const BaseType = []const u8; // how it is stored in DB

    value: []const []const u8,

    // zig -> db
    pub fn bindField(self: Stamp, allocator: Allocator) !BaseType {
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(allocator);

        for (self.value) |items| {
            try list.appendSlice(allocator, items);
            try list.appendSlice(allocator, separator);
        }

        return list.toOwnedSlice(allocator);
    }

    // db -> zig
    pub fn readField(allocator: Allocator, base: BaseType) !Stamp {
        var list: std.ArrayList([]const u8) = .empty;
        defer {
            for (list.items) |item| {
                allocator.free(item);
            }

            list.deinit(allocator);
        }

        var it = std.mem.splitSequence(u8, base, separator);
        while (it.next()) |item| {
            if (item.len == 0) {
                std.debug.assert(it.next() == null);
                break;
            }

            const copy = try allocator.dupe(u8, item);
            try list.append(allocator, copy);
        }

        return .{
            .value = try list.toOwnedSlice(allocator),
        };
    }
};

// TODO: add format()
