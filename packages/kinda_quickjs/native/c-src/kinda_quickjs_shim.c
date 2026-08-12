#include "kinda_quickjs_shim.h"
#include <quickjs.h>
#include <stdlib.h>
#include <string.h>

struct kinda_quickjs_runtime {
  JSRuntime *handle;
  uint64_t interrupt_budget;
  int interrupt_limited;
};

struct kinda_quickjs_context {
  JSContext *handle;
};

static int interrupt_handler(JSRuntime *runtime, void *opaque) {
  (void)runtime;
  struct kinda_quickjs_runtime *owner = opaque;
  if (!owner->interrupt_limited) return 0;
  if (owner->interrupt_budget == 0) return 1;
  owner->interrupt_budget--;
  return 0;
}

const char *kinda_quickjs_version(void) { return CONFIG_VERSION; }

static int export_value(JSContext *context, JSValueConst value,
                        struct kinda_quickjs_result *result) {
  if (JS_IsUndefined(value)) result->type = KINDA_QUICKJS_UNDEFINED;
  else if (JS_IsNull(value)) result->type = KINDA_QUICKJS_NULL;
  else if (JS_IsBool(value)) {
    result->type = KINDA_QUICKJS_BOOLEAN;
    result->boolean_value = JS_ToBool(context, value);
  } else if (JS_IsNumber(value)) {
    int64_t integer;
    double number;
    if (JS_ToInt64(context, &integer, value) == 0 &&
        JS_ToFloat64(context, &number, value) == 0 && (double)integer == number) {
      result->type = KINDA_QUICKJS_INTEGER;
      result->integer_value = integer;
    } else if (JS_ToFloat64(context, &result->number_value, value) == 0) {
      result->type = KINDA_QUICKJS_NUMBER;
    } else return -1;
  } else if (JS_IsString(value)) {
    const char *string = JS_ToCStringLen(context, &result->string_length, value);
    if (string == NULL) return -1;
    result->string_value = malloc(result->string_length);
    if (result->string_value == NULL && result->string_length != 0) {
      JS_FreeCString(context, string);
      return -1;
    }
    if (result->string_length != 0)
      memcpy(result->string_value, string, result->string_length);
    JS_FreeCString(context, string);
    result->type = KINDA_QUICKJS_STRING;
  } else result->type = KINDA_QUICKJS_UNSUPPORTED;
  return 0;
}

int kinda_quickjs_eval(const char *source, size_t length,
                       struct kinda_quickjs_result *result) {
  char *terminated = malloc(length + 1);
  if (terminated == NULL) return -1;
  memcpy(terminated, source, length);
  terminated[length] = '\0';
  JSRuntime *runtime = JS_NewRuntime();
  if (runtime == NULL) { free(terminated); return -1; }
  JSContext *context = JS_NewContext(runtime);
  if (context == NULL) { JS_FreeRuntime(runtime); free(terminated); return -1; }
  JSValue value = JS_Eval(context, terminated, length, "kinda", JS_EVAL_TYPE_GLOBAL);
  int status = JS_IsException(value) ? -1 : export_value(context, value, result);
  JS_FreeValue(context, value);
  JS_FreeContext(context);
  JS_FreeRuntime(runtime);
  free(terminated);
  return status;
}

void kinda_quickjs_result_release(struct kinda_quickjs_result *result) {
  free(result->string_value);
  result->string_value = NULL;
  result->string_length = 0;
}

kinda_quickjs_runtime *kinda_quickjs_runtime_create(size_t memory_limit,
                                                    size_t stack_limit) {
  struct kinda_quickjs_runtime *runtime = calloc(1, sizeof(*runtime));
  if (runtime == NULL) return NULL;
  runtime->handle = JS_NewRuntime();
  if (runtime->handle == NULL) { free(runtime); return NULL; }
  if (memory_limit != 0) JS_SetMemoryLimit(runtime->handle, memory_limit);
  if (stack_limit != 0) JS_SetMaxStackSize(runtime->handle, stack_limit);
  JS_SetInterruptHandler(runtime->handle, interrupt_handler, runtime);
  return runtime;
}

void kinda_quickjs_runtime_destroy(kinda_quickjs_runtime *runtime) {
  if (runtime == NULL) return;
  JS_FreeRuntime(runtime->handle);
  free(runtime);
}

void kinda_quickjs_runtime_stats(kinda_quickjs_runtime *runtime,
                                 size_t *allocations, size_t *live_bytes,
                                 size_t *limit) {
  JSMemoryUsage usage;
  JS_ComputeMemoryUsage(runtime->handle, &usage);
  *allocations = usage.malloc_count;
  *live_bytes = usage.malloc_size;
  *limit = usage.malloc_limit;
}

kinda_quickjs_context *kinda_quickjs_context_create(kinda_quickjs_runtime *runtime) {
  struct kinda_quickjs_context *context = malloc(sizeof(*context));
  if (context == NULL) return NULL;
  context->handle = JS_NewContext(runtime->handle);
  if (context->handle == NULL) { free(context); return NULL; }
  return context;
}

void kinda_quickjs_context_destroy(kinda_quickjs_context *context) {
  if (context == NULL) return;
  JS_FreeContext(context->handle);
  free(context);
}

int kinda_quickjs_context_eval(kinda_quickjs_runtime *runtime,
                               kinda_quickjs_context *context,
                               const char *source, size_t length,
                               uint64_t interrupt_budget,
                               struct kinda_quickjs_result *result) {
  char *terminated = malloc(length + 1);
  if (terminated == NULL) return -1;
  memcpy(terminated, source, length);
  terminated[length] = '\0';
  runtime->interrupt_budget = interrupt_budget;
  runtime->interrupt_limited = interrupt_budget != 0;
  JSValue value = JS_Eval(context->handle, terminated, length, "kinda",
                          JS_EVAL_TYPE_GLOBAL);
  runtime->interrupt_limited = 0;
  free(terminated);
  int status = JS_IsException(value) ? -1 : export_value(context->handle, value, result);
  JS_FreeValue(context->handle, value);
  return status;
}
