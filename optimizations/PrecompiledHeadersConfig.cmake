# =============================================================================
# PrecompiledHeadersConfig.cmake
# Universal precompiled headers configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure precompiled headers
# for MSVC, GCC, and Clang.
#
# Functions:
#   configure_precompiled_headers(<target>
#     [HEADERS <headers...>]
#     [STANDARD_HEADERS <headers...>]
#     [REUSE_FROM <target>]
#   )
#
# Usage:
#   include(PrecompiledHeadersConfig)
#   configure_precompiled_headers(MyApp HEADERS stdafx.h STANDARD_HEADERS <vector> <string>)
#
# =============================================================================

# =============================================================================
# Function: configure_precompiled_headers
#
# Configures precompiled headers for a target.
#
# Parameters:
#   <target>              - Target name (required)
#   HEADERS <...>         - Custom header files to precompile
#   STANDARD_HEADERS <...> - Standard library headers to precompile (e.g., <vector>, <string>)
#   REUSE_FROM <target>   - Reuse precompiled headers from another target
#
# Usage:
#   configure_precompiled_headers(MyApp HEADERS stdafx.h STANDARD_HEADERS <vector> <string> <memory>)
#   configure_precompiled_headers(MyLib REUSE_FROM CommonPCH)
# =============================================================================
function(configure_precompiled_headers target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "PrecompiledHeadersConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs REUSE_FROM)
  set(multiValueArgs HEADERS STANDARD_HEADERS)
  cmake_parse_arguments(PCH_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Check CMake version (requires 3.16+)
  if(CMAKE_VERSION VERSION_LESS "3.16")
    message(WARNING "PrecompiledHeadersConfig: Precompiled headers require CMake 3.16+ (current: ${CMAKE_VERSION})")
    return()
  endif()

  # Reuse from another target
  if(PCH_CONFIG_REUSE_FROM)
    if(TARGET ${PCH_CONFIG_REUSE_FROM})
      target_link_libraries(${target} PRIVATE ${PCH_CONFIG_REUSE_FROM})
      message(STATUS "PrecompiledHeadersConfig: Reusing PCH from '${PCH_CONFIG_REUSE_FROM}' for '${target}'")
    else()
      message(WARNING "PrecompiledHeadersConfig: Target '${PCH_CONFIG_REUSE_FROM}' does not exist")
    endif()
    return()
  endif()

  # Collect headers
  set(pch_headers "")

  # Add custom headers
  if(PCH_CONFIG_HEADERS)
    list(APPEND pch_headers ${PCH_CONFIG_HEADERS})
  endif()

  # Add standard headers
  if(PCH_CONFIG_STANDARD_HEADERS)
    list(APPEND pch_headers ${PCH_CONFIG_STANDARD_HEADERS})
  endif()

  # Apply precompiled headers
  if(pch_headers)
    target_precompile_headers(${target} PRIVATE ${pch_headers})
    message(STATUS "PrecompiledHeadersConfig: Precompiled headers configured for '${target}'")
    message(STATUS "PrecompiledHeadersConfig:   Headers: ${pch_headers}")
  else()
    message(FATAL_ERROR "PrecompiledHeadersConfig: No headers specified for precompilation. "
      "Provide HEADERS and/or STANDARD_HEADERS parameters.")
  endif()
endfunction()

# =============================================================================
# Function: create_pch_library
#
# Creates an interface library with precompiled headers that can be reused.
#
# Parameters:
#   <target>              - Library target name (required)
#   HEADERS <...>         - Custom header files to precompile
#   STANDARD_HEADERS <...> - Standard library headers to precompile
#
# Usage:
#   create_pch_library(CommonPCH STANDARD_HEADERS <vector> <string> <memory>)
#   target_link_libraries(MyApp PRIVATE CommonPCH)
# =============================================================================
function(create_pch_library target)
  # Parse arguments
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs HEADERS STANDARD_HEADERS)
  cmake_parse_arguments(PCH_LIB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Check CMake version
  if(CMAKE_VERSION VERSION_LESS "3.16")
    message(WARNING "PrecompiledHeadersConfig: Precompiled headers require CMake 3.16+")
    return()
  endif()

  # Create interface library
  add_library(${target} INTERFACE)

  # Collect headers
  set(pch_headers "")

  if(PCH_LIB_HEADERS)
    list(APPEND pch_headers ${PCH_LIB_HEADERS})
  endif()

  if(PCH_LIB_STANDARD_HEADERS)
    list(APPEND pch_headers ${PCH_LIB_STANDARD_HEADERS})
  endif()

  # Apply precompiled headers
  if(pch_headers)
    target_precompile_headers(${target} INTERFACE ${pch_headers})
    message(STATUS "PrecompiledHeadersConfig: PCH library '${target}' created")
    message(STATUS "PrecompiledHeadersConfig:   Headers: ${pch_headers}")
  else()
    message(WARNING "PrecompiledHeadersConfig: No headers specified for PCH library")
  endif()
endfunction()
