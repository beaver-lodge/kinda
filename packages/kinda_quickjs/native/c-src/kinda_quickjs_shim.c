#include "kinda_quickjs_shim.h"
#include <quickjs.h>
#include <stdlib.h>
#include <string.h>

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
