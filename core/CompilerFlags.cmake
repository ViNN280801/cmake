# =============================================================================
# CompilerFlags.cmake
# Universal compiler flags configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure compiler flags
# for MSVC, GCC, Clang, Intel ICC, and other compilers.
#
# Functions:
#   configure_compiler_flags(<target>
#     [STANDARD <c++_standard>]
#     [WARNINGS <level>]
#     [USE_DEFAULT_FLAGS <ON|OFF>]
#     [CUSTOM_FLAGS <flags...>]
#     [CUSTOM_DEFINITIONS <definitions...>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#     [INTEL_FLAGS <flags...>]
#   )
#
# Usage:
#   include(CompilerFlags)
#   configure_compiler_flags(MyTarget STANDARD 17 WARNINGS HIGH)
#
# =============================================================================

# =============================================================================
# Function: configure_compiler_flags
#
# Configures compiler flags for a target with universal support for all compilers.
#
# Parameters:
#   <target>          - Target name (required)
#   STANDARD <std>     - C++ standard (11|14|17|20|23|26). Default: 17
#   WARNINGS <level>   - Warning level (OFF|LOW|MEDIUM|HIGH|PEDANTIC). Default: MEDIUM
#   USE_DEFAULT_FLAGS <on> - Use default compiler flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...> - Completely override all default flags with custom ones.
#                        If specified, USE_DEFAULT_FLAGS is ignored.
#                        If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   CUSTOM_DEFINITIONS <...> - Custom preprocessor definitions (in addition to defaults)
#   EXTRA_FLAGS <...>  - Extra flags applied to all compilers (added to defaults or custom)
#   MSVC_FLAGS <...>   - MSVC-specific flags (added to defaults or custom)
#   GCC_FLAGS <...>    - GCC-specific flags (added to defaults or custom)
#   CLANG_FLAGS <...>  - Clang-specific flags (added to defaults or custom)
#   INTEL_FLAGS <...>  - Intel ICC-specific flags (added to defaults or custom)
#
# Usage:
#   # Use defaults with custom additions
#   configure_compiler_flags(MyApp STANDARD 20 WARNINGS HIGH)
#
#   # Use only custom flags (no defaults)
#   configure_compiler_flags(MyApp USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS -Wall -Wextra)
#
#   # Completely override with custom flags
#   configure_compiler_flags(MyApp CUSTOM_FLAGS -Wall -Wextra -std=c++20)
#
#   # Add custom definitions
#   configure_compiler_flags(MyApp CUSTOM_DEFINITIONS MY_CUSTOM_DEF MY_VALUE=42)
# =============================================================================
function(configure_compiler_flags target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "CompilerFlags: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs STANDARD WARNINGS USE_DEFAULT_FLAGS)
  set(multiValueArgs CUSTOM_FLAGS CUSTOM_DEFINITIONS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS INTEL_FLAGS)
  cmake_parse_arguments(COMPILER_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED COMPILER_CONFIG_USE_DEFAULT_FLAGS)
    set(COMPILER_CONFIG_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT COMPILER_CONFIG_USE_DEFAULT_FLAGS AND NOT COMPILER_CONFIG_CUSTOM_FLAGS)
    message(FATAL_ERROR "CompilerFlags: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # Set C++ standard
  if(COMPILER_CONFIG_STANDARD)
    set_property(TARGET ${target} PROPERTY CXX_STANDARD ${COMPILER_CONFIG_STANDARD})
    set_property(TARGET ${target} PROPERTY CXX_STANDARD_REQUIRED ON)
    set_property(TARGET ${target} PROPERTY CXX_EXTENSIONS OFF)
  endif()

  # Apply custom definitions
  if(COMPILER_CONFIG_CUSTOM_DEFINITIONS)
    target_compile_definitions(${target} PRIVATE ${COMPILER_CONFIG_CUSTOM_DEFINITIONS})
  endif()

  # Apply default definitions if USE_DEFAULT_FLAGS is ON
  if(COMPILER_CONFIG_USE_DEFAULT_FLAGS AND MSVC)
    target_compile_definitions(${target} PRIVATE
      _CRT_SECURE_NO_WARNINGS
      _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
      WIN32_LEAN_AND_MEAN
      NOMINMAX
    )
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(COMPILER_CONFIG_CUSTOM_FLAGS)
    target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_CUSTOM_FLAGS})
    message(STATUS "CompilerFlags: Using custom flags only for '${target}'")
    return()
  endif()

  # Apply extra flags to all compilers (if defaults are enabled)
  if(COMPILER_CONFIG_EXTRA_FLAGS)
    target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_EXTRA_FLAGS})
  endif()

  # Configure compiler-specific flags
  if(COMPILER_CONFIG_USE_DEFAULT_FLAGS)
    # MSVC configuration
    if(MSVC)
      _configure_msvc_flags(${target} "${COMPILER_CONFIG_WARNINGS}" "${COMPILER_CONFIG_MSVC_FLAGS}")
    # GCC configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      _configure_gcc_flags(${target} "${COMPILER_CONFIG_WARNINGS}" "${COMPILER_CONFIG_GCC_FLAGS}")
    # Clang configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      _configure_clang_flags(${target} "${COMPILER_CONFIG_WARNINGS}" "${COMPILER_CONFIG_CLANG_FLAGS}")
    # Intel ICC configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
      _configure_intel_flags(${target} "${COMPILER_CONFIG_WARNINGS}" "${COMPILER_CONFIG_INTEL_FLAGS}")
    else()
      message(STATUS "CompilerFlags: Unsupported compiler '${CMAKE_CXX_COMPILER_ID}', using default flags")
    endif()
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(COMPILER_CONFIG_MSVC_FLAGS)
      target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_MSVC_FLAGS})
    endif()
    if(COMPILER_CONFIG_GCC_FLAGS)
      target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_GCC_FLAGS})
    endif()
    if(COMPILER_CONFIG_CLANG_FLAGS)
      target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_CLANG_FLAGS})
    endif()
    if(COMPILER_CONFIG_INTEL_FLAGS)
      target_compile_options(${target} PRIVATE ${COMPILER_CONFIG_INTEL_FLAGS})
    endif()
    message(STATUS "CompilerFlags: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_msvc_flags
# =============================================================================
function(_configure_msvc_flags target warnings extra_flags)
  # Common MSVC flags
  set(msvc_flags
    /Zc:__cplusplus           # Enable correct __cplusplus macro
    /utf-8                    # UTF-8 source and execution
    /permissive-              # Standards conformance mode
    /MP                       # Multi-processor compilation
    /EHsc                     # Exception handling model
  )

  # Warning level configuration
  if(warnings STREQUAL "OFF")
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "TurnOffAllWarnings"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 0)
    list(APPEND msvc_flags /w)
  elseif(warnings STREQUAL "LOW")
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level1"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 1)
    list(APPEND msvc_flags /W1)
  elseif(warnings STREQUAL "MEDIUM")
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level3"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 3)
    list(APPEND msvc_flags /W3)
  elseif(warnings STREQUAL "HIGH")
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level4"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 4)
    list(APPEND msvc_flags /W4)
  elseif(warnings STREQUAL "PEDANTIC")
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level4"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 4)
    list(APPEND msvc_flags /W4 /Wall)
  else()
    # Default: MEDIUM
    set_target_properties(${target} PROPERTIES
      VS_GLOBAL_WarningLevel "Level3"
    )
    set_property(TARGET ${target} PROPERTY MSVC_WARNING_LEVEL 3)
    list(APPEND msvc_flags /W3)
  endif()

  # Default definitions are applied in main function if USE_DEFAULT_FLAGS is ON

  # Apply flags
  if(extra_flags)
    list(APPEND msvc_flags ${extra_flags})
  endif()

  target_compile_options(${target} PRIVATE ${msvc_flags})

  message(STATUS "CompilerFlags: MSVC flags applied to '${target}' (warnings: ${warnings})")
endfunction()

# =============================================================================
# Internal function: _configure_gcc_flags
# =============================================================================
function(_configure_gcc_flags target warnings extra_flags)
  set(gcc_flags "")

  # Warning level configuration
  if(warnings STREQUAL "OFF")
    list(APPEND gcc_flags -w)
  elseif(warnings STREQUAL "LOW")
    list(APPEND gcc_flags -Wall)
  elseif(warnings STREQUAL "MEDIUM")
    list(APPEND gcc_flags -Wall -Wextra)
  elseif(warnings STREQUAL "HIGH")
    list(APPEND gcc_flags
      -Wall
      -Wextra
      -Wpedantic
      -Wconversion
      -Wsign-conversion
      -Wshadow
      -Wformat=2
      -Wundef
      -Wcast-align
      -Wcast-qual
      -Wwrite-strings
      -Wmissing-declarations
      -Wredundant-decls
      -Woverloaded-virtual
      -Wold-style-cast
    )
  elseif(warnings STREQUAL "PEDANTIC")
    list(APPEND gcc_flags
      -Wall
      -Wextra
      -Wpedantic
      -Wconversion
      -Wsign-conversion
      -Wshadow
      -Wformat=2
      -Wundef
      -Wcast-align
      -Wcast-qual
      -Wwrite-strings
      -Wmissing-declarations
      -Wredundant-decls
      -Woverloaded-virtual
      -Wold-style-cast
      -Weffc++
      -Wstrict-null-sentinel
      -Wno-unused-parameter
    )
  else()
    # Default: MEDIUM
    list(APPEND gcc_flags -Wall -Wextra)
  endif()

  # Debug symbols (all build types)
  list(APPEND gcc_flags -g)

  # Apply flags
  if(extra_flags)
    list(APPEND gcc_flags ${extra_flags})
  endif()

  target_compile_options(${target} PRIVATE ${gcc_flags})

  message(STATUS "CompilerFlags: GCC flags applied to '${target}' (warnings: ${warnings})")
endfunction()

# =============================================================================
# Internal function: _configure_clang_flags
# =============================================================================
function(_configure_clang_flags target warnings extra_flags)
  set(clang_flags "")

  # Warning level configuration (similar to GCC)
  if(warnings STREQUAL "OFF")
    list(APPEND clang_flags -w)
  elseif(warnings STREQUAL "LOW")
    list(APPEND clang_flags -Wall)
  elseif(warnings STREQUAL "MEDIUM")
    list(APPEND clang_flags -Wall -Wextra)
  elseif(warnings STREQUAL "HIGH")
    list(APPEND clang_flags
      -Wall
      -Wextra
      -Wpedantic
      -Wconversion
      -Wsign-conversion
      -Wshadow
      -Wformat=2
      -Wundef
      -Wcast-align
      -Wcast-qual
      -Wwrite-strings
      -Wmissing-declarations
      -Wredundant-decls
      -Woverloaded-virtual
      -Wold-style-cast
    )
  elseif(warnings STREQUAL "PEDANTIC")
    list(APPEND clang_flags
      -Wall
      -Wextra
      -Wpedantic
      -Wconversion
      -Wsign-conversion
      -Wshadow
      -Wformat=2
      -Wundef
      -Wcast-align
      -Wcast-qual
      -Wwrite-strings
      -Wmissing-declarations
      -Wredundant-decls
      -Woverloaded-virtual
      -Wold-style-cast
      -Weffc++
      -Wstrict-null-sentinel
      -Wno-unused-parameter
    )
  else()
    # Default: MEDIUM
    list(APPEND clang_flags -Wall -Wextra)
  endif()

  # Debug symbols (all build types)
  list(APPEND clang_flags -g)

  # Apply flags
  if(extra_flags)
    list(APPEND clang_flags ${extra_flags})
  endif()

  target_compile_options(${target} PRIVATE ${clang_flags})

  message(STATUS "CompilerFlags: Clang flags applied to '${target}' (warnings: ${warnings})")
endfunction()

# =============================================================================
# Internal function: _configure_intel_flags
# =============================================================================
function(_configure_intel_flags target warnings extra_flags)
  set(intel_flags "")

  # Warning level configuration
  if(warnings STREQUAL "OFF")
    list(APPEND intel_flags -w)
  elseif(warnings STREQUAL "LOW")
    list(APPEND intel_flags -w1)
  elseif(warnings STREQUAL "MEDIUM")
    list(APPEND intel_flags -w2)
  elseif(warnings STREQUAL "HIGH")
    list(APPEND intel_flags -w3)
  elseif(warnings STREQUAL "PEDANTIC")
    list(APPEND intel_flags -w3 -Wall)
  else()
    # Default: MEDIUM
    list(APPEND intel_flags -w2)
  endif()

  # Debug symbols
  list(APPEND intel_flags -g)

  # Apply flags
  if(extra_flags)
    list(APPEND intel_flags ${extra_flags})
  endif()

  target_compile_options(${target} PRIVATE ${intel_flags})

  message(STATUS "CompilerFlags: Intel ICC flags applied to '${target}' (warnings: ${warnings})")
endfunction()
