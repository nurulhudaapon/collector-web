const std = @import("std");
const assert = std.debug.assert;

const zx = @import("zx");
const js = zx.Client.js;

const options = @import("options");

const wasm = @import("../wasm.zig");

comptime {
    if (zx.platform == .browser) {
        @export(&onPromiseCompleted, .{
            .name = "onPromiseCompleted",
        });
    }
}

const Id = u32;
const RawObj = u64;

/// calls back to `onPromiseCompleted`, allowing access to awaited value
extern "collector-web" fn startAwaiting(promise_id: u32, out: *RawObj) void;

pub const AwaitHandler = fn (js.Object) anyerror!void;

const Callbacks = struct {
    onFulfill: *const AwaitHandler,
    onReject: *const AwaitHandler = printOnReject,
};

fn emptyFulfill(_: js.Object) !void {
    @panic("called emptyFulfill callback");
}

const Awaitable = struct {
    promise_id: ?Id,
    output: RawObj,
    callbacks: Callbacks,

    const empty: Awaitable = .{
        .promise_id = null,
        .output = undefined,
        .callbacks = .{
            .onFulfill = emptyFulfill,
        },
    };
};

const global = struct {
    var awaitables: [options.max_awaitable_promises]Awaitable = @splat(.empty);
};

fn printOnReject(object: js.Object) !void {
    try log(.{ js.string("error awaiting for Promise:"), object });
}

fn onPromiseCompleted(id: Id, success: bool) callconv(wasm.calling_convention) void {
    const awaitable = blk: {
        for (&global.awaitables) |*awaitable| {
            if (awaitable.promise_id == id) {
                break :blk awaitable;
            }
        }

        log(.{js.string("onPromiseComplete received unknown id")}) catch {};
        return;
    };

    const function = if (success)
        awaitable.callbacks.onFulfill
    else
        awaitable.callbacks.onReject;

    const object: js.Object = .{ .value = @enumFromInt(awaitable.output) };
    defer object.deinit();

    function(object) catch |err| {
        log(.{ js.string("await handler failed with:"), js.string(@errorName(err)) }) catch {};
    };
}

// Public API

/// Write to console. Useful because there is no stdout
pub fn log(args: anytype) !void {
    const console: js.Object = try js.global.get(js.Object, "console");
    defer console.deinit();

    try console.call(void, "log", args);
}

/// Construct the JS equivalent of a zig object
pub fn fromZig(allocator: std.mem.Allocator, zig: anytype) !js.Object {
    // allocate an empty JS object
    var object: js.Object = try js.global.call(js.Object, "Object", .{});

    inline for (std.meta.fields(@TypeOf(zig))) |field| {
        const T = field.type;
        const field_value: T = @field(zig, field.name);

        const value: js.Value = switch (T) {
            []const u8 => .init(js.string(field_value)),
            else => switch (@typeInfo(T)) {
                .@"struct" => (try fromZig(allocator, field_value)).value,
                else => .init(field_value),
            },
        };

        try object.set(field.name, value);
    }

    return object;
}

/// Set up functions to be executed when promise is completed
/// Default value for rejection is to `console.log` the error
pub fn await(promise: js.Object, callbacks: Callbacks) !void {
    // copied from non-pub js.Value.ref()
    const ref: js.Ref = @bitCast(@intFromEnum(promise.value));
    const promise_id = ref.id;

    const awaitable = blk: {
        for (&global.awaitables) |*awaitable| {
            if (awaitable.promise_id == null) {
                break :blk awaitable;
            }
        }

        return error.AwaitablesExhausted;
    };

    awaitable.* = .{
        .promise_id = promise_id,
        .output = undefined,
        .callbacks = callbacks,
    };

    // call into JS, it will call us back upon completion
    startAwaiting(promise_id, &awaitable.output);
}
