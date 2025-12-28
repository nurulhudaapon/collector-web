const std = @import("std");
const Allocator = std.mem.Allocator;

const fr = @import("fridge");
pub const Session = fr.Session;

pub const Card = struct {
    id: u64,
    card_id: []const u8,
    name: []const u8,
    image_url: []const u8,
};

pub const Owned = struct {
    id: u64,
    user_id: u64,
    variant_id: u64,
    owned: bool,
};

pub const Variant = struct {
    id: u64,
    card_id: []const u8,
    type: []const u8,
    subtype: ?[]const u8 = null,
    size: ?[]const u8 = null,
    stamps: ?[]const []const u8 = null,
    foil: ?[]const u8 = null,
};

const state = struct {
    var pool: ?fr.Pool(fr.SQLite3) = null;
};

fn mkdir(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    const absolute_path = try std.fs.path.resolve(allocator, &.{dir_path});
    defer allocator.free(absolute_path);

    std.fs.accessAbsolute(absolute_path, .{}) catch |e| switch (e) {
        error.FileNotFound => try std.fs.makeDirAbsolute(absolute_path),
        else => return e,
    };
}

pub fn init(allocator: Allocator) !void {
    if (state.pool) |_| return;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const appdir = args.next() orelse @panic("args[0] == null");
    const appname = std.fs.path.basename(appdir);

    const dir_path = try std.fs.getAppDataDir(allocator, appname);
    defer allocator.free(dir_path);

    try mkdir(allocator, dir_path);

    const filename = try std.fs.path.joinZ(allocator, &.{ dir_path, "db.sqlite3" });
    // NOTE: seems like sqlite uses this internally without copying
    defer if (false) allocator.free(filename);

    var db: Session = try .open(fr.SQLite3, allocator, .{ .filename = filename });
    defer db.deinit();

    try fr.migrate(&db, @embedFile("schema.sql"));

    state.pool = try .init(
        allocator,
        .{ .max_count = 5 },
        .{ .filename = filename },
    );
}

pub fn getSession(allocator: Allocator) !Session {
    if (state.pool) |*pool| {
        return pool.getSession(allocator);
    }

    return error.DatabaseNotInit;
}
