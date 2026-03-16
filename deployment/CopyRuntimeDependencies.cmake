# =============================================================================
# CopyRuntimeDependencies.cmake
# Universal cross-platform runtime dependency copy helper (cmake -P script mode)
# =============================================================================
#
# Copies compiler runtime shared libraries next to a built binary so that the
# binary is runnable without the user having to install the toolchain runtimes.
#
# This script runs in CMake SCRIPT mode (cmake -P). It is designed to be
# invoked as a POST_BUILD command from CMakeLists.txt:
#
# add_custom_command(TARGET MyTarget POST_BUILD
# COMMAND ${CMAKE_COMMAND}
# -Dtarget_file=$<TARGET_FILE:MyTarget>
# [-Ddependency_name_regex=<regex>]
# -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/deployment/CopyRuntimeDependencies.cmake
# VERBATIM
# )
#
# Parameters (passed via -D on the cmake command line):
# target_file            - REQUIRED. Full path to the built binary.
# dependency_name_regex  - OPTIONAL. Regex against the dependency filename.
# If omitted, platform-specific defaults are used.
#
# Platform defaults (when dependency_name_regex is not specified):
# Windows  - vcruntime*, msvcp*, concrt*, ucrtbase*, api-ms-win-*
# macOS    - libc++, libc++abi, libunwind
# Linux    - libstdc++, libgcc_s, libgomp, libatomic, libc++, libunwind
# Other    - all resolved dependencies
#
# Notes:
# - Requires CMake 3.16+ (file(GET_RUNTIME_DEPENDENCIES) was added in 3.16).
# - Only already-resolved dependencies are copied; unresolved ones are logged.
# - System DLLs (kernel32.dll, ntdll.dll, etc.) are intentionally excluded by
# the default regex and are never copied.
# - On Windows, enable DCHANNEL_COPY_RUNTIME_DEPENDENCIES only for /MD
# (dynamic runtime); static /MT builds do not require separate DLLs.
# =============================================================================

cmake_minimum_required(VERSION 3.16)

if(NOT target_file OR NOT EXISTS "${target_file}")
  message(WARNING
    "CopyRuntimeDependencies: target_file missing or not found: '${target_file}'. "
    "Ensure the target was built before this script runs.")
  return()
endif()

get_filename_component(output_dir "${target_file}" DIRECTORY)

# --- Platform-specific default regex ----------------------------------------
if(NOT DEFINED dependency_name_regex OR dependency_name_regex STREQUAL "")
  if(WIN32)
    # MSVC CRT (vcruntime140, msvcp140, concrt140, ucrtbase)
    # Universal CRT forwarder DLLs (api-ms-win-crt-*)
    set(dependency_name_regex
      "^(vcruntime|msvcp|concrt|ucrtbase|api-ms-win)")
  elseif(APPLE)
    # libc++, libc++abi, libunwind shipped with Clang/libc++
    set(dependency_name_regex
      "^(libc\\+\\+|libc\\+\\+abi|libunwind)")
  elseif(UNIX)
    # libstdc++ / libgcc_s (GCC), libc++ / libunwind (Clang),
    # libgomp (OpenMP), libatomic (C++ atomics)
    set(dependency_name_regex
      "^(libstdc\\+\\+|libgcc_s|libgomp|libatomic|libquadmath|libc\\+\\+|libc\\+\\+abi|libunwind)")
  else()
    # Unknown host: copy everything that was resolved
    set(dependency_name_regex ".*")
  endif()
endif()

# --- Resolve runtime dependencies -------------------------------------------
# Use EXECUTABLES for executables (.exe or no .so/.dll/.dylib) so dependencies resolve correctly.
get_filename_component(_target_name "${target_file}" NAME)

if(WIN32 AND _target_name MATCHES "\\.exe$")
  set(_use_executables TRUE)
elseif(UNIX AND NOT _target_name MATCHES "\\.so")
  set(_use_executables TRUE)
else()
  set(_use_executables FALSE)
endif()

if(_use_executables)
  file(GET_RUNTIME_DEPENDENCIES
    EXECUTABLES "${target_file}"
    RESOLVED_DEPENDENCIES_VAR _resolved
    UNRESOLVED_DEPENDENCIES_VAR _unresolved
  )
else()
  file(GET_RUNTIME_DEPENDENCIES
    LIBRARIES "${target_file}"
    RESOLVED_DEPENDENCIES_VAR _resolved
    UNRESOLVED_DEPENDENCIES_VAR _unresolved
  )
endif()

# --- Copy matched dependencies ----------------------------------------------
set(_copied_count 0)

foreach(dep ${_resolved})
  get_filename_component(dep_name "${dep}" NAME)

  if(dep_name MATCHES "${dependency_name_regex}")
    file(COPY "${dep}" DESTINATION "${output_dir}")
    message(STATUS "CopyRuntimeDependencies: copied '${dep_name}' → '${output_dir}'")
    math(EXPR _copied_count "${_copied_count} + 1")
  endif()
endforeach()

if(_copied_count EQUAL 0)
  message(STATUS "CopyRuntimeDependencies: no matching runtime dependencies found "
    "(regex='${dependency_name_regex}')")
endif()

# --- Report unresolved (informational only) ---------------------------------
foreach(dep ${_unresolved})
  message(STATUS "CopyRuntimeDependencies: unresolved dependency '${dep}' "
    "(expected for system libraries)")
endforeach()
