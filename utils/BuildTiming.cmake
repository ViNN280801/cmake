# =============================================================================
# BuildTiming.cmake
# Profile per-compile / per-link wall time and optional full-build totals
# =============================================================================
#
# Uses RULE_LAUNCH_COMPILE / RULE_LAUNCH_LINK (Ninja and Makefile generators).
#
# On Windows, CMAKE_COMMAND often lives under "Program Files". Prefixing the
# raw path into a cmd.exe rule splits on the space ("C:/Program" not found).
# This module writes a tiny launcher script into the build tree (quoted cmake
# path inside) and points RULE_LAUNCH_* at that script instead.
#
# Do not also set CMAKE_<LANG>_COMPILER_LAUNCHER to the same wrapper - that
# double-wraps and breaks the command line.
#
# Functions:
#   configure_build_timing(
#     [ENABLE <ON|OFF>]           # Default: OFF
#   )
#
# When ENABLE is ON:
#   1. Prefixes every compile and link with `cmake -E time` so each step prints
#      "Elapsed time: ..." in the build log.
#   2. Prints how to get a single total wall-clock for the whole build
#      (sum of per-rule times is NOT wall-clock under --parallel):
#
#        cmake -Dbuild_dir=<bin> [-Dconfig=<cfg>] -P .../BuildTimingRun.cmake
#
# Usage:
#   include(utils/BuildTiming)
#   configure_build_timing(ENABLE ON)
# =============================================================================

include_guard(GLOBAL)

set(_BUILD_TIMING_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(configure_build_timing)
  set(options "")
  set(oneValueArgs ENABLE)
  set(multiValueArgs "")
  cmake_parse_arguments(BT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT DEFINED BT_ENABLE)
    set(BT_ENABLE OFF)
  endif()

  if(NOT BT_ENABLE)
    message(STATUS "BuildTiming: disabled (pass -D<PROJECT>_BUILD_TIMING=ON to enable)")
    return()
  endif()

  if(CMAKE_GENERATOR MATCHES "Visual Studio|Xcode")
    message(WARNING
      "BuildTiming: RULE_LAUNCH_* is ignored by generator '${CMAKE_GENERATOR}'. "
      "Use Ninja or Makefiles for per-rule timing. "
      "Full-build wall-clock via BuildTimingRun.cmake still works.")
  endif()

  # Clear any COMPILER_LAUNCHER we may have set earlier (double-wrap breaks builds).
  foreach(_bt_var
      CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER
      CMAKE_C_LINKER_LAUNCHER CMAKE_CXX_LINKER_LAUNCHER)
    unset(${_bt_var} PARENT_SCOPE)
    unset(${_bt_var} CACHE)
  endforeach()

  # Launcher script in the build tree - avoids unquoted "Program Files" in cmd.
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}")
  if(WIN32)
    set(_bt_launcher "${CMAKE_BINARY_DIR}/dchannel_cmake_e_time.cmd")
    # %* forwards all args; cmake path must stay quoted.
    file(WRITE "${_bt_launcher}"
      "@echo off\r\n\"${CMAKE_COMMAND}\" -E time %*\r\n")
  else()
    set(_bt_launcher "${CMAKE_BINARY_DIR}/dchannel_cmake_e_time")
    file(WRITE "${_bt_launcher}"
      "#!/bin/sh\nexec \"${CMAKE_COMMAND}\" -E time \"$@\"\n")
    # file(CHMOD) needs CMake 3.19+; keep 3.16-compatible.
    execute_process(COMMAND chmod +x "${_bt_launcher}")
  endif()

  # Forward slashes work in Ninja on Windows and avoid backslash escapes.
  file(TO_CMAKE_PATH "${_bt_launcher}" _bt_launcher)
  set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${_bt_launcher}")
  set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "${_bt_launcher}")

  set(_run_script "${_BUILD_TIMING_MODULE_DIR}/BuildTimingRun.cmake")
  set(_timed_cmd
    "cmake -Dbuild_dir=\"${CMAKE_BINARY_DIR}\" -P \"${_run_script}\"")
  if(CMAKE_CONFIGURATION_TYPES)
    set(_timed_cmd
      "cmake -Dbuild_dir=\"${CMAKE_BINARY_DIR}\" -Dconfig=<cfg> -P \"${_run_script}\"")
  elseif(CMAKE_BUILD_TYPE)
    set(_timed_cmd
      "cmake -Dbuild_dir=\"${CMAKE_BINARY_DIR}\" -Dconfig=${CMAKE_BUILD_TYPE} -P \"${_run_script}\"")
  endif()

  message(STATUS "BuildTiming: enabled - launcher: ${_bt_launcher}")
  message(STATUS "BuildTiming: total wall-clock (whole build, incl. parallel):")
  message(STATUS "  ${_timed_cmd}")
endfunction()
