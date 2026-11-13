const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const allocator = common.allocator;
const newVM = common.newVM;

test "value type predicates and Ruby truthiness" {
    var vm = try newVM();
    defer vm.deinit();

    const nil_value = try vm.eval("nil");
    const true_value = try vm.eval("true");
    const false_value = try vm.eval("false");
    const zero = try vm.eval("0");
    const empty_string = try vm.eval("\"\"");
    const string_value = try vm.eval("\"hello\"");
    const integer_value = try vm.eval("42");
    const float_value = try vm.eval("1.5");
    const array_value = try vm.eval("[1, 2]");
    const hash_value = try vm.eval("{a: 1}");
    const symbol_value = try vm.eval(":alpha");

    try std.testing.expect(nil_value.isNil());
    try std.testing.expect(true_value.isTrue());
    try std.testing.expect(false_value.isFalse());
    try std.testing.expect(string_value.isString());
    try std.testing.expect(integer_value.isInteger());
    try std.testing.expect(float_value.isFloat());
    try std.testing.expect(array_value.isArray());
    try std.testing.expect(hash_value.isHash());
    try std.testing.expect(symbol_value.isSymbol());
    try std.testing.expect(!integer_value.isException());

    try std.testing.expect(!nil_value.truthy());
    try std.testing.expect(!false_value.truthy());
    try std.testing.expect(zero.truthy());
    try std.testing.expect(empty_string.truthy());
    try std.testing.expect(true_value.truthy());

    try std.testing.expect(zruby.Value.fromBool(&vm, true).isTrue());
    try std.testing.expect(zruby.Value.fromBool(&vm, false).isFalse());
    try std.testing.expect(zruby.Value.nilValue(&vm).isNil());
}

test "integer boundaries and wide values" {
    var vm = try newVM();
    defer vm.deinit();

    const values = [_]i64{
        0,
        1,
        -1,
        1 << 30,
        -(1 << 30),
        1 << 40,
        std.math.maxInt(i64),
        std.math.minInt(i64),
    };
    for (values) |expected| {
        const value = try zruby.Value.fromInt(&vm, expected);
        try std.testing.expect(value.isInteger());
        try std.testing.expectEqual(expected, try value.asInt());
    }

    try std.testing.expectError(error.InvalidType, (try vm.eval("\"42\"")).asInt());
    try std.testing.expectError(error.InvalidType, (try vm.eval("42")).asFloat());
}

test "float values include infinities and NaN" {
    var vm = try newVM();
    defer vm.deinit();

    const normal = try zruby.Value.fromFloat(&vm, 2.5);
    try std.testing.expect(normal.isFloat());
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), try normal.asFloat(), 1e-12);

    const infinity = try zruby.Value.fromFloat(&vm, std.math.inf(f64));
    try std.testing.expect(std.math.isInf(try infinity.asFloat()));

    const negative_infinity = try zruby.Value.fromFloat(&vm, -std.math.inf(f64));
    const negative_value = try negative_infinity.asFloat();
    try std.testing.expect(std.math.isInf(negative_value));
    try std.testing.expect(negative_value < 0);

    const nan = try zruby.Value.fromFloat(&vm, std.math.nan(f64));
    try std.testing.expect(std.math.isNan(try nan.asFloat()));

    const evaluated_infinity = try vm.eval("1.0 / 0.0");
    try std.testing.expect(std.math.isInf(try evaluated_infinity.asFloat()));
}

test "strings preserve bytes, NUL and long payloads" {
    var vm = try newVM();
    defer vm.deinit();

    const empty = try zruby.Value.fromString(&vm, "");
    try std.testing.expect(empty.isString());
    const empty_text = try empty.toString(allocator);
    defer allocator.free(empty_text);
    try std.testing.expectEqual(@as(usize, 0), empty_text.len);

    const nul_string = try zruby.Value.fromString(&vm, "a\x00b");
    const nul_text = try nul_string.toString(allocator);
    defer allocator.free(nul_text);
    try std.testing.expectEqualSlices(u8, "a\x00b", nul_text);

    const invalid_utf8 = try zruby.Value.fromString(&vm, "\xff\xfeA");
    const invalid_text = try invalid_utf8.toString(allocator);
    defer allocator.free(invalid_text);
    try std.testing.expectEqualSlices(u8, "\xff\xfeA", invalid_text);

    var long: [8192]u8 = undefined;
    @memset(long[0..7000], 'z');
    const long_value = try zruby.Value.fromString(&vm, long[0..7000]);
    const long_text = try long_value.toString(allocator);
    defer allocator.free(long_text);
    try std.testing.expectEqual(@as(usize, 7000), long_text.len);

    const unicode = try zruby.Value.fromString(&vm, "Zig 世界 🚀");
    const unicode_text = try unicode.toString(allocator);
    defer allocator.free(unicode_text);
    try std.testing.expectEqualStrings("Zig 世界 🚀", unicode_text);

    try std.testing.expectError(error.InvalidType, (try vm.eval("1")).toString(allocator));
}

test "symbols round-trip and work as hash keys" {
    var vm = try newVM();
    defer vm.deinit();

    const symbol = try zruby.Value.fromSymbol(&vm, "alpha");
    try std.testing.expect(symbol.isSymbol());
    const symbol_text = try symbol.inspect();
    defer allocator.free(symbol_text);
    try std.testing.expectEqualStrings(":alpha", symbol_text);

    const hash = try vm.eval("{ alpha: 42 }");
    const value = try hash.hashGet(symbol);
    try std.testing.expectEqual(@as(i64, 42), try value.asInt());
}

test "inspect covers scalar, string, symbol and container values" {
    var vm = try newVM();
    defer vm.deinit();

    const cases = .{
        .{ "nil", "nil" },
        .{ "true", "true" },
        .{ "false", "false" },
        .{ "42", "42" },
        .{ "1.5", "1.5" },
        .{ "\"x\"", "\"x\"" },
        .{ ":foo", ":foo" },
        .{ "[1, 2]", "[1, 2]" },
        .{ "{a: 1}", "{a: 1}" },
        .{ "\"a\\nb\"", "\"a\\nb\"" },
    };
    inline for (cases) |case| {
        const value = try vm.eval(case[0]);
        const inspected = try value.inspect();
        defer allocator.free(inspected);
        try std.testing.expectEqualStrings(case[1], inspected);
    }
}

test "array indexing, mutation and extension" {
    var vm = try newVM();
    defer vm.deinit();

    const array = try vm.eval("[10, 20, 30]");
    try std.testing.expectEqual(@as(i64, 3), try array.arrayLen());
    try std.testing.expectEqual(@as(i64, 10), try (try array.get(0)).asInt());
    try std.testing.expectEqual(@as(i64, 30), try (try array.get(-1)).asInt());
    try std.testing.expect((try array.get(99)).isNil());

    try array.set(1, try zruby.Value.fromInt(&vm, 40));
    try std.testing.expectEqual(@as(i64, 40), try (try array.get(1)).asInt());

    try array.set(5, try zruby.Value.fromInt(&vm, 50));
    try std.testing.expectEqual(@as(i64, 6), try array.arrayLen());
    try std.testing.expect((try array.get(4)).isNil());
    try std.testing.expectEqual(@as(i64, 50), try (try array.get(5)).asInt());
}

test "hash keys, missing values and mutation" {
    var vm = try newVM();
    defer vm.deinit();

    const hash = try vm.eval("{\"a\" => 1, :b => 2, 1099511627776 => 3}");
    try std.testing.expectEqual(@as(i64, 3), try hash.arrayLen());

    const a = try hash.hashGet(try zruby.Value.fromString(&vm, "a"));
    try std.testing.expectEqual(@as(i64, 1), try a.asInt());

    const b = try hash.hashGet(try zruby.Value.fromSymbol(&vm, "b"));
    try std.testing.expectEqual(@as(i64, 2), try b.asInt());

    const wide = try hash.hashGet(try zruby.Value.fromInt(&vm, 1 << 40));
    try std.testing.expectEqual(@as(i64, 3), try wide.asInt());

    const missing = try hash.hashGet(try zruby.Value.fromString(&vm, "missing"));
    try std.testing.expect(missing.isNil());

    try hash.hashSet(try zruby.Value.fromString(&vm, "c"), try zruby.Value.fromInt(&vm, 4));
    try std.testing.expectEqual(@as(i64, 4), try (try hash.hashGet(try zruby.Value.fromString(&vm, "c"))).asInt());
    try std.testing.expectEqual(@as(i64, 4), try hash.arrayLen());

    try hash.hashSet(try zruby.Value.fromString(&vm, "nil"), zruby.Value.nilValue(&vm));
    try std.testing.expect((try hash.hashGet(try zruby.Value.fromString(&vm, "nil"))).isNil());
}

test "exception values are inspectable and typed" {
    var vm = try newVM();
    defer vm.deinit();

    const exception = try vm.eval(
        \\begin
        \\  raise "inspect me"
        \\rescue => error
        \\  error
        \\end
    );
    try std.testing.expect(exception.isException());
    const inspected = try exception.inspect();
    defer allocator.free(inspected);
    try std.testing.expect(std.mem.indexOf(u8, inspected, "RuntimeError") != null);
    try std.testing.expect(std.mem.indexOf(u8, inspected, "inspect me") != null);
}

test "Value.call returns nil, booleans, strings and floats" {
    var vm = try newVM();
    defer vm.deinit();

    _ = try vm.eval(
        \\def zruby_call_nil; nil; end
        \\def zruby_call_true; true; end
        \\def zruby_call_false; false; end
        \\def zruby_call_string; "called"; end
        \\def zruby_call_float; 2.5; end
        \\def zruby_call_echo(value); value; end
        \\def zruby_call_truthy?; true; end
    );
    const receiver = try vm.eval("self");

    try std.testing.expect((try receiver.call("zruby_call_nil", &.{})).isNil());
    try std.testing.expect((try receiver.call("zruby_call_true", &.{})).isTrue());
    try std.testing.expect((try receiver.call("zruby_call_false", &.{})).isFalse());
    try std.testing.expect((try receiver.call("zruby_call_truthy?", &.{})).truthy());

    const string_value = try receiver.call("zruby_call_string", &.{});
    const string_text = try string_value.toString(allocator);
    defer allocator.free(string_text);
    try std.testing.expectEqualStrings("called", string_text);

    const float_value = try receiver.call("zruby_call_float", &.{});
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), try float_value.asFloat(), 1e-12);

    const echoed = try receiver.call("zruby_call_echo", &.{try zruby.Value.fromString(&vm, "echo")});
    const echoed_text = try echoed.toString(allocator);
    defer allocator.free(echoed_text);
    try std.testing.expectEqualStrings("echo", echoed_text);

    const one = try zruby.Value.fromInt(&vm, 1);
    const two = try zruby.Value.fromInt(&vm, 2);
    const sum = try one.call("+", &.{two});
    try std.testing.expectEqual(@as(i64, 3), try sum.asInt());
}

test "larger arrays and hashes remain consistent" {
    var vm = try newVM();
    defer vm.deinit();

    const array = try vm.eval("(1..1000).to_a");
    try std.testing.expectEqual(@as(i64, 1000), try array.arrayLen());
    try std.testing.expectEqual(@as(i64, 1000), try (try array.get(999)).asInt());

    const hash = try vm.eval("h = {}; 200.times { |i| h[i] = i * 2 }; h");
    try std.testing.expectEqual(@as(i64, 200), try hash.arrayLen());
    const key = try zruby.Value.fromInt(&vm, 150);
    try std.testing.expectEqual(@as(i64, 300), try (try hash.hashGet(key)).asInt());
}

test "Value.call supports more than eight arguments" {
    var vm = try newVM();
    defer vm.deinit();

    const lambda = try vm.eval(
        "->(a, b, c, d, e, f, g, h, i) { a + b + c + d + e + f + g + h + i }",
    );
    const args = [_]zruby.Value{
        try zruby.Value.fromInt(&vm, 1),
        try zruby.Value.fromInt(&vm, 2),
        try zruby.Value.fromInt(&vm, 3),
        try zruby.Value.fromInt(&vm, 4),
        try zruby.Value.fromInt(&vm, 5),
        try zruby.Value.fromInt(&vm, 6),
        try zruby.Value.fromInt(&vm, 7),
        try zruby.Value.fromInt(&vm, 8),
        try zruby.Value.fromInt(&vm, 9),
    };
    const result = try lambda.call("call", &args);
    try std.testing.expectEqual(@as(i64, 45), try result.asInt());
}
