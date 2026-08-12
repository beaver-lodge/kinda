#ifndef KINDA_MRUBY_SHIM_H
#define KINDA_MRUBY_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef struct mrb_state mrb_state;
typedef uintptr_t kinda_mruby_value;

enum kinda_mruby_type {
  KINDA_MRUBY_TT_FALSE = 0,
  KINDA_MRUBY_TT_TRUE = 1,
  KINDA_MRUBY_TT_INTEGER = 6,
  KINDA_MRUBY_TT_STRING = 18
};

typedef struct kinda_mruby_allocator {
  size_t allocation_calls;
  size_t live_bytes;
  size_t peak_bytes;
  size_t fail_after;
  size_t failure_count;
} kinda_mruby_allocator;

const char *kinda_mruby_version(void);
mrb_state *kinda_mruby_open_default(void);
void kinda_mruby_close(mrb_state *mrb);
int kinda_mruby_raised(mrb_state *mrb);
int kinda_mruby_type(kinda_mruby_value value);
int kinda_mruby_nil(kinda_mruby_value value);
int64_t kinda_mruby_integer(kinda_mruby_value value);
const char *kinda_mruby_string_ptr(kinda_mruby_value value);
size_t kinda_mruby_string_len(kinda_mruby_value value);
kinda_mruby_value kinda_mruby_eval(mrb_state *mrb, const char *source, size_t length, int *raised);
int kinda_mruby_arena_save(mrb_state *mrb);
void kinda_mruby_arena_restore(mrb_state *mrb, int index);
int kinda_mruby_immediate(kinda_mruby_value value);
void kinda_mruby_gc_register(mrb_state *mrb, kinda_mruby_value value);
void kinda_mruby_gc_unregister(mrb_state *mrb, kinda_mruby_value value);
void kinda_mruby_clear_exception(mrb_state *mrb);
int kinda_mruby_compile(mrb_state *mrb, const char *source, size_t length, uint8_t **bytes, size_t *size);
void kinda_mruby_free(mrb_state *mrb, void *pointer);
kinda_mruby_value kinda_mruby_run_bytecode_protected(mrb_state *mrb, const void *bytes, size_t size, int *raised);
void kinda_mruby_allocator_init(kinda_mruby_allocator *allocator);
void kinda_mruby_allocator_set_budget(kinda_mruby_allocator *allocator, size_t additional_allocations);
kinda_mruby_allocator *kinda_mruby_allocator_enter(kinda_mruby_allocator *allocator);
void kinda_mruby_allocator_leave(kinda_mruby_allocator *previous);
mrb_state *kinda_mruby_open(kinda_mruby_allocator *allocator);

#endif
