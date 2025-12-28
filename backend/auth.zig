//! Basic authorization utilities
//!
//! Likely not secure in the slightest :)

const std = @import("std");
const Allocator = std.mem.Allocator;

const database = @import("database.zig");

const zx = @import("zx");

const salt_len = 8;
const hashed_len = 128;
const token_len = 32;

const cookie_name = "auth-token";

const UserId = u64;

const User = struct {
    id: UserId,
    username: []const u8,
};

const Token = struct {
    id: UserId,
    value: []const u8,
};

const Secret = struct {
    id: UserId,
    salt: []const u8,
    hashed_password: []const u8,
};

fn hash(password: []const u8, salt: []const u8) ![hashed_len]u8 {
    var key: [hashed_len]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, password, salt, 10, std.crypto.auth.hmac.sha2.HmacSha256);
    return key;
}

fn randomSlice(allocator: Allocator, len: usize) ![]const u8 {
    const slice = try allocator.alloc(u8, len);
    for (slice) |*c| {
        c.* = std.crypto.random.intRangeAtMost(u8, '0', 'z');
    }
    return slice;
}

fn createTokenFor(allocator: Allocator, session: *database.Session, user_id: u64) ![]const u8 {
    const value = try randomSlice(allocator, token_len);

    // remove existing
    if (try session.find(Token, user_id)) |_| {
        try session.delete(Token, user_id);
    }

    const token = try session.create(Token, .{
        .id = user_id,
        .value = value,
    });

    return token.value;
}

pub fn signin(allocator: Allocator, username: []const u8, password: []const u8) ![]const u8 {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const user_id = session.insert(User, .{
        .username = username,
    }) catch |err| switch (err) {
        error.UniqueViolation => return error.UsernameNotAvailable,
        else => return err,
    };
    errdefer session.delete(
        User,
        user_id,
    ) catch |e| std.log.err("{t}", .{e});

    const salt = try randomSlice(allocator, salt_len);
    const hashed = try hash(password, salt);

    const secret_id = try session.insert(Secret, .{
        .id = user_id,
        .salt = salt,
        .hashed_password = &hashed,
    });
    errdefer session.delete(
        Secret,
        secret_id,
    ) catch |e| std.log.err("{t}", .{e});

    return createTokenFor(allocator, &session, user_id);
}

pub fn login(allocator: Allocator, username: []const u8, password: []const u8) ![]const u8 {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const user = try session.query(User).where(
        "username",
        username,
    ).findFirst() orelse return error.UserNotFound;

    const secret = try session.find(Secret, user.id) orelse return error.SecretNotFound;

    const hashed = hash(
        password,
        secret.salt,
    ) catch |e| std.debug.panic("unreachable?: {}", .{e});

    if (!std.mem.eql(u8, &hashed, secret.hashed_password)) return error.InvalidCredentials;

    return createTokenFor(allocator, &session, user.id);
}

pub fn logout(allocator: Allocator, token: []const u8) !void {
    var session = try database.getSession(allocator);
    defer session.deinit();

    try session.query(Token).where("value", token).delete().exec();
}

pub fn getUser(allocator: Allocator, token_value: []const u8) !?User {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const token = try session.query(Token).findBy(
        "value",
        token_value,
    ) orelse return error.InvalidToken;

    return session.find(User, token.id);
}

pub fn getCookie(ctx: zx.PageContext) ?[]const u8 {
    return ctx.request.cookies().get(cookie_name);
}

pub fn setCookie(ctx: zx.PageContext, token: []const u8) !void {
    return ctx.response.setCookie(cookie_name, token, .{
        .max_age = 3600,
        .secure = true,
        .same_site = .strict,
    });
}

pub fn rmCookie(ctx: zx.PageContext) !void {
    return ctx.response.setCookie(cookie_name, "", .{
        .max_age = 1,
    });
}
