CMAKE_BUILD_DIR = ${MIX_APP_PATH}/cmake_build
NATIVE_INSTALL_DIR = ${MIX_APP_PATH}/native_install
cmake_build:
	cmake -G Ninja -S native/c-src -B ${CMAKE_BUILD_DIR} -DCMAKE_INSTALL_PREFIX=${NATIVE_INSTALL_DIR}
	cmake --build ${CMAKE_BUILD_DIR} --target install

clean:
	rm -rf ${CMAKE_BUILD_DIR}
	rm -rf ${NATIVE_INSTALL_DIR}
