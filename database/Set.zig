const database = @import("database.zig");

const Set = @This();

pub const sql_table_name = "Set_";

id: database.Id,
tcgdex_id: []const u8,
name: []const u8,
release_date: []const u8,

pub fn getCards(self: Set, session: *database.Session) ![]const database.Card {
    return session
        .query(database.Card)
        .where("set_id", self.tcgdex_id)
        .findAll();
}
