const std = @import("std");

const zx = @import("zx");
const bom = zx.Client.bom;
const HTMLElement = bom.Document.HTMLElement;

pub fn getElementById(allocator: std.mem.Allocator, id: []const u8) ?HTMLElement {
    const document: bom.Document = .init(allocator);

    return document.getElementById(id) catch |err| switch (err) {
        error.ElementNotFound => null,
    };
}
