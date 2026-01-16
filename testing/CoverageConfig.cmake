# =============================================================================
# CoverageConfig.cmake
# Universal code coverage configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure code coverage
# (gcov, lcov, llvm-cov) for GCC, Clang, and MSVC.
#
# Functions:
#   configure_coverage(<target>
#     [TOOL <tool>]
#     [OUTPUT_DIR <dir>]
#     [USE_DEFAULT_FLAGS <ON|OFF>]
#     [CUSTOM_FLAGS <flags...>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#   )
#   generate_coverage_report([TOOL <tool>] [OUTPUT_DIR <dir>])
#
# Usage:
#   include(CoverageConfig)
#   configure_coverage(MyTests TOOL gcov)
#   generate_coverage_report(TOOL gcov OUTPUT_DIR ${CMAKE_BINARY_DIR}/coverage)
#
# =============================================================================

# =============================================================================
# Function: configure_coverage
#
# Configures code coverage for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   TOOL <tool>      - Coverage tool (gcov|llvm-cov|msvc). Default: auto-detect
#   OUTPUT_DIR <dir>  - Directory for coverage data. Default: ${CMAKE_BINARY_DIR}/coverage
#   USE_DEFAULT_FLAGS <on> - Use default coverage flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...> - Completely override all default coverage flags with custom ones.
#                        If specified, USE_DEFAULT_FLAGS is ignored.
#                        If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   EXTRA_FLAGS <...> - Extra coverage flags (added to defaults or custom)
#   MSVC_FLAGS <...>  - MSVC-specific coverage flags (added to defaults or custom)
#   GCC_FLAGS <...>   - GCC-specific coverage flags (added to defaults or custom)
#   CLANG_FLAGS <...> - Clang-specific coverage flags (added to defaults or custom)
#
# Usage:
#   # Use defaults
#   configure_coverage(MyTests TOOL gcov)
#
#   # Use only custom flags
#   configure_coverage(MyTests USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS --coverage)
#
#   # Completely override with custom flags
#   configure_coverage(MyTests CUSTOM_FLAGS -fprofile-instr-generate -fcoverage-mapping)
# =============================================================================
function(configure_coverage target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "CoverageConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs TOOL OUTPUT_DIR USE_DEFAULT_FLAGS)
  set(multiValueArgs CUSTOM_FLAGS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS)
  cmake_parse_arguments(COV_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED COV_CONFIG_USE_DEFAULT_FLAGS)
    set(COV_CONFIG_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT COV_CONFIG_USE_DEFAULT_FLAGS AND NOT COV_CONFIG_CUSTOM_FLAGS)
    message(FATAL_ERROR "CoverageConfig: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # Set default output directory
  if(NOT COV_CONFIG_OUTPUT_DIR)
    set(COV_CONFIG_OUTPUT_DIR "${CMAKE_BINARY_DIR}/coverage")
  endif()

  # Auto-detect tool if not specified
  if(NOT COV_CONFIG_TOOL)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      set(COV_CONFIG_TOOL "gcov")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      set(COV_CONFIG_TOOL "llvm-cov")
    elseif(MSVC)
      set(COV_CONFIG_TOOL "msvc")
    else()
      message(WARNING "CoverageConfig: Unknown compiler, defaulting to gcov")
      set(COV_CONFIG_TOOL "gcov")
    endif()
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(COV_CONFIG_CUSTOM_FLAGS)
    target_compile_options(${target} PRIVATE ${COV_CONFIG_CUSTOM_FLAGS})
    target_link_options(${target} PRIVATE ${COV_CONFIG_CUSTOM_FLAGS})
    message(STATUS "CoverageConfig: Using custom coverage flags only for '${target}'")
    return()
  endif()

  # Configure based on tool
  if(COV_CONFIG_USE_DEFAULT_FLAGS)
    if(COV_CONFIG_TOOL STREQUAL "gcov")
      _configure_gcov_coverage(${target} "${COV_CONFIG_OUTPUT_DIR}" "${COV_CONFIG_EXTRA_FLAGS}" "${COV_CONFIG_GCC_FLAGS}")
    elseif(COV_CONFIG_TOOL STREQUAL "llvm-cov")
      _configure_llvm_cov_coverage(${target} "${COV_CONFIG_OUTPUT_DIR}" "${COV_CONFIG_EXTRA_FLAGS}" "${COV_CONFIG_CLANG_FLAGS}")
    elseif(COV_CONFIG_TOOL STREQUAL "msvc")
      _configure_msvc_coverage(${target} "${COV_CONFIG_OUTPUT_DIR}" "${COV_CONFIG_EXTRA_FLAGS}" "${COV_CONFIG_MSVC_FLAGS}")
    else()
      message(FATAL_ERROR "CoverageConfig: Unknown coverage tool '${COV_CONFIG_TOOL}'")
    endif()
    message(STATUS "CoverageConfig: Code coverage configured for '${target}' using '${COV_CONFIG_TOOL}'")
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(COV_CONFIG_EXTRA_FLAGS)
      target_compile_options(${target} PRIVATE ${COV_CONFIG_EXTRA_FLAGS})
      target_link_options(${target} PRIVATE ${COV_CONFIG_EXTRA_FLAGS})
    endif()
    if(COV_CONFIG_MSVC_FLAGS)
      target_compile_options(${target} PRIVATE ${COV_CONFIG_MSVC_FLAGS})
      target_link_options(${target} PRIVATE ${COV_CONFIG_MSVC_FLAGS})
    endif()
    if(COV_CONFIG_GCC_FLAGS)
      target_compile_options(${target} PRIVATE ${COV_CONFIG_GCC_FLAGS})
      target_link_options(${target} PRIVATE ${COV_CONFIG_GCC_FLAGS})
    endif()
    if(COV_CONFIG_CLANG_FLAGS)
      target_compile_options(${target} PRIVATE ${COV_CONFIG_CLANG_FLAGS})
      target_link_options(${target} PRIVATE ${COV_CONFIG_CLANG_FLAGS})
    endif()
    message(STATUS "CoverageConfig: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_gcov_coverage
# GCC: --coverage flag
# =============================================================================
function(_configure_gcov_coverage target output_dir extra_flags compiler_flags)
  # Add coverage flags
  target_compile_options(${target} PRIVATE --coverage)
  target_link_options(${target} PRIVATE --coverage)

  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()

  # Create coverage directory
  file(MAKE_DIRECTORY "${output_dir}")

  message(STATUS "CoverageConfig: GCC coverage (gcov) enabled for '${target}'")
  message(STATUS "CoverageConfig:   Coverage data directory: ${output_dir}")
  message(STATUS "CoverageConfig:   Run tests, then use: lcov --capture --directory . --output-file coverage.info")
endfunction()

# =============================================================================
# Internal function: _configure_llvm_cov_coverage
# Clang: -fprofile-instr-generate -fcoverage-mapping
# =============================================================================
function(_configure_llvm_cov_coverage target output_dir extra_flags compiler_flags)
  # Add coverage flags
  target_compile_options(${target} PRIVATE
    -fprofile-instr-generate
    -fcoverage-mapping
  )
  target_link_options(${target} PRIVATE -fprofile-instr-generate)

  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()

  # Create coverage directory
  file(MAKE_DIRECTORY "${output_dir}")

  # Set environment variable for coverage output
  set_target_properties(${target} PROPERTIES
    ENVIRONMENT "LLVM_PROFILE_FILE=${output_dir}/%p.profraw"
  )

  message(STATUS "CoverageConfig: Clang coverage (llvm-cov) enabled for '${target}'")
  message(STATUS "CoverageConfig:   Coverage data directory: ${output_dir}")
  message(STATUS "CoverageConfig:   Run tests, then use: llvm-profdata merge -output=${output_dir}/merged.profdata ${output_dir}/*.profraw")
  message(STATUS "CoverageConfig:   Then: llvm-cov show ${target} -instr-profile=${output_dir}/merged.profdata")
endfunction()

# =============================================================================
# Internal function: _configure_msvc_coverage
# MSVC: /ZI and Code Coverage tools
# =============================================================================
function(_configure_msvc_coverage target output_dir extra_flags compiler_flags)
  # MSVC coverage requires /ZI (Edit and Continue) and Code Coverage tools
  target_compile_options(${target} PRIVATE /ZI)
  target_compile_options(${target} PRIVATE $<$<CONFIG:Debug>:/JMC>)  # Just My Code debugging

  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()

  # Create coverage directory
  file(MAKE_DIRECTORY "${output_dir}")

  message(STATUS "CoverageConfig: MSVC coverage enabled for '${target}'")
  message(STATUS "CoverageConfig:   Coverage data directory: ${output_dir}")
  message(STATUS "CoverageConfig:   Use Visual Studio Code Coverage tools or OpenCppCoverage")
endfunction()

# =============================================================================
# Function: generate_coverage_report
#
# Generates a coverage report using the specified tool.
#
# Parameters:
#   TOOL <tool>       - Coverage tool (gcov|llvm-cov|msvc). Default: auto-detect
#   OUTPUT_DIR <dir>  - Directory for coverage data. Default: ${CMAKE_BINARY_DIR}/coverage
#   FORMAT <format>   - Report format (html|xml|text). Default: html
#
# Usage:
#   generate_coverage_report(TOOL gcov OUTPUT_DIR ${CMAKE_BINARY_DIR}/coverage FORMAT html)
# =============================================================================
function(generate_coverage_report)
  # Parse arguments
  set(options "")
  set(oneValueArgs TOOL OUTPUT_DIR FORMAT)
  set(multiValueArgs "")
  cmake_parse_arguments(COV_REPORT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT COV_REPORT_OUTPUT_DIR)
    set(COV_REPORT_OUTPUT_DIR "${CMAKE_BINARY_DIR}/coverage")
  endif()

  if(NOT COV_REPORT_FORMAT)
    set(COV_REPORT_FORMAT "html")
  endif()

  # Auto-detect tool
  if(NOT COV_REPORT_TOOL)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      set(COV_REPORT_TOOL "gcov")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      set(COV_REPORT_TOOL "llvm-cov")
    elseif(MSVC)
      set(COV_REPORT_TOOL "msvc")
    else()
      set(COV_REPORT_TOOL "gcov")
    endif()
  endif()

  # Generate report based on tool
  if(COV_REPORT_TOOL STREQUAL "gcov")
    _generate_gcov_report("${COV_REPORT_OUTPUT_DIR}" "${COV_REPORT_FORMAT}")
  elseif(COV_REPORT_TOOL STREQUAL "llvm-cov")
    _generate_llvm_cov_report("${COV_REPORT_OUTPUT_DIR}" "${COV_REPORT_FORMAT}")
  else()
    message(WARNING "CoverageConfig: Report generation for '${COV_REPORT_TOOL}' not implemented")
  endif()
endfunction()

# =============================================================================
# Internal function: _generate_gcov_report
# =============================================================================
function(_generate_gcov_report output_dir format)
  find_program(LCOV_EXECUTABLE lcov)
  find_program(GENHTML_EXECUTABLE genhtml)

  if(LCOV_EXECUTABLE AND GENHTML_EXECUTABLE)
    if(format STREQUAL "html")
      add_custom_target(coverage_report
        COMMAND ${LCOV_EXECUTABLE} --directory . --capture --output-file ${output_dir}/coverage.info
        COMMAND ${LCOV_EXECUTABLE} --remove ${output_dir}/coverage.info '/usr/*' '*/test/*' --output-file ${output_dir}/coverage.info.cleaned
        COMMAND ${GENHTML_EXECUTABLE} -o ${output_dir}/html ${output_dir}/coverage.info.cleaned
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating HTML coverage report"
      )
      message(STATUS "CoverageConfig: Coverage report target 'coverage_report' created")
      message(STATUS "CoverageConfig:   Run: cmake --build . --target coverage_report")
    else()
      message(WARNING "CoverageConfig: Format '${format}' not supported for gcov")
    endif()
  else()
    message(WARNING "CoverageConfig: lcov or genhtml not found. Install lcov package.")
  endif()
endfunction()

# =============================================================================
# Internal function: _generate_llvm_cov_report
# =============================================================================
function(_generate_llvm_cov_report output_dir format)
  find_program(LLVM_PROFDATA_EXECUTABLE llvm-profdata)
  find_program(LLVM_COV_EXECUTABLE llvm-cov)

  if(LLVM_PROFDATA_EXECUTABLE AND LLVM_COV_EXECUTABLE)
    set(merged_profile "${output_dir}/merged.profdata")

    if(format STREQUAL "html")
      add_custom_target(coverage_report
        COMMAND ${LLVM_PROFDATA_EXECUTABLE} merge -output=${merged_profile} ${output_dir}/*.profraw
        COMMAND ${LLVM_COV_EXECUTABLE} show -format=html -output-dir=${output_dir}/html -instr-profile=${merged_profile} $<TARGET_FILE:${CMAKE_PROJECT_NAME}>
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Generating HTML coverage report"
      )
      message(STATUS "CoverageConfig: Coverage report target 'coverage_report' created")
      message(STATUS "CoverageConfig:   Run: cmake --build . --target coverage_report")
    else()
      message(WARNING "CoverageConfig: Format '${format}' not supported for llvm-cov")
    endif()
  else()
    message(WARNING "CoverageConfig: llvm-profdata or llvm-cov not found")
  endif()
endfunction()
