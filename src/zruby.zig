//! zruby — embed mruby in Zig.
//!
//! ```zig
//! var vm = try zruby.VM.init(std.heap.page_allocator);
//! defer vm.deinit();
//! const value = try vm.eval("1 + 2");
//! try std.testing.expectEqual(@as(i64, 3), try value.asInt());
//! ```

const std = @import("std");

pub const c = @import("c.zig");

// mruby's default Linux build enables MRB_USE_ETEXT_RO_DATA_P, so the
// prebuilt libmruby.a references the linker-provided `etext`/`edata`
// symbols. Zig's linker does not synthesize them. Exporting the expected
// names is the narrowest compatibility fix; these are only used by mruby's
// read-only-data check, never mutated here.
export var etext: u8 = 0;
export var edata: u8 = 0;
export var end: u8 = 0;

comptime {
    if (@sizeOf(c.mrb_value) != @sizeOf(usize)) {
        @compileError("zruby expects mruby word-boxing mrb_value to be pointer-sized");
    }
}

pub const Error = error{
    OutOfMemory,
    VmInitFailed,
    RubyException,
    InvalidType,
    InvalidSource,
    NullPointer,
};

/// A high-level Zig callback. Arguments are copied into `Value` wrappers and
/// the return value must belong to the same VM. Returning a Zig error raises
/// a Ruby exception; `error.RubyException` reuses the message captured by the
/// VM (class is mapped for common exception classes).
pub const CallbackFn = *const fn (*VM, []const Value) Error!Value;

/// A mark for the mruby GC arena.
pub const ArenaMark = struct {
    index: c_int,
};

/// One mruby VM. A VM is not thread-safe; use one VM per thread.
pub const VM = struct {
    raw: *c.mrb_state,
    allocator: std.mem.Allocator,
    last_error: ?[]u8 = null,
    last_error_class: ?[]u8 = null,
    last_exception: ?c.mrb_value = null,
    callbacks: std.ArrayListUnmanaged(*CallbackEntry) = .empty,

    pub fn init(allocator: std.mem.Allocator) Error!VM {
        const raw = c.mrb_open() orelse return error.OutOfMemory;
        if (c.zruby_has_exc(raw)) {
            c.mrb_close(raw);
            return error.VmInitFailed;
        }
        return .{ .raw = raw, .allocator = allocator };
    }

    pub fn deinit(self: *VM) void {
        self.clearLastError();
        for (self.callbacks.items) |entry| self.allocator.destroy(entry);
        self.callbacks.deinit(self.allocator);
        c.mrb_close(self.raw);
        self.* = undefined;
    }

    pub const EvalOptions = struct {
        /// Used in error messages and backtraces.
        filename: ?[:0]const u8 = null,
    };

    /// Evaluate Ruby source in this VM.
    pub fn eval(self: *VM, source: []const u8) Error!Value {
        return self.evalWithOptions(source, .{});
    }

    pub fn evalWithOptions(self: *VM, source: []const u8, options: EvalOptions) Error!Value {
        // mruby 4.0's lexer expects a NUL sentinel; a plain slice is not
        // guaranteed to have one. Interior NUL would truncate silently.
        if (std.mem.indexOfScalar(u8, source, 0) != null) return error.InvalidSource;

        self.clearLastError();
        const mark = self.arenaSave();
        var restored = false;
        defer if (!restored) self.arenaRestore(mark);

        const source_z = self.allocator.dupeZ(u8, source) catch return error.OutOfMemory;
        defer self.allocator.free(source_z);

        var data = EvalData{ .source = source_z, .filename = options.filename orelse "(eval)" };
        var prepare_state: c.mrb_bool = false;
        _ = c.mrb_protect_error(self.raw, &prepareBody, &data, &prepare_state);

        if (prepare_state) {
            const exc = c.zruby_get_exc(self.raw);
            if (c.zruby_nil_p(exc)) {
                self.setLastError("mruby preparation failed", null);
            } else {
                self.captureException(exc);
            }
            c.zruby_clear_exc(self.raw);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        if (data.oom) {
            self.setLastError("failed to allocate mruby parser state", null);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.OutOfMemory;
        }

        if (data.parse_failed) {
            self.setSyntaxError(&data);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        const parser = data.parser orelse {
            self.setLastError("undefined parser state", null);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        };
        // mrb_load_exec takes ownership of the parser and frees it before
        // executing the compiled proc.
        data.parser = null;
        var load_data = LoadData{ .parser = parser, .cxt = data.cxt };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(self.raw, &loadBody, &load_data, &state);

        if (state or c.zruby_has_exc(self.raw)) {
            const exc = if (state) result else c.zruby_get_exc(self.raw);
            self.captureException(exc);
            c.zruby_clear_exc(self.raw);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        if (c.zruby_undef_p(result)) {
            self.setLastError("undefined Ruby result", null);
            data.cleanup(self);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        data.cleanup(self);
        self.arenaRestore(mark);
        restored = true;
        c.mrb_gc_protect(self.raw, result);
        return .{ .vm = self, .raw = result };
    }

    pub const IrepOptions = struct {
        /// Used for debug information and backtraces.
        filename: ?[:0]const u8 = null,
    };

    /// Load compiled mruby bytecode (`.mrb`) from memory.
    pub fn loadIrep(self: *VM, bytes: []const u8) Error!Value {
        return self.loadIrepWithOptions(bytes, .{});
    }

    pub fn loadIrepWithOptions(self: *VM, bytes: []const u8, options: IrepOptions) Error!Value {
        if (bytes.len == 0) return error.InvalidSource;
        self.clearLastError();
        const mark = self.arenaSave();
        var restored = false;
        defer if (!restored) self.arenaRestore(mark);

        var data = IrepData{
            .bytes = bytes,
            .filename = options.filename orelse "(irep)",
        };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(self.raw, &irepBody, &data, &state);
        if (data.cxt) |cxt| c.mrb_ccontext_free(self.raw, cxt);

        if (data.oom) {
            self.setLastError("failed to allocate mruby compile context", null);
            self.arenaRestore(mark);
            restored = true;
            return error.OutOfMemory;
        }

        if (state or c.zruby_has_exc(self.raw)) {
            const exc = if (state) result else c.zruby_get_exc(self.raw);
            self.captureException(exc);
            c.zruby_clear_exc(self.raw);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        if (c.zruby_undef_p(result)) {
            self.setLastError("invalid mruby bytecode", null);
            self.arenaRestore(mark);
            restored = true;
            return error.RubyException;
        }

        self.arenaRestore(mark);
        restored = true;
        c.mrb_gc_protect(self.raw, result);
        return .{ .vm = self, .raw = result };
    }

    fn setSyntaxError(self: *VM, data: *EvalData) void {
        const parser = data.parser orelse {
            self.setLastError("syntax error", "SyntaxError");
            return;
        };
        const message_ptr = c.zruby_parser_error_message(parser, 0);
        const line = c.zruby_parser_error_lineno(parser, 0);
        const column = c.zruby_parser_error_column(parser, 0);
        const message = if (message_ptr != null)
            std.mem.span(@as([*:0]const u8, @ptrCast(message_ptr)))
        else
            "syntax error";
        const formatted = std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}:{d}: {s}",
            .{ data.filename, line, column, message },
        ) catch null;
        if (formatted) |text| {
            self.setLastError(text, "SyntaxError");
            self.allocator.free(text);
        } else {
            self.setLastError("syntax error", "SyntaxError");
        }
    }

    /// Last Ruby exception message captured by `eval` or `Value.call`.
    pub fn lastError(self: *const VM) ?[]const u8 {
        return self.last_error;
    }

    /// Last Ruby exception class name, when available.
    pub fn lastErrorClass(self: *const VM) ?[]const u8 {
        return self.last_error_class;
    }

    /// The last captured Ruby exception object, if the failure produced one.
    /// The value is GC-protected until the next operation clears diagnostics.
    pub fn lastException(self: *VM) ?Value {
        const raw = self.last_exception orelse return null;
        return .{ .vm = self, .raw = raw };
    }

    /// A bounded, joined Ruby backtrace for the last exception. Returns null
    /// when there is no exception or Ruby reports no backtrace.
    pub fn lastBacktrace(self: *VM, allocator: std.mem.Allocator) Error!?[]u8 {
        const raw = self.last_exception orelse return null;
        const exception = Value{ .vm = self, .raw = raw };
        const backtrace = exception.invoke("backtrace", &.{}, false) catch return null;
        if (backtrace.isNil()) return null;

        const separator = try makeValueInternal(self, .{ .string = "\n" }, false);
        const joined = backtrace.invoke("join", &.{separator}, false) catch return null;
        const text = try joined.toString(allocator);
        if (text.len <= 4096) return text;

        const bounded = allocator.dupe(u8, text[0..4096]) catch {
            allocator.free(text);
            return error.OutOfMemory;
        };
        allocator.free(text);
        return bounded;
    }

    pub fn arenaSave(self: *VM) ArenaMark {
        return .{ .index = c.zruby_arena_save(self.raw) };
    }

    pub fn arenaRestore(self: *VM, mark: ArenaMark) void {
        c.zruby_arena_restore(self.raw, mark.index);
    }

    /// Root a value for subsequent calls that may trigger GC.
    pub fn protect(self: *VM, value: Value) void {
        c.mrb_gc_protect(self.raw, value.raw);
    }

    /// Create a rooted handle. The value stays protected until an enclosing
    /// arena restore or VM shutdown; the handle itself owns no extra memory.
    pub fn root(self: *VM, value: Value) RootedValue {
        std.debug.assert(value.vm == self);
        self.protect(value);
        return .{ .vm = self, .value = value };
    }

    /// Open an explicit GC arena scope. Call `deinit` to restore the arena.
    pub fn arenaScope(self: *VM) ArenaScope {
        return .{ .vm = self, .mark = self.arenaSave() };
    }

    /// The root Object class, useful as an explicit superclass.
    pub fn objectClass(self: *VM) *c.RClass {
        return c.zruby_object_class(self.raw);
    }

    pub fn defineModule(self: *VM, name: []const u8) Error!*c.RClass {
        const z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(z);
        var data = DefineData{ .kind = .module, .name = z };
        try self.protectDefine(&data);
        return data.out orelse error.OutOfMemory;
    }

    pub fn defineClass(self: *VM, name: []const u8, super: ?*c.RClass) Error!*c.RClass {
        const z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(z);
        var data = DefineData{ .kind = .class, .name = z, .super = super };
        try self.protectDefine(&data);
        return data.out orelse error.OutOfMemory;
    }

    /// Define a module function backed by a C-ABI Zig function.
    pub fn defineModuleFunction(
        self: *VM,
        module: *c.RClass,
        name: []const u8,
        function: c.mrb_func_t,
        aspec: c.mrb_aspec,
    ) Error!void {
        const z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(z);
        var data = DefineData{
            .kind = .module_function,
            .name = z,
            .owner = module,
            .function = function,
            .aspec = aspec,
        };
        try self.protectDefine(&data);
    }

    /// Define an instance method backed by a C-ABI Zig function.
    pub fn defineMethod(
        self: *VM,
        class: *c.RClass,
        name: []const u8,
        function: c.mrb_func_t,
        aspec: c.mrb_aspec,
    ) Error!void {
        const z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(z);
        var data = DefineData{
            .kind = .method,
            .name = z,
            .owner = class,
            .function = function,
            .aspec = aspec,
        };
        try self.protectDefine(&data);
    }

    /// Define a class method backed by a C-ABI Zig function.
    pub fn defineClassMethod(
        self: *VM,
        class: *c.RClass,
        name: []const u8,
        function: c.mrb_func_t,
        aspec: c.mrb_aspec,
    ) Error!void {
        const z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(z);
        var data = DefineData{
            .kind = .class_method,
            .name = z,
            .owner = class,
            .function = function,
            .aspec = aspec,
        };
        try self.protectDefine(&data);
    }

    fn protectDefine(self: *VM, data: *DefineData) Error!void {
        self.clearLastError();
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(self.raw, &defineBody, data, &state);
        if (state or c.zruby_has_exc(self.raw)) {
            const exc = if (state) result else c.zruby_get_exc(self.raw);
            self.captureException(exc);
            c.zruby_clear_exc(self.raw);
            return error.RubyException;
        }
    }

    /// Define a module function backed by a high-level Zig callback.
    /// The callback receives all Ruby arguments as `Value`s and may return
    /// any `Value` belonging to this VM.
    pub fn defineModuleCallback(
        self: *VM,
        module: *c.RClass,
        name: []const u8,
        function: CallbackFn,
        aspec: c.mrb_aspec,
    ) Error!void {
        return self.defineCallback(module, name, function, .module_function, aspec);
    }

    /// Define an instance method backed by a high-level Zig callback.
    pub fn defineMethodCallback(
        self: *VM,
        class: *c.RClass,
        name: []const u8,
        function: CallbackFn,
        aspec: c.mrb_aspec,
    ) Error!void {
        return self.defineCallback(class, name, function, .method, aspec);
    }

    /// Define a class method backed by a high-level Zig callback.
    pub fn defineClassMethodCallback(
        self: *VM,
        class: *c.RClass,
        name: []const u8,
        function: CallbackFn,
        aspec: c.mrb_aspec,
    ) Error!void {
        return self.defineCallback(class, name, function, .class_method, aspec);
    }

    fn defineCallback(
        self: *VM,
        owner: *c.RClass,
        name: []const u8,
        function: CallbackFn,
        kind: CallbackKind,
        aspec: c.mrb_aspec,
    ) Error!void {
        self.clearLastError();
        const entry = try self.allocateCallbackEntry(function);

        var data = CallbackDefineData{
            .entry = entry,
            .owner = owner,
            .name = name,
            .kind = kind,
            .aspec = aspec,
        };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(self.raw, &callbackDefineBody, &data, &state);
        if (state or c.zruby_has_exc(self.raw)) {
            const exc = if (state) result else c.zruby_get_exc(self.raw);
            self.captureException(exc);
            c.zruby_clear_exc(self.raw);
            return error.RubyException;
        }
    }

    /// Create a standalone Ruby Proc backed by a high-level Zig callback.
    pub fn createCallbackProc(self: *VM, function: CallbackFn) Error!Value {
        self.clearLastError();
        const entry = try self.allocateCallbackEntry(function);
        var data = CallbackProcData{ .entry = entry };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(self.raw, &callbackProcBody, &data, &state);
        if (state or c.zruby_has_exc(self.raw)) {
            const exc = if (state) result else c.zruby_get_exc(self.raw);
            self.captureException(exc);
            c.zruby_clear_exc(self.raw);
            return error.RubyException;
        }
        if (c.zruby_nil_p(result) or c.zruby_undef_p(result)) {
            self.setLastError("failed to create Ruby Proc", null);
            return error.RubyException;
        }
        return .{ .vm = self, .raw = result };
    }

    fn allocateCallbackEntry(self: *VM, function: CallbackFn) Error!*CallbackEntry {
        const entry = self.allocator.create(CallbackEntry) catch return error.OutOfMemory;
        entry.* = .{ .vm = self, .function = function };
        self.callbacks.append(self.allocator, entry) catch {
            self.allocator.destroy(entry);
            return error.OutOfMemory;
        };
        return entry;
    }

    fn clearLastError(self: *VM) void {
        if (self.last_error) |msg| self.allocator.free(msg);
        if (self.last_error_class) |name| self.allocator.free(name);
        self.last_error = null;
        self.last_error_class = null;
        self.last_exception = null;
    }

    fn setLastError(self: *VM, message: []const u8, class_name: ?[]const u8) void {
        self.clearLastError();
        self.last_error = self.allocator.dupe(u8, message) catch null;
        if (class_name) |name| {
            self.last_error_class = self.allocator.dupe(u8, name) catch null;
        }
    }

    fn captureException(self: *VM, exc: c.mrb_value) void {
        self.clearLastError();

        var inspect_data = InspectData{ .exc = exc };
        var inspect_state: c.mrb_bool = false;
        const inspected = c.mrb_protect_error(self.raw, &inspectBody, &inspect_data, &inspect_state);
        if (!inspect_state and c.zruby_string_p(inspected)) {
            const p = c.zruby_str_ptr(inspected);
            const n = c.zruby_str_len(inspected);
            if (p != null and n >= 0) {
                const bytes: [*]const u8 = @ptrCast(p);
                self.last_error = self.allocator.dupe(u8, bytes[0..@intCast(n)]) catch null;
            }
        }
        if (self.last_error == null) {
            self.last_error = self.allocator.dupe(u8, "Ruby exception") catch null;
        }

        const class_name = c.mrb_obj_classname(self.raw, exc);
        if (class_name != null) {
            const z: [*:0]const u8 = @ptrCast(class_name);
            self.last_error_class = self.allocator.dupe(u8, std.mem.span(z)) catch null;
        }
        if (!c.zruby_nil_p(exc)) {
            self.last_exception = exc;
            c.mrb_gc_protect(self.raw, exc);
        }
        if (c.zruby_has_exc(self.raw)) c.zruby_clear_exc(self.raw);
    }
};

/// A GC-rooted handle created by `VM.root`. It is valid until an enclosing
/// arena restore or VM shutdown; the handle itself has no destructor.
pub const RootedValue = struct {
    vm: *VM,
    value: Value,

    pub fn get(self: *const RootedValue) Value {
        std.debug.assert(self.vm == self.value.vm);
        return self.value;
    }
};

/// An explicit arena scope. `deinit` restores the arena mark and invalidates
/// values created or protected after the scope was opened.
pub const ArenaScope = struct {
    vm: *VM,
    mark: ArenaMark,
    active: bool = true,

    pub fn deinit(self: *ArenaScope) void {
        std.debug.assert(self.active);
        self.vm.arenaRestore(self.mark);
        self.active = false;
    }
};

/// A Ruby value owned by a VM. Values returned by eval/call are protected
/// against GC; a value created from a Zig literal is valid for the current
/// arena. Use `VM.protect` for long-lived values.
pub const Value = struct {
    vm: *VM,
    raw: c.mrb_value,

    pub fn nilValue(vm: *VM) Value {
        return .{ .vm = vm, .raw = c.zruby_nil_value() };
    }

    pub fn fromInt(vm: *VM, value: i64) Error!Value {
        return makeValue(vm, .{ .int = @intCast(value) });
    }

    pub fn fromFloat(vm: *VM, value: f64) Error!Value {
        return makeValue(vm, .{ .float = value });
    }

    pub fn fromBool(vm: *VM, value: bool) Value {
        return .{ .vm = vm, .raw = c.zruby_bool_value(vm.raw, value) };
    }

    pub fn fromString(vm: *VM, value: []const u8) Error!Value {
        return makeValue(vm, .{ .string = value });
    }

    pub fn fromSymbol(vm: *VM, name: []const u8) Error!Value {
        return makeValue(vm, .{ .symbol = name });
    }

    pub fn fromRange(vm: *VM, start: Value, finish: Value, exclude_end: bool) Error!Value {
        if (start.vm != vm or finish.vm != vm) return error.InvalidType;
        return makeValue(vm, .{ .range = .{
            .start = start.raw,
            .finish = finish.raw,
            .exclude = exclude_end,
        } });
    }

    /// Create a Ruby Proc backed by a high-level Zig callback.
    pub fn fromCallback(vm: *VM, function: CallbackFn) Error!Value {
        return vm.createCallbackProc(function);
    }

    pub fn isNil(self: Value) bool {
        return c.zruby_nil_p(self.raw);
    }

    pub fn isTrue(self: Value) bool {
        return c.zruby_true_p(self.raw);
    }

    pub fn isFalse(self: Value) bool {
        return c.zruby_false_p(self.raw);
    }

    pub fn isInteger(self: Value) bool {
        return c.zruby_integer_p(self.raw);
    }

    pub fn isFloat(self: Value) bool {
        return c.zruby_float_p(self.raw);
    }

    pub fn isString(self: Value) bool {
        return c.zruby_string_p(self.raw);
    }

    pub fn isArray(self: Value) bool {
        return c.zruby_array_p(self.raw);
    }

    pub fn isHash(self: Value) bool {
        return c.zruby_hash_p(self.raw);
    }

    pub fn isSymbol(self: Value) bool {
        return c.zruby_symbol_p(self.raw);
    }

    pub fn isRange(self: Value) bool {
        return c.zruby_range_p(self.raw);
    }

    pub fn isProc(self: Value) bool {
        return c.zruby_proc_p(self.raw);
    }

    pub fn isObject(self: Value) bool {
        return c.zruby_object_p(self.raw);
    }

    /// Convenience predicate for the default mruby Time class. Subclasses are
    /// not matched; use `className` when that distinction matters.
    pub fn isTime(self: Value) bool {
        const name = c.mrb_obj_classname(self.vm.raw, self.raw);
        if (name == null) return false;
        const z: [*:0]const u8 = @ptrCast(name);
        return std.mem.eql(u8, std.mem.span(z), "Time");
    }

    pub fn isException(self: Value) bool {
        return c.zruby_exception_p(self.raw);
    }

    /// Copy the Ruby class name into `allocator`.
    pub fn className(self: Value, allocator: std.mem.Allocator) Error![]u8 {
        const name = c.mrb_obj_classname(self.vm.raw, self.raw);
        if (name == null) return error.NullPointer;
        const z: [*:0]const u8 = @ptrCast(name);
        return allocator.dupe(u8, std.mem.span(z));
    }

    /// Ruby truthiness: everything except nil and false is truthy.
    pub fn truthy(self: Value) bool {
        return !self.isNil() and !self.isFalse();
    }

    pub fn asInt(self: Value) Error!i64 {
        if (!self.isInteger()) return error.InvalidType;
        return c.zruby_to_int(self.vm.raw, self.raw);
    }

    pub fn asFloat(self: Value) Error!f64 {
        if (!self.isFloat()) return error.InvalidType;
        return c.zruby_to_float(self.vm.raw, self.raw);
    }

    /// Copy a Ruby string into `allocator`.
    pub fn toString(self: Value, allocator: std.mem.Allocator) Error![]u8 {
        if (!self.isString()) return error.InvalidType;
        const p = c.zruby_str_ptr(self.raw);
        const n = c.zruby_str_len(self.raw);
        if (p == null or n < 0) return error.NullPointer;
        const bytes: [*]const u8 = @ptrCast(p);
        return allocator.dupe(u8, bytes[0..@intCast(n)]);
    }

    /// Call `inspect` on the value and copy the resulting string.
    pub fn inspect(self: Value) Error![]u8 {
        const result = try self.call("inspect", &.{});
        return result.toString(self.vm.allocator);
    }

    /// Call a Ruby method with `args`. The method name is looked up as a
    /// symbol on every call; cache symbols yourself for hot paths.
    pub fn call(self: Value, method: []const u8, call_args: []const Value) Error!Value {
        // mruby's Proc#call is a tail call in the VM. Invoking it through
        // mrb_funcall_argv from C can lose the result, so use the yield path.
        if (self.isProc() and
            (std.mem.eql(u8, method, "call") or
                std.mem.eql(u8, method, "[]") or
                std.mem.eql(u8, method, "yield")))
        {
            return self.callProc(call_args);
        }
        return self.invoke(method, call_args, true);
    }

    /// Invoke this Proc directly, bypassing Proc#call dispatch.
    pub fn callProc(self: Value, call_args: []const Value) Error!Value {
        if (!self.isProc()) return error.InvalidType;
        const vm = self.vm;
        vm.clearLastError();

        const raw_args = try vm.allocator.alloc(c.mrb_value, call_args.len);
        defer vm.allocator.free(raw_args);
        for (call_args, 0..) |arg, i| {
            if (arg.vm != vm) return error.InvalidType;
            raw_args[i] = arg.raw;
        }

        var data = ProcCallData{ .proc = self.raw, .args = raw_args };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(vm.raw, &procCallBody, &data, &state);
        if (state or c.zruby_has_exc(vm.raw)) {
            const exc = if (state) result else c.zruby_get_exc(vm.raw);
            vm.captureException(exc);
            c.zruby_clear_exc(vm.raw);
            return error.RubyException;
        }
        return .{ .vm = vm, .raw = result };
    }

    fn invoke(
        self: Value,
        method: []const u8,
        call_args: []const Value,
        clear_errors: bool,
    ) Error!Value {
        const vm = self.vm;
        if (clear_errors) vm.clearLastError();

        const raw_args = try vm.allocator.alloc(c.mrb_value, call_args.len);
        defer vm.allocator.free(raw_args);

        for (call_args, 0..) |arg, i| {
            if (arg.vm != vm) return error.InvalidType;
            raw_args[i] = arg.raw;
        }

        var data = CallData{
            .receiver = self.raw,
            .method = method,
            .args = raw_args,
        };
        var state: c.mrb_bool = false;
        const result = c.mrb_protect_error(vm.raw, &callBody, &data, &state);
        if (state or c.zruby_has_exc(vm.raw)) {
            const exc = if (state) result else c.zruby_get_exc(vm.raw);
            vm.captureException(exc);
            c.zruby_clear_exc(vm.raw);
            return error.RubyException;
        }

        return .{ .vm = vm, .raw = result };
    }

    pub fn get(self: Value, index: i64) Error!Value {
        const index_value = try Value.fromInt(self.vm, index);
        return self.call("[]", &.{index_value});
    }

    pub fn set(self: Value, index: i64, value: Value) Error!void {
        const index_value = try Value.fromInt(self.vm, index);
        _ = try self.call("[]=", &.{ index_value, value });
    }

    pub fn hashGet(self: Value, key: Value) Error!Value {
        return self.call("[]", &.{key});
    }

    pub fn hashSet(self: Value, key: Value, value: Value) Error!void {
        _ = try self.call("[]=", &.{ key, value });
    }

    pub fn arrayLen(self: Value) Error!i64 {
        const length = try self.call("length", &.{});
        return length.asInt();
    }

    pub fn hashLen(self: Value) Error!i64 {
        if (!self.isHash()) return error.InvalidType;
        return self.arrayLen();
    }

    /// Return a new Ruby array containing the hash keys.
    pub fn hashKeys(self: Value) Error!Value {
        if (!self.isHash()) return error.InvalidType;
        return self.call("keys", &.{});
    }

    pub fn arrayIterator(self: Value) ArrayIterator {
        return .{ .array = self };
    }

    pub fn hashIterator(self: Value) Error!HashIterator {
        return .{ .hash = self, .keys = try self.hashKeys() };
    }
};

pub const ArrayIterator = struct {
    array: Value,
    index: i64 = 0,

    pub fn next(self: *ArrayIterator) Error!?Value {
        if (!self.array.isArray()) return error.InvalidType;
        const length = try self.array.arrayLen();
        if (self.index >= length) return null;
        const value = try self.array.get(self.index);
        self.index += 1;
        return value;
    }
};

pub const HashEntry = struct {
    key: Value,
    value: Value,
};

pub const HashIterator = struct {
    hash: Value,
    keys: Value,
    index: i64 = 0,

    pub fn next(self: *HashIterator) Error!?HashEntry {
        if (!self.hash.isHash()) return error.InvalidType;
        const length = try self.keys.arrayLen();
        if (self.index >= length) return null;
        const key = try self.keys.get(self.index);
        self.index += 1;
        return .{ .key = key, .value = try self.hash.hashGet(key) };
    }
};

/// Argument spec helpers mirroring MRB_ARGS_*.
pub const args = struct {
    pub fn none() c.mrb_aspec {
        return 0;
    }

    pub fn req(n: u32) c.mrb_aspec {
        return (n & 0x1f) << 18;
    }

    pub fn opt(n: u32) c.mrb_aspec {
        return (n & 0x1f) << 13;
    }

    pub fn rest() c.mrb_aspec {
        return 1 << 12;
    }
};

const EvalData = struct {
    source: [:0]const u8,
    filename: [:0]const u8,
    cxt: ?*c.mrb_ccontext = null,
    parser: ?*c.mrb_parser_state = null,
    parse_failed: bool = false,
    oom: bool = false,

    fn cleanup(self: *EvalData, vm: *VM) void {
        if (self.parser) |parser| c.mrb_parser_free(parser);
        if (self.cxt) |cxt| c.mrb_ccontext_free(vm.raw, cxt);
        self.parser = null;
        self.cxt = null;
    }
};

const IrepData = struct {
    bytes: []const u8,
    filename: [:0]const u8,
    cxt: ?*c.mrb_ccontext = null,
    oom: bool = false,
};

fn irepBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *IrepData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;

    const cxt = c.mrb_ccontext_new(state) orelse {
        data.oom = true;
        return c.zruby_nil_value();
    };
    data.cxt = cxt;
    _ = c.mrb_ccontext_filename(state, cxt, data.filename.ptr);
    return c.mrb_load_irep_buf_cxt(state, data.bytes.ptr, data.bytes.len, cxt);
}

fn prepareBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *EvalData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;

    const cxt = c.mrb_ccontext_new(state) orelse {
        data.oom = true;
        return c.zruby_nil_value();
    };
    data.cxt = cxt;
    _ = c.mrb_ccontext_filename(state, cxt, data.filename.ptr);
    c.zruby_cxt_capture_errors(cxt);

    const parser = c.mrb_parse_nstring(state, data.source.ptr, data.source.len, cxt) orelse {
        data.oom = true;
        return c.zruby_nil_value();
    };
    data.parser = parser;
    if (c.zruby_parser_nerr(parser) > 0) data.parse_failed = true;
    return c.zruby_nil_value();
}

const LoadData = struct {
    parser: *c.mrb_parser_state,
    cxt: ?*c.mrb_ccontext,
};

fn loadBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *LoadData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;
    return c.mrb_load_exec(state, data.parser, data.cxt);
}

const CallData = struct {
    receiver: c.mrb_value,
    method: []const u8,
    args: []const c.mrb_value,
};

fn callBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *CallData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;

    // Keep the entire raising operation inside one protection frame:
    // rooting, interning, argument dispatch, and result rooting.
    c.mrb_gc_protect(state, data.receiver);
    for (data.args) |arg| c.mrb_gc_protect(state, arg);
    const symbol = c.mrb_intern(state, data.method.ptr, data.method.len);
    const result = c.mrb_funcall_argv(
        state,
        data.receiver,
        symbol,
        @intCast(data.args.len),
        data.args.ptr,
    );
    c.mrb_gc_protect(state, result);
    return result;
}

const ProcCallData = struct {
    proc: c.mrb_value,
    args: []const c.mrb_value,
};

fn procCallBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *ProcCallData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;
    c.mrb_gc_protect(state, data.proc);
    for (data.args) |arg| c.mrb_gc_protect(state, arg);
    const result = c.mrb_yield_argv(
        state,
        data.proc,
        @intCast(data.args.len),
        data.args.ptr,
    );
    c.mrb_gc_protect(state, result);
    return result;
}

const InspectData = struct {
    exc: c.mrb_value,
};

fn inspectBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *InspectData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;
    c.mrb_gc_protect(state, data.exc);
    return c.mrb_inspect(state, data.exc);
}

const DefineKind = enum {
    module,
    class,
    module_function,
    method,
    class_method,
};

const DefineData = struct {
    kind: DefineKind,
    name: [:0]const u8,
    super: ?*c.RClass = null,
    owner: ?*c.RClass = null,
    function: c.mrb_func_t = null,
    aspec: c.mrb_aspec = 0,
    out: ?*c.RClass = null,
};

fn defineBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *DefineData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;
    switch (data.kind) {
        .module => data.out = c.mrb_define_module(state, data.name.ptr),
        .class => data.out = c.mrb_define_class(state, data.name.ptr, data.super),
        .module_function => c.mrb_define_module_function(
            state,
            data.owner,
            data.name.ptr,
            data.function,
            data.aspec,
        ),
        .method => c.mrb_define_method(
            state,
            data.owner,
            data.name.ptr,
            data.function,
            data.aspec,
        ),
        .class_method => c.mrb_define_class_method(
            state,
            data.owner,
            data.name.ptr,
            data.function,
            data.aspec,
        ),
    }
    return c.zruby_nil_value();
}

const CallbackKind = enum {
    module_function,
    method,
    class_method,
};

const CallbackEntry = struct {
    vm: *VM,
    function: CallbackFn,
};

const CallbackDefineData = struct {
    entry: *CallbackEntry,
    owner: *c.RClass,
    name: []const u8,
    kind: CallbackKind,
    aspec: c.mrb_aspec,
};

const CallbackProcData = struct {
    entry: *CallbackEntry,
};

fn callbackProcBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *CallbackProcData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;

    var env = c.zruby_cptr_value(state, data.entry);
    const proc = c.mrb_proc_new_cfunc_with_env(
        state,
        &callbackTrampoline,
        1,
        &env,
    ) orelse return c.zruby_nil_value();
    c.zruby_proc_set_env_mid(proc, c.mrb_intern(state, "call", 4));
    const value = c.zruby_proc_value(proc);
    c.mrb_gc_protect(state, value);
    return value;
}

fn callbackDefineBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *CallbackDefineData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;

    var env = c.zruby_cptr_value(state, data.entry);
    const proc = c.mrb_proc_new_cfunc_with_env(
        state,
        &callbackTrampoline,
        1,
        &env,
    ) orelse return c.zruby_nil_value();
    const mid = c.mrb_intern(state, data.name.ptr, data.name.len);

    switch (data.kind) {
        .module_function => c.zruby_define_module_function_proc(
            state,
            data.owner,
            mid,
            proc,
            data.aspec,
        ),
        .method => c.zruby_define_proc_method(
            state,
            data.owner,
            mid,
            proc,
            data.aspec,
            0,
        ),
        .class_method => c.zruby_define_class_method_proc(
            state,
            data.owner,
            mid,
            proc,
            data.aspec,
        ),
    }
    return c.zruby_nil_value();
}

fn callbackTrampoline(mrb: ?*c.mrb_state, self: c.mrb_value) callconv(.c) c.mrb_value {
    _ = self;
    const state = mrb orelse unreachable;

    const env = c.mrb_proc_cfunc_env_get(state, 0);
    const raw_ptr = c.zruby_cptr(env);
    if (raw_ptr == null) {
        const message = "zruby callback environment is missing";
        c.zruby_raise_callback_error(state, 3, message.ptr, message.len);
        unreachable;
    }
    const entry: *CallbackEntry = @ptrCast(@alignCast(raw_ptr.?));

    var raw_args: [*c]const c.mrb_value = null;
    const raw_count = c.zruby_get_args_array(state, &raw_args);
    const count: usize = if (raw_count > 0) @intCast(raw_count) else 0;

    var stack_args: [16]Value = undefined;
    var heap_args: ?[]Value = null;
    const values: []Value = if (count <= stack_args.len)
        stack_args[0..count]
    else blk: {
        heap_args = entry.vm.allocator.alloc(Value, count) catch {
            const message = "out of memory while marshalling callback arguments";
            c.zruby_raise_callback_error(state, 3, message.ptr, message.len);
            unreachable;
        };
        break :blk heap_args.?;
    };
    for (0..count) |i| {
        values[i] = .{ .vm = entry.vm, .raw = raw_args[i] };
    }

    const result = entry.function(entry.vm, values) catch |err| {
        if (heap_args) |buffer| entry.vm.allocator.free(buffer);
        const message = entry.vm.lastError() orelse @errorName(err);
        c.zruby_raise_callback_error(
            state,
            classifyCallbackError(entry.vm, err),
            message.ptr,
            message.len,
        );
        unreachable;
    };
    if (heap_args) |buffer| entry.vm.allocator.free(buffer);

    if (result.vm != entry.vm) {
        const message = "zruby callback returned a value from another VM";
        c.zruby_raise_callback_error(state, 1, message.ptr, message.len);
        unreachable;
    }
    return result.raw;
}

fn classifyCallbackError(vm: *VM, err: Error) c_int {
    if (err == error.RubyException) {
        const class_name = vm.lastErrorClass() orelse return 0;
        if (std.mem.eql(u8, class_name, "TypeError")) return 1;
        if (std.mem.eql(u8, class_name, "ArgumentError")) return 2;
        if (std.mem.eql(u8, class_name, "NoMemoryError")) return 3;
        return 0;
    }
    return switch (err) {
        error.InvalidType => 1,
        error.InvalidSource, error.NullPointer => 2,
        error.OutOfMemory => 3,
        else => 0,
    };
}

const ValueData = union(enum) {
    int: c.mrb_int,
    float: c.mrb_float,
    string: []const u8,
    symbol: []const u8,
    range: struct {
        start: c.mrb_value,
        finish: c.mrb_value,
        exclude: c.mrb_bool,
    },
};

fn valueBody(mrb: ?*c.mrb_state, userdata: ?*anyopaque) callconv(.c) c.mrb_value {
    const data: *ValueData = @ptrCast(@alignCast(userdata orelse unreachable));
    const state = mrb orelse unreachable;
    const value = switch (data.*) {
        .int => |i| c.zruby_int_value(state, i),
        .float => |f| c.zruby_float_value(state, f),
        .string => |s| c.mrb_str_new(state, s.ptr, s.len),
        .symbol => |s| c.zruby_symbol_value(state, c.mrb_intern(state, s.ptr, s.len)),
        .range => |r| c.mrb_range_new(state, r.start, r.finish, r.exclude),
    };
    c.mrb_gc_protect(state, value);
    return value;
}

fn makeValue(vm: *VM, data: ValueData) Error!Value {
    return makeValueInternal(vm, data, true);
}

fn makeValueInternal(vm: *VM, data: ValueData, clear_errors: bool) Error!Value {
    if (clear_errors) vm.clearLastError();
    var payload = data;
    var state: c.mrb_bool = false;
    const result = c.mrb_protect_error(vm.raw, &valueBody, &payload, &state);
    if (state or c.zruby_has_exc(vm.raw)) {
        const exc = if (state) result else c.zruby_get_exc(vm.raw);
        vm.captureException(exc);
        c.zruby_clear_exc(vm.raw);
        return error.RubyException;
    }
    return .{ .vm = vm, .raw = result };
}
