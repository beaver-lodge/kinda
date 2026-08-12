#include "kinda_lua_shim.h"
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <stdlib.h>
#include <string.h>

struct kinda_lua_allocator {
  size_t budget;
  size_t calls;
  size_t live_bytes;
  size_t peak_bytes;
};

static void *kinda_lua_allocate(void *userdata, void *pointer, size_t old_size, size_t new_size) {
  struct kinda_lua_allocator *allocator = userdata;
  allocator->calls++;
  if (new_size == 0) {
    allocator->live_bytes -= old_size;
    free(pointer);
    return NULL;
  }
  size_t next = allocator->live_bytes - old_size + new_size;
  if (allocator->budget != 0 && next > allocator->budget) return NULL;
  void *result = realloc(pointer, new_size);
  if (result == NULL) return NULL;
  allocator->live_bytes = next;
  if (next > allocator->peak_bytes) allocator->peak_bytes = next;
  return result;
}

kinda_lua_allocator *kinda_lua_allocator_create(size_t budget) {
  struct kinda_lua_allocator *allocator = calloc(1, sizeof(*allocator));
  if (allocator != NULL) allocator->budget = budget;
  return allocator;
}

void kinda_lua_allocator_destroy(kinda_lua_allocator *allocator) { free(allocator); }
size_t kinda_lua_allocator_calls(kinda_lua_allocator *allocator) { return allocator->calls; }
size_t kinda_lua_allocator_live_bytes(kinda_lua_allocator *allocator) { return allocator->live_bytes; }
size_t kinda_lua_allocator_peak_bytes(kinda_lua_allocator *allocator) { return allocator->peak_bytes; }

lua_State *kinda_lua_open(kinda_lua_allocator *allocator) {
  lua_State *state = lua_newstate(kinda_lua_allocate, allocator);
  if (state != NULL) luaL_openlibs(state);
  return state;
}

void kinda_lua_close(lua_State *state) { lua_close(state); }

const char *kinda_lua_version(void) { return LUA_RELEASE; }

static void kinda_lua_export(lua_State *state, struct kinda_lua_result *result) {
  int type = lua_type(state, -1);
  if (type == LUA_TNIL) result->type = KINDA_LUA_NIL;
  else if (type == LUA_TBOOLEAN) {
    result->type = KINDA_LUA_BOOLEAN;
    result->boolean_value = lua_toboolean(state, -1);
  }
  else if (type == LUA_TNUMBER && lua_isinteger(state, -1)) {
    result->type = KINDA_LUA_INTEGER;
    result->integer_value = (int64_t)lua_tointeger(state, -1);
  }
  else if (type == LUA_TNUMBER) {
    result->type = KINDA_LUA_NUMBER;
    result->number_value = (double)lua_tonumber(state, -1);
  }
  else if (type == LUA_TSTRING) {
    result->type = KINDA_LUA_STRING;
    result->string_value = lua_tolstring(state, -1, &result->string_length);
  }
  else result->type = KINDA_LUA_UNSUPPORTED;
}

int kinda_lua_eval_state(lua_State *state, const char *source, size_t length, int *count) {
  lua_settop(state, 0);
  int status = luaL_loadbufferx(state, source, length, "kinda", "t");
  if (status == LUA_OK) status = lua_pcall(state, 0, LUA_MULTRET, 0);
  *count = status == LUA_OK ? lua_gettop(state) : 0;
  return status;
}

void kinda_lua_result_at(lua_State *state, int index, struct kinda_lua_result *result) {
  lua_pushvalue(state, index);
  kinda_lua_export(state, result);
  lua_pop(state, 1);
}

void kinda_lua_clear_stack(lua_State *state) { lua_settop(state, 0); }

int kinda_lua_coroutine_create(lua_State *state, const char *source, size_t length, int *reference) {
  lua_State *thread = lua_newthread(state);
  *reference = luaL_ref(state, LUA_REGISTRYINDEX);
  int status = luaL_loadbufferx(thread, source, length, "kinda-coroutine", "t");
  if (status != LUA_OK) {
    luaL_unref(state, LUA_REGISTRYINDEX, *reference);
    *reference = LUA_NOREF;
  }
  return status;
}

static lua_State *kinda_lua_coroutine(lua_State *state, int reference) {
  lua_rawgeti(state, LUA_REGISTRYINDEX, reference);
  lua_State *thread = lua_tothread(state, -1);
  lua_pop(state, 1);
  return thread;
}

int kinda_lua_coroutine_resume(lua_State *state, int reference, int *yielded, int *count) {
  lua_State *thread = kinda_lua_coroutine(state, reference);
  if (thread == NULL) return LUA_ERRRUN;
  int results = 0;
  int status = lua_resume(thread, state, 0, &results);
  *yielded = status == LUA_YIELD;
  *count = (status == LUA_OK || status == LUA_YIELD) ? results : 0;
  return status == LUA_YIELD ? LUA_OK : status;
}

void kinda_lua_coroutine_result_at(lua_State *state, int reference, int index,
                                   struct kinda_lua_result *result) {
  lua_State *thread = kinda_lua_coroutine(state, reference);
  lua_pushvalue(thread, index);
  kinda_lua_export(thread, result);
  lua_pop(thread, 1);
}

void kinda_lua_coroutine_clear(lua_State *state, int reference) {
  lua_State *thread = kinda_lua_coroutine(state, reference);
  if (thread != NULL) lua_settop(thread, 0);
}

void kinda_lua_coroutine_release(lua_State *state, int reference) {
  luaL_unref(state, LUA_REGISTRYINDEX, reference);
}

int kinda_lua_eval(const char *source, size_t length, struct kinda_lua_result *result) {
  lua_State *state = luaL_newstate();
  if (state == NULL) return LUA_ERRMEM;
  luaL_openlibs(state);
  int status = luaL_loadbufferx(state, source, length, "kinda", "t");
  if (status == LUA_OK) status = lua_pcall(state, 0, 1, 0);
  if (status == LUA_OK) {
    kinda_lua_export(state, result);
    if (result->type == KINDA_LUA_STRING) {
      char *copy = malloc(result->string_length);
      if (copy == NULL && result->string_length != 0) status = LUA_ERRMEM;
      else {
        memcpy(copy, result->string_value, result->string_length);
        result->string_value = copy;
        result->owns_string = 1;
      }
    }
  }
  lua_close(state);
  return status;
}

void kinda_lua_result_release(struct kinda_lua_result *result) {
  if (result->owns_string) free((void *)result->string_value);
  result->string_value = NULL;
  result->string_length = 0;
  result->owns_string = 0;
}
