const std = @import("std");
const builtin = @import("builtin");

const zx = @import("zx");

pub const api = @import("utils/api.zig");
pub const html = @import("utils/html.zig");
pub const routing = @import("utils/routing.zig");

// NOTE: **must** to be inline to work correctly if there are arch-specific types and whatnot
/// use in codepaths like
/// ```zig
/// if (!inClient()) return;
/// clientOnlyCode();
/// ```
pub inline fn inClient() bool {
    return builtin.os.tag == .freestanding and builtin.cpu.arch.isWasm();
}
