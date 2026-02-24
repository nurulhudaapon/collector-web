//! Basic authorization utilities
//!
//! Likely not secure in the slightest :)

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.auth);

const database = @import("database.zig");

const User = @This();

const salt_len = 8;
const hashed_len = 128;
const token_len = 32;

id: database.Id,
username: []const u8,

pub const AuthArgs = struct {
    username: []const u8,
    password: []const u8,
};

pub const AuthResponse = struct {
    user: User,
    token: []const u8,

    pub fn init(
        allocator: Allocator,
        session: *database.Session,
        user_id: database.Id,
        username: []const u8,
    ) !AuthResponse {
        return .{
            .user = .{
                .id = user_id,
                .username = username,
            },
            .token = try createTokenFor(
                allocator,
                session,
                user_id,
            ),
        };
    }
};

const Token = struct {
    id: database.Id,
    user_id: database.Id,
    value: []const u8,
};

const Secret = struct {
    id: database.Id,
    salt: []const u8,
    hashed_password: []const u8,
};

fn hash(password: []const u8, salt: []const u8) ![hashed_len]u8 {
    var key: [hashed_len]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, password, salt, 10, std.crypto.auth.hmac.sha2.HmacSha256);
    return key;
}

fn randomSlice(allocator: Allocator, len: usize) ![]const u8 {
    const options = std.ascii.letters;

    const slice = try allocator.alloc(u8, len);
    for (slice) |*char| {
        const index = std.crypto.random.uintLessThan(u8, options.len);
        char.* = options[index];
    }
    return slice;
}

fn createTokenFor(
    allocator: Allocator,
    session: *database.Session,
    user_id: database.Id,
) ![]const u8 {
    const value = try randomSlice(allocator, token_len);

    const maybe_row = try session
        .query(Token)
        .where("user_id", user_id)
        .findFirst();

    if (maybe_row) |row| {
        try session.update(Token, row.id, .{
            .value = value,
        });
    } else {
        _ = try session.insert(Token, .{
            .user_id = user_id,
            .value = value,
        });
    }

    return value;
}

pub fn register(session: *database.Session, args: AuthArgs) !AuthResponse {
    const allocator = session.arena;

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

    return .init(allocator, session, user_id, args.username);
}

pub fn login(session: *database.Session, args: AuthArgs) !AuthResponse {
    const allocator = session.arena;

    const user = try session
        .query(User)
        .findBy("username", args.username) orelse return error.UserNotFound;

    const secret = try session.find(Secret, user.id) orelse return error.SecretNotFound;

    const hashed = hash(
        args.password,
        secret.salt,
    ) catch |err| {
        log.err("couldn't hash password & salt  ({})", .{err});
        return err;
    };

    if (!std.mem.eql(u8, &hashed, secret.hashed_password)) return error.InvalidCredentials;

    return .init(allocator, session, user.id, user.username);
}

pub fn logout(self: *const User, session: *database.Session) !void {
    try session
        .query(Token)
        .where("user_id", self.id)
        .delete()
        .exec();
}

pub fn get(session: *database.Session, token_value: []const u8) !?User {
    const token = try session.query(Token).findBy(
        "value",
        token_value,
    ) orelse return null;

    return session.find(User, token.user_id);
}

const UserTracking = struct {
    species: []const database.Tracked,
    cards: []const database.Card,
};

pub fn getTracked(self: *const User, session: *database.Session) !UserTracking {
    const species = try session
        .query(database.Tracked)
        .where("user_id", self.id)
        .where("tracked", true)
        .findAll();

    if (species.len == 0) {
        return .{
            .species = &.{},
            .cards = &.{},
        };
    }

    var query = session.query(database.Card);
    for (species) |tracked| {
        const wildcard = try std.fmt.allocPrint(session.arena, "%{c}{}{c}%", .{
            database.Card.DexIds.separator,
            tracked.species_dex,
            database.Card.DexIds.separator,
        });

        query = query.orWhereRaw("dex_ids LIKE ?", .{wildcard});
    }

    return .{
        .species = species,
        .cards = try query.findAll(),
    };
}

pub fn isTracking(self: *const User, session: *database.Session, species: database.Species) !bool {
    const tracked = try session
        .query(database.Tracked)
        .where("user_id", self.id)
        .where("species_dex", species.pokedex)
        .findFirst() orelse return false;

    return tracked.tracked;
}
