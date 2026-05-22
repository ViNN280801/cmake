# =============================================================================
# SanitizerProfile.cmake
# Universal, project-agnostic helpers for sanitizer profile selection and
# propagation from cache options to targets.
#
# Requires SanitizersConfig.cmake (configure_sanitizers).
#
# Functions:
#   sanitizer_profile_validate(<profile> <allowed_profiles...>)
#   sanitizer_profile_apply(<profile> PREFIX <opt_prefix> [BUILD_TESTS <var>] [SKIP_IF_NO_TESTS])
#   sanitizer_configure_global_settings(
#     PREFIX <opt_prefix> PROJECT_LABEL <name>
#     [BUILD_SHARED_LIBS_WARN <ON|OFF>])
#   sanitizer_apply_to_target_from_options(<target>
#     PREFIX <opt_prefix> ENABLE_VAR <cache_var>)
#   sanitizer_build_uses_any(PREFIX <opt_prefix> OUT <var>)
# =============================================================================

function(sanitizer_profile_validate profileValue)
  set(_allowed ${ARGN})
  if(NOT profileValue IN_LIST _allowed)
    string(JOIN ", " _allowedStr ${_allowed})
    message(FATAL_ERROR
      "Invalid sanitizer profile '${profileValue}'. Allowed: ${_allowedStr}")
  endif()
endfunction()

function(_sanitizer_profile_set_option optPrefix suffix value description)
  set(${optPrefix}${suffix} ${value} CACHE BOOL "${description}" FORCE)
endfunction()

# Applies ASAN_UBSAN | TSAN | CFI | NONE profile to ${PREFIX}ASAN, ${PREFIX}TSAN, etc.
function(sanitizer_profile_apply profileValue)
  set(options SKIP_IF_NO_TESTS)
  set(oneValueArgs PREFIX BUILD_TESTS_VAR PROJECT_LABEL)
  cmake_parse_arguments(SP "${options}" "${oneValueArgs}" "" ${ARGN})

  if(NOT SP_PREFIX)
    message(FATAL_ERROR "sanitizer_profile_apply: PREFIX is required")
  endif()

  if(SP_SKIP_IF_NO_TESTS AND SP_BUILD_TESTS_VAR)
    if(NOT ${SP_BUILD_TESTS_VAR})
      return()
    endif()
  endif()

  if(WIN32 AND SP_SKIP_IF_NO_TESTS)
    return()
  endif()

  set(_label "${SP_PROJECT_LABEL}")
  if(NOT _label)
    set(_label "Project")
  endif()

  set(_p "${SP_PREFIX}")

  if(profileValue STREQUAL "ASAN_UBSAN")
    _sanitizer_profile_set_option("${_p}" "ASAN" ON "Enable AddressSanitizer (memory errors)")
    _sanitizer_profile_set_option("${_p}" "UBSAN" ON "Enable UndefinedBehaviorSanitizer (UB detection)")
    _sanitizer_profile_set_option("${_p}" "TSAN" OFF "Enable ThreadSanitizer (race conditions)")
    _sanitizer_profile_set_option("${_p}" "MSAN" OFF "Enable MemorySanitizer (uninitialized memory, Clang only)")
    _sanitizer_profile_set_option("${_p}" "LSAN" OFF "Enable LeakSanitizer (memory leaks)")
    _sanitizer_profile_set_option("${_p}" "CFI" OFF "Enable Control Flow Integrity (Clang only; requires LTO)")
    message(STATUS
      "${_label}: sanitizer profile ASAN_UBSAN - AddressSanitizer+UndefinedBehaviorSanitizer ON. "
      "Binary dir: ${CMAKE_BINARY_DIR}")
  elseif(profileValue STREQUAL "TSAN")
    _sanitizer_profile_set_option("${_p}" "TSAN" ON "Enable ThreadSanitizer (race conditions)")
    _sanitizer_profile_set_option("${_p}" "ASAN" OFF "Enable AddressSanitizer (memory errors)")
    _sanitizer_profile_set_option("${_p}" "UBSAN" OFF "Enable UndefinedBehaviorSanitizer (UB detection)")
    _sanitizer_profile_set_option("${_p}" "MSAN" OFF "Enable MemorySanitizer (uninitialized memory, Clang only)")
    _sanitizer_profile_set_option("${_p}" "LSAN" OFF "Enable LeakSanitizer (memory leaks)")
    _sanitizer_profile_set_option("${_p}" "CFI" OFF "Enable Control Flow Integrity (Clang only; requires LTO)")
    message(STATUS
      "${_label}: sanitizer profile TSAN - ThreadSanitizer ON (separate build tree). "
      "Binary dir: ${CMAKE_BINARY_DIR}")
  elseif(profileValue STREQUAL "CFI")
    _sanitizer_profile_set_option("${_p}" "CFI" ON "Enable Control Flow Integrity (Clang only; requires LTO)")
    _sanitizer_profile_set_option("${_p}" "UBSAN" ON "Enable UndefinedBehaviorSanitizer (UB detection)")
    _sanitizer_profile_set_option("${_p}" "ASAN" OFF "Enable AddressSanitizer (memory errors)")
    _sanitizer_profile_set_option("${_p}" "TSAN" OFF "Enable ThreadSanitizer (race conditions)")
    _sanitizer_profile_set_option("${_p}" "MSAN" OFF "Enable MemorySanitizer (uninitialized memory, Clang only)")
    _sanitizer_profile_set_option("${_p}" "LSAN" OFF "Enable LeakSanitizer (memory leaks)")
    message(STATUS
      "${_label}: sanitizer profile CFI - Control Flow Integrity + UBSan (Clang + LTO). "
      "Binary dir: ${CMAKE_BINARY_DIR}")
  elseif(profileValue STREQUAL "MSAN")
    _sanitizer_profile_set_option("${_p}" "MSAN" ON "Enable MemorySanitizer (uninitialized memory, Clang only)")
    _sanitizer_profile_set_option("${_p}" "ASAN" OFF "Enable AddressSanitizer (memory errors)")
    _sanitizer_profile_set_option("${_p}" "UBSAN" OFF "Enable UndefinedBehaviorSanitizer (UB detection)")
    _sanitizer_profile_set_option("${_p}" "TSAN" OFF "Enable ThreadSanitizer (race conditions)")
    _sanitizer_profile_set_option("${_p}" "LSAN" OFF "Enable LeakSanitizer (memory leaks)")
    _sanitizer_profile_set_option("${_p}" "CFI" OFF "Enable Control Flow Integrity (Clang only; requires LTO)")
    message(STATUS
      "${_label}: sanitizer profile MSAN - MemorySanitizer ON (Clang + MSan-instrumented libc++). "
      "Binary dir: ${CMAKE_BINARY_DIR}")
  elseif(profileValue STREQUAL "NONE")
    message(STATUS
      "${_label}: sanitizer profile NONE - use explicit ${SP_PREFIX}* cache options. "
      "Binary dir: ${CMAKE_BINARY_DIR}")
  else()
    message(FATAL_ERROR "sanitizer_profile_apply: unsupported profile '${profileValue}'")
  endif()
endfunction()

function(sanitizer_configure_global_settings)
  set(oneValueArgs PREFIX PROJECT_LABEL BUILD_SHARED_LIBS_WARN)
  cmake_parse_arguments(SG "" "${oneValueArgs}" "" ${ARGN})

  if(NOT SG_PREFIX)
    message(FATAL_ERROR "sanitizer_configure_global_settings: PREFIX is required")
  endif()

  set(_p "${SG_PREFIX}")
  set(_label "${SG_PROJECT_LABEL}")
  if(NOT _label)
    set(_label "Project")
  endif()

  if(NOT (${${_p}ASAN} OR ${${_p}UBSAN} OR ${${_p}TSAN} OR ${${_p}LSAN} OR ${${_p}MSAN} OR ${${_p}CFI}))
    return()
  endif()

  if(${${_p}MSAN} AND ${${_p}CFI})
    message(FATAL_ERROR
      "${_label}: ${SG_PREFIX}MSAN and ${SG_PREFIX}CFI are incompatible. "
      "Use separate build directories.")
  endif()

  if(${${_p}MSAN})
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      message(FATAL_ERROR
        "${_label} MSan requires Clang. Current compiler: ${CMAKE_CXX_COMPILER_ID}. "
        "Set CMAKE_C_COMPILER/CMAKE_CXX_COMPILER to MSan-instrumented clang/clang++ "
        "(e.g. ~/bin/clang-msan and ~/bin/clang++-msan).")
    endif()
    if(SG_BUILD_SHARED_LIBS_WARN AND BUILD_SHARED_LIBS)
      message(WARNING
        "${_label} MSan: BUILD_SHARED_LIBS=ON is discouraged (prefer OFF). "
        "Use -DBUILD_SHARED_LIBS=OFF in a fresh build dir.")
    endif()
    message(STATUS
      "${_label} MSan: all linked code (including gtest) must be built with MSan. "
      "Use MSan-instrumented libc++ (wrapper scripts or DCHANNEL_MSAN_LIBCXX_ROOT).")
  endif()

  if(${${_p}CFI})
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      message(FATAL_ERROR
        "${_label} CFI requires Clang. Current compiler: ${CMAKE_CXX_COMPILER_ID}. "
        "Set CMAKE_C_COMPILER/CMAKE_CXX_COMPILER to clang/clang++.")
    endif()
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON CACHE BOOL "Enable IPO/LTO for CFI builds" FORCE)
    set(CMAKE_POSITION_INDEPENDENT_CODE OFF CACHE BOOL "Disable PIC for CFI builds" FORCE)
    if(SG_BUILD_SHARED_LIBS_WARN AND BUILD_SHARED_LIBS)
      message(WARNING
        "${_label} CFI: BUILD_SHARED_LIBS=ON is discouraged (prefer OFF). "
        "Use -DBUILD_SHARED_LIBS=OFF in a fresh build dir.")
    endif()
    if(${${_p}UBSAN})
      message(STATUS "${_label} CFI: UBSan enabled for clearer diagnostics.")
    else()
      message(WARNING
        "${_label} CFI: pairing with UBSan is recommended for clearer diagnostics.")
    endif()
  endif()

  if(NOT MSVC AND (${${_p}ASAN} OR ${${_p}UBSAN} OR ${${_p}TSAN} OR ${${_p}CFI}))
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      message(STATUS
        "${_label} sanitizers: compiler is ${CMAKE_CXX_COMPILER_ID}. "
        "Clang is recommended for ASan/UBSan/TSan/CFI on Linux.")
    endif()
  endif()
endfunction()

function(sanitizer_apply_to_target_from_options target)
  set(oneValueArgs PREFIX ENABLE_VAR)
  cmake_parse_arguments(ST "" "${oneValueArgs}" "" ${ARGN})

  if(NOT TARGET ${target})
    message(FATAL_ERROR "sanitizer_apply_to_target_from_options: target '${target}' does not exist")
  endif()
  if(NOT ST_PREFIX OR NOT ST_ENABLE_VAR)
    message(FATAL_ERROR "sanitizer_apply_to_target_from_options: PREFIX and ENABLE_VAR are required")
  endif()

  if(NOT ${ST_ENABLE_VAR})
    return()
  endif()

  set(_p "${ST_PREFIX}")

  if(MSVC)
    if(${${_p}ASAN})
      configure_sanitizers(${target}
        ADDRESS ON
        THREAD OFF
        UNDEFINED OFF
        LEAK OFF
      )
    endif()
    return()
  endif()

  if(${${_p}ASAN} OR ${${_p}TSAN} OR ${${_p}UBSAN} OR ${${_p}LSAN} OR ${${_p}MSAN} OR ${${_p}CFI})
    configure_sanitizers(${target}
      ADDRESS ${${_p}ASAN}
      MEMORY ${${_p}MSAN}
      THREAD ${${_p}TSAN}
      UNDEFINED ${${_p}UBSAN}
      LEAK ${${_p}LSAN}
      CFI ${${_p}CFI}
    )
    message(STATUS
      "Sanitizers enabled for ${target}: "
      "ASAN=${${_p}ASAN} TSAN=${${_p}TSAN} UBSAN=${${_p}UBSAN} "
      "LSAN=${${_p}LSAN} MSAN=${${_p}MSAN} CFI=${${_p}CFI}")
  endif()
endfunction()

function(sanitizer_build_uses_any)
  set(options)
  set(oneValueArgs PREFIX OUT)
  cmake_parse_arguments(SU "${options}" "${oneValueArgs}" "" ${ARGN})

  if(NOT SU_PREFIX OR NOT SU_OUT)
    message(FATAL_ERROR "sanitizer_build_uses_any: PREFIX and OUT are required")
  endif()

  set(_p "${SU_PREFIX}")
  if(${${_p}ASAN} OR ${${_p}UBSAN} OR ${${_p}TSAN} OR ${${_p}LSAN} OR ${${_p}MSAN} OR ${${_p}CFI})
    set(${SU_OUT} TRUE PARENT_SCOPE)
  else()
    set(${SU_OUT} FALSE PARENT_SCOPE)
  endif()
endfunction()
