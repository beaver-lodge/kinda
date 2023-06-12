set -ex
mkdir -p build
cd build
cmake -DCMAKE_CXX_COMPILER="clang++" -G 'Ninja' ../
ninja
