# =============================================================================
# VersionConfig.cmake
# Universal version management for C/C++ projects
# =============================================================================
#
# This module provides universal functions to manage project versions
# and generate version information headers.
#
# Functions:
#   configure_version([VERSION <version>] [OUTPUT_HEADER <file>])
#   get_version_info()
#
# Usage:
#   include(VersionConfig)
#   configure_version(VERSION 1.2.3 OUTPUT_HEADER ${CMAKE_BINARY_DIR}/version.h)
#
# =============================================================================

# =============================================================================
# Function: configure_version
#
# Configures project version and optionally generates version header.
#
# Parameters:
#   VERSION <version>     - Project version (e.g., "1.2.3" or "1.2.3.4")
#                          Default: ${PROJECT_VERSION} or "1.0.0"
#   OUTPUT_HEADER <file> - Output header file path. If specified, generates version.h
#
# Output variables:
#   PROJECT_VERSION_MAJOR - Major version number
#   PROJECT_VERSION_MINOR - Minor version number
#   PROJECT_VERSION_PATCH - Patch version number
#   PROJECT_VERSION_TWEAK - Tweak version number (if provided)
#
# Usage:
#   configure_version(VERSION 1.2.3 OUTPUT_HEADER ${CMAKE_BINARY_DIR}/version.h)
#   configure_version(VERSION ${PROJECT_VERSION})
# =============================================================================
function(configure_version)
  # Parse arguments
  set(options "")
  set(oneValueArgs VERSION OUTPUT_HEADER)
  set(multiValueArgs "")
  cmake_parse_arguments(VERSION_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Get version
  if(VERSION_CONFIG_VERSION)
    set(project_version "${VERSION_CONFIG_VERSION}")
  elseif(PROJECT_VERSION)
    set(project_version "${PROJECT_VERSION}")
  else()
    set(project_version "1.0.0")
    message(WARNING "VersionConfig: No version specified, defaulting to 1.0.0")
  endif()

  # Parse version components
  string(REPLACE "." ";" version_parts "${project_version}")
  list(LENGTH version_parts version_parts_count)

  if(version_parts_count GREATER_EQUAL 1)
    list(GET version_parts 0 PROJECT_VERSION_MAJOR)
  else()
    set(PROJECT_VERSION_MAJOR "1")
  endif()

  if(version_parts_count GREATER_EQUAL 2)
    list(GET version_parts 1 PROJECT_VERSION_MINOR)
  else()
    set(PROJECT_VERSION_MINOR "0")
  endif()

  if(version_parts_count GREATER_EQUAL 3)
    list(GET version_parts 2 PROJECT_VERSION_PATCH)
  else()
    set(PROJECT_VERSION_PATCH "0")
  endif()

  if(version_parts_count GREATER_EQUAL 4)
    list(GET version_parts 3 PROJECT_VERSION_TWEAK)
  else()
    set(PROJECT_VERSION_TWEAK "0")
  endif()

  # Export to parent scope
  set(PROJECT_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}" PARENT_SCOPE)
  set(PROJECT_VERSION_MINOR "${PROJECT_VERSION_MINOR}" PARENT_SCOPE)
  set(PROJECT_VERSION_PATCH "${PROJECT_VERSION_PATCH}" PARENT_SCOPE)
  set(PROJECT_VERSION_TWEAK "${PROJECT_VERSION_TWEAK}" PARENT_SCOPE)
  set(PROJECT_VERSION "${project_version}" PARENT_SCOPE)

  # Generate version header if requested
  if(VERSION_CONFIG_OUTPUT_HEADER)
    _generate_version_header("${VERSION_CONFIG_OUTPUT_HEADER}" "${PROJECT_VERSION_MAJOR}" "${PROJECT_VERSION_MINOR}" "${PROJECT_VERSION_PATCH}" "${PROJECT_VERSION_TWEAK}")
  endif()

  message(STATUS "VersionConfig: Project version configured: ${project_version}")
  message(STATUS "VersionConfig:   Major: ${PROJECT_VERSION_MAJOR}, Minor: ${PROJECT_VERSION_MINOR}, Patch: ${PROJECT_VERSION_PATCH}")
endfunction()

# =============================================================================
# Internal function: _generate_version_header
# =============================================================================
function(_generate_version_header output_file major minor patch tweak)
  # Generate version header content
  set(header_content "#ifndef PROJECT_VERSION_H\n")
  set(header_content "${header_content}#define PROJECT_VERSION_H\n\n")
  set(header_content "${header_content}#define PROJECT_VERSION_MAJOR ${major}\n")
  set(header_content "${header_content}#define PROJECT_VERSION_MINOR ${minor}\n")
  set(header_content "${header_content}#define PROJECT_VERSION_PATCH ${patch}\n")
  set(header_content "${header_content}#define PROJECT_VERSION_TWEAK ${tweak}\n")
  set(header_content "${header_content}#define PROJECT_VERSION \"${major}.${minor}.${patch}")
  if(NOT tweak STREQUAL "0")
    set(header_content "${header_content}.${tweak}")
  endif()
  set(header_content "${header_content}\"\n\n")
  set(header_content "${header_content}#endif // PROJECT_VERSION_H\n")

  # Write header file
  file(WRITE "${output_file}" "${header_content}")

  message(STATUS "VersionConfig: Version header generated: ${output_file}")
endfunction()

# =============================================================================
# Function: get_version_info
#
# Returns version information.
#
# Output variables:
#   PROJECT_VERSION_MAJOR - Major version number
#   PROJECT_VERSION_MINOR - Minor version number
#   PROJECT_VERSION_PATCH - Patch version number
#   PROJECT_VERSION_TWEAK - Tweak version number
#   PROJECT_VERSION        - Full version string
#
# Usage:
#   get_version_info()
#   message(STATUS "Version: ${PROJECT_VERSION}")
# =============================================================================
function(get_version_info)
  if(NOT PROJECT_VERSION_MAJOR)
    configure_version()
  endif()

  set(PROJECT_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}" PARENT_SCOPE)
  set(PROJECT_VERSION_MINOR "${PROJECT_VERSION_MINOR}" PARENT_SCOPE)
  set(PROJECT_VERSION_PATCH "${PROJECT_VERSION_PATCH}" PARENT_SCOPE)
  set(PROJECT_VERSION_TWEAK "${PROJECT_VERSION_TWEAK}" PARENT_SCOPE)
  set(PROJECT_VERSION "${PROJECT_VERSION}" PARENT_SCOPE)
endfunction()
