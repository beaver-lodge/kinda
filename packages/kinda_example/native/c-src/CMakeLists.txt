cmake_minimum_required(VERSION 3.13.4)
set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
project(kinda-example)

add_library(KindaExample SHARED lib/KindaExample.cpp)
target_include_directories(KindaExample PUBLIC include)
install(TARGETS KindaExample DESTINATION lib)
