const std = @import("std");

const zx = @import("zx");
const js = zx.Client.js;

fn zigToJs(zig: anytype) !js.Object {
    var object: js.Value = .init(js.Object);

    inline for (std.meta.fields(@TypeOf(zig))) |field| {
        const T = field.type;
        const field_value = @field(zig, field.name);

        const value: js.Value = switch (T) {
            []const u8 => .init(js.string(field_value)),
            else => switch (@typeInfo(T)) {
                .@"struct" => (try zigToJs(field_value)).value,
                else => .init(field_value),
            },
        };

        try object.set(field.name, value);
    }

    return .{ .value = object };
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

/// Helper to call an api from client
pub fn call(comptime api: type, allocator: std.mem.Allocator, url: []const u8, body: api.Input) !api.Output {
    const options = try zigToJs(.{
        .method = js.string("POST"),
        .body = body,
        .headers = .{
            .@"Content-Type" = js.string("application/json"),
        },
    });

    const response: js.Object = try js.global.call(js.Object, "fetch", .{
        url,
        options,
    });

    const json: js.Object = try response.call(js.Object, "json", .{});
    return jsToZig(api.Output, allocator, json);
}
