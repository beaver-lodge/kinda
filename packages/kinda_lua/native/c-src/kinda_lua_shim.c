#include "kinda_lua_shim.h"
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <stdlib.h>
#include <string.h>

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
