cmake_minimum_required(VERSION 3.13.4)
set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "")
project(kinda-example)

add_library(KindaExample SHARED lib/KindaExample.cpp)
set_target_properties(KindaExample PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_include_directories(KindaExample PUBLIC include)
install(
  TARGETS KindaExample
  RUNTIME DESTINATION lib
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
