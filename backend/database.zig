const std = @import("std");
const Allocator = std.mem.Allocator;

const fr = @import("fridge");
pub const Session = fr.Session;

fn mkdir(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    const absolute_path = try std.fs.path.resolve(allocator, &.{dir_path});
    defer allocator.free(absolute_path);

    std.fs.accessAbsolute(absolute_path, .{}) catch |e| switch (e) {
        error.FileNotFound => try std.fs.makeDirAbsolute(absolute_path),
        else => return e,
    };
}

fn dbFilename(allocator: Allocator) ![:0]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const appdir = args.next() orelse return error.MissingExeArg;
    const appname = std.fs.path.basename(appdir);

    const dir_path = try std.fs.getAppDataDir(allocator, appname);
    defer allocator.free(dir_path);

    try mkdir(allocator, dir_path);

    return std.fs.path.joinZ(allocator, &.{ dir_path, "db.sqlite3" });
}

const state = struct {
    var init = false;
};

pub fn getSession(allocator: Allocator) !Session {
    const filename = try dbFilename(allocator);
    defer if (false) allocator.free(filename); // NOTE: seems like sqlite uses this internally without duping

    var db: Session = try .open(fr.SQLite3, allocator, .{ .filename = filename });
    if (state.init) {
        try fr.migrate(&db, @embedFile("schema.sql"));
        state.init = true;
    }

    return db;
}
