const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const newVM = common.newVM;

const bytecode = @embedFile("fixtures/bytecode.mrb");

test "loadIrep executes compiled mruby bytecode" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.loadIrep(bytecode);
    try std.testing.expectEqual(@as(i64, 42), try value.asInt());

    const method_value = try vm.eval("bytecode_answer");
    try std.testing.expectEqual(@as(i64, 42), try method_value.asInt());
}

test "loadIrepWithOptions keeps a filename for diagnostics" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.loadIrepWithOptions(bytecode, .{ .filename = "bytecode.rb" });
    try std.testing.expectEqual(@as(i64, 42), try value.asInt());
    try std.testing.expect(vm.lastError() == null);
}

test "loadIrep rejects empty and malformed bytecode without breaking the VM" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.InvalidSource, vm.loadIrep(&.{}));

    const malformed = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    try std.testing.expectError(error.RubyException, vm.loadIrep(&malformed));
    try std.testing.expect(vm.lastError() != null);
    try std.testing.expect(vm.lastErrorClass() != null);

    try std.testing.expectEqual(@as(i64, 2), try (try vm.eval("1 + 1")).asInt());
}

test "loadIrep can be called repeatedly" {
    var vm = try newVM();
    defer vm.deinit();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const value = try vm.loadIrep(bytecode);
        try std.testing.expectEqual(@as(i64, 42), try value.asInt());
    }
}
