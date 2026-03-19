# =============================================================================
# StaticAnalysisConfig.cmake
# Universal static analysis configuration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to configure static analysis tools
# (clang-tidy, cppcheck) for code quality checking. Presets are aligned with
# sanitizer bug classes (ASan, UBSan, TSan) for complementary static+runtime
# analysis. See .cursor/docs/gcc_clang_sanitizers.md for sanitizer integration.
#
# Functions:
#   configure_static_analysis(<target>
#     [CLANG_TIDY <ON|OFF>]
#     [CPPCHECK <ON|OFF>]
#     [PROFILE <profile>]          # memory|undefined|thread|security|full|default
#     [CHECKS <checks...>]         # Overrides PROFILE for clang-tidy
#     [SUPPRESSIONS <file>]
#     [WARN_AS_ERROR <ON|OFF>]
#     [CLANG_TIDY_EXECUTABLE <path>]
#     [CPPCHECK_EXECUTABLE <path>]
#     [CLANG_TIDY_FLAGS <flags...>]
#     [CPPCHECK_FLAGS <flags...>]
#     [HEADER_FILTER <regex>]
#   )
#
# Presets (PROFILE)  - complement sanitizers from gcc_clang_sanitizers.md:
#          memory    - ASan/LSan: buffer overflows, use-after-free, leaks
#          undefined - UBSan: signed overflow, alignment, null, shift
#          thread    - TSan: data races, locking
#          security  - CWE/Security-critical patterns
#          full      - memory + undefined + thread + security
#          default   - readability, performance, modernize (legacy)
#
# Sanitizer compatibility (runtime): ASan+TSan (NO), ASan+MSan (NO), TSan+MSan (NO).
# CFI (Control Flow Integrity): Clang only; requires LTO; compatible with UBSan/ASan.
# Use configure_sanitizers() from SanitizersConfig for runtime; it enforces these rules.
#
# Usage:
#   include(StaticAnalysisConfig)
#   configure_static_analysis(MyApp CLANG_TIDY ON PROFILE full)
#   configure_static_analysis(MyApp CLANG_TIDY ON PROFILE memory CHECKS bugprone-*)
#
# CI recommendation (with SanitizersConfig for runtime):
#   configure_static_analysis(MyApp CLANG_TIDY ON PROFILE full WARN_AS_ERROR ON)
#   configure_sanitizers(MyApp ADDRESS ON UNDEFINED ON)  # from SanitizersConfig
#
# =============================================================================

# =============================================================================
# Preset check sets (aligned with sanitizer document)
# =============================================================================
#
# memory - Corresponds to ASan/LSan. Use when configure_sanitizers(ADDRESS ON)
#   or standalone LSan. Catches: buffer overflows, use-after-free, double free,
#   invalid free, memory leaks. Do not combine with TSan/MSan in runtime.
#
set(STATIC_ANALYSIS_PROFILE_MEMORY
  "bugprone-*"
  "cppcoreguidelines-owning-memory"
  "cppcoreguidelines-no-malloc"
  "cppcoreguidelines-avoid-c-arrays"
  "cppcoreguidelines-pro-bounds-*"
  "clang-analyzer-unix.Malloc"
  "clang-analyzer-unix.MallocSizeof"
  "clang-analyzer-cplusplus.NewDelete"
  "clang-analyzer-cplusplus.NewDeleteLeaks"
)

# undefined - Corresponds to UBSan. Use when configure_sanitizers(UNDEFINED ON).
#   Catches: signed/unsigned overflow, division by zero, null dereference, alignment,
#   shift, uninitialized read. UBSan is compatible with all other sanitizers.
#
set(STATIC_ANALYSIS_PROFILE_UNDEFINED
  "bugprone-integer-division-by-zero"
  "bugprone-signal-handler"
  "bugprone-signed-char-misuse"
  "bugprone-sizeof-expression"
  "bugprone-undefined-memory-manipulation"
  "cert-exp36-c"
  "cert-int34-c"
  "clang-analyzer-core.NullDereference"
  "clang-analyzer-core.UndefinedBinaryOperatorResult"
  "clang-analyzer-core.DivideZero"
  "clang-analyzer-core.uninitialized.*"
)

# thread - Corresponds to TSan. Use when configure_sanitizers(THREAD ON).
#   Catches: data races, deadlocks, thread-safety violations. TSan MUST NOT
#   be combined with ASan or MSan (conflict on shadow memory).
#
set(STATIC_ANALYSIS_PROFILE_THREAD
  "concurrency-*"
  "clang-analyzer-thread-safety.*"
  "clang-analyzer-core.CallAndMessage"
)

# security - CWE/CERT security patterns. Not bound to a specific sanitizer.
#   Complements ASan/UBSan for security-critical code. Works on all platforms.
#
set(STATIC_ANALYSIS_PROFILE_SECURITY
  "cert-*"
  "clang-analyzer-security.*"
  "misc-static-assert"
)

# full - Combines memory+undefined+thread+security. For CI with separate
#   runtime-runs: one with ASan+UBSan, another with TSan+UBSan (not simultaneously).
#
set(STATIC_ANALYSIS_PROFILE_FULL
  "bugprone-*"
  "cppcoreguidelines-*"
  "clang-analyzer-*"
  "concurrency-*"
  "cert-*"
  "readability-*"
  "performance-*"
  "modernize-*"
  "portability-*"
  "misc-*"
)

# default - Base set without sanitizer binding: readability, performance,
#   modernize. Minimal noise, suitable for legacy code and fast checks.
#
set(STATIC_ANALYSIS_PROFILE_DEFAULT
  "readability-*"
  "performance-*"
  "modernize-*"
)

# =============================================================================
# Function: configure_static_analysis
#
# Configures static analysis tools for a target.
#
# Parameters:
#   <target>                     - Target name (required)
#   CLANG_TIDY <on>              - Enable clang-tidy. Default: OFF
#   CPPCHECK <on>                - Enable cppcheck. Default: OFF
#   PROFILE <name>               - Preset: memory|undefined|thread|security|full|default
#   CHECKS <...>                 - clang-tidy checks (overrides PROFILE if both set)
#   SUPPRESSIONS <file>          - Suppressions file for cppcheck
#   WARN_AS_ERROR <on>           - Treat warnings as errors (for CI). Default: OFF
#   HEADER_FILTER <regex>        - Regex for header files to analyze. Default: .*
#   CLANG_TIDY_EXECUTABLE <path> - Path to clang-tidy. Default: auto-detect
#   CPPCHECK_EXECUTABLE <path>   - Path to cppcheck. Default: auto-detect
#   CLANG_TIDY_FLAGS <...>       - Additional clang-tidy flags
#   CPPCHECK_FLAGS <...>         - Additional cppcheck flags
#
# =============================================================================
function(configure_static_analysis target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "StaticAnalysisConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs
    CLANG_TIDY
    CPPCHECK
    PROFILE
    SUPPRESSIONS
    WARN_AS_ERROR
    HEADER_FILTER
    CLANG_TIDY_EXECUTABLE
    CPPCHECK_EXECUTABLE
  )
  set(multiValueArgs CHECKS CLANG_TIDY_FLAGS CPPCHECK_FLAGS)
  cmake_parse_arguments(STATIC_ANALYSIS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT DEFINED STATIC_ANALYSIS_CLANG_TIDY)
    set(STATIC_ANALYSIS_CLANG_TIDY OFF)
  endif()

  if(NOT DEFINED STATIC_ANALYSIS_CPPCHECK)
    set(STATIC_ANALYSIS_CPPCHECK OFF)
  endif()

  if(NOT DEFINED STATIC_ANALYSIS_WARN_AS_ERROR)
    set(STATIC_ANALYSIS_WARN_AS_ERROR OFF)
  endif()

  if(NOT DEFINED STATIC_ANALYSIS_HEADER_FILTER)
    set(STATIC_ANALYSIS_HEADER_FILTER ".*")
  endif()

  # Resolve CHECKS from PROFILE if CHECKS not provided
  set(resolved_checks "")
  if(STATIC_ANALYSIS_CHECKS)
    set(resolved_checks "${STATIC_ANALYSIS_CHECKS}")
  elseif(STATIC_ANALYSIS_PROFILE)
    string(TOLOWER "${STATIC_ANALYSIS_PROFILE}" profile_lower)
    if(profile_lower STREQUAL "memory")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_MEMORY}")
    elseif(profile_lower STREQUAL "undefined")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_UNDEFINED}")
    elseif(profile_lower STREQUAL "thread")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_THREAD}")
    elseif(profile_lower STREQUAL "security")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_SECURITY}")
    elseif(profile_lower STREQUAL "full")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_FULL}")
    elseif(profile_lower STREQUAL "default")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_DEFAULT}")
    else()
      message(WARNING "StaticAnalysisConfig: Unknown PROFILE '${STATIC_ANALYSIS_PROFILE}', using default")
      set(resolved_checks "${STATIC_ANALYSIS_PROFILE_DEFAULT}")
    endif()
  endif()

  # Configure clang-tidy
  if(STATIC_ANALYSIS_CLANG_TIDY)
    _configure_clang_tidy(
      ${target}
      "${resolved_checks}"
      "${STATIC_ANALYSIS_CLANG_TIDY_EXECUTABLE}"
      "${STATIC_ANALYSIS_CLANG_TIDY_FLAGS}"
      "${STATIC_ANALYSIS_WARN_AS_ERROR}"
      "${STATIC_ANALYSIS_HEADER_FILTER}"
    )
  endif()

  # Configure cppcheck
  if(STATIC_ANALYSIS_CPPCHECK)
    _configure_cppcheck(
      ${target}
      "${STATIC_ANALYSIS_SUPPRESSIONS}"
      "${STATIC_ANALYSIS_CPPCHECK_EXECUTABLE}"
      "${STATIC_ANALYSIS_CPPCHECK_FLAGS}"
      "${STATIC_ANALYSIS_WARN_AS_ERROR}"
    )
  endif()

  # If neither tool is enabled, warn user
  if(NOT STATIC_ANALYSIS_CLANG_TIDY AND NOT STATIC_ANALYSIS_CPPCHECK)
    message(STATUS "StaticAnalysisConfig: No static analysis tools enabled for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_clang_tidy
# =============================================================================
function(_configure_clang_tidy target checks executable custom_flags warn_as_error header_filter)
  # Find or use provided executable
  if(executable)
    set(CLANG_TIDY_EXECUTABLE "${executable}")
    if(NOT EXISTS "${CLANG_TIDY_EXECUTABLE}")
      message(FATAL_ERROR "StaticAnalysisConfig: clang-tidy executable not found at '${CLANG_TIDY_EXECUTABLE}'")
    endif()
  else()
    find_program(CLANG_TIDY_EXECUTABLE clang-tidy)
    if(NOT CLANG_TIDY_EXECUTABLE)
      message(FATAL_ERROR "StaticAnalysisConfig: clang-tidy not found. Install clang-tidy or provide CLANG_TIDY_EXECUTABLE parameter.")
    endif()
  endif()

  # Build checks string
  set(checks_string "")
  if(checks)
    if(checks MATCHES ";")
      string(REPLACE ";" "," checks_string "${checks}")
    else()
      set(checks_string "${checks}")
    endif()
  else()
    set(checks_string "readability-*,performance-*,modernize-*")
  endif()

  # Build command
  set(clang_tidy_cmd "${CLANG_TIDY_EXECUTABLE}")
  list(APPEND clang_tidy_cmd "-checks=${checks_string}")
  list(APPEND clang_tidy_cmd "-header-filter=${header_filter}")

  if(warn_as_error)
    list(APPEND clang_tidy_cmd "-warnings-as-errors=*")
    message(STATUS "StaticAnalysisConfig: clang-tidy WARN_AS_ERROR enabled")
  endif()

  if(custom_flags)
    list(APPEND clang_tidy_cmd ${custom_flags})
  endif()

  # Set clang-tidy property
  set_target_properties(${target} PROPERTIES
    CXX_CLANG_TIDY "${clang_tidy_cmd}"
  )

  message(STATUS "StaticAnalysisConfig: clang-tidy enabled for '${target}'")
  message(STATUS "StaticAnalysisConfig:   Executable: ${CLANG_TIDY_EXECUTABLE}")
  message(STATUS "StaticAnalysisConfig:   Checks: ${checks_string}")
  message(STATUS "StaticAnalysisConfig:   Header filter: ${header_filter}")
  if(custom_flags)
    message(STATUS "StaticAnalysisConfig:   Custom flags: ${custom_flags}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_cppcheck
# =============================================================================
function(_configure_cppcheck target suppressions executable custom_flags warn_as_error)
  # Find or use provided executable
  if(executable)
    set(CPPCHECK_EXECUTABLE "${executable}")
    if(NOT EXISTS "${CPPCHECK_EXECUTABLE}")
      message(FATAL_ERROR "StaticAnalysisConfig: cppcheck executable not found at '${CPPCHECK_EXECUTABLE}'")
    endif()
  else()
    find_program(CPPCHECK_EXECUTABLE cppcheck)
    if(NOT CPPCHECK_EXECUTABLE)
      message(FATAL_ERROR "StaticAnalysisConfig: cppcheck not found. Install cppcheck or provide CPPCHECK_EXECUTABLE parameter.")
    endif()
  endif()

  # Build cppcheck command - enables aligned with sanitizer bug classes
  set(cppcheck_cmd "${CPPCHECK_EXECUTABLE}")
  list(APPEND cppcheck_cmd "--enable=all")
  list(APPEND cppcheck_cmd "--suppress=missingIncludeSystem")
  list(APPEND cppcheck_cmd "--suppress=unusedFunction")
  list(APPEND cppcheck_cmd "--inline-suppr")

  # C++ standard for better analysis
  if(CMAKE_CXX_STANDARD)
    list(APPEND cppcheck_cmd "--std=c++${CMAKE_CXX_STANDARD}")
  else()
    list(APPEND cppcheck_cmd "--std=c++17")
  endif()

  # Platform for consistent results
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    list(APPEND cppcheck_cmd "--platform=unix64")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    list(APPEND cppcheck_cmd "--platform=win64")
  endif()

  if(warn_as_error)
    list(APPEND cppcheck_cmd "--error-exitcode=1")
    message(STATUS "StaticAnalysisConfig: cppcheck WARN_AS_ERROR enabled (--error-exitcode=1)")
  endif()

  if(suppressions)
    list(APPEND cppcheck_cmd "--suppressions-list=${suppressions}")
  endif()

  if(custom_flags)
    list(APPEND cppcheck_cmd ${custom_flags})
  endif()

  # Set cppcheck property
  set_target_properties(${target} PROPERTIES
    CXX_CPPCHECK "${cppcheck_cmd}"
  )

  message(STATUS "StaticAnalysisConfig: cppcheck enabled for '${target}'")
  message(STATUS "StaticAnalysisConfig:   Executable: ${CPPCHECK_EXECUTABLE}")
  if(suppressions)
    message(STATUS "StaticAnalysisConfig:   Suppressions: ${suppressions}")
  endif()
  if(custom_flags)
    message(STATUS "StaticAnalysisConfig:   Custom flags: ${custom_flags}")
  endif()
endfunction()

# =============================================================================
# Function: get_sanitizer_env_recommendations
#
# Returns recommended environment variables for sanitizers when running tests.
# Use with add_test(COMMAND ...) or ctest. Based on gcc_clang_sanitizers.md.
#
# Parameters:
#   OUT_VAR    - Variable name to receive the env string/list
#   ASAN_OPTS  - Override ASAN_OPTIONS (optional)
#   UBSAN_OPTS - Override UBSAN_OPTIONS (optional)
#   LSAN_OPTS  - Override LSAN_OPTIONS (optional)
#   DETECT_LEAKS - For ASAN: detect_leaks=1. Values: ON|OFF. Default: ON
#
# Note: ASAN_OPTIONS=symbolize=1 requires llvm-symbolizer in PATH for readable
# stack traces. Install llvm (e.g. llvm-symbolizer) for best results.
#
# Usage:
#   get_sanitizer_env_recommendations(ENV_STR DETECT_LEAKS ON)
#   set_tests_properties(MyTest PROPERTIES ENVIRONMENT "${ENV_STR}")
#
# =============================================================================
function(get_sanitizer_env_recommendations out_var)
  set(options "")
  set(oneValueArgs ASAN_OPTS UBSAN_OPTS LSAN_OPTS DETECT_LEAKS)
  set(multiValueArgs "")
  cmake_parse_arguments(SAN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT DEFINED SAN_DETECT_LEAKS)
    set(SAN_DETECT_LEAKS ON)
  endif()
  if(SAN_DETECT_LEAKS STREQUAL "OFF" OR SAN_DETECT_LEAKS STREQUAL "0" OR SAN_DETECT_LEAKS STREQUAL "FALSE")
    set(SAN_DETECT_LEAKS OFF)
  else()
    set(SAN_DETECT_LEAKS ON)
  endif()

  set(env_list "")

  # ASAN_OPTIONS - from gcc_clang_sanitizers.md
  if(NOT SAN_ASAN_OPTS)
    set(asan_opts "symbolize=1:abort_on_error=1:print_stats=0")
    if(SAN_DETECT_LEAKS)
      string(APPEND asan_opts ":detect_leaks=1")
    endif()
    list(APPEND env_list "ASAN_OPTIONS=${asan_opts}")
  else()
    list(APPEND env_list "ASAN_OPTIONS=${SAN_ASAN_OPTS}")
  endif()

  # UBSAN_OPTIONS - halt_on_error for CI, recover for interactive
  if(NOT SAN_UBSAN_OPTS)
    list(APPEND env_list "UBSAN_OPTIONS=print_stacktrace=1:abort_on_error=1")
  else()
    list(APPEND env_list "UBSAN_OPTIONS=${SAN_UBSAN_OPTS}")
  endif()

  # LSAN_OPTIONS - when using standalone LSan
  if(SAN_LSAN_OPTS)
    list(APPEND env_list "LSAN_OPTIONS=${SAN_LSAN_OPTS}")
  endif()

  set(${out_var} "${env_list}" PARENT_SCOPE)
endfunction()
