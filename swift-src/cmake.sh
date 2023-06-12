set -ex
mkdir -p build
cd build
cmake -DCMAKE_CXX_COMPILER="clang++" -G 'Ninja' ../
ninja
./src/fibonacci_cpp
./src/fibonacci_swift
