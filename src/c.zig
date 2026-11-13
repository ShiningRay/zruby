//! Hand-written bindings for the mruby 4.x C API.
//!
//! `mrb_value` is intentionally declared as the word-boxing representation
//! used by mruby's default build (`struct mrb_value { uintptr_t w; }`).
//! The build script compiles `shim.c`, whose static assertions verify the
//! layout and whose helpers cover inline functions and macros that are not
//! exported symbols. Keep this file in sync with the shim.

pub const mrb_state = opaque {};
pub const mrb_ccontext = opaque {};
pub const mrb_parser_state = opaque {};
pub const RClass = opaque {};
pub const RObject = opaque {};

/// Default mruby 4.x build: word boxing, 64-bit `mrb_int`.
pub const mrb_value = extern struct {
    w: usize,
};

pub const mrb_int = i64;
pub const mrb_float = f64;
pub const mrb_sym = u32;
pub const mrb_aspec = u32;
pub const mrb_bool = bool;

pub const mrb_func_t = ?*const fn (mrb: ?*mrb_state, self: mrb_value) callconv(.c) mrb_value;
pub const RProc = opaque {};

pub const mrb_protect_error_func = fn (
    mrb: ?*mrb_state,
    userdata: ?*anyopaque,
) callconv(.c) mrb_value;

// Core VM.
pub extern fn mrb_open() ?*mrb_state;
pub extern fn mrb_close(mrb: *mrb_state) void;
pub extern fn mrb_show_version(mrb: *mrb_state) void;

// Compilation and evaluation.
pub extern fn mrb_ccontext_new(mrb: *mrb_state) ?*mrb_ccontext;
pub extern fn mrb_ccontext_free(mrb: *mrb_state, cxt: ?*mrb_ccontext) void;
pub extern fn mrb_ccontext_filename(
    mrb: *mrb_state,
    cxt: ?*mrb_ccontext,
    s: [*c]const u8,
) [*c]const u8;
pub extern fn mrb_load_nstring_cxt(
    mrb: *mrb_state,
    s: [*c]const u8,
    len: usize,
    cxt: ?*mrb_ccontext,
) mrb_value;
pub extern fn mrb_parse_nstring(
    mrb: *mrb_state,
    s: [*c]const u8,
    len: usize,
    cxt: ?*mrb_ccontext,
) ?*mrb_parser_state;
pub extern fn mrb_load_exec(
    mrb: *mrb_state,
    parser: *mrb_parser_state,
    cxt: ?*mrb_ccontext,
) mrb_value;
pub extern fn mrb_parser_free(parser: *mrb_parser_state) void;
pub extern fn mrb_protect_error(
    mrb: *mrb_state,
    body: *const mrb_protect_error_func,
    userdata: ?*anyopaque,
    err: *mrb_bool,
) mrb_value;

// Calls and values.
pub extern fn mrb_intern(mrb: *mrb_state, s: [*c]const u8, len: usize) mrb_sym;
pub extern fn mrb_intern_cstr(mrb: *mrb_state, s: [*c]const u8) mrb_sym;
pub extern fn mrb_funcall_argv(
    mrb: *mrb_state,
    val: mrb_value,
    name: mrb_sym,
    argc: mrb_int,
    argv: [*c]const mrb_value,
) mrb_value;
pub extern fn mrb_inspect(mrb: *mrb_state, obj: mrb_value) mrb_value;
pub extern fn mrb_str_new(mrb: *mrb_state, p: [*c]const u8, len: usize) mrb_value;
pub extern fn mrb_obj_classname(mrb: *mrb_state, obj: mrb_value) [*c]const u8;
pub extern fn mrb_gc_protect(mrb: *mrb_state, obj: mrb_value) void;

// C functions with an environment, used by the high-level callback API.
pub extern fn mrb_proc_new_cfunc_with_env(
    mrb: *mrb_state,
    func: mrb_func_t,
    argc: mrb_int,
    argv: [*c]const mrb_value,
) ?*RProc;
pub extern fn mrb_proc_cfunc_env_get(mrb: *mrb_state, idx: mrb_int) mrb_value;

// Class/module definition for Zig-implemented methods.
pub extern fn mrb_define_module(mrb: *mrb_state, name: [*c]const u8) ?*RClass;
pub extern fn mrb_define_class(
    mrb: *mrb_state,
    name: [*c]const u8,
    super: ?*RClass,
) ?*RClass;
pub extern fn mrb_define_module_function(
    mrb: *mrb_state,
    cla: ?*RClass,
    name: [*c]const u8,
    fun: mrb_func_t,
    aspec: mrb_aspec,
) void;
pub extern fn mrb_define_method(
    mrb: *mrb_state,
    cla: ?*RClass,
    name: [*c]const u8,
    fun: mrb_func_t,
    aspec: mrb_aspec,
) void;
pub extern fn mrb_define_class_method(
    mrb: *mrb_state,
    cla: ?*RClass,
    name: [*c]const u8,
    fun: mrb_func_t,
    aspec: mrb_aspec,
) void;

// Variadic C API used by callbacks; only called from Zig functions registered
// with mruby, with format strings fixed at the call site.
pub extern fn mrb_get_args(mrb: *mrb_state, format: [*:0]const u8, ...) mrb_int;

// Helpers implemented in shim.c.
pub extern fn zruby_value_size() usize;
pub extern fn zruby_object_class(mrb: *mrb_state) *RClass;
pub extern fn zruby_arena_save(mrb: *mrb_state) c_int;
pub extern fn zruby_arena_restore(mrb: *mrb_state, idx: c_int) void;
pub extern fn zruby_nil_value() mrb_value;
pub extern fn zruby_true_value() mrb_value;
pub extern fn zruby_false_value() mrb_value;
pub extern fn zruby_undef_value() mrb_value;
pub extern fn zruby_int_value(mrb: *mrb_state, i: mrb_int) mrb_value;
pub extern fn zruby_float_value(mrb: *mrb_state, f: mrb_float) mrb_value;
pub extern fn zruby_bool_value(mrb: *mrb_state, b: mrb_bool) mrb_value;
pub extern fn zruby_symbol_value(mrb: *mrb_state, sym: mrb_sym) mrb_value;
pub extern fn zruby_type(v: mrb_value) c_int;
pub extern fn zruby_nil_p(v: mrb_value) bool;
pub extern fn zruby_true_p(v: mrb_value) bool;
pub extern fn zruby_false_p(v: mrb_value) bool;
pub extern fn zruby_undef_p(v: mrb_value) bool;
pub extern fn zruby_integer_p(v: mrb_value) bool;
pub extern fn zruby_float_p(v: mrb_value) bool;
pub extern fn zruby_string_p(v: mrb_value) bool;
pub extern fn zruby_array_p(v: mrb_value) bool;
pub extern fn zruby_hash_p(v: mrb_value) bool;
pub extern fn zruby_symbol_p(v: mrb_value) bool;
pub extern fn zruby_exception_p(v: mrb_value) bool;
pub extern fn zruby_to_int(mrb: *mrb_state, v: mrb_value) mrb_int;
pub extern fn zruby_to_float(mrb: *mrb_state, v: mrb_value) mrb_float;
pub extern fn zruby_str_ptr(v: mrb_value) [*c]const u8;
pub extern fn zruby_str_len(v: mrb_value) mrb_int;
pub extern fn zruby_has_exc(mrb: *mrb_state) bool;
pub extern fn zruby_get_exc(mrb: *mrb_state) mrb_value;
pub extern fn zruby_clear_exc(mrb: *mrb_state) void;
pub extern fn zruby_cxt_capture_errors(cxt: *mrb_ccontext) void;
pub extern fn zruby_parser_nerr(parser: *const mrb_parser_state) usize;
pub extern fn zruby_parser_error_message(
    parser: *const mrb_parser_state,
    index: usize,
) [*c]const u8;
pub extern fn zruby_parser_error_lineno(parser: *const mrb_parser_state, index: usize) c_int;
pub extern fn zruby_parser_error_column(parser: *const mrb_parser_state, index: usize) c_int;

// High-level callback helpers implemented in shim.c.
pub extern fn zruby_cptr_value(mrb: *mrb_state, p: ?*anyopaque) mrb_value;
pub extern fn zruby_cptr(value: mrb_value) ?*anyopaque;
pub extern fn zruby_get_args_array(
    mrb: *mrb_state,
    argv: *[*c]const mrb_value,
) mrb_int;
pub extern fn zruby_define_proc_method(
    mrb: *mrb_state,
    class: *RClass,
    mid: mrb_sym,
    proc: *RProc,
    aspec: mrb_aspec,
    visibility: c_int,
) void;
pub extern fn zruby_define_module_function_proc(
    mrb: *mrb_state,
    module: *RClass,
    mid: mrb_sym,
    proc: *RProc,
    aspec: mrb_aspec,
) void;
pub extern fn zruby_define_class_method_proc(
    mrb: *mrb_state,
    class: *RClass,
    mid: mrb_sym,
    proc: *RProc,
    aspec: mrb_aspec,
) void;
pub extern fn zruby_raise_callback_error(
    mrb: *mrb_state,
    kind: c_int,
    message: [*c]const u8,
    message_len: usize,
) noreturn;
