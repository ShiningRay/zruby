const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const allocator = common.allocator;
const newVM = common.newVM;

test "ABI guard: mrb_value is pointer-sized" {
    try std.testing.expectEqual(@sizeOf(usize), zruby.c.zruby_value_size());
}

test "VM opens and closes" {
    var vm = try newVM();
    defer vm.deinit();
    try std.testing.expect(@intFromPtr(vm.raw) != 0);
}

test "eval integer arithmetic" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval("1 + 2 * 3");
    try std.testing.expect(value.isInteger());
    try std.testing.expectEqual(@as(i64, 7), try value.asInt());
}

test "eval string and unicode" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval("\"hello \" + \"世界\"");
    try std.testing.expect(value.isString());
    const text = try value.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello 世界", text);
}

test "eval float, bool and nil" {
    var vm = try newVM();
    defer vm.deinit();

    const pi = try vm.eval("3.25");
    try std.testing.expect(pi.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 3.25), try pi.asFloat(), 1e-9);

    const yes = try vm.eval("true");
    try std.testing.expect(yes.isTrue());
    try std.testing.expect(yes.truthy());

    const no = try vm.eval("false");
    try std.testing.expect(no.isFalse());
    try std.testing.expect(!no.truthy());

    const nothing = try vm.eval("nil");
    try std.testing.expect(nothing.isNil());
    try std.testing.expect(!nothing.truthy());
}

test "array access and mutation" {
    var vm = try newVM();
    defer vm.deinit();

    const array = try vm.eval("[10, 20, 30]");
    try std.testing.expect(array.isArray());
    try std.testing.expectEqual(@as(i64, 3), try array.arrayLen());
    try std.testing.expectEqual(@as(i64, 20), try (try array.get(1)).asInt());

    const forty = try zruby.Value.fromInt(&vm, 40);
    try array.set(1, forty);
    try std.testing.expectEqual(@as(i64, 40), try (try array.get(1)).asInt());
}

test "hash access and mutation" {
    var vm = try newVM();
    defer vm.deinit();

    const hash = try vm.eval("{ name: \"zruby\", stars: 5 }");
    try std.testing.expect(hash.isHash());

    const name_key = try zruby.Value.fromSymbol(&vm, "name");
    const name = try hash.hashGet(name_key);
    const text = try name.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("zruby", text);

    const stars_key = try zruby.Value.fromSymbol(&vm, "stars");
    try hash.hashSet(stars_key, try zruby.Value.fromInt(&vm, 6));
    try std.testing.expectEqual(@as(i64, 6), try (try hash.hashGet(stars_key)).asInt());
}

test "wide integer key round-trips through the hash" {
    var vm = try newVM();
    defer vm.deinit();

    const hash = try vm.eval("{}");
    const key = try zruby.Value.fromInt(&vm, 1 << 40);
    const value = try zruby.Value.fromString(&vm, "wide");
    try hash.hashSet(key, value);

    const lookup_key = try zruby.Value.fromInt(&vm, 1 << 40);
    const found = try hash.hashGet(lookup_key);
    const text = try found.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("wide", text);
}

test "call a Ruby method with arguments" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval(
        \\def zruby_add(a, b)
        \\  a + b
        \\end
    );
    const receiver = try vm.eval("self");
    const result = try receiver.call("zruby_add", &.{
        try zruby.Value.fromInt(&vm, 20),
        try zruby.Value.fromInt(&vm, 22),
    });
    try std.testing.expectEqual(@as(i64, 42), try result.asInt());
}

test "eval accepts a slice without a NUL sentinel" {
    var vm = try newVM();
    defer vm.deinit();

    var buffer: [5]u8 = .{ '1', '+', '3', 'x', 'x' };
    const value = try vm.eval(buffer[0..3]);
    try std.testing.expectEqual(@as(i64, 4), try value.asInt());
}

test "Ruby strings can contain NUL bytes" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try zruby.Value.fromString(&vm, "a\x00b");
    const text = try value.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8, "a\x00b", text);
}

test "eval rejects interior NUL bytes" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.InvalidSource, vm.eval("1\x00+2"));
}

test "defineClass and instance method work" {
    var vm = try newVM();
    defer vm.deinit();

    const point = try vm.defineClass("ZigPoint", vm.objectClass());
    try vm.defineMethod(point, "answer", &zigAnswer, zruby.args.none());

    const result = try vm.eval("ZigPoint.new.answer");
    try std.testing.expectEqual(@as(i64, 42), try result.asInt());
}

fn zigAnswer(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = mrb orelse unreachable;
    return zruby.c.zruby_int_value(state, 42);
}

test "register a Zig function as a Ruby module function" {
    var vm = try newVM();
    defer vm.deinit();

    const zig_module = try vm.defineModule("Zig");
    try vm.defineModuleFunction(zig_module, "square", &zigSquare, zruby.args.req(1));

    const result = try vm.eval("Zig.square(9)");
    try std.testing.expectEqual(@as(i64, 81), try result.asInt());
}

fn zigSquare(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = mrb orelse unreachable;
    var n: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "i", &n);
    return zruby.c.zruby_int_value(state, n * n);
}

test "Ruby exception is reported with message and class" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("raise ArgumentError, \"boom\""));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "boom") != null);
    const class_name = vm.lastErrorClass() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ArgumentError", class_name);
}

test "wrong Ruby argument count becomes RubyException" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval("def zruby_one_arg(a); a; end");
    const receiver = try vm.eval("self");
    try std.testing.expectError(
        error.RubyException,
        receiver.call("zruby_one_arg", &.{}),
    );
    try std.testing.expect(vm.lastError() != null);
}

test "exception raised inside a called method is caught" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval(
        \\def zruby_boom
        \\  raise "from method"
        \\end
    );
    const receiver = try vm.eval("self");
    try std.testing.expectError(error.RubyException, receiver.call("zruby_boom", &.{}));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "from method") != null);
}

test "division by zero is caught" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(error.RubyException, vm.eval("1 / 0"));
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "divided by 0") != null);
}

test "syntax error is caught and keeps filename" {
    var vm = try newVM();
    defer vm.deinit();

    try std.testing.expectError(
        error.RubyException,
        vm.evalWithOptions("def broken(", .{ .filename = "broken.rb" }),
    );
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "broken.rb") != null);
}

test "inspect returns a Ruby representation" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval("[1, 2]");
    const text = try value.inspect();
    defer allocator.free(text);
    try std.testing.expectEqualStrings("[1, 2]", text);
}

test "values from another VM are rejected" {
    var first = try newVM();
    defer first.deinit();
    var second = try newVM();
    defer second.deinit();

    const receiver = try first.eval("self");
    const arg = try zruby.Value.fromInt(&second, 1);
    try std.testing.expectError(error.InvalidType, receiver.call("inspect", &.{arg}));
}

test "invalid scalar conversion returns InvalidType" {
    var vm = try newVM();
    defer vm.deinit();

    const value = try vm.eval("\"not an int\"");
    try std.testing.expectError(error.InvalidType, value.asInt());
}

test "consecutive evaluations keep working" {
    var vm = try newVM();
    defer vm.deinit();

    var i: i64 = 0;
    while (i < 50) : (i += 1) {
        const value = try vm.eval("1 + 1");
        try std.testing.expectEqual(@as(i64, 2), try value.asInt());
    }
}

test {
    _ = @import("values.zig");
    _ = @import("lifecycle.zig");
    _ = @import("errors.zig");
    _ = @import("callbacks.zig");
    _ = @import("ruby_suites.zig");
}
