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

typedef struct lua_State lua_State;
typedef struct kinda_lua_allocator kinda_lua_allocator;

const char *kinda_lua_version(void);
int kinda_lua_eval(const char *source, size_t length, struct kinda_lua_result *result);
void kinda_lua_result_release(struct kinda_lua_result *result);
kinda_lua_allocator *kinda_lua_allocator_create(size_t budget);
void kinda_lua_allocator_destroy(kinda_lua_allocator *allocator);
size_t kinda_lua_allocator_calls(kinda_lua_allocator *allocator);
size_t kinda_lua_allocator_live_bytes(kinda_lua_allocator *allocator);
size_t kinda_lua_allocator_peak_bytes(kinda_lua_allocator *allocator);
lua_State *kinda_lua_open(kinda_lua_allocator *allocator);
void kinda_lua_close(lua_State *state);
int kinda_lua_eval_state(lua_State *state, const char *source, size_t length, int *count);
void kinda_lua_result_at(lua_State *state, int index, struct kinda_lua_result *result);
void kinda_lua_clear_stack(lua_State *state);
int kinda_lua_coroutine_create(lua_State *state, const char *source, size_t length, int *reference);
int kinda_lua_coroutine_resume(lua_State *state, int reference, int *yielded, int *count);
void kinda_lua_coroutine_result_at(lua_State *state, int reference, int index, struct kinda_lua_result *result);
void kinda_lua_coroutine_clear(lua_State *state, int reference);
void kinda_lua_coroutine_release(lua_State *state, int reference);
int kinda_lua_compile(const char *source, size_t length, unsigned char **bytes, size_t *size);
void kinda_lua_free(void *pointer);
int kinda_lua_run_bytecode(lua_State *state, const unsigned char *bytes, size_t size, int *count);
int kinda_lua_userdata_create(lua_State *state, int64_t value, int *reference);
int64_t kinda_lua_userdata_value(lua_State *state, int reference);
void kinda_lua_userdata_release(lua_State *state, int reference);

#endif
