const database = @import("database");

const ProxyState = @This();

token: ?[]const u8,

pub fn getUser(self: *const ProxyState, session: *database.Session) !?database.User {
    const token = self.token orelse return null;
    return .get(session, token);
}
