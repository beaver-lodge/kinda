#include "kinda_mruby_shim.h"
#include <mruby.h>
#include <mruby/compile.h>
#include <mruby/error.h>
#include <mruby/string.h>
#include <mruby/version.h>

#ifndef MRB_WORD_BOXING
#error "kinda_mruby requires MRB_WORD_BOXING"
#endif

_Static_assert(KINDA_MRUBY_TT_FALSE == MRB_TT_FALSE, "false tag mismatch");
_Static_assert(KINDA_MRUBY_TT_TRUE == MRB_TT_TRUE, "true tag mismatch");
_Static_assert(KINDA_MRUBY_TT_INTEGER == MRB_TT_INTEGER, "integer tag mismatch");
_Static_assert(KINDA_MRUBY_TT_STRING == MRB_TT_STRING, "string tag mismatch");

static kinda_mruby_value kinda_mruby_export_value(mrb_value value) { return value.w; }
static mrb_value kinda_mruby_import_value(kinda_mruby_value value) {
  mrb_value result = {value};
  return result;
}
#include <mruby/dump.h>
#include <mruby/internal.h>
#include <mruby/irep.h>
#include <mruby/proc.h>

const char *kinda_mruby_version(void) { return MRUBY_VERSION; }
mrb_state *kinda_mruby_open_default(void) { return mrb_open(); }
void kinda_mruby_close(mrb_state *mrb) { mrb_close(mrb); }
int kinda_mruby_raised(mrb_state *mrb) { return mrb->exc != NULL; }
int kinda_mruby_type(kinda_mruby_value value) { return mrb_type(kinda_mruby_import_value(value)); }
int kinda_mruby_nil(kinda_mruby_value value) { return mrb_nil_p(kinda_mruby_import_value(value)); }
int64_t kinda_mruby_integer(kinda_mruby_value value) { return mrb_integer(kinda_mruby_import_value(value)); }
const char *kinda_mruby_string_ptr(kinda_mruby_value value) { return RSTRING_PTR(kinda_mruby_import_value(value)); }
size_t kinda_mruby_string_len(kinda_mruby_value value) { return RSTRING_LEN(kinda_mruby_import_value(value)); }
struct kinda_mruby_eval_request {
  const char *source;
  size_t length;
};

static mrb_value kinda_mruby_eval_body(mrb_state *mrb, void *userdata) {
  struct kinda_mruby_eval_request *request = userdata;
  return mrb_load_nstring(mrb, request->source, request->length);
}

kinda_mruby_value kinda_mruby_eval(mrb_state *mrb, const char *source, size_t length, int *raised) {
  struct kinda_mruby_eval_request request = {source, length};
  mrb_bool did_raise = FALSE;
  mrb_value value = mrb_protect_error(mrb, kinda_mruby_eval_body, &request, &did_raise);
  *raised = did_raise;
  return kinda_mruby_export_value(value);
}

int kinda_mruby_arena_save(mrb_state *mrb) { return mrb_gc_arena_save(mrb); }
void kinda_mruby_arena_restore(mrb_state *mrb, int index) { mrb_gc_arena_restore(mrb, index); }
int kinda_mruby_immediate(kinda_mruby_value value) { return mrb_immediate_p(kinda_mruby_import_value(value)); }
void kinda_mruby_gc_register(mrb_state *mrb, kinda_mruby_value value) { mrb_gc_register(mrb, kinda_mruby_import_value(value)); }
void kinda_mruby_gc_unregister(mrb_state *mrb, kinda_mruby_value value) { mrb_gc_unregister(mrb, kinda_mruby_import_value(value)); }
void kinda_mruby_clear_exception(mrb_state *mrb) { mrb->exc = NULL; }

int kinda_mruby_compile(mrb_state *mrb, const char *source, size_t length, uint8_t **bytes, size_t *size) {
  struct mrb_parser_state *parser = mrb_parse_nstring(mrb, source, length, NULL);
  if (parser == NULL) return MRB_DUMP_GENERAL_FAILURE;
  if (parser->nerr > 0) {
    mrb_parser_free(parser);
    return MRB_DUMP_INVALID_ARGUMENT;
  }
  struct RProc *proc = mrb_generate_code(mrb, parser);
  mrb_parser_free(parser);
  if (proc == NULL) return MRB_DUMP_GENERAL_FAILURE;
  return mrb_dump_irep(mrb, proc->body.irep, 0, bytes, size);
}

void kinda_mruby_free(mrb_state *mrb, void *pointer) { mrb_free(mrb, pointer); }

struct kinda_mruby_bytecode_request {
  const void *bytes;
  size_t size;
};

static mrb_value kinda_mruby_run_bytecode_body(mrb_state *mrb, void *userdata) {
  struct kinda_mruby_bytecode_request *request = userdata;
  return mrb_load_irep_buf(mrb, request->bytes, request->size);
}

kinda_mruby_value kinda_mruby_run_bytecode_protected(mrb_state *mrb, const void *bytes, size_t size, int *raised) {
  struct kinda_mruby_bytecode_request request = {bytes, size};
  mrb_bool did_raise = FALSE;
  mrb_value value = mrb_protect_error(mrb, kinda_mruby_run_bytecode_body, &request, &did_raise);
  *raised = did_raise;
  return kinda_mruby_export_value(value);
}
