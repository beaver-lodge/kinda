#ifndef KINDA_LUA_SHIM_H
#define KINDA_LUA_SHIM_H

#include <stddef.h>
#include <stdint.h>

enum kinda_lua_type {
  KINDA_LUA_NIL = 0,
  KINDA_LUA_BOOLEAN = 1,
  KINDA_LUA_INTEGER = 2,
  KINDA_LUA_NUMBER = 3,
  KINDA_LUA_STRING = 4,
  KINDA_LUA_UNSUPPORTED = 5
};

struct kinda_lua_result {
  int type;
  int boolean_value;
  int64_t integer_value;
  double number_value;
  const char *string_value;
  size_t string_length;
  int owns_string;
};

const char *kinda_lua_version(void);
int kinda_lua_eval(const char *source, size_t length, struct kinda_lua_result *result);
void kinda_lua_result_release(struct kinda_lua_result *result);

#endif
