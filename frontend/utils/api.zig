const std = @import("std");
const assert = std.debug.assert;

const zx = @import("zx");
const js = zx.Client.js;

const utils = @import("../utils.zig");

// HACK: allow this code to compile (does nothing) on server side
const Value = if (utils.inClient())
    js.Value
else
    u0;

const Object = if (utils.inClient())
    js.Object
else
    struct { value: Value };

fn consoleLog(args: anytype) !void {
    const console: js.Object = try js.global.get(js.Object, "console");
    defer console.deinit();

    try console.call(void, "log", args);
}

fn zigToJs(allocator: std.mem.Allocator, zig: anytype) !js.Object {
    // allocate an empty JS object
    var object = try js.global.callAlloc(js.Object, allocator, "Object", .{});

    inline for (std.meta.fields(@TypeOf(zig))) |field| {
        const T = field.type;
        const field_value: T = @field(zig, field.name);

        const value: Value = switch (T) {
            []const u8 => .init(js.string(field_value)),
            else => switch (@typeInfo(T)) {
                .@"struct" => (try zigToJs(allocator, field_value)).value,
                else => .init(field_value),
            },
        };

        try object.set(field.name, value);
    }

    return object;
}

// TODO: support nested structs
fn jsToZig(comptime T: type, allocator: std.mem.Allocator, object: js.Object) !T {
    var zig: T = undefined;

    inline for (@typeInfo(T).@"struct".fields) |field| {
        const value = switch (field.type) {
            []const u8 => try object.getAlloc(js.String, allocator, field.name),
            bool => @compileError("dont use booleans"),
            else => |F| try object.get(F, field.name),
        };

        @field(zig, field.name) = value;
    }

    return zig;
}

/// Helper to parse input to an API (server)
pub fn getInput(comptime api: type, ctx: zx.PageContext) !std.json.Parsed(api.Input) {
    const text = ctx.request.text() orelse return error.EmptyRequest;
    return std.json.parseFromSlice(api.Input, ctx.arena, text, .{});
}

/// Helper to write an error (server)
pub fn writeError(ctx: zx.PageContext, err: anyerror) !void {
    const old_writer = ctx.response.writer() orelse return error.CantSendJson;
    var writer = old_writer.adaptToNewApi(&.{});

    ctx.response.setStatus(.internal_server_error);
    ctx.response.setContentType(.@"application/json");

    const fmt = std.json.fmt(.{
        .@"error" = @errorName(err),
    }, .{});
    try fmt.format(&writer.new_interface);
}

/// Helper to write the output for an API request (server)
pub fn writeOutput(comptime api: type, ctx: zx.PageContext, value: anyerror!api.Output) !void {
    const old_writer = ctx.response.writer() orelse return error.CantSendJson;
    var writer = old_writer.adaptToNewApi(&.{});

    const success = value catch |err| return writeError(ctx, err);

    ctx.response.setStatus(.ok);
    ctx.response.setContentType(.@"application/json");

    const fmt = std.json.fmt(success, .{});
    try fmt.format(&writer.new_interface);
}

const Awaiter = union(enum) {
    waiting,
    value: Object,
    reason: Object,
};

var awaiter: Awaiter = .waiting;

export fn fulfill(value: Value) void {
    awaiter.value = .{ .value = value };
}

export fn reject(reason: Value) void {
    awaiter.reason = .{ .value = reason };
}

/// Helper to call an api from client
pub fn execute(comptime api: type, allocator: std.mem.Allocator, url: []const u8, body: api.Input) !api.Output {
    if (!utils.inClient()) return error.NotInBrowser;

    const JSON = try js.global.get(js.Object, "JSON");
    defer JSON.deinit();

    const js_body = try zigToJs(allocator, body);
    defer js_body.deinit();

    const body_str: []const u8 = try JSON.callAlloc(
        js.String,
        allocator,
        "stringify",
        .{
            js_body,
        },
    );

    const options = try zigToJs(allocator, .{
        .method = @as([]const u8, "POST"),
        .body = body_str,
        .headers = .{
            .@"Content-Type" = @as([]const u8, "application/json"),
        },
    });
    defer options.deinit();

    const fetch = try js.global.callAlloc(
        js.Object,
        allocator,
        "fetch",
        .{
            js.string(url),
            options,
        },
    );
    defer fetch.deinit();
    assert(awaiter == .waiting);
    try fetch.call(void, "then", .{ fulfill, reject });

    // wait for `fetch` to finish
    const response = wait: while (true) {
        switch (awaiter) {
            .waiting => {},
            .value => |val| break :wait val,
            .reason => return error.FetchFailed, // TODO: handle better
        }
    };
    awaiter = .waiting;
    try consoleLog(.{ js.string("response:"), response });

    // FIXME: remove
    const clean: []const u8 = try response.callAlloc(
        js.String,
        allocator,
        "replace",
        .{
            js.string("<!DOCTYPE html>"),
            js.string(""),
        },
    );

    const json = try JSON.callAlloc(
        js.Object,
        allocator,
        "parse",
        .{
            js.string(clean),
        },
    );
    defer json.deinit();

    return jsToZig(api.Output, allocator, json);
}
