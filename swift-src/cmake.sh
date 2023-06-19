set -ex
cmake \
  -DCMAKE_C_COMPILER="clang"  -DCMAKE_CXX_COMPILER="clang++" \
  -B 3_bidirectional_cxx_interop/build \
  -G 'Ninja' \
  -DLLVM_DIR=/usr/lib/llvm-17/lib/cmake/llvm \
  -DMLIR_DIR=/usr/lib/llvm-17/lib/cmake/mlir \
  3_bidirectional_cxx_interop
cmake --build 3_bidirectional_cxx_interop/build
./3_bidirectional_cxx_interop/build/src/fibonacci_cpp
./3_bidirectional_cxx_interop/build/src/fibonacci_swift
