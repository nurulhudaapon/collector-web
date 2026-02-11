const std = @import("std");

const database = @import("database");

const ServerState = @This();

pool: *database.Pool,

fn appDataDir(allocator: std.mem.Allocator) ![]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const exe_path = args.next() orelse @panic("missing exe arg");
    const exe_name = std.fs.path.basename(exe_path);

    return std.fs.getAppDataDir(allocator, exe_name);
}

pub fn init(allocator: std.mem.Allocator) !ServerState {
    const options: database.Options = if (std.process.hasEnvVar(
        allocator,
        "__TESTING__",
    ) catch false)
        .{
            .filename = ":memory:",
        }
    else
        .{
            // NOTE: not freeing because it seems like sqlite doesn't dupe it
            .dir = try appDataDir(allocator),
            .filename = "db.sqlite3",
        };

    const pool = try allocator.create(database.Pool);
    errdefer allocator.destroy(pool);

    pool.* = try .init(allocator, .{ .max_count = 16 }, options);
    errdefer pool.deinit();

    var session = try pool.getSession(allocator);
    defer session.deinit();

    try database.migrate(&session, database.schema);

    return .{
        .pool = pool,
    };
}

pub fn deinit(self: *ServerState, allocator: std.mem.Allocator) void {
    self.pool.deinit();
    allocator.destroy(self.pool);
}
