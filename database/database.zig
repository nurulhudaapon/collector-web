const std = @import("std");
const Allocator = std.mem.Allocator;
const Field = std.builtin.Type.StructField;

const fr = @import("fridge");
pub const migrate = fr.migrate;
pub const Options = fr.SQLite3.Options;
pub const Pool = fr.Pool(fr.SQLite3);
pub const Session = fr.Session;

pub const Id = Int;
pub const Int = i64;

pub const Card = @import("Card.zig");
pub const Owned = @import("Owned.zig");
pub const Set = @import("Set.zig");
pub const User = @import("User.zig");
pub const Variant = @import("Variant.zig");

pub const schema = @embedFile("schema.sql");

fn Omit(comptime T: type, comptime field_name: []const u8) type {
    const info = @typeInfo(T).@"struct";

    var copy = info;
    copy.decls = &.{};
    copy.fields = &.{};

    for (info.fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) continue;
        copy.fields = copy.fields ++ &[_]Field{field};
    }

    if (copy.fields.len == info.fields.len) {
        const msg = std.fmt.comptimePrint("{} has no field named {}", .{ T, field_name });
        @compileError(msg);
    }

    return @Type(.{ .@"struct" = copy });
}

fn Query(comptime T: type, session: *Session, filters: anytype) fr.Query(T) {
    var query = session.query(T);

    const Filters = @TypeOf(filters);
    inline for (@typeInfo(Filters).@"struct".fields) |field| {
        const val = @field(filters, field.name);
        query = query.where(field.name, val);
    }

    return query;
}

pub fn findOne(comptime T: type, session: *Session, filters: anytype) !?T {
    return Query(T, session, filters).findFirst();
}

pub fn findAll(comptime T: type, session: *Session, filters: anytype) ![]const T {
    return Query(T, session, filters).findAll();
}

/// update or insert a value
pub fn save(comptime T: type, session: *Session, data: Omit(T, "id")) !@FieldType(T, "id") {
    if (try findOne(T, session, data)) |row| {
        try session.update(T, row.id, data);
        return row.id;
    }

    return session.insert(T, data);
}
