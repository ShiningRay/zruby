const std = @import("std");
const zruby = @import("zruby");

pub const allocator = std.testing.allocator;

pub fn newVM() !zruby.VM {
    return zruby.VM.init(allocator);
}
