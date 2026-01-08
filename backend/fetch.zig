//! Functions to update local database with API data

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.fetch);

const sdk = @import("sdk").For(.en);

const api = @import("api");
const options = @import("options");

const database = @import("database.zig");
const Card = @import("Card.zig");

const Task = struct {
    const State = union(enum) {
        free,
        running,
        complete: u64,
    };

    id: u32,
    state: State,
    count: u64,
    start: i64,

    fn init(id: u32) Task {
        return .{
            .state = .running,
            .id = id,
            .count = 0,
            .start = now(),
        };
    }

    const none: Task = .{
        .state = .free,
        .id = 0,
        .count = 0,
        .start = 0,
    };
};

const global = struct {
    var next_id: u32 = 0;
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

fn now() i64 {
    return std.time.milliTimestamp();
}

fn msElapsed(since: i64) u64 {
    return @intCast(now() - since);
}

fn entrypoint(allocator: Allocator, owned_name: []const u8, task: *Task) !void {
    defer {
        allocator.free(owned_name);
        task.state = .{
            .complete = msElapsed(task.start),
        };
    }

    var session = try database.getSession(allocator);
    defer session.deinit();

    var iterator = sdk.Card.all(allocator, .{
        .page_size = 250,
        .where = &.{
            .like(.name, owned_name),
        },
    });

    while (iterator.next() catch null) |briefs| {
        for (briefs) |brief| {
            defer brief.deinit();
            task.count += try variants(allocator, &session, brief);
        }
    }
}

pub fn start(_: Allocator, args: api.fetch.start.Args) !api.fetch.start.Response {
    const allocator = std.heap.smp_allocator;

    const owned_name = try allocator.dupe(u8, args.name);
    errdefer allocator.free(owned_name);

    const task = blk: {
        for (&global.tasks) |*task| {
            // slot never been used or has already finished
            switch (task.state) {
                .free,
                .complete,
                => break :blk task,

                .running => {},
            }
        }

        return error.TasksExhausted;
    };

    defer global.next_id += 1;
    task.* = .init(global.next_id);

    var thread: std.Thread = try .spawn(.{}, entrypoint, .{ allocator, owned_name, task });
    thread.detach();

    return .{
        .id = task.id,
    };
}

pub fn status(allocator: Allocator, args: api.fetch.status.Args) !api.fetch.status.Response {
    // argument is there so that all APIs have same signature
    _ = allocator;

    for (global.tasks) |task| {
        if (task.id != args.id) continue;

        switch (task.state) {
            .free => {},
            .running => return .{
                .count = task.count,
                .finished = false,
                .ms_elapsed = msElapsed(task.start),
            },
            .complete => |elapsed| return .{
                .count = task.count,
                .finished = true,
                .ms_elapsed = elapsed,
            },
        }
    }

    return error.TaskNotFound;
}
