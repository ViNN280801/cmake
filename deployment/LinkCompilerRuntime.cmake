cmake_minimum_required(VERSION 3.16)
include_guard(GLOBAL)

#[=======================================================================[.rst:
LinkCompilerRuntime
-------------------

Provides :command:`link_compiler_runtime` - a single, cross-compiler,
cross-platform function that probes the active C++ toolchain, locates the
correct runtime shared library, and links it to a CMake target.

Compilers
^^^^^^^^^
* GCC - finds `libstdc++.so` via `-print-file-name`; optionally
  validates the ABI version with `nm -D` (`_M_replace_cold` marker,
  present since GCC 12).
* Clang / LLVMFlang - auto-detects `-stdlib=libc++` from the global
  CMake flags; falls back to the libstdc++ probe (Clang's default on Linux)
  when `-stdlib=libc++` is absent.
* MSVC - no-op; the CRT is linked implicitly through
  `MSVC_RUNTIME_LIBRARY`.
* AppleClang / macOS - no-op for the system libc++; links `-lc++` only
  when `-stdlib=libc++` is detected in the global CMake flags.

Minimum CMake version: 3.16
#]=======================================================================]

# =============================================================================
# Internal helpers  (all prefixed _lcr_ to avoid name collisions)
# =============================================================================

# -----------------------------------------------------------------------------
# _lcr_probe_file_name(<compiler_exe> <lib_name> <out_var>)
#
# Asks <compiler_exe> for the full resolved path to <lib_name> via
# -print-file-name.  Sets <out_var> to the path when it exists on disk,
# otherwise sets it to the empty string.
# -----------------------------------------------------------------------------
function(_lcr_probe_file_name compiler lib_name out_var)
  execute_process(
    COMMAND "${compiler}" "-print-file-name=${lib_name}"
    OUTPUT_VARIABLE _lcr_path
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )
  # The compiler returns the bare name unchanged when the library is not found
  # in its own search paths.
  if(_lcr_path AND EXISTS "${_lcr_path}" AND NOT _lcr_path STREQUAL "${lib_name}")
    set(${out_var} "${_lcr_path}" PARENT_SCOPE)
  else()
    set(${out_var} "" PARENT_SCOPE)
  endif()
endfunction()

# -----------------------------------------------------------------------------
# _lcr_detect_stdlib_flag(<out_var>)
#
# Scans the global CMake C++ compile/link flags (and $ENV{CXXFLAGS}) for a
# -stdlib=<name> option.  Sets <out_var> to the matched name (e.g. "libc++")
# or to the empty string when no such flag is present.
# -----------------------------------------------------------------------------
function(_lcr_detect_stdlib_flag out_var)
  set(_lcr_stdlib "")
  foreach(_lcr_flags_var IN ITEMS
    CMAKE_CXX_FLAGS
    CMAKE_EXE_LINKER_FLAGS
    CMAKE_SHARED_LINKER_FLAGS
    CMAKE_MODULE_LINKER_FLAGS)
    if(DEFINED ${_lcr_flags_var} AND "${${_lcr_flags_var}}" MATCHES "-stdlib=([A-Za-z0-9+_-]+)")
      set(_lcr_stdlib "${CMAKE_MATCH_1}")
      break()
    endif()
  endforeach()

  if(_lcr_stdlib STREQUAL "" AND DEFINED ENV{CXXFLAGS}
     AND "$ENV{CXXFLAGS}" MATCHES "-stdlib=([A-Za-z0-9+_-]+)")
    set(_lcr_stdlib "${CMAKE_MATCH_1}")
  endif()

  set(${out_var} "${_lcr_stdlib}" PARENT_SCOPE)
endfunction()

# -----------------------------------------------------------------------------
# _lcr_find_libstdcxx(<out_var> <validate_abi>)
#
# Locates the best available libstdc++.so candidate:
#
#  1. Ask the compiler directly (fastest, most accurate).
#  2. Glob common non-system GCC installation prefixes.
#
# When <validate_abi> is TRUE and CMAKE_NM is set, the function prefers the
# first candidate that exposes the _M_replace_cold symbol (GCC >= 12 ABI
# marker).  Falls back to the first found candidate when no ABI-validated one
# is available.  Sets <out_var> to "" when nothing is found.
# -----------------------------------------------------------------------------
function(_lcr_find_libstdcxx out_var validate_abi)
  set(_lcr_candidates "")

  # --- Method 1: ask the compiler -------------------------------------------
  foreach(_lcr_name IN ITEMS "libstdc++.so" "libstdc++.so.6")
    _lcr_probe_file_name("${CMAKE_CXX_COMPILER}" "${_lcr_name}" _lcr_probe)
    if(_lcr_probe)
      list(APPEND _lcr_candidates "${_lcr_probe}")
    endif()
  endforeach()

  # --- Method 2: glob common non-system GCC installation prefixes -----------
  file(GLOB _lcr_glob_hits
    "/usr/local/gcc-*/lib64/libstdc++.so"
    "/usr/local/gcc-*/lib64/libstdc++.so.6"
    "/opt/gcc-*/lib64/libstdc++.so"
    "/opt/gcc-*/lib64/libstdc++.so.6"
    "/opt/local/lib/gcc*/libstdc++.so"      # MacPorts (non-Apple check done by caller)
    "/usr/lib/gcc/*/*/libstdc++.so"          # Debian/Ubuntu multiarch GCC layouts
  )
  list(APPEND _lcr_candidates ${_lcr_glob_hits})
  list(REMOVE_DUPLICATES _lcr_candidates)

  if(NOT _lcr_candidates)
    set(${out_var} "" PARENT_SCOPE)
    return()
  endif()

  # --- ABI validation: prefer GCC >= 12 libstdc++ ---------------------------
  if(validate_abi AND DEFINED CMAKE_NM AND CMAKE_NM)
    foreach(_lcr_cand IN LISTS _lcr_candidates)
      execute_process(
        COMMAND "${CMAKE_NM}" -D "${_lcr_cand}"
        OUTPUT_VARIABLE _lcr_nm_out
        ERROR_QUIET
        RESULT_VARIABLE _lcr_nm_rc
      )
      if(_lcr_nm_rc EQUAL 0 AND _lcr_nm_out MATCHES "_M_replace_cold")
        set(${out_var} "${_lcr_cand}" PARENT_SCOPE)
        return()
      endif()
    endforeach()
    # None passed the ABI check - fall through to first-candidate fallback.
  endif()

  list(GET _lcr_candidates 0 _lcr_first)
  set(${out_var} "${_lcr_first}" PARENT_SCOPE)
endfunction()

# -----------------------------------------------------------------------------
# _lcr_find_libcxx(<out_var>)
#
# Locates libc++.so (LLVM) by asking the compiler and by globbing common LLVM
# installation paths.  Sets <out_var> to the full path or "" when not found.
# -----------------------------------------------------------------------------
function(_lcr_find_libcxx out_var)
  # Ask the compiler first.
  foreach(_lcr_name IN ITEMS "libc++.so" "libc++.so.1")
    _lcr_probe_file_name("${CMAKE_CXX_COMPILER}" "${_lcr_name}" _lcr_probe)
    if(_lcr_probe)
      set(${out_var} "${_lcr_probe}" PARENT_SCOPE)
      return()
    endif()
  endforeach()

  # Glob common LLVM installation paths.
  file(GLOB _lcr_glob_hits
    "/usr/lib/llvm-*/lib/libc++.so"
    "/usr/lib/llvm-*/lib/libc++.so.1"
    "/usr/local/llvm-*/lib/libc++.so"
    "/usr/local/llvm/lib/libc++.so"
    "/opt/homebrew/opt/llvm/lib/libc++.so"
    "/opt/llvm-*/lib/libc++.so"
  )
  if(_lcr_glob_hits)
    list(GET _lcr_glob_hits 0 _lcr_first)
    set(${out_var} "${_lcr_first}" PARENT_SCOPE)
    return()
  endif()

  set(${out_var} "" PARENT_SCOPE)
endfunction()

# =============================================================================
# Public API
# =============================================================================

#[=======================================================================[.rst:
.. cmake:command:: link_compiler_runtime

  Select and link the compiler's C++ runtime shared library to a target.

  ::

    link_compiler_runtime(
      <target>
      [PRIVATE | PUBLIC | INTERFACE]
      [STDLIB <libstdc++ | libc++>]
      [VALIDATE_ABI]
      [VERBOSE]
    )

  `target`
    A valid CMake target (executable or library).

  `PRIVATE | PUBLIC | INTERFACE`
    Link visibility.  Defaults to `PRIVATE`.

  `STDLIB <name>`
    Override the detected C++ standard library.  Accepted values:
    `libstdc++` (GCC runtime) and `libc++` (LLVM runtime).
    When omitted the function auto-detects from `CMAKE_CXX_FLAGS`,
    `CMAKE_EXE_LINKER_FLAGS`, `CMAKE_SHARED_LINKER_FLAGS`, and
    `$ENV{CXXFLAGS}`.

  `VALIDATE_ABI`
    (Linux, GCC or Clang+libstdc++) Before accepting a libstdc++ candidate,
    verify it exposes the `_M_replace_cold` symbol (GCC >= 12 ABI marker)
    using `nm -D`.  Requires `CMAKE_NM` (CMake sets this automatically on
    Unix).  Falls back gracefully to the first available candidate, or to the
    bare `-lstdc++` linker flag, when validation fails.

  `VERBOSE`
    Emit a `STATUS` message naming the selected runtime path.

  Platform behaviour
  ^^^^^^^^^^^^^^^^^^

  +------------------+----------------------------------------------------------+
  | Platform         | Behaviour                                                |
  +==================+==========================================================+
  | Linux / Unix     | Probes the compiler with `-print-file-name`, globs       |
  | (GCC)            | common GCC installation prefixes, optionally ABI-checks  |
  |                  | with `nm`, and links the full library path.  Falls back  |
  |                  | to `-lstdc++` when no full path is found.                |
  +------------------+----------------------------------------------------------+
  | Linux / Unix     | Detects `-stdlib=libc++` from global flags.  If set,     |
  | (Clang)          | probes for `libc++.so` + optional `libunwind.so`         |
  |                  | and links them; falls back to `-lc++`.  Otherwise uses   |
  |                  | the libstdc++ probe identical to the GCC path.           |
  +------------------+----------------------------------------------------------+
  | macOS            | No-op for the system libc++.  Links `-lc++` only when    |
  | (Apple/Clang)    | `-stdlib=libc++` is detected in the global flags (i.e.   |
  |                  | a custom LLVM installation).                             |
  +------------------+----------------------------------------------------------+
  | Windows / MSVC   | No-op.  The CRT is linked implicitly via the             |
  |                  | `MSVC_RUNTIME_LIBRARY` target property.                  |
  +------------------+----------------------------------------------------------+
  | Other            | No-op with an optional VERBOSE status message.           |
  +------------------+----------------------------------------------------------+

  Example
  ^^^^^^^

  .. code-block:: cmake

    add_executable(my_app main.cpp)
    include(cmake/deployment/LinkCompilerRuntime.cmake)

    # GCC: ABI-validated libstdc++; Clang: auto-detect stdlib
    link_compiler_runtime(my_app PRIVATE VALIDATE_ABI VERBOSE)

    # Clang built with -stdlib=libc++, explicit override
    link_compiler_runtime(my_app STDLIB libc++ VERBOSE)

#]=======================================================================]
function(link_compiler_runtime target)
  # ---------------------------------------------------------------------------
  # Argument parsing
  # ---------------------------------------------------------------------------
  set(_lcr_options   VALIDATE_ABI VERBOSE)
  set(_lcr_one_value STDLIB)
  cmake_parse_arguments(_LCR "${_lcr_options}" "${_lcr_one_value}" "" ${ARGN})

  # Accept PRIVATE / PUBLIC / INTERFACE as a positional argument.
  set(_vis PRIVATE)
  foreach(_lcr_arg IN LISTS _LCR_UNPARSED_ARGUMENTS)
    if(_lcr_arg MATCHES "^(PRIVATE|PUBLIC|INTERFACE)$")
      set(_vis "${_lcr_arg}")
    else()
      message(WARNING
        "link_compiler_runtime: unrecognised argument '${_lcr_arg}' (ignored)")
    endif()
  endforeach()

  # ---------------------------------------------------------------------------
  # Target validation
  # ---------------------------------------------------------------------------
  if(NOT TARGET "${target}")
    message(FATAL_ERROR
      "link_compiler_runtime: '${target}' is not a known CMake target")
  endif()

  # ---------------------------------------------------------------------------
  # Windows / MSVC: runtime linked implicitly - nothing to do.
  # ---------------------------------------------------------------------------
  if(MSVC)
    if(_LCR_VERBOSE)
      message(STATUS
        "link_compiler_runtime(${target}): MSVC - CRT linked implicitly (no-op)")
    endif()
    return()
  endif()

  # ---------------------------------------------------------------------------
  # macOS (any compiler): system libc++ is always present; only act when a
  # custom libc++ is explicitly requested via -stdlib=libc++.
  # ---------------------------------------------------------------------------
  if(APPLE)
    set(_lcr_apple_stdlib "${_LCR_STDLIB}")
    if(_lcr_apple_stdlib STREQUAL "")
      _lcr_detect_stdlib_flag(_lcr_apple_stdlib)
    endif()
    if(_lcr_apple_stdlib STREQUAL "libc++")
      target_link_libraries("${target}" "${_vis}" c++)
      if(_LCR_VERBOSE)
        message(STATUS
          "link_compiler_runtime(${target}): macOS + -stdlib=libc++ → -lc++")
      endif()
    else()
      if(_LCR_VERBOSE)
        message(STATUS
          "link_compiler_runtime(${target}): macOS - system libc++ (no-op)")
      endif()
    endif()
    return()
  endif()

  # ---------------------------------------------------------------------------
  # Non-Unix platforms not covered above: no action.
  # ---------------------------------------------------------------------------
  if(NOT UNIX)
    if(_LCR_VERBOSE)
      message(STATUS
        "link_compiler_runtime(${target}): unsupported platform - no action")
    endif()
    return()
  endif()

  # ---------------------------------------------------------------------------
  # Linux / other Unix
  # ---------------------------------------------------------------------------

  # Resolve stdlib: explicit override > flag detection > compiler default.
  set(_lcr_stdlib "${_LCR_STDLIB}")
  if(_lcr_stdlib STREQUAL "")
    _lcr_detect_stdlib_flag(_lcr_stdlib)
  endif()
  # Clang's default on Linux/Unix is libstdc++ unless -stdlib=libc++ is given.
  # GCC always uses libstdc++.

  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # ------------------------------------------------------------------
    # GCC: always libstdc++
    # ------------------------------------------------------------------
    _lcr_find_libstdcxx(_lcr_selected "${_LCR_VALIDATE_ABI}")
    if(_lcr_selected)
      target_link_libraries("${target}" "${_vis}" "${_lcr_selected}")
      if(_LCR_VERBOSE)
        message(STATUS
          "link_compiler_runtime(${target}): GCC/libstdc++ → ${_lcr_selected}")
      endif()
    else()
      if(_LCR_VALIDATE_ABI)
        message(WARNING
          "link_compiler_runtime(${target}): no ABI-validated libstdc++ "
          "found (no _M_replace_cold symbol); falling back to -lstdc++")
      endif()
      target_link_libraries("${target}" "${_vis}" stdc++)
      if(_LCR_VERBOSE)
        message(STATUS
          "link_compiler_runtime(${target}): GCC/libstdc++ → -lstdc++ (fallback)")
      endif()
    endif()

  elseif(CMAKE_CXX_COMPILER_ID MATCHES "^(Clang|LLVMFlang)$")
    if(_lcr_stdlib STREQUAL "libc++")
      # ----------------------------------------------------------------
      # Clang configured with -stdlib=libc++
      # ----------------------------------------------------------------
      _lcr_find_libcxx(_lcr_selected_cxx)
      if(_lcr_selected_cxx)
        target_link_libraries("${target}" "${_vis}" "${_lcr_selected_cxx}")
        if(_LCR_VERBOSE)
          message(STATUS
            "link_compiler_runtime(${target}): Clang/libc++ → ${_lcr_selected_cxx}")
        endif()
      else()
        target_link_libraries("${target}" "${_vis}" c++)
        if(_LCR_VERBOSE)
          message(STATUS
            "link_compiler_runtime(${target}): Clang/libc++ → -lc++ (fallback)")
        endif()
      endif()

      # libunwind is the optional unwinder companion to libc++ on Linux.
      _lcr_probe_file_name("${CMAKE_CXX_COMPILER}" "libunwind.so"   _lcr_unwind)
      if(NOT _lcr_unwind)
        _lcr_probe_file_name("${CMAKE_CXX_COMPILER}" "libunwind.so.1" _lcr_unwind)
      endif()
      if(_lcr_unwind)
        target_link_libraries("${target}" "${_vis}" "${_lcr_unwind}")
        if(_LCR_VERBOSE)
          message(STATUS
            "link_compiler_runtime(${target}): Clang/libc++ + libunwind → ${_lcr_unwind}")
        endif()
      endif()

    else()
      # ----------------------------------------------------------------
      # Clang defaulting to libstdc++ (standard on most Linux distros)
      # ----------------------------------------------------------------
      _lcr_find_libstdcxx(_lcr_selected "${_LCR_VALIDATE_ABI}")
      if(_lcr_selected)
        target_link_libraries("${target}" "${_vis}" "${_lcr_selected}")
        if(_LCR_VERBOSE)
          message(STATUS
            "link_compiler_runtime(${target}): Clang/libstdc++ → ${_lcr_selected}")
        endif()
      else()
        if(_LCR_VALIDATE_ABI)
          message(WARNING
            "link_compiler_runtime(${target}): no ABI-validated libstdc++ "
            "found (no _M_replace_cold symbol); falling back to -lstdc++")
        endif()
        target_link_libraries("${target}" "${_vis}" stdc++)
        if(_LCR_VERBOSE)
          message(STATUS
            "link_compiler_runtime(${target}): Clang/libstdc++ → -lstdc++ (fallback)")
        endif()
      endif()
    endif()

  else()
    # Unknown compiler - no action.
    if(_LCR_VERBOSE)
      message(STATUS
        "link_compiler_runtime(${target}): compiler '${CMAKE_CXX_COMPILER_ID}' "
        "not handled - no action")
    endif()
  endif()
endfunction()
