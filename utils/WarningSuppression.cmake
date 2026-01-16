# =============================================================================
# WarningSuppression.cmake
# Universal warning suppression configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to suppress compiler warnings
# for MSVC, GCC, Clang, Intel ICC, and other compilers.
#
# Functions:
#   suppress_warnings(<target>
#     [KEEP <warning1> <warning2> ...]
#   )
#
# Usage:
#   include(WarningSuppression)
#   # Suppress all warnings
#   suppress_warnings(MyTarget)
#
#   # Suppress all warnings except specific ones (MSVC warning codes or GCC/Clang warning names)
#   suppress_warnings(MyTarget KEEP 4996 4267 unused-parameter unused-variable)
#
# =============================================================================

# =============================================================================
# Function: suppress_warnings
#
# Suppresses compiler warnings for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   KEEP <warnings...> - List of warnings to keep (not suppress).
#                       If not specified, ALL warnings are suppressed.
#                       For MSVC: use numeric codes (e.g., 4996, 4267)
#                       For GCC/Clang: use warning names without -W prefix (e.g., unused-parameter, unused-variable)
#                       For Intel: use numeric codes (e.g., 181, 869)
#
# Usage:
#   # Suppress all warnings
#   suppress_warnings(MyTarget)
#
#   # Suppress all except specific warnings (MSVC)
#   suppress_warnings(MyTarget KEEP 4996 4267)
#
#   # Suppress all except specific warnings (GCC/Clang)
#   suppress_warnings(MyTarget KEEP unused-parameter unused-variable)
#
# Notes:
#   - MSVC warning codes: https://docs.microsoft.com/en-us/cpp/error-messages/compiler-warnings/compiler-warnings-by-compiler-version
#   - GCC/Clang warning names: remove -W prefix (e.g., -Wunused-parameter -> unused-parameter)
#   - Intel warning codes: https://software.intel.com/content/www/us/en/develop/documentation/cpp-compiler-developer-guide-and-reference/top/compiler-reference/compiler-options/compiler-diagnostic-options/diag-disable.html
# =============================================================================
function(suppress_warnings target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "WarningSuppression: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs KEEP)
  cmake_parse_arguments(WARN_SUPPRESS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Configure based on compiler
  if(MSVC)
    _suppress_msvc_warnings(${target} "${WARN_SUPPRESS_KEEP}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    _suppress_gcc_warnings(${target} "${WARN_SUPPRESS_KEEP}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    _suppress_clang_warnings(${target} "${WARN_SUPPRESS_KEEP}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
    _suppress_intel_warnings(${target} "${WARN_SUPPRESS_KEEP}")
  else()
    message(STATUS "WarningSuppression: Unsupported compiler '${CMAKE_CXX_COMPILER_ID}', using generic suppression")
    _suppress_generic_warnings(${target})
  endif()
endfunction()

# =============================================================================
# Internal helper function: _generate_suppress_flags_from_ranges
#
# Generates suppression flags for numeric warning codes in given ranges.
#
# Parameters:
#   keep_warnings  - List of warning codes to keep (not suppress)
#   flag_prefix    - Prefix for suppression flag (e.g., "/wd" for MSVC, "-diag-disable:" for Intel)
#   result_var     - Variable name to store generated flags
#   warning_ranges - Variable number of range arguments in format "start;end" (e.g., "4000;4999")
# =============================================================================
function(_generate_suppress_flags_from_ranges keep_warnings flag_prefix result_var)
  set(generated_flags "")
  set(ranges_list ${ARGN})  # Get all remaining arguments as ranges

  # Process each range
  foreach(range ${ranges_list})
    string(REPLACE ";" " " range_list ${range})
    list(GET range_list 0 range_start)
    list(GET range_list 1 range_end)
    math(EXPR range_end "${range_end} + 1")

    # Generate codes in range and suppress all except kept ones
    foreach(warn_code RANGE ${range_start} ${range_end})
      # Check if this warning should be kept
      set(should_keep FALSE)
      foreach(keep ${keep_warnings})
        if(warn_code STREQUAL "${keep}")
          set(should_keep TRUE)
          break()
        endif()
      endforeach()

      # Suppress if not kept
      if(NOT should_keep)
        list(APPEND generated_flags ${flag_prefix}${warn_code})
      endif()
    endforeach()
  endforeach()

  set(${result_var} ${generated_flags} PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _suppress_msvc_warnings
#
# Suppresses MSVC warnings.
# =============================================================================
function(_suppress_msvc_warnings target keep_warnings)
  set(msvc_flags "")

  if(NOT keep_warnings)
    # Suppress all warnings
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "TurnOffAllWarnings"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 0)
    list(APPEND msvc_flags /w)
    message(STATUS "WarningSuppression: MSVC - All warnings suppressed for '${target}'")
  else()
    # Enable all warnings first, then suppress all except kept ones
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level4"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 4)
    list(APPEND msvc_flags /W4)

    # Generate MSVC warning codes dynamically (common ranges: 4000-4999, 5000-5999)
    # MSVC warnings are typically in ranges 4000-4999, 5000-5999, etc.
    _generate_suppress_flags_from_ranges("${keep_warnings}" "/wd" suppress_flags "4000;4999" "5000;5999" "6000;6999")
    list(APPEND msvc_flags ${suppress_flags})

    message(STATUS "WarningSuppression: MSVC - Suppressed all warnings except: ${keep_warnings} for '${target}'")
  endif()

  if(msvc_flags)
    target_compile_options(${target} PRIVATE ${msvc_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _suppress_gcc_warnings
#
# Suppresses GCC warnings.
# =============================================================================
function(_suppress_gcc_warnings target keep_warnings)
  set(gcc_flags "")

  if(NOT keep_warnings)
    # Suppress all warnings
    list(APPEND gcc_flags -w)
    message(STATUS "WarningSuppression: GCC - All warnings suppressed for '${target}'")
  else()
    # Enable all warnings first, then suppress all except kept ones
    list(APPEND gcc_flags -Wall -Wextra -Wpedantic)

    # Common GCC warning names (without -W prefix)
    set(all_gcc_warnings
      all
      extra
      pedantic
      conversion
      sign-conversion
      shadow
      format=2
      undef
      cast-align
      cast-qual
      write-strings
      missing-declarations
      redundant-decls
      overloaded-virtual
      old-style-cast
      effc++
      strict-null-sentinel
      unused-parameter
      unused-variable
      unused-function
      unused-label
      unused-value
      unused-result
      maybe-uninitialized
      uninitialized
      strict-overflow
      array-bounds
      return-type
      switch
      switch-default
      switch-enum
      implicit-fallthrough
      missing-field-initializers
      missing-braces
      pointer-arith
      type-limits
      sign-compare
      address
      logical-op
      agnostic
      attributes
      builtin-declaration-mismatch
      cast-function-type
      conditionally-supported
      delete-non-virtual-dtor
      disabled-optimization
      double-promotion
      duplicate-decl-specifier
      format-overflow
      format-security
      format-truncation
      free-nonheap-object
      invalid-pch
      long-long
      missing-include-dirs
      noexcept
      non-template-friend
      non-virtual-dtor
      packed
      pmm-intrinsics-not-portable
      reorder
      restrict
      sizeof-pointer-div
      sizeof-pointer-memaccess
      stack-protector
      strict-aliasing
      suggest-attribute=const
      suggest-attribute=format
      suggest-attribute=noreturn
      suggest-attribute=pure
      suggest-final-methods
      suggest-final-types
      suggest-override
      trampolines
      vector-operation-performance
      zero-as-null-pointer-constant
    )

    # Suppress all warnings except those in keep_warnings
    foreach(warn_name ${all_gcc_warnings})
      # Check if this warning should be kept
      set(should_keep FALSE)
      foreach(keep ${keep_warnings})
        if(warn_name STREQUAL "${keep}")
          set(should_keep TRUE)
          break()
        endif()
      endforeach()

      # Suppress if not kept
      if(NOT should_keep)
        list(APPEND gcc_flags -Wno-${warn_name})
      endif()
    endforeach()

    message(STATUS "WarningSuppression: GCC - Suppressed all warnings except: ${keep_warnings} for '${target}'")
  endif()

  if(gcc_flags)
    target_compile_options(${target} PRIVATE ${gcc_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _suppress_clang_warnings
#
# Suppresses Clang warnings (same as GCC).
# =============================================================================
function(_suppress_clang_warnings target keep_warnings)
  set(clang_flags "")

  if(NOT keep_warnings)
    # Suppress all warnings
    list(APPEND clang_flags -w)
    message(STATUS "WarningSuppression: Clang - All warnings suppressed for '${target}'")
  else()
    # Enable all warnings first, then suppress all except kept ones
    list(APPEND clang_flags -Wall -Wextra -Wpedantic)

    # Common Clang warning names (same as GCC)
    set(all_clang_warnings
      all
      extra
      pedantic
      conversion
      sign-conversion
      shadow
      format=2
      undef
      cast-align
      cast-qual
      write-strings
      missing-declarations
      redundant-decls
      overloaded-virtual
      old-style-cast
      unused-parameter
      unused-variable
      unused-function
      unused-label
      unused-value
      unused-result
      uninitialized
      array-bounds
      return-type
      switch
      switch-default
      switch-enum
      implicit-fallthrough
      missing-field-initializers
      missing-braces
      pointer-arith
      type-limits
      sign-compare
      address
      logical-op
      attributes
      cast-function-type
      conditionally-supported
      delete-non-virtual-dtor
      disabled-optimization
      double-promotion
      duplicate-decl-specifier
      format-overflow
      format-security
      format-truncation
      free-nonheap-object
      invalid-pch
      long-long
      missing-include-dirs
      noexcept
      non-template-friend
      non-virtual-dtor
      packed
      reorder
      restrict
      sizeof-pointer-div
      sizeof-pointer-memaccess
      stack-protector
      strict-aliasing
      suggest-attribute=const
      suggest-attribute=format
      suggest-attribute=noreturn
      suggest-attribute=pure
      suggest-final-methods
      suggest-final-types
      suggest-override
      zero-as-null-pointer-constant
    )

    # Suppress all warnings except those in keep_warnings
    foreach(warn_name ${all_clang_warnings})
      # Check if this warning should be kept
      set(should_keep FALSE)
      foreach(keep ${keep_warnings})
        if(warn_name STREQUAL "${keep}")
          set(should_keep TRUE)
          break()
        endif()
      endforeach()

      # Suppress if not kept
      if(NOT should_keep)
        list(APPEND clang_flags -Wno-${warn_name})
      endif()
    endforeach()

    message(STATUS "WarningSuppression: Clang - Suppressed all warnings except: ${keep_warnings} for '${target}'")
  endif()

  if(clang_flags)
    target_compile_options(${target} PRIVATE ${clang_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _suppress_intel_warnings
#
# Suppresses Intel ICC warnings.
# =============================================================================
function(_suppress_intel_warnings target keep_warnings)
  set(intel_flags "")

  if(NOT keep_warnings)
    # Suppress all warnings
    list(APPEND intel_flags -w)
    message(STATUS "WarningSuppression: Intel - All warnings suppressed for '${target}'")
  else()
    # Enable warnings first
    list(APPEND intel_flags -w3)

    # Generate Intel warning codes dynamically (common ranges: 100-999, 1000-1999, etc.)
    # Intel warnings are typically in ranges 100-999, 1000-1999, etc.
    _generate_suppress_flags_from_ranges("${keep_warnings}" "-diag-disable:" suppress_flags "100;999" "1000;1999" "2000;2999")
    list(APPEND intel_flags ${suppress_flags})

    message(STATUS "WarningSuppression: Intel - Suppressed all warnings except: ${keep_warnings} for '${target}'")
  endif()

  if(intel_flags)
    target_compile_options(${target} PRIVATE ${intel_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _suppress_generic_warnings
#
# Generic warning suppression for unsupported compilers.
# =============================================================================
function(_suppress_generic_warnings target)
  # Try common flags
  if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC|Clang|GNU")
    target_compile_options(${target} PRIVATE -w)
  else()
    message(STATUS "WarningSuppression: Generic suppression attempted for '${target}'")
  endif()
endfunction()
