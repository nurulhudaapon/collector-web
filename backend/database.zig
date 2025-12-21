const std = @import("std");
const compPrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const zmig = @import("zmig");
const sqlite = zmig.sqlite;

pub const Connection = sqlite.Db;
pub const Diagnostics = sqlite.Diagnostics;

pub const Table = enum {
    card,
    owned,
    user,
    variant,

    pub fn getType(comptime self: Table) type {
        return switch (self) {
            .card => @import("database/tables/Card.zig"),
            .owned => @import("database/tables/Owned.zig"),
            .user => @import("database/tables/User.zig"),
            .variant => @import("database/tables/Variant.zig"),
        };
    }

    pub fn name(self: Table) []const u8 {
        return @tagName(self);
    }
};

pub fn get(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    comptime column: std.meta.FieldEnum(table.getType()),
    value: @FieldType(table.getType(), @tagName(column)),
    diagnostics: ?*sqlite.Diagnostics,
) !Owned(?table.getType()) {
    const query = comptime compPrint("SELECT * FROM {s} WHERE {s}=?", .{
        table.name(),
        @tagName(column),
    });

    var stmt = try connection.prepareWithDiags(query, .{
        .diags = diagnostics,
    });
    defer stmt.deinit();

    const arena = try newArena(allocator);
    errdefer allocator.destroy(arena);

    return .{
        .arena = arena,
        .value = try stmt.oneAlloc(
            table.getType(),
            arena.allocator(),
            .{},
            .{value},
        ),
    };
}

pub fn all(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    diagnostics: ?*sqlite.Diagnostics,
) !Owned([]const table.getType()) {
    const query = comptime compPrint("SELECT * FROM {s}", .{table.name()});

    var stmt = try connection.prepareWithDiags(query, .{ .diags = diagnostics });
    defer stmt.deinit();

    const arena = try newArena(allocator);
    errdefer allocator.destroy(arena);

    return .{
        .arena = arena,
        .value = try stmt.all(
            table.getType(),
            arena.allocator(),
            .{},
            .{},
        ),
    };
}

// TODO: create() method, so that id is not required

/// inserts or updates the given values
pub fn save(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    value: table.getType(),
    diagnostics: ?*sqlite.Diagnostics,
) !void {
    const query = comptime queryBuilder(
        table,
        queryBuilder(
            table,
            compPrint("REPLACE INTO {s} (", .{table.name()}),
            nameCommaSpace,
            nameCloseParen,
        ) ++ " VALUES (",
        placeholderCommaSpace,
        placeholderCloseParen,
    );

    var stmt = try connection.prepareWithDiags(query, .{
        .diags = diagnostics,
    });
    defer stmt.deinit();

    // HACK: work around sqlite's leak
    const arena = try newArena(allocator);
    defer {
        arena.deinit();
        allocator.destroy(arena);
    }

    try stmt.execAlloc(arena.allocator(), .{}, value);
}

pub fn getFilename(connection: *Connection) [*c]const u8 {
    return sqlite.c.sqlite3_db_filename(connection.db, null);
}

// internal query-related code

const StructField = std.builtin.Type.StructField;
const Format = fn (comptime []const u8, StructField) []const u8;

fn queryBuilder(
    comptime table: Table,
    query: []const u8,
    formatEach: Format,
    formatLast: Format,
) []const u8 {
    if (!@inComptime()) @compileError("must call this in comptime");

    var q = query;

    const fields = @typeInfo(table.getType()).@"struct".fields;

    if (fields.len == 0) @compileError("bad type");
    if (fields.len > 1) {
        inline for (fields[0 .. fields.len - 1]) |field| {
            q = formatEach(q, field);
        }
    }

    return formatLast(q, fields[fields.len - 1]);
}

fn spaceNamePlaceholder(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=?", .{field.name});
}

fn spaceNamePlaceholderAnd(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=? AND", .{field.name});
}

fn spaceNamePlaceholderCloseParen(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=?)", .{field.name});
}

fn nameCommaSpace(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint("{s}, ", .{field.name});
}

fn nameCloseParen(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint("{s})", .{field.name});
}

fn placeholderCommaSpace(comptime query: []const u8, _: StructField) []const u8 {
    return query ++ "?, ";
}

fn placeholderCloseParen(comptime query: []const u8, _: StructField) []const u8 {
    return query ++ "?)";
}

fn newArena(allocator: Allocator) Allocator.Error!*ArenaAllocator {
    const arena = try allocator.create(ArenaAllocator);
    arena.* = .init(allocator);
    return arena;
}

/// Caller-owned value, with a method to free it
pub fn Owned(comptime T: type) type {
    return struct {
        value: T,
        arena: *ArenaAllocator,

        pub fn deinit(self: @This()) void {
            const child = self.arena.child_allocator;
            self.arena.deinit();
            child.destroy(self.arena);
        }
    };
}
