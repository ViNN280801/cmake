# =============================================================================
# BuildTimingRun.cmake
# Script-mode wrapper: time a full `cmake --build` (total wall-clock)
# =============================================================================
#
# Usage:
#   cmake -Dbuild_dir=<binary_dir> [-Dconfig=<cfg>] [-Dtarget=<name>] \
#     -P <path>/BuildTimingRun.cmake
#
# Prefer calling configure_build_timing(ENABLE ON) from CMakeLists.txt, which
# prints the exact command for the current build tree.
# =============================================================================

cmake_minimum_required(VERSION 3.16)

if(NOT DEFINED build_dir OR build_dir STREQUAL "")
  message(FATAL_ERROR
    "BuildTimingRun: pass -Dbuild_dir=<path to CMake binary dir>")
endif()

get_filename_component(build_dir "${build_dir}" ABSOLUTE)

if(NOT EXISTS "${build_dir}/CMakeCache.txt")
  message(FATAL_ERROR
    "BuildTimingRun: '${build_dir}' does not look like a CMake build tree "
    "(CMakeCache.txt missing)")
endif()

set(_cmd "${CMAKE_COMMAND}" --build "${build_dir}")
if(DEFINED config AND NOT config STREQUAL "")
  list(APPEND _cmd --config "${config}")
endif()
if(DEFINED target AND NOT target STREQUAL "")
  list(APPEND _cmd --target "${target}")
endif()
list(APPEND _cmd --parallel)

message(STATUS "BuildTiming: starting timed build")
message(STATUS "BuildTiming: ${_cmd}")

string(TIMESTAMP _t0 "%s")
execute_process(
  COMMAND ${_cmd}
  RESULT_VARIABLE _rc
)
string(TIMESTAMP _t1 "%s")
math(EXPR _elapsed "${_t1} - ${_t0}")

set(_human "${_elapsed}s")
if(_elapsed GREATER_EQUAL 60)
  math(EXPR _m "${_elapsed} / 60")
  math(EXPR _s "${_elapsed} % 60")
  if(_m GREATER_EQUAL 60)
    math(EXPR _h "${_m} / 60")
    math(EXPR _m "${_m} % 60")
    set(_human "${_h}h ${_m}m ${_s}s (${_elapsed}s)")
  else()
    set(_human "${_m}m ${_s}s (${_elapsed}s)")
  endif()
endif()

message(STATUS "BuildTiming: total wall-clock ${_human}")

if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "BuildTiming: build failed with exit code ${_rc}")
endif()
