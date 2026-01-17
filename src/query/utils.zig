const std = @import("std");

pub fn compCamelToSnakeCase(comptime camel: [:0]const u8) [:0]const u8 {
    var buf: [camel.len * 2:0]u8 = undefined;
    var i = 0;
    for (camel) |c| {
        if (std.ascii.isUpper(c)) {
            if (i != 0) {
                buf[i] = '_';
                i += 1;
            }
            buf[i] = std.ascii.toLower(c);
        } else {
            buf[i] = c;
        }
        i += 1;
    }
    buf[i] = 0;
    const final = buf;
    return final[0..i :0];
}

pub fn getCanonicalQueryType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |p| getCanonicalQueryType(p.child),
        .optional => |o| getCanonicalQueryType(o.child),
        else => T,
    };
}
