const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const allocator = common.allocator;
const newVM = common.newVM;

test "syntax errors carry filename, location and class" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(
        error.RubyException,
        vm.evalWithOptions("def broken(", .{ .filename = "syntax_case.rb" }),
    );
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "syntax_case.rb") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "syntax_case.rb:1") != null);
    try std.testing.expectEqualStrings("SyntaxError", vm.lastErrorClass().?);
}

test "syntax error reports the correct line in multiline source" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(
        error.RubyException,
        vm.evalWithOptions("\n\ndef broken(", .{ .filename = "multiline.rb" }),
    );
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "multiline.rb:3") != null);
}

test "runtime errors expose class and message" {
    var vm = try newVM();
    defer vm.deinit();

    const cases = .{
        .{ "raise \"boom\"", "RuntimeError", "boom" },
        .{ "raise ArgumentError, \"bad argument\"", "ArgumentError", "bad argument" },
        .{ "raise TypeError, \"bad type\"", "TypeError", "bad type" },
        .{ "1 / 0", "ZeroDivisionError", "divided by 0" },
        .{ "nil.not_a_method", "NoMethodError", "not_a_method" },
    };

    inline for (cases) |case| {
        try std.testing.expectError(error.RubyException, vm.eval(case[0]));
        const message = vm.lastError() orelse return error.TestUnexpectedResult;
        try std.testing.expect(std.mem.indexOf(u8, message, case[2]) != null);
        try std.testing.expectEqualStrings(case[1], vm.lastErrorClass().?);
    }
}

test "Ruby rescue prevents an exception from escaping" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval(
        \\begin
        \\  raise "handled"
        \\rescue => error
        \\  error.message
        \\ensure
        \\  $ensured = true
        \\end
    );
    const text = try value.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("handled", text);
    try std.testing.expect(vm.lastError() == null);

    const ensured = try vm.eval("$ensured");
    try std.testing.expect(ensured.truthy());
}

test "exception raised inside nested Ruby calls is captured" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval(
        \\def zruby_inner
        \\  raise "deep failure"
        \\end
        \\def zruby_outer
        \\  zruby_inner
        \\end
    );
    try std.testing.expectError(error.RubyException, vm.eval("zruby_outer"));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "deep failure") != null);
}

test "missing method and wrong arity from Value.call are errors" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval("def zruby_one_argument(a); a; end");
    const receiver = try vm.eval("self");

    try std.testing.expectError(error.RubyException, receiver.call("zruby_missing", &.{}));
    try std.testing.expectEqualStrings("NoMethodError", vm.lastErrorClass().?);

    try std.testing.expectError(error.RubyException, receiver.call("zruby_one_argument", &.{}));
    try std.testing.expectEqualStrings("ArgumentError", vm.lastErrorClass().?);
}

test "successful operations clear the previous diagnostic" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("raise \"first\""));
    try std.testing.expect(vm.lastError() != null);
    try std.testing.expect(vm.lastErrorClass() != null);

    const value = try vm.eval("40 + 2");
    try std.testing.expectEqual(@as(i64, 42), try value.asInt());
    try std.testing.expect(vm.lastError() == null);
    try std.testing.expect(vm.lastErrorClass() == null);
}

test "a later error replaces the previous diagnostic" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("raise \"first\""));
    try std.testing.expectError(error.RubyException, vm.eval("raise ArgumentError, \"second\""));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "second") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "first") == null);
    try std.testing.expectEqualStrings("ArgumentError", vm.lastErrorClass().?);
}

test "mutating frozen containers becomes RubyException" {
    var vm = try newVM();
    defer vm.deinit();

    const frozen_array = try vm.eval("[1].freeze");
    const frozen_hash = try vm.eval("{}.freeze");
    const value = try zruby.Value.fromInt(&vm, 2);
    const key = try zruby.Value.fromString(&vm, "key");

    try std.testing.expectError(error.RubyException, frozen_array.set(0, value));
    try std.testing.expectError(error.RubyException, frozen_hash.hashSet(key, value));
}

test "foreign values are rejected by mutation and lookup" {
    var first = try newVM();
    defer first.deinit();
    var second = try newVM();
    defer second.deinit();

    const array = try first.eval("[1]");
    const hash = try first.eval("{}");
    const foreign = try zruby.Value.fromString(&second, "foreign");

    try std.testing.expectError(error.InvalidType, array.set(0, foreign));
    try std.testing.expectError(error.InvalidType, hash.hashSet(foreign, foreign));
    try std.testing.expectError(error.InvalidType, hash.hashGet(foreign));

    const receiver = try first.eval("self");
    try std.testing.expectError(error.InvalidType, receiver.call("inspect", &.{foreign}));
}

test "Value.call missing method reports NoMethodError without crashing" {
    var vm = try newVM();
    defer vm.deinit();

    const receiver = try vm.eval("self");
    try std.testing.expectError(error.RubyException, receiver.call("definitely_missing", &.{}));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "definitely_missing") != null);
}

test "calling a method that requires a block without one is an error" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval("def zruby_needs_block; yield; end");
    const receiver = try vm.eval("self");
    try std.testing.expectError(error.RubyException, receiver.call("zruby_needs_block", &.{}));
    try std.testing.expectEqualStrings("LocalJumpError", vm.lastErrorClass().?);
    try std.testing.expect(std.mem.indexOf(u8, vm.lastError().?, "yield") != null);
}

test "lastException keeps the Ruby exception object alive" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("raise ArgumentError, \"kept\""));
    const exception = vm.lastException() orelse return error.TestUnexpectedResult;
    try std.testing.expect(exception.isException());
    const inspected = try exception.inspect();
    defer allocator.free(inspected);
    try std.testing.expect(std.mem.indexOf(u8, inspected, "ArgumentError") != null);
    try std.testing.expect(std.mem.indexOf(u8, inspected, "kept") != null);

    try std.testing.expectEqual(@as(i64, 1), try (try vm.eval("1")).asInt());
    try std.testing.expect(vm.lastException() == null);
}

test "lastBacktrace returns a bounded backtrace for runtime errors" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval(
        \\def zruby_trace_target
        \\  raise "trace me"
        \\end
    );
    try std.testing.expectError(error.RubyException, vm.eval("zruby_trace_target"));
    const backtrace = try vm.lastBacktrace(allocator) orelse return error.TestUnexpectedResult;
    defer allocator.free(backtrace);
    try std.testing.expect(backtrace.len > 0);
    try std.testing.expect(backtrace.len <= 4096);
    try std.testing.expect(std.mem.indexOf(u8, backtrace, "zruby_trace_target") != null);
}

test "syntax errors have no exception object" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("def broken("));
    try std.testing.expect(vm.lastException() == null);
    try std.testing.expect((try vm.lastBacktrace(allocator)) == null);
}
