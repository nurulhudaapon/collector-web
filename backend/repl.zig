const std = @import("std");
const assert = std.debug.assert;

const ushell = @import("ushell");

const Card = @import("Card.zig");
const Variant = Card.Variant;
const Owned = Variant.Owned;
const Omit = @import("utils.zig").Omit;
const database = @import("database.zig");
const fetch = @import("fetch.zig");

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{
            .scope = .db_migrate,
            .level = .warn,
        },
    },
};

// TODO: support context as part of usell
const Ctx = struct {
    allocator: std.mem.Allocator,
    user_id: u64,
};
var ctx: Ctx = undefined;

const ListOptions = struct {
    pokemon_name: ?[]const u8,
    mode: enum { all, missing },
};

fn list(session: *database.Session, shell: *Shell, options: ListOptions) !void {
    const cards = try Card.all(session, options.pokemon_name);
    if (cards.len == 0) {
        shell.applyStyle(.{ .foreground = .Yellow });
        shell.print("no cards in database", .{});
        return;
    }

    const owned = try database.findAll(Owned, session, .{
        .user_id = ctx.user_id,
    });

    for (cards) |card| {
        shell.print("{s} ({s}) | {s}\n", .{
            card.name,
            card.card_id,
            card.image_url,
        });

        const variants = try card.variants(session);
        if (variants.len == 0) {
            shell.print("  no variants info\n", .{});
            continue;
        }

        var all_owned = true;
        defer if (all_owned) shell.print("  complete\n", .{});

        for (variants) |variant| {
            const is_owned = blk: {
                for (owned) |own| {
                    if (own.variant_id == variant.id) {
                        break :blk true;
                    }
                }

                break :blk false;
            };

            if (is_owned and options.mode == .missing) continue;
            if (!is_owned) all_owned = false;

            // TODO: more info
            shell.print("  ", .{});

            defer shell.applyStyle(.{ .foreground = .Default });
            switch (options.mode) {
                .all => {
                    shell.applyStyle(.{ .foreground = if (is_owned) .Green else .Red });
                    shell.print("[{}]", .{variant.id});
                },
                .missing => {},
            }

            defer shell.print("\n", .{});

            shell.print("{s}", .{variant.type});

            if (variant.subtype) |subtype| {
                shell.print(" {s}", .{subtype});
            }

            if (variant.foil) |foil| {
                shell.print(" {s}", .{foil});
            }

            if (variant.size) |size| {
                if (!std.mem.eql(u8, "standard", size)) {
                    shell.print(" {s}", .{size});
                }
            }

            if (variant.stamps) |stamps| {
                for (stamps) |stamp| {
                    shell.print(" {s}", .{stamp});
                }
            }
        }
    }
}

const Command = union(enum) {
    add: struct {
        variant_id: u64,

        pub fn handle(args: @This(), shell: *Shell) !void {
            defer shell.applyStyle(.{ .foreground = .Default });

            var session = try database.getSession(ctx.allocator);
            defer session.deinit();

            const variant = try session.find(Variant, args.variant_id) orelse {
                shell.applyStyle(.{ .foreground = .Red });
                shell.print("variant {} does not exist", .{args.variant_id});
                return;
            };

            const data: Omit(Owned, "id") = .{
                .user_id = ctx.user_id,
                .variant_id = variant.id,
                .owned = true,
            };

            const in_db = try database.findOne(Owned, &session, .{
                .variant_id = variant.id,
                .user_id = ctx.user_id,
            });

            if (in_db) |row| {
                if (row.owned) {
                    shell.applyStyle(.{ .foreground = .Yellow });
                    shell.print("already owned\n", .{});
                    return;
                }

                try session.update(Owned, row.id, data);
            } else {
                _ = try session.insert(Owned, data);
            }

            shell.applyStyle(.{ .foreground = .Green });

            const card = try database.findOne(Card, &session, .{
                .card_id = variant.card_id,
            }) orelse return error.CardNotFound;

            shell.print("added {s} ({s}) - {s}\n", .{
                card.name,
                card.card_id,
                variant.type,
            });
        }
    },

    fetch: struct {
        pokemon_name: []const u8,

        pub fn handle(args: @This(), shell: *Shell) !void {
            const count = try fetch.run(ctx.allocator, args.pokemon_name);
            shell.print("collected {} cards", .{count});
        }
    },

    missing: struct {
        pokemon_name: ?[]const u8 = null,

        pub fn handle(args: @This(), shell: *Shell) !void {
            defer shell.applyStyle(.{ .foreground = .Default });

            var session = try database.getSession(ctx.allocator);
            defer session.deinit();

            try list(&session, shell, .{
                .pokemon_name = args.pokemon_name,
                .mode = .missing,
            });
        }
    },

    status: struct {
        pokemon_name: ?[]const u8 = null,

        pub fn handle(args: @This(), shell: *Shell) !void {
            defer shell.applyStyle(.{ .foreground = .Default });

            var session = try database.getSession(ctx.allocator);
            defer session.deinit();

            try list(&session, shell, .{
                .pokemon_name = args.pokemon_name,
                .mode = .all,
            });
        }
    },
};

const Shell = ushell.MakeShell(Command, .{
    .parser_options = .{
        .max_tokens = 15,
    },
    .max_history_size = 100,
    .prompt = "collector> ",
});

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    var args: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args.deinit();

    var buffer: [1]u8 = undefined;
    var stdin: std.fs.File.Reader = .init(.stdin(), &buffer);
    var stdout: std.fs.File.Writer = .init(.stdout(), &.{});

    ctx = .{
        .allocator = allocator,
        .user_id = 1,
    };

    var shell: Shell = .new(&stdin.interface, &stdout.interface);
    shell.loop();
}
