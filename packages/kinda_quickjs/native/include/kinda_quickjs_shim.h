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

const char *kinda_quickjs_version(void);
int kinda_quickjs_eval(const char *source, size_t length,
                       struct kinda_quickjs_result *result);
void kinda_quickjs_result_release(struct kinda_quickjs_result *result);

#endif
