const database = @import("database.zig");

const Set = @This();

pub const sql_table_name = "Set_";

id: database.Id,
tcgdex_id: []const u8,
name: []const u8,
release_date: []const u8,

pub fn cards(self: *const Set, session: *database.Session) ![]const database.Card {
    return database.findAll(database.Card, session, .{
        .set_id = self.id,
    });
}
