/*
 * Small C bridge for mruby inline functions and macros that are not exported
 * symbols. This file is compiled by Zig with the same mruby headers as the
 * bindings.
 */
#include <stdbool.h>
#include <mruby.h>
#include <mruby/compile.h>
#include <mruby/error.h>
#include <mruby/string.h>
#include <mruby/version.h>

#if MRUBY_RELEASE_MAJOR != 4
#error "zruby currently requires mruby 4.x"
#endif
#if !defined(ZRUBY_ALLOW_ANY_MRUBY_4) && MRUBY_RELEASE_MINOR != 0
#error "zruby is tested with mruby 4.0.x; define ZRUBY_ALLOW_ANY_MRUBY_4 to try another 4.x"
#endif

_Static_assert(sizeof(mrb_value) == sizeof(uintptr_t),
               "zruby requires mruby's word-boxing mrb_value layout");
_Static_assert(sizeof(mrb_int) == 8, "zruby requires 64-bit mrb_int");
_Static_assert(sizeof(mrb_float) == 8, "zruby requires 64-bit mrb_float");

size_t zruby_value_size(void) { return sizeof(mrb_value); }

int zruby_arena_save(mrb_state *mrb) { return mrb_gc_arena_save(mrb); }
void zruby_arena_restore(mrb_state *mrb, int idx) {
  mrb_gc_arena_restore(mrb, idx);
}

mrb_value zruby_nil_value(void) { return mrb_nil_value(); }
mrb_value zruby_true_value(void) { return mrb_true_value(); }
mrb_value zruby_false_value(void) { return mrb_false_value(); }
mrb_value zruby_undef_value(void) { return mrb_undef_value(); }
mrb_value zruby_int_value(mrb_state *mrb, mrb_int i) {
  return mrb_int_value(mrb, i);
}
mrb_value zruby_float_value(mrb_state *mrb, mrb_float f) {
  return mrb_float_value(mrb, f);
}
mrb_value zruby_bool_value(mrb_state *mrb, mrb_bool b) {
  (void)mrb;
  return mrb_bool_value(b);
}
mrb_value zruby_symbol_value(mrb_state *mrb, mrb_sym sym) {
  (void)mrb;
  return mrb_symbol_value(sym);
}

int zruby_type(mrb_value v) { return (int)mrb_type(v); }
bool zruby_nil_p(mrb_value v) { return mrb_nil_p(v); }
bool zruby_true_p(mrb_value v) { return mrb_true_p(v); }
bool zruby_false_p(mrb_value v) { return mrb_false_p(v); }
bool zruby_undef_p(mrb_value v) { return mrb_undef_p(v); }
bool zruby_integer_p(mrb_value v) { return mrb_integer_p(v); }
bool zruby_float_p(mrb_value v) { return mrb_float_p(v); }
bool zruby_string_p(mrb_value v) { return mrb_string_p(v); }
bool zruby_array_p(mrb_value v) { return mrb_array_p(v); }
bool zruby_hash_p(mrb_value v) { return mrb_hash_p(v); }
bool zruby_symbol_p(mrb_value v) { return mrb_symbol_p(v); }
bool zruby_exception_p(mrb_value v) { return mrb_exception_p(v); }

mrb_int zruby_to_int(mrb_state *mrb, mrb_value v) {
  (void)mrb;
  return mrb_integer(v);
}
mrb_float zruby_to_float(mrb_state *mrb, mrb_value v) {
  (void)mrb;
  return mrb_float(v);
}
const char *zruby_str_ptr(mrb_value v) { return RSTRING_PTR(v); }
mrb_int zruby_str_len(mrb_value v) { return RSTRING_LEN(v); }

struct RClass *zruby_object_class(mrb_state *mrb) { return mrb->object_class; }

bool zruby_has_exc(mrb_state *mrb) { return mrb->exc != NULL; }
mrb_value zruby_get_exc(mrb_state *mrb) {
  return mrb->exc ? mrb_obj_value(mrb->exc) : mrb_nil_value();
}
void zruby_clear_exc(mrb_state *mrb) { mrb->exc = NULL; }

void zruby_cxt_capture_errors(mrb_ccontext *cxt) {
  cxt->capture_errors = TRUE;
}
size_t zruby_parser_nerr(const struct mrb_parser_state *parser) {
  return parser->nerr;
}
const char *zruby_parser_error_message(const struct mrb_parser_state *parser,
                                       size_t index) {
  if (index >= parser->nerr ||
      index >= sizeof(parser->error_buffer) / sizeof(parser->error_buffer[0])) {
    return NULL;
  }
  return parser->error_buffer[index].message;
}
int zruby_parser_error_lineno(const struct mrb_parser_state *parser,
                              size_t index) {
  if (index >= parser->nerr ||
      index >= sizeof(parser->error_buffer) / sizeof(parser->error_buffer[0])) {
    return 0;
  }
  return parser->error_buffer[index].lineno;
}
int zruby_parser_error_column(const struct mrb_parser_state *parser,
                              size_t index) {
  if (index >= parser->nerr ||
      index >= sizeof(parser->error_buffer) / sizeof(parser->error_buffer[0])) {
    return 0;
  }
  return parser->error_buffer[index].column;
}
