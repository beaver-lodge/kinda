#include "kinda_quickjs_shim.h"
#include <quickjs.h>
#include <stdlib.h>
#include <string.h>

struct kinda_quickjs_runtime {
  JSRuntime *handle;
  uint64_t interrupt_budget;
  int interrupt_limited;
  struct kinda_quickjs_module *modules;
};

struct kinda_quickjs_module {
  char *name;
  char *source;
  size_t source_length;
  struct kinda_quickjs_module *next;
};

struct kinda_quickjs_context {
  JSContext *handle;
};

struct kinda_quickjs_value {
  JSContext *context;
  JSValue handle;
};

static int interrupt_handler(JSRuntime *runtime, void *opaque) {
  (void)runtime;
  struct kinda_quickjs_runtime *owner = opaque;
  if (!owner->interrupt_limited) return 0;
  if (owner->interrupt_budget == 0) return 1;
  owner->interrupt_budget--;
  return 0;
}

static JSModuleDef *module_loader(JSContext *context, const char *name,
                                  void *opaque) {
  struct kinda_quickjs_runtime *runtime = opaque;
  struct kinda_quickjs_module *module = runtime->modules;
  while (module != NULL && strcmp(module->name, name) != 0) module = module->next;
  if (module == NULL) {
    JS_ThrowReferenceError(context, "module '%s' is not registered", name);
    return NULL;
  }
  JSValue compiled = JS_Eval(context, module->source, module->source_length,
                             name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
  if (JS_IsException(compiled)) return NULL;
  JSModuleDef *definition = JS_VALUE_GET_PTR(compiled);
  JS_FreeValue(context, compiled);
  return definition;
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
  JS_SetModuleLoaderFunc(runtime->handle, NULL, module_loader, runtime);
  return runtime;
}

void kinda_quickjs_runtime_destroy(kinda_quickjs_runtime *runtime) {
  if (runtime == NULL) return;
  struct kinda_quickjs_module *module = runtime->modules;
  while (module != NULL) {
    struct kinda_quickjs_module *next = module->next;
    free(module->name);
    free(module->source);
    free(module);
    module = next;
  }
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
  /* A BEAM dirty scheduler may execute this runtime on a different OS thread
     than the one that created it. QuickJS caches the current thread's stack
     top, so refresh it before entering the interpreter. */
  JS_UpdateStackTop(runtime->handle);
  JSValue value = JS_Eval(context->handle, terminated, length, "kinda",
                          JS_EVAL_TYPE_GLOBAL);
  runtime->interrupt_limited = 0;
  free(terminated);
  int status = JS_IsException(value) ? -1 : export_value(context->handle, value, result);
  JS_FreeValue(context->handle, value);
  return status;
}

kinda_quickjs_value *kinda_quickjs_value_eval(kinda_quickjs_runtime *runtime,
                                              kinda_quickjs_context *context,
                                              const char *source, size_t length) {
  (void)runtime;
  char *terminated = malloc(length + 1);
  if (terminated == NULL) return NULL;
  memcpy(terminated, source, length);
  terminated[length] = '\0';
  JSValue handle = JS_Eval(context->handle, terminated, length, "kinda-value",
                           JS_EVAL_TYPE_GLOBAL);
  free(terminated);
  if (JS_IsException(handle)) { JS_FreeValue(context->handle, handle); return NULL; }
  struct kinda_quickjs_value *value = malloc(sizeof(*value));
  if (value == NULL) { JS_FreeValue(context->handle, handle); return NULL; }
  value->context = context->handle;
  value->handle = handle;
  return value;
}

void kinda_quickjs_value_destroy(kinda_quickjs_value *value) {
  if (value == NULL) return;
  JS_FreeValue(value->context, value->handle);
  free(value);
}

int kinda_quickjs_value_export(kinda_quickjs_value *value,
                               struct kinda_quickjs_result *result) {
  return export_value(value->context, value->handle, result);
}

int kinda_quickjs_promise_state(kinda_quickjs_value *value) {
  return JS_PromiseState(value->context, value->handle);
}

int kinda_quickjs_promise_result(kinda_quickjs_value *value,
                                 struct kinda_quickjs_result *result) {
  JSValue handle = JS_PromiseResult(value->context, value->handle);
  int status = export_value(value->context, handle, result);
  JS_FreeValue(value->context, handle);
  return status;
}

int kinda_quickjs_run_jobs(kinda_quickjs_runtime *runtime, size_t limit,
                           size_t *executed) {
  *executed = 0;
  while (limit == 0 || *executed < limit) {
    JSContext *context = NULL;
    int status = JS_ExecutePendingJob(runtime->handle, &context);
    if (status < 0) return -1;
    if (status == 0) return 0;
    (*executed)++;
  }
  return 0;
}

int kinda_quickjs_register_module(kinda_quickjs_runtime *runtime,
                                  const char *name, size_t name_length,
                                  const char *source, size_t source_length) {
  struct kinda_quickjs_module *module = calloc(1, sizeof(*module));
  if (module == NULL) return -1;
  module->name = malloc(name_length + 1);
  module->source = malloc(source_length + 1);
  if (module->name == NULL || module->source == NULL) {
    free(module->name); free(module->source); free(module); return -1;
  }
  memcpy(module->name, name, name_length); module->name[name_length] = '\0';
  memcpy(module->source, source, source_length); module->source[source_length] = '\0';
  module->source_length = source_length;
  module->next = runtime->modules;
  runtime->modules = module;
  return 0;
}

int kinda_quickjs_eval_module(kinda_quickjs_runtime *runtime,
                              kinda_quickjs_context *context,
                              const char *source, size_t length) {
  (void)runtime;
  char *terminated = malloc(length + 1);
  if (terminated == NULL) return -1;
  memcpy(terminated, source, length);
  terminated[length] = '\0';
  JSValue value = JS_Eval(context->handle, terminated, length, "kinda-entry.mjs",
                          JS_EVAL_TYPE_MODULE);
  free(terminated);
  int status = JS_IsException(value) ? -1 : 0;
  JS_FreeValue(context->handle, value);
  return status;
}

int kinda_quickjs_compile(kinda_quickjs_context *context,
                          const char *source, size_t length,
                          unsigned char **bytes, size_t *size) {
  char *terminated = malloc(length + 1);
  if (terminated == NULL) return -1;
  memcpy(terminated, source, length);
  terminated[length] = '\0';
  JSValue compiled = JS_Eval(context->handle, terminated, length, "kinda-bytecode",
                             JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
  free(terminated);
  if (JS_IsException(compiled)) return -1;
  uint8_t *encoded = JS_WriteObject(context->handle, size, compiled, JS_WRITE_OBJ_BYTECODE);
  JS_FreeValue(context->handle, compiled);
  if (encoded == NULL) return -1;
  *bytes = malloc(*size);
  if (*bytes != NULL) memcpy(*bytes, encoded, *size);
  js_free(context->handle, encoded);
  return *bytes == NULL ? -1 : 0;
}

int kinda_quickjs_run_bytecode(kinda_quickjs_context *context,
                               const unsigned char *bytes, size_t size,
                               struct kinda_quickjs_result *result) {
  JSValue compiled = JS_ReadObject(context->handle, bytes, size, JS_READ_OBJ_BYTECODE);
  if (JS_IsException(compiled)) return -1;
  JSValue value = JS_EvalFunction(context->handle, compiled);
  int status = JS_IsException(value) ? -1 : export_value(context->handle, value, result);
  JS_FreeValue(context->handle, value);
  return status;
}

void kinda_quickjs_free(void *pointer) { free(pointer); }
