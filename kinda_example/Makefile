CMAKE_BUILD_DIR = ${MIX_APP_PATH}/cmake_build
NATIVE_INSTALL_DIR = ${MIX_APP_PATH}/priv
ZIG_CACHE_DIR = ${MIX_APP_PATH}/zig_cache
.PHONY: all zig_build cmake_build

all: zig_build

zig_build: cmake_build
	cd .. && zig build --cache-dir ${ZIG_CACHE_DIR} \
		--build-file build.example.zig \
	  --prefix ${NATIVE_INSTALL_DIR} \
		--search-prefix kinda_example/native/c-src \
		--search-prefix ${NATIVE_INSTALL_DIR} \
		--search-prefix ${ERTS_INCLUDE_DIR}/.. \
		-freference-trace

cmake_build:
	cmake -G Ninja -S native/c-src -B ${CMAKE_BUILD_DIR} -DCMAKE_INSTALL_PREFIX=${NATIVE_INSTALL_DIR}
	cmake --build ${CMAKE_BUILD_DIR} --target install

clean:
	rm -rf ${CMAKE_BUILD_DIR}
	rm -rf ${NATIVE_INSTALL_DIR}
