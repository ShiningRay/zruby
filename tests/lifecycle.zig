const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const allocator = common.allocator;
const newVM = common.newVM;

test "empty and comment-only source evaluate to nil" {
    var vm = try newVM();
    defer vm.deinit();

    const empty = try vm.eval("");
    try std.testing.expect(empty.isNil());

    const comment = try vm.eval("# only a comment\n");
    try std.testing.expect(comment.isNil());
}

test "source filename drives __FILE__" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.evalWithOptions("__FILE__", .{ .filename = "custom/path.rb" });
    const text = try value.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("custom/path.rb", text);
}

test "source filename also drives __LINE__" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.evalWithOptions("__LINE__", .{ .filename = "line.rb" });
    try std.testing.expectEqual(@as(i64, 1), try value.asInt());
}

test "CRLF and multiline source are accepted" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval("x = 1\r\ny = 2\r\nx + y");
    try std.testing.expectEqual(@as(i64, 3), try value.asInt());
}

test "multiple VMs keep definitions isolated" {
    var first = try newVM();
    defer first.deinit();
    var second = try newVM();
    defer second.deinit();

    _ = try first.eval("module OnlyInFirst; VALUE = 42; end");
    const first_defined = try first.eval("Object.const_defined?(:OnlyInFirst)");
    const second_defined = try second.eval("Object.const_defined?(:OnlyInFirst)");

    try std.testing.expect(first_defined.truthy());
    try std.testing.expect(!second_defined.truthy());
}

test "objectClass is usable as an explicit superclass" {
    var vm = try newVM();
    defer vm.deinit();

    const root = vm.objectClass();
    try std.testing.expect(@intFromPtr(root) != 0);

    const child = try vm.defineClass("ObjectChild", root);
    try std.testing.expect(@intFromPtr(child) != 0);

    const value = try vm.eval("ObjectChild.new.class == ObjectChild");
    try std.testing.expect(value.truthy());
}

test "defineClass over a non-class constant is a Ruby error" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval("Runner = 5");
    try std.testing.expectError(
        error.RubyException,
        vm.defineClass("Runner", vm.objectClass()),
    );
    try std.testing.expect(vm.lastError() != null);
}

test "defineModule over a non-module constant is a Ruby error" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval("Runner = 5");
    try std.testing.expectError(error.RubyException, vm.defineModule("Runner"));
    try std.testing.expect(vm.lastError() != null);
}

test "defining an existing module is allowed" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.defineModule("Enumerable");
    _ = try vm.defineModule("Enumerable");
}

test "large source exercises the heap eval path" {
    var vm = try newVM();
    defer vm.deinit();

    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    try source.appendSlice(allocator, "value = 0\n");
    for (0..1200) |_| {
        try source.appendSlice(allocator, "# padding line\n");
    }
    try source.appendSlice(allocator, "value + 42");

    const value = try vm.eval(source.items);
    try std.testing.expectEqual(@as(i64, 42), try value.asInt());
}

test "consecutive evaluations remain stable" {
    var vm = try newVM();
    defer vm.deinit();

    var i: usize = 0;
    while (i < 250) : (i += 1) {
        const value = try vm.eval("1 + 1");
        try std.testing.expectEqual(@as(i64, 2), try value.asInt());
    }
}

test "protected value survives GC churn" {
    var vm = try newVM();
    defer vm.deinit();

    const held = try vm.eval("\"held across GC\"");
    vm.protect(held);

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        _ = try vm.eval("100.times { Object.new }; GC.start");
    }

    const text = try held.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("held across GC", text);
}

test "protected value survives arena restoration" {
    var vm = try newVM();
    defer vm.deinit();

    const held = try vm.eval("\"arena-held\"");
    vm.protect(held);

    const mark = vm.arenaSave();
    _ = try vm.eval("[\"temporary\", 1, 2, 3]");
    vm.arenaRestore(mark);
    _ = try vm.eval("GC.start");

    const text = try held.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("arena-held", text);
}

test "VM deinit after an error does not leak Zig-owned diagnostics" {
    {
        var vm = try newVM();
        defer vm.deinit();
        try std.testing.expectError(error.RubyException, vm.eval("raise \"diagnostic\""));
    }
    {
        var vm = try newVM();
        defer vm.deinit();
        try std.testing.expectError(error.RubyException, vm.eval("def broken("));
    }
}

fn threadedEval() void {
    var vm = zruby.VM.init(std.heap.page_allocator) catch @panic("threaded VM init failed");
    defer vm.deinit();

    const value = vm.eval("x = 0; 100.times { x += 1 }; x") catch @panic("threaded eval failed");
    const result = value.asInt() catch @panic("threaded asInt failed");
    if (result != 100) @panic("threaded eval returned the wrong value");
}

test "separate VMs can run on separate threads" {
    const first = try std.Thread.spawn(.{}, threadedEval, .{});
    const second = try std.Thread.spawn(.{}, threadedEval, .{});
    first.join();
    second.join();
}
