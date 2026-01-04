const std = @import("std");
const Allocator = std.mem.Allocator;

const fr = @import("fridge");
pub const Session = fr.Session;

fn appDataDir(allocator: Allocator) ![]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const exe_path = args.next() orelse @panic("missing exe arg");
    const exe_name = std.fs.path.basename(exe_path);

    return std.fs.getAppDataDir(allocator, exe_name);
}

const state = struct {
    var pool: ?fr.Pool(fr.SQLite3) = null;
};

pub fn getSession(allocator: Allocator) !Session {
    if (state.pool) |*pool| {
        return pool.getSession(allocator);
    } else {
        errdefer state.pool = null;

        const options: fr.SQLite3.Options = if (std.process.hasEnvVar(allocator, "__TESTING__") catch false)
            .{
                .filename = ":memory:",
            }
        else
            .{
                // NOTE: not freeing because it seems like sqlite doesn't dupe it
                .dir = try appDataDir(allocator),
                .filename = "db.sqlite3",
            };

        state.pool = try .init(allocator, .{ .max_count = 10 }, options);
        errdefer state.pool.?.deinit();

        var session = try getSession(allocator);
        errdefer session.deinit();

        try fr.migrate(&session, @embedFile("schema.sql"));

        return session;
    }
}
