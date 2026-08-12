NATIVE_INSTALL_DIR = ${MIX_APP_PATH}/priv
ZIG_CACHE_DIR = ${MIX_APP_PATH}/zig_cache
.PHONY: all clean

all:
	elixir scripts/build.exs ${ZIG_CACHE_DIR} ${NATIVE_INSTALL_DIR} ${ERTS_INCLUDE_DIR}

clean:
	rm -rf ${NATIVE_INSTALL_DIR}
