# =============================================================================
# DependenciesConfig.cmake
# Universal dependency management for C/C++ projects
# =============================================================================
#
# This module provides universal functions to manage dependencies using
# FetchContent, find_package, and other dependency management methods.
#
# Functions:
#   add_dependency(<name>
#     [METHOD <FETCH|FIND|SYSTEM>]
#     [GIT_REPOSITORY <url>]
#     [GIT_TAG <tag>]
#     [PACKAGE_NAME <name>]
#     [COMPONENTS <components...>]
#   )
#
# Usage:
#   include(DependenciesConfig)
#   add_dependency(googletest METHOD FETCH GIT_REPOSITORY https://github.com/google/googletest.git GIT_TAG v1.14.0)
#   add_dependency(Boost METHOD FIND PACKAGE_NAME Boost COMPONENTS system filesystem)
#
# =============================================================================

# =============================================================================
# Function: add_dependency
#
# Adds a dependency to the project using the specified method.
#
# Parameters:
#   <name>              - Dependency name (required)
#   METHOD <method>     - Dependency method (FETCH|FIND|SYSTEM). Default: FIND
#   GIT_REPOSITORY <url> - Git repository URL (for FETCH method)
#   GIT_TAG <tag>       - Git tag/commit (for FETCH method)
#   PACKAGE_NAME <name> - Package name for find_package (for FIND method)
#   COMPONENTS <...>    - Package components (for FIND method)
#   REQUIRED <on>       - Whether dependency is required. Default: ON
#
# Usage:
#   add_dependency(googletest METHOD FETCH GIT_REPOSITORY https://github.com/google/googletest.git GIT_TAG v1.14.0)
#   add_dependency(Boost METHOD FIND PACKAGE_NAME Boost COMPONENTS system filesystem)
# =============================================================================
function(add_dependency name)
  # Parse arguments
  set(options REQUIRED)
  set(oneValueArgs METHOD GIT_REPOSITORY GIT_TAG PACKAGE_NAME)
  set(multiValueArgs COMPONENTS)
  cmake_parse_arguments(DEP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT DEP_METHOD)
    set(DEP_METHOD "FIND")
  endif()

  if(NOT DEFINED DEP_REQUIRED)
    set(DEP_REQUIRED ON)
  endif()

  # Set package name if not specified
  if(NOT DEP_PACKAGE_NAME)
    set(DEP_PACKAGE_NAME "${name}")
  endif()

  # Validate required parameters based on method
  if(DEP_METHOD STREQUAL "FETCH")
    if(NOT DEP_GIT_REPOSITORY)
      message(FATAL_ERROR "DependenciesConfig: FETCH method requires GIT_REPOSITORY parameter")
    endif()
    if(NOT DEP_GIT_TAG)
      message(FATAL_ERROR "DependenciesConfig: FETCH method requires GIT_TAG parameter")
    endif()
    _add_dependency_fetch("${name}" "${DEP_GIT_REPOSITORY}" "${DEP_GIT_TAG}")
  elseif(DEP_METHOD STREQUAL "FIND")
    if(NOT DEP_PACKAGE_NAME)
      message(FATAL_ERROR "DependenciesConfig: FIND method requires PACKAGE_NAME parameter")
    endif()
    _add_dependency_find("${DEP_PACKAGE_NAME}" "${DEP_COMPONENTS}" "${DEP_REQUIRED}")
  elseif(DEP_METHOD STREQUAL "SYSTEM")
    if(NOT DEP_PACKAGE_NAME)
      message(FATAL_ERROR "DependenciesConfig: SYSTEM method requires PACKAGE_NAME parameter")
    endif()
    _add_dependency_system("${DEP_PACKAGE_NAME}" "${DEP_COMPONENTS}" "${DEP_REQUIRED}")
  else()
    message(FATAL_ERROR "DependenciesConfig: Unknown method '${DEP_METHOD}'. Must be FETCH, FIND, or SYSTEM")
  endif()
endfunction()

# =============================================================================
# Internal function: _add_dependency_fetch
# =============================================================================
function(_add_dependency_fetch name git_repo git_tag)
  if(NOT git_repo)
    message(FATAL_ERROR "DependenciesConfig: FETCH method requires GIT_REPOSITORY")
  endif()

  if(NOT git_tag)
    message(FATAL_ERROR "DependenciesConfig: FETCH method requires GIT_TAG")
  endif()

  include(FetchContent)
  FetchContent_Declare(
    ${name}
    GIT_REPOSITORY ${git_repo}
    GIT_TAG ${git_tag}
    GIT_SHALLOW TRUE
  )
  FetchContent_MakeAvailable(${name})

  message(STATUS "DependenciesConfig: Dependency '${name}' fetched from ${git_repo} (${git_tag})")
endfunction()

# =============================================================================
# Internal function: _add_dependency_find
# =============================================================================
function(_add_dependency_find package_name components required)
  if(required)
    if(components)
      find_package(${package_name} REQUIRED COMPONENTS ${components})
    else()
      find_package(${package_name} REQUIRED)
    endif()
  else()
    if(components)
      find_package(${package_name} QUIET COMPONENTS ${components})
    else()
      find_package(${package_name} QUIET)
    endif()
  endif()

  if(${package_name}_FOUND)
    message(STATUS "DependenciesConfig: Dependency '${package_name}' found")
    if(components)
      message(STATUS "DependenciesConfig:   Components: ${components}")
    endif()
  else()
    if(required)
      message(FATAL_ERROR "DependenciesConfig: Required dependency '${package_name}' not found")
    else()
      message(STATUS "DependenciesConfig: Optional dependency '${package_name}' not found")
    endif()
  endif()
endfunction()

# =============================================================================
# Internal function: _add_dependency_system
# =============================================================================
function(_add_dependency_system package_name components required)
  # System dependencies are typically handled via pkg-config or system package manager
  find_package(PkgConfig QUIET)

  if(PkgConfig_FOUND)
    pkg_check_modules(${package_name} ${required} ${package_name})
    if(${package_name}_FOUND)
      message(STATUS "DependenciesConfig: System dependency '${package_name}' found via pkg-config")
    endif()
  else()
    message(WARNING "DependenciesConfig: pkg-config not found, cannot check system dependency '${package_name}'")
  endif()
endfunction()
