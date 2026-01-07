//! Functions to update local database with API data

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const sdk = @import("sdk").For(.en);

const api = @import("api");
const options = @import("options");

const database = @import("database.zig");
const Card = @import("Card.zig");

const Task = struct {
    const Int = u64;

    const Id = enum(Int) {
        const backing_integer = Int;

        none,
        _,
    };

    id: Id,
    count: u64,
    timer: std.time.Timer,

    fn init(id: Id) !Task {
        return .{
            .id = id,
            .count = 0,
            .timer = try .start(),
        };
    }

    const none: Task = .{
        .id = .none,
        .count = 0,
        .timer = undefined,
    };
};

const global = struct {
    var counter: usize = 0;
    var tasks: [options.max_fetch_threads]Task = @splat(.none);
};

// numbers should never get bigger than u16 (65k years is far away)
// but we are using u64 to simplify the multiplication (u16 * value causes panic due to overflowing u16)
fn consume(it: *std.mem.SplitIterator(u8, .scalar)) !u64 {
    const buf = it.next() orelse return error.BadDateStr;
    return std.fmt.parseInt(u64, buf, 10);
}

fn dateToNum(release_date: []const u8) !u64 {
    var it = std.mem.splitScalar(u8, release_date, '-');

    const year = try consume(&it);
    const month = try consume(&it);
    const day = try consume(&it);

    return year * 366 + month * 31 + day;
}

/// from a card brief, store all variants into database
fn variants(allocator: Allocator, session: *database.Session, brief: sdk.Card.Brief) !usize {
    const url, const free = if (brief.image) |image|
        .{ try std.fmt.allocPrint(allocator, "{f}", .{image}), true }
    else
        .{ "", false }; // TODO: 404.png or something?
    defer if (free) allocator.free(url);

    // ignore TCG Pocket cards
    if (std.mem.indexOf(u8, url, "tcgp")) |_| {
        return 0;
    }

    const card: sdk.Card = try .get(allocator, .{ .id = brief.id });
    defer card.deinit();

    const set_id = switch (card) {
        inline else => |info| info.set.id,
    };

    const set: sdk.Set = try .get(allocator, .{
        .id = set_id,
    });
    defer set.deinit();

    try Card.insert(session, .{
        .card_id = brief.id,
        .name = brief.name,
        .image_url = url,
        .release_date = try dateToNum(set.releaseDate),
    });

    // TODO: remove this, error out if variants aren't present
    const card_variants: []const sdk.VariantDetailed = switch (card) {
        inline else => |info| info.variant_detailed,
    } orelse return 1;

    for (card_variants) |variant| {
        try Card.Variant.insert(session, .{
            .card_id = brief.id,
            .type = variant.type,
            .subtype = variant.subtype,
            .size = variant.size,
            .stamps = variant.stamp,
            .foil = variant.foil,
        });
    }

    return card_variants.len;
}

fn entrypoint(allocator: Allocator, name: []const u8, task: *Task) !void {
    defer allocator.free(name);

    assert(task.id != .none);
    defer task.id = .none;

    var session = try database.getSession(allocator);
    defer session.deinit();

    var iterator = sdk.Card.all(allocator, .{
        .page_size = 250,
        .where = &.{
            .like(.name, name),
        },
    });

    while (iterator.next() catch null) |briefs| {
        for (briefs) |brief| {
            defer brief.deinit();
            task.count += try variants(allocator, &session, brief);
        }
    }
}

pub fn run(allocator: Allocator, args: api.fetch.start.Args) !api.fetch.start.Response {
    const copy = try allocator.dupe(u8, args.name);
    errdefer allocator.free(copy);

    const task = blk: {
        for (&global.tasks) |*task| {
            if (task.id == .none) {
                break :blk task;
            }
        }

        return error.TasksExhausted;
    };

    global.counter += 1;
    task.* = try .init(@enumFromInt(global.counter));

    var thread: std.Thread = try .spawn(.{}, entrypoint, .{ allocator, copy, task });
    thread.detach();

    return .{
        .id = @intFromEnum(task.id),
    };
}

pub fn status(allocator: Allocator, args: api.fetch.status.Args) !api.fetch.status.Response {
    // argument is there so that all APIs have same signature
    _ = allocator;

    for (&global.tasks) |*task| {
        if (task.id != .none and @intFromEnum(task.id) == args.id) {
            return .{
                .count = task.count,
                .finished = task.id == .none,
                .ms_elapsed = task.timer.read() / std.time.ns_per_ms,
            };
        }
    }

    return error.TaskNotFound;
}
