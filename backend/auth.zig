//! Basic authorization utilities
//!
//! Likely not secure in the slightest :)

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.auth);

const api = @import("api");

const database = @import("database.zig");

const salt_len = 8;
const hashed_len = 128;
const token_len = 32;

const UserId = u64;

pub const User = struct {
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

pub fn signin(allocator: Allocator, args: api.signin.Args) !api.signin.Response {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const user_id = session.insert(User, .{
        .username = args.username,
    }) catch |err| switch (err) {
        error.UniqueViolation => return error.UsernameNotAvailable,
        else => return err,
    };
    errdefer session.delete(
        User,
        user_id,
    ) catch |err| {
        log.err("couldn't delete user, database corrupted ({t})", .{err});
    };

    const salt = try randomSlice(allocator, salt_len);
    const hashed = hash(
        args.password,
        salt,
    ) catch |err| {
        log.err("couldn't hash password & salt  ({})", .{err});
        return err;
    };

    const secret_id = try session.insert(Secret, .{
        .id = user_id,
        .salt = salt,
        .hashed_password = &hashed,
    });
    errdefer session.delete(
        Secret,
        secret_id,
    ) catch |err| {
        log.err("couldn't delete secret  ({})", .{err});
    };

    return .{
        .username = args.username,
        .token = try createTokenFor(
            allocator,
            &session,
            user_id,
        ),
    };
}

pub fn login(allocator: Allocator, args: api.login.Args) !api.login.Response {
    var session = try database.getSession(allocator);
    defer session.deinit();

    const user = try session.query(User).where(
        "username",
        args.username,
    ).findFirst() orelse return error.UserNotFound;

    const secret = try session.find(Secret, user.id) orelse return error.SecretNotFound;

    const hashed = hash(
        args.password,
        secret.salt,
    ) catch |err| {
        log.err("couldn't hash password & salt  ({})", .{err});
        return err;
    };

    if (!std.mem.eql(u8, &hashed, secret.hashed_password)) return error.InvalidCredentials;

    return .{
        .username = args.username,
        .token = try createTokenFor(
            allocator,
            &session,
            user.id,
        ),
    };
}

pub fn logout(allocator: Allocator, args: api.logout.Args) !api.logout.Response {
    var session = try database.getSession(allocator);
    defer session.deinit();

    try session.query(Token).where("value", args.token).delete().exec();

    return .{
        .ok = 1,
    };
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
