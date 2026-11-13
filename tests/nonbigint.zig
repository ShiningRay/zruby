const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const newVM = common.newVM;

test "non-BigInt 64-bit builds keep wide integer hash keys" {
    var vm = try newVM();
    defer vm.deinit();

    const hash = try vm.eval("h = {}; h[1 << 40] = :found; h");
    const key = try zruby.Value.fromInt(&vm, 1 << 40);
    const found = try hash.hashGet(key);
    try std.testing.expect(found.isSymbol());
    const inspected = try found.inspect();
    defer std.testing.allocator.free(inspected);
    try std.testing.expectEqualStrings(":found", inspected);

    const wide = try zruby.Value.fromInt(&vm, std.math.maxInt(i64));
    try std.testing.expect(wide.isInteger());
    try std.testing.expectEqual(std.math.maxInt(i64), try wide.asInt());
}
