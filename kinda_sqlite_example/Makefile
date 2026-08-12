NATIVE_INSTALL_DIR = ${MIX_APP_PATH}/priv
ZIG_CACHE_DIR = ${MIX_APP_PATH}/zig_cache
.PHONY: all clean

all:
	zig build --cache-dir ${ZIG_CACHE_DIR} \
	  --prefix ${NATIVE_INSTALL_DIR} \
	  --search-prefix ${ERTS_INCLUDE_DIR}/.. \
	  -freference-trace

clean:
	rm -rf ${NATIVE_INSTALL_DIR}
