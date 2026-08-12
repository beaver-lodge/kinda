cmake_minimum_required(VERSION 3.13.4)
set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
project(kinda-example)

if(WIN32)
  add_library(KindaExample STATIC lib/KindaExample.cpp)
else()
  add_library(KindaExample SHARED lib/KindaExample.cpp)
endif()
target_include_directories(KindaExample PUBLIC include)
install(
  TARGETS KindaExample
  RUNTIME DESTINATION lib
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
