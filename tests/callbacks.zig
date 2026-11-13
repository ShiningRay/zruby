const std = @import("std");
const zruby = @import("zruby");
const common = @import("common.zig");

const allocator = common.allocator;
const newVM = common.newVM;

fn stateOf(mrb: ?*zruby.c.mrb_state) *zruby.c.mrb_state {
    return mrb orelse unreachable;
}

fn cstrLen(ptr: [*c]const u8) i64 {
    if (ptr == null) return 0;
    const sentinel: [*:0]const u8 = @ptrCast(ptr);
    return @intCast(std.mem.len(sentinel));
}

fn zigNoArgs(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    return zruby.c.zruby_int_value(stateOf(mrb), 42);
}

fn zigSeven(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    return zruby.c.zruby_int_value(stateOf(mrb), 7);
}

fn zigAdd(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var a: zruby.c.mrb_int = 0;
    var b: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "ii", &a, &b);
    return zruby.c.zruby_int_value(state, a + b);
}

fn zigConcatLen(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var a: [*c]const u8 = null;
    var b: [*c]const u8 = null;
    _ = zruby.c.mrb_get_args(state, "zz", &a, &b);
    return zruby.c.zruby_int_value(state, cstrLen(a) + cstrLen(b));
}

fn zigEchoS(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_value = undefined;
    _ = zruby.c.mrb_get_args(state, "S", &value);
    return value;
}

fn zigEchoO(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_value = undefined;
    _ = zruby.c.mrb_get_args(state, "o", &value);
    return value;
}

fn zigArrayLength(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var values: [*c]const zruby.c.mrb_value = null;
    var length: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "a", &values, &length);
    return zruby.c.zruby_int_value(state, length);
}

fn zigHashEcho(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_value = undefined;
    _ = zruby.c.mrb_get_args(state, "H", &value);
    return value;
}

fn zigNot(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_bool = false;
    _ = zruby.c.mrb_get_args(state, "b", &value);
    return zruby.c.zruby_bool_value(state, !value);
}

fn zigHalf(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_float = 0;
    _ = zruby.c.mrb_get_args(state, "f", &value);
    return zruby.c.zruby_float_value(state, value / 2.0);
}

fn zigSymbol(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var symbol: zruby.c.mrb_sym = 0;
    _ = zruby.c.mrb_get_args(state, "n", &symbol);
    return zruby.c.zruby_symbol_value(state, symbol);
}

fn zigOptional(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var a: zruby.c.mrb_int = 0;
    var b: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "i|i", &a, &b);
    return zruby.c.zruby_int_value(state, a + b);
}

fn zigRest(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var values: [*c]const zruby.c.mrb_value = null;
    var count: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "*", &values, &count);
    return zruby.c.zruby_int_value(state, count);
}

fn zigString(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    const text = "zig";
    return zruby.c.mrb_str_new(state, text.ptr, text.len);
}

fn zigNil(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    _ = mrb;
    return zruby.c.zruby_nil_value();
}

fn zigTrue(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    _ = mrb;
    return zruby.c.zruby_true_value();
}

fn zigRequireInt(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = self;
    const state = stateOf(mrb);
    var value: zruby.c.mrb_int = 0;
    _ = zruby.c.mrb_get_args(state, "i", &value);
    return zruby.c.zruby_int_value(state, value);
}

fn zigIdentity(mrb: ?*zruby.c.mrb_state, self: zruby.c.mrb_value) callconv(.c) zruby.c.mrb_value {
    _ = mrb;
    return self;
}

fn register(vm: *zruby.VM) !void {
    const module = try vm.defineModule("ZigTest");
    try vm.defineModuleFunction(module, "noArgs", &zigNoArgs, zruby.args.none());
    try vm.defineModuleFunction(module, "add", &zigAdd, zruby.args.req(2));
    try vm.defineModuleFunction(module, "concatLen", &zigConcatLen, zruby.args.req(2));
    try vm.defineModuleFunction(module, "echoS", &zigEchoS, zruby.args.req(1));
    try vm.defineModuleFunction(module, "echoO", &zigEchoO, zruby.args.req(1));
    try vm.defineModuleFunction(module, "arrayLength", &zigArrayLength, zruby.args.req(1));
    try vm.defineModuleFunction(module, "hashEcho", &zigHashEcho, zruby.args.req(1));
    try vm.defineModuleFunction(module, "not", &zigNot, zruby.args.req(1));
    try vm.defineModuleFunction(module, "half", &zigHalf, zruby.args.req(1));
    try vm.defineModuleFunction(module, "symbol", &zigSymbol, zruby.args.req(1));
    try vm.defineModuleFunction(
        module,
        "optional",
        &zigOptional,
        zruby.args.req(1) | zruby.args.opt(1),
    );
    try vm.defineModuleFunction(module, "rest", &zigRest, zruby.args.rest());
    try vm.defineModuleFunction(module, "string", &zigString, zruby.args.none());
    try vm.defineModuleFunction(module, "nilValue", &zigNil, zruby.args.none());
    try vm.defineModuleFunction(module, "trueValue", &zigTrue, zruby.args.none());
    try vm.defineModuleFunction(module, "requireInt", &zigRequireInt, zruby.args.req(1));

    const class = try vm.defineClass("ZigObject", vm.objectClass());
    try vm.defineMethod(class, "identity", &zigIdentity, zruby.args.none());
    try vm.defineMethod(class, "answer", &zigNoArgs, zruby.args.none());
    try vm.defineClassMethod(class, "version", &zigString, zruby.args.none());
    try vm.defineMethod(class, "seven", &zigSeven, zruby.args.none());
}

test "module functions cover scalar, string, symbol and object marshalling" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigTest.noArgs")).asInt());
    try std.testing.expectEqual(@as(i64, 5), try (try vm.eval("ZigTest.add(2, 3)")).asInt());
    try std.testing.expectEqual(@as(i64, 5), try (try vm.eval("ZigTest.concatLen(\"ab\", \"cde\")")).asInt());
    try std.testing.expectEqual(@as(f64, 2.5), try (try vm.eval("ZigTest.half(5.0)")).asFloat());

    const echoed_string = try vm.eval("ZigTest.echoS(\"hello\")");
    const echoed_text = try echoed_string.toString(allocator);
    defer allocator.free(echoed_text);
    try std.testing.expectEqualStrings("hello", echoed_text);

    const echoed_array = try vm.eval("ZigTest.echoO([1, 2, 3])");
    try std.testing.expect(echoed_array.isArray());
    try std.testing.expectEqual(@as(i64, 3), try echoed_array.arrayLen());

    try std.testing.expectEqual(@as(i64, 3), try (try vm.eval("ZigTest.arrayLength([1, 2, 3])")).asInt());
    const echoed_hash = try vm.eval("ZigTest.hashEcho({a: 1})");
    try std.testing.expect(echoed_hash.isHash());
    try std.testing.expectEqual(
        @as(i64, 1),
        try (try echoed_hash.hashGet(try zruby.Value.fromSymbol(&vm, "a"))).asInt(),
    );

    try std.testing.expect((try vm.eval("ZigTest.not(true)")).isFalse());
    try std.testing.expect((try vm.eval("ZigTest.not(false)")).isTrue());

    const symbol = try vm.eval("ZigTest.symbol(:alpha)");
    try std.testing.expect(symbol.isSymbol());
    const symbol_text = try symbol.inspect();
    defer allocator.free(symbol_text);
    try std.testing.expectEqualStrings(":alpha", symbol_text);

    const string = try vm.eval("ZigTest.string");
    const text = try string.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("zig", text);

    try std.testing.expect((try vm.eval("ZigTest.nilValue")).isNil());
    try std.testing.expect((try vm.eval("ZigTest.trueValue")).isTrue());
}

test "optional and rest argument specs work" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    try std.testing.expectEqual(@as(i64, 5), try (try vm.eval("ZigTest.optional(5)")).asInt());
    try std.testing.expectEqual(@as(i64, 11), try (try vm.eval("ZigTest.optional(5, 6)")).asInt());
    try std.testing.expectEqual(@as(i64, 0), try (try vm.eval("ZigTest.rest")).asInt());
    try std.testing.expectEqual(@as(i64, 3), try (try vm.eval("ZigTest.rest(1, 2, 3)")).asInt());
    try std.testing.expectEqual(@as(i64, 4), try (try vm.eval("ZigTest.rest(*[1, 2, 3, 4])")).asInt());
}

test "instance and class methods both dispatch to Zig" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    const identity = try vm.eval(
        "object = ZigObject.new; object.identity.equal?(object)",
    );
    try std.testing.expect(identity.truthy());

    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigObject.new.answer")).asInt());
    try std.testing.expectEqual(@as(i64, 7), try (try vm.eval("ZigObject.new.seven")).asInt());

    const version = try vm.eval("ZigObject.version");
    const version_text = try version.toString(allocator);
    defer allocator.free(version_text);
    try std.testing.expectEqualStrings("zig", version_text);
}

test "Value.call can invoke Zig-backed module, class and instance methods" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    const module = try vm.eval("ZigTest");
    const added = try module.call("add", &.{
        try zruby.Value.fromInt(&vm, 20),
        try zruby.Value.fromInt(&vm, 22),
    });
    try std.testing.expectEqual(@as(i64, 42), try added.asInt());

    const class = try vm.eval("ZigObject");
    const version = try class.call("version", &.{});
    const version_text = try version.toString(allocator);
    defer allocator.free(version_text);
    try std.testing.expectEqualStrings("zig", version_text);

    const instance = try vm.eval("ZigObject.new");
    const answer = try instance.call("answer", &.{});
    try std.testing.expectEqual(@as(i64, 42), try answer.asInt());
}

test "callback arity and type errors become Ruby exceptions" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.add(1)"));
    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.add(\"x\", 1)"));
    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.noArgs(1)"));
    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.optional"));
    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.requireInt(\"x\")"));
    try std.testing.expectError(error.RubyException, vm.eval("ZigTest.echoS(1)"));

    // The VM remains usable after callback failures.
    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigTest.noArgs")).asInt());
    try std.testing.expect(vm.lastError() == null);
}

test "redefining a Zig-backed method replaces the previous implementation" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    try std.testing.expectEqual(@as(i64, 7), try (try vm.eval("ZigObject.new.seven")).asInt());

    const class = try vm.defineClass("ZigObject", vm.objectClass());
    try vm.defineMethod(class, "seven", &zigNoArgs, zruby.args.none());

    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigObject.new.seven")).asInt());
}

test "redefining a module function replaces the implementation" {
    var vm = try newVM();
    defer vm.deinit();
    try register(&vm);

    const module = try vm.defineModule("ZigTest");
    try vm.defineModuleFunction(module, "noArgs", &zigSeven, zruby.args.none());
    try std.testing.expectEqual(@as(i64, 7), try (try vm.eval("ZigTest.noArgs")).asInt());

    try vm.defineModuleFunction(module, "noArgs", &zigNoArgs, zruby.args.none());
    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigTest.noArgs")).asInt());
}

fn autoAdd(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    if (values.len != 2) return error.InvalidSource;
    return zruby.Value.fromInt(vm, try values[0].asInt() + try values[1].asInt());
}

fn autoSum(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    var total: i64 = 0;
    for (values) |value| total += try value.asInt();
    return zruby.Value.fromInt(vm, total);
}

fn autoEcho(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    _ = vm;
    if (values.len != 1) return error.InvalidSource;
    return values[0];
}

fn autoVersion(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    if (values.len != 0) return error.InvalidSource;
    return zruby.Value.fromString(vm, "auto");
}

fn autoInvalidType(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    _ = vm;
    _ = values;
    return error.InvalidType;
}

fn autoRaiseRuby(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    _ = values;
    _ = vm.eval("raise ArgumentError, \"raised from Zig callback\"") catch {};
    return error.RubyException;
}

var foreign_vm: ?*zruby.VM = null;

fn autoForeignValue(vm: *zruby.VM, values: []const zruby.Value) zruby.Error!zruby.Value {
    _ = vm;
    _ = values;
    const other = foreign_vm orelse return error.InvalidType;
    return zruby.Value.fromInt(other, 1);
}

fn registerCallbacks(vm: *zruby.VM) !void {
    const module = try vm.defineModule("ZigAuto");
    try vm.defineModuleCallback(module, "add", &autoAdd, zruby.args.req(2));
    try vm.defineModuleCallback(module, "sum", &autoSum, zruby.args.rest());
    try vm.defineModuleCallback(module, "echo", &autoEcho, zruby.args.req(1));
    try vm.defineModuleCallback(module, "version", &autoVersion, zruby.args.none());
    try vm.defineModuleCallback(module, "invalidType", &autoInvalidType, zruby.args.none());
    try vm.defineModuleCallback(module, "raiseRuby", &autoRaiseRuby, zruby.args.none());
    try vm.defineModuleCallback(module, "foreignValue", &autoForeignValue, zruby.args.none());

    const class = try vm.defineClass("ZigAutoObject", vm.objectClass());
    try vm.defineMethodCallback(class, "add", &autoAdd, zruby.args.req(2));
    try vm.defineClassMethodCallback(class, "version", &autoVersion, zruby.args.none());
}

test "high-level module callbacks receive arguments and return values" {
    var vm = try newVM();
    defer vm.deinit();
    try registerCallbacks(&vm);

    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigAuto.add(20, 22)")).asInt());
    try std.testing.expectEqual(@as(i64, 10), try (try vm.eval("ZigAuto.sum(1, 2, 3, 4)")).asInt());

    const echoed = try vm.eval("ZigAuto.echo(\"hello\")");
    const text = try echoed.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);

    const version = try vm.eval("ZigAuto.version");
    const version_text = try version.toString(allocator);
    defer allocator.free(version_text);
    try std.testing.expectEqualStrings("auto", version_text);
}

test "high-level instance and class method callbacks dispatch correctly" {
    var vm = try newVM();
    defer vm.deinit();
    try registerCallbacks(&vm);

    try std.testing.expectEqual(@as(i64, 9), try (try vm.eval("ZigAutoObject.new.add(4, 5)")).asInt());
    const version = try vm.eval("ZigAutoObject.version");
    const text = try version.toString(allocator);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("auto", text);
}

test "high-level callbacks marshal more than sixteen arguments" {
    var vm = try newVM();
    defer vm.deinit();
    try registerCallbacks(&vm);

    const result = try vm.eval("ZigAuto.sum(*(1..20).to_a)");
    try std.testing.expectEqual(@as(i64, 210), try result.asInt());
}

test "high-level callback errors become Ruby exceptions and VM stays usable" {
    var vm = try newVM();
    defer vm.deinit();
    try registerCallbacks(&vm);

    try std.testing.expectError(error.RubyException, vm.eval("ZigAuto.add(1)"));
    const arity_message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(arity_message.len > 0);

    try std.testing.expectError(error.RubyException, vm.eval("ZigAuto.invalidType"));
    try std.testing.expectEqualStrings("TypeError", vm.lastErrorClass() orelse "");

    try std.testing.expectError(error.RubyException, vm.eval("ZigAuto.raiseRuby"));
    try std.testing.expectEqualStrings("ArgumentError", vm.lastErrorClass() orelse "");
    const message = vm.lastError() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, message, "raised from Zig callback") != null);

    try std.testing.expectEqual(@as(i64, 42), try (try vm.eval("ZigAuto.add(20, 22)")).asInt());
    try std.testing.expect(vm.lastError() == null);
}

test "high-level callback rejects a value from another VM" {
    var first = try newVM();
    defer first.deinit();
    var second = try newVM();
    defer second.deinit();
    try registerCallbacks(&first);

    foreign_vm = &second;
    defer foreign_vm = null;

    try std.testing.expectError(error.RubyException, first.eval("ZigAuto.foreignValue"));
    try std.testing.expectEqualStrings("TypeError", first.lastErrorClass() orelse "");
}
