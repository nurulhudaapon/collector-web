const Id = @import("database.zig").Id;

pub const sql_table_name = "Set_";

id: Id,
name: []const u8,
release_date: []const u8,
