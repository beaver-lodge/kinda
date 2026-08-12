#ifndef KINDA_QUICKJS_SHIM_H
#define KINDA_QUICKJS_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum kinda_quickjs_type {
  KINDA_QUICKJS_UNDEFINED = 0,
  KINDA_QUICKJS_NULL = 1,
  KINDA_QUICKJS_BOOLEAN = 2,
  KINDA_QUICKJS_INTEGER = 3,
  KINDA_QUICKJS_NUMBER = 4,
  KINDA_QUICKJS_STRING = 5,
  KINDA_QUICKJS_UNSUPPORTED = 6
};

struct kinda_quickjs_result {
  int type;
  int boolean_value;
  int64_t integer_value;
  double number_value;
  char *string_value;
  size_t string_length;
};

typedef struct kinda_quickjs_runtime kinda_quickjs_runtime;
typedef struct kinda_quickjs_context kinda_quickjs_context;
typedef struct kinda_quickjs_value kinda_quickjs_value;

const char *kinda_quickjs_version(void);
int kinda_quickjs_eval(const char *source, size_t length,
                       struct kinda_quickjs_result *result);
void kinda_quickjs_result_release(struct kinda_quickjs_result *result);
kinda_quickjs_runtime *kinda_quickjs_runtime_create(size_t memory_limit,
                                                    size_t stack_limit);
void kinda_quickjs_runtime_destroy(kinda_quickjs_runtime *runtime);
void kinda_quickjs_runtime_stats(kinda_quickjs_runtime *runtime,
                                 size_t *allocations, size_t *live_bytes,
                                 size_t *limit);
kinda_quickjs_context *kinda_quickjs_context_create(kinda_quickjs_runtime *runtime);
void kinda_quickjs_context_destroy(kinda_quickjs_context *context);
int kinda_quickjs_context_eval(kinda_quickjs_runtime *runtime,
                               kinda_quickjs_context *context,
                               const char *source, size_t length,
                               uint64_t interrupt_budget,
                               struct kinda_quickjs_result *result);
kinda_quickjs_value *kinda_quickjs_value_eval(kinda_quickjs_runtime *runtime,
                                              kinda_quickjs_context *context,
                                              const char *source, size_t length);
void kinda_quickjs_value_destroy(kinda_quickjs_value *value);
int kinda_quickjs_value_export(kinda_quickjs_value *value,
                               struct kinda_quickjs_result *result);
int kinda_quickjs_promise_state(kinda_quickjs_value *value);
int kinda_quickjs_promise_result(kinda_quickjs_value *value,
                                 struct kinda_quickjs_result *result);
int kinda_quickjs_run_jobs(kinda_quickjs_runtime *runtime, size_t limit,
                           size_t *executed);

#endif
