# =============================================================================
# StaticAnalysisConfig.cmake
# Universal static analysis configuration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to configure static analysis tools
# (clang-tidy, cppcheck) for code quality checking.
#
# Functions:
#   configure_static_analysis(<target>
#     [CLANG_TIDY <ON|OFF>]
#     [CPPCHECK <ON|OFF>]
#     [CHECKS <checks...>]
#     [SUPPRESSIONS <file>]
#     [CLANG_TIDY_EXECUTABLE <path>]
#     [CPPCHECK_EXECUTABLE <path>]
#     [CLANG_TIDY_FLAGS <flags...>]
#     [CPPCHECK_FLAGS <flags...>]
#   )
#
# Usage:
#   include(StaticAnalysisConfig)
#   configure_static_analysis(MyApp CLANG_TIDY ON CHECKS readability-*)
#
# =============================================================================

# =============================================================================
# Function: configure_static_analysis
#
# Configures static analysis tools for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   CLANG_TIDY <on>   - Enable clang-tidy. Default: OFF
#   CPPCHECK <on>     - Enable cppcheck. Default: OFF
#   CHECKS <...>      - clang-tidy checks to enable/disable
#   SUPPRESSIONS <file> - Suppressions file for cppcheck
#   CLANG_TIDY_EXECUTABLE <path> - Path to clang-tidy executable. Default: auto-detect
#   CPPCHECK_EXECUTABLE <path> - Path to cppcheck executable. Default: auto-detect
#   CLANG_TIDY_FLAGS <...> - Additional clang-tidy flags
#   CPPCHECK_FLAGS <...> - Additional cppcheck flags
#
# Usage:
#   # Use defaults
#   configure_static_analysis(MyApp CLANG_TIDY ON CHECKS readability-* performance-*)
#
#   # Use custom executables and flags
#   configure_static_analysis(MyApp CLANG_TIDY ON CLANG_TIDY_EXECUTABLE /usr/local/bin/clang-tidy CLANG_TIDY_FLAGS -header-filter=.*)
#   configure_static_analysis(MyLib CPPCHECK ON CPPCHECK_EXECUTABLE /opt/cppcheck/bin/cppcheck SUPPRESSIONS suppressions.txt)
# =============================================================================
function(configure_static_analysis target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "StaticAnalysisConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs CLANG_TIDY CPPCHECK SUPPRESSIONS CLANG_TIDY_EXECUTABLE CPPCHECK_EXECUTABLE)
  set(multiValueArgs CHECKS CLANG_TIDY_FLAGS CPPCHECK_FLAGS)
  cmake_parse_arguments(STATIC_ANALYSIS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT DEFINED STATIC_ANALYSIS_CLANG_TIDY)
    set(STATIC_ANALYSIS_CLANG_TIDY OFF)
  endif()

  if(NOT DEFINED STATIC_ANALYSIS_CPPCHECK)
    set(STATIC_ANALYSIS_CPPCHECK OFF)
  endif()

  # Configure clang-tidy
  if(STATIC_ANALYSIS_CLANG_TIDY)
    _configure_clang_tidy(${target} "${STATIC_ANALYSIS_CHECKS}" "${STATIC_ANALYSIS_CLANG_TIDY_EXECUTABLE}" "${STATIC_ANALYSIS_CLANG_TIDY_FLAGS}")
  endif()

  # Configure cppcheck
  if(STATIC_ANALYSIS_CPPCHECK)
    _configure_cppcheck(${target} "${STATIC_ANALYSIS_SUPPRESSIONS}" "${STATIC_ANALYSIS_CPPCHECK_EXECUTABLE}" "${STATIC_ANALYSIS_CPPCHECK_FLAGS}")
  endif()

  # If neither tool is enabled, warn user
  if(NOT STATIC_ANALYSIS_CLANG_TIDY AND NOT STATIC_ANALYSIS_CPPCHECK)
    message(STATUS "StaticAnalysisConfig: No static analysis tools enabled for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_clang_tidy
# =============================================================================
function(_configure_clang_tidy target checks executable custom_flags)
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
    string(REPLACE ";" "," checks_string "${checks}")
  else()
    set(checks_string "readability-*,performance-*,modernize-*")
  endif()

  # Build command
  set(clang_tidy_cmd "${CLANG_TIDY_EXECUTABLE};-checks=${checks_string}")
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
  if(custom_flags)
    message(STATUS "StaticAnalysisConfig:   Custom flags: ${custom_flags}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_cppcheck
# =============================================================================
function(_configure_cppcheck target suppressions executable custom_flags)
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

  # Build cppcheck command
  set(cppcheck_cmd "${CPPCHECK_EXECUTABLE}")
  list(APPEND cppcheck_cmd "--enable=all")
  list(APPEND cppcheck_cmd "--suppress=missingIncludeSystem")
  list(APPEND cppcheck_cmd "--suppress=unusedFunction")
  list(APPEND cppcheck_cmd "--inline-suppr")

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
