const std = @import("std");

pub fn Omit(comptime T: type, comptime field: std.meta.FieldEnum(T)) type {
    const info = @typeInfo(T).@"struct";

    var fields: [info.fields.len - 1]std.builtin.Type.StructField = undefined;

    var i: usize = 0;
    for (info.fields) |struct_field| {
        if (std.mem.eql(u8, @tagName(field), struct_field.name)) {
            continue;
        }

        defer i += 1;
        fields[i] = struct_field;
    }

    var fixed = info;
    fixed.decls = &.{};
    fixed.fields = fields[0..i];

    return @Type(.{ .@"struct" = fixed });
}
