# =============================================================================
# UnityBuildConfig.cmake
# Universal Unity builds configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure Unity builds
# (combining multiple source files) to speed up compilation.
#
# Functions:
#   configure_unity_build(<target>
#     [ENABLE <ON|OFF>]
#     [BATCH_SIZE <size>]
#     [MODE <BATCH|GROUP>]
#     [EXCLUDE_FILES <files...>]
#   )
#
# Usage:
#   include(UnityBuildConfig)
#   configure_unity_build(MyApp ENABLE ON BATCH_SIZE 8)
#
# =============================================================================

# =============================================================================
# Function: configure_unity_build
#
# Configures Unity builds for a target to speed up compilation.
#
# Parameters:
#   <target>          - Target name (required)
#   ENABLE <on>       - Enable Unity builds. Default: ON
#   BATCH_SIZE <size> - Maximum files per unity file. Default: 8
#   MODE <mode>       - Unity build mode (BATCH|GROUP). Default: BATCH
#   EXCLUDE_FILES <...> - Files to exclude from unity build
#
# Usage:
#   configure_unity_build(MyApp ENABLE ON BATCH_SIZE 8)
#   configure_unity_build(MyLib ENABLE ON MODE GROUP EXCLUDE_FILES special.cpp)
# =============================================================================
function(configure_unity_build target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "UnityBuildConfig: Target '${target}' does not exist")
  endif()

  # Check CMake version (requires 3.16+)
  if(CMAKE_VERSION VERSION_LESS "3.16")
    message(WARNING "UnityBuildConfig: Unity builds require CMake 3.16+ (current: ${CMAKE_VERSION})")
    return()
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs ENABLE BATCH_SIZE MODE)
  set(multiValueArgs EXCLUDE_FILES)
  cmake_parse_arguments(UNITY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT DEFINED UNITY_ENABLE)
    set(UNITY_ENABLE ON)
  endif()

  if(NOT UNITY_BATCH_SIZE)
    set(UNITY_BATCH_SIZE 8)
  endif()

  if(NOT UNITY_MODE)
    set(UNITY_MODE "BATCH")
  endif()

  # Validate MODE
  if(NOT UNITY_MODE MATCHES "^(BATCH|GROUP)$")
    message(FATAL_ERROR "UnityBuildConfig: Invalid MODE '${UNITY_MODE}'. Must be BATCH or GROUP.")
  endif()

  # Validate BATCH_SIZE
  if(UNITY_BATCH_SIZE LESS 1)
    message(FATAL_ERROR "UnityBuildConfig: BATCH_SIZE must be >= 1. Got: ${UNITY_BATCH_SIZE}")
  endif()

  # Enable/disable Unity builds
  if(UNITY_ENABLE)
    set_target_properties(${target} PROPERTIES
      UNITY_BUILD ON
      UNITY_BUILD_BATCH_SIZE ${UNITY_BATCH_SIZE}
      UNITY_BUILD_MODE ${UNITY_MODE}
    )

    # Exclude specific files
    if(UNITY_EXCLUDE_FILES)
      foreach(file ${UNITY_EXCLUDE_FILES})
        set_source_files_properties(${file} PROPERTIES
          SKIP_UNITY_BUILD_INCLUSION ON
        )
      endforeach()
    endif()

    message(STATUS "UnityBuildConfig: Unity builds enabled for '${target}'")
    message(STATUS "UnityBuildConfig:   Batch size: ${UNITY_BATCH_SIZE}, Mode: ${UNITY_MODE}")
    if(UNITY_EXCLUDE_FILES)
      message(STATUS "UnityBuildConfig:   Excluded files: ${UNITY_EXCLUDE_FILES}")
    endif()
  else()
    set_target_properties(${target} PROPERTIES
      UNITY_BUILD OFF
    )
    message(STATUS "UnityBuildConfig: Unity builds disabled for '${target}'")
  endif()
endfunction()
