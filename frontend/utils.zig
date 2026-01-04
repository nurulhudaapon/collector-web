const std = @import("std");
const builtin = @import("builtin");

const zx = @import("zx");

pub const api = @import("utils/api.zig");
pub const html = @import("utils/html.zig");
pub const routing = @import("utils/routing.zig");

// for functions that can only be Client-Side-Rendered
pub inline fn csr(src: std.builtin.SourceLocation) void {
    if (builtin.os.tag != .freestanding) {
        std.debug.panic("{s}:{} function '{s}' is intended for CSR", .{
            src.file,
            src.line,
            src.fn_name,
        });
    }
}

// TODO: add ssr()?
