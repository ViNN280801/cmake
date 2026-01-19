# =============================================================================
# BoostConfig.cmake
# Universal Boost C++ Libraries integration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to integrate Boost C++ Libraries
# into any CMake project using FetchContent, find_package, or system packages.
#
# Functions:
#   add_boost_dependency(
#     [METHOD <FETCH|FIND|SYSTEM>]
#     [VERSION <version>]
#     [GIT_REPOSITORY <url>]
#     [GIT_TAG <tag>]
#     [COMPONENTS <components...>]
#     [REQUIRED <ON|OFF>]
#     [BUILD_SHARED_LIBS <ON|OFF>]
#     [BUILD_TESTING <ON|OFF>]
#     [USE_BOOST_CMAKE <ON|OFF>]
#     [CUSTOM_CMAKE_ARGS <args...>]
#   )
#   link_boost_to_target(<target>
#     [COMPONENTS <components...>]
#     [INTERFACE_TARGET <target_name>]
#   )
#
# Usage:
#   include(BoostConfig)
#   # Use FetchContent to download and build Boost
#   add_boost_dependency(METHOD FETCH VERSION 1.84.0 COMPONENTS system filesystem)
#   link_boost_to_target(MyTarget COMPONENTS system filesystem)
#
#   # Use system-installed Boost
#   add_boost_dependency(METHOD SYSTEM VERSION 1.82.0 COMPONENTS system filesystem)
#   link_boost_to_target(MyTarget)
#
#   # Use find_package to locate Boost
#   add_boost_dependency(METHOD FIND VERSION 1.84.0 COMPONENTS system filesystem REQUIRED ON)
#   link_boost_to_target(MyTarget COMPONENTS system filesystem)
#
# =============================================================================

# Default cache variables (can be overridden by users)
set(BOOST_VERSION "1.84.0" CACHE STRING "Default Boost version to use")
set(BOOST_GIT_REPOSITORY "https://github.com/boostorg/boost.git" CACHE STRING "Boost Git repository URL")
set(BOOST_BUILD_SHARED_LIBS OFF CACHE BOOL "Build Boost as shared libraries")
set(BOOST_BUILD_TESTING OFF CACHE BOOL "Build Boost tests")
set(BOOST_USE_BOOST_CMAKE ON CACHE BOOL "Use Boost.CMake build system when using FetchContent")

# =============================================================================
# Function: add_boost_dependency
#
# Adds Boost C++ Libraries to the project using the specified method.
#
# Parameters:
#   METHOD <method>          - Integration method (FETCH|FIND|SYSTEM). Default: FETCH
#                              FETCH: Download and build Boost using FetchContent
#                              FIND: Use find_package to locate Boost (requires installed Boost)
#                              SYSTEM: Use system package manager to locate Boost
#   VERSION <version>        - Boost version to use (e.g., "1.84.0"). Default: ${BOOST_VERSION}
#   GIT_REPOSITORY <url>     - Git repository URL (for FETCH method).
#                              Default: https://github.com/boostorg/boost.git
#   GIT_TAG <tag>            - Git tag/commit/branch (for FETCH method).
#                              Default: "boost-${VERSION}" (e.g., "boost-1.84.0")
#   COMPONENTS <components>  - List of Boost components to include.
#                              Common: system, filesystem, thread, chrono, date_time,
#                              regex, serialization, program_options, etc.
#                              Default: system filesystem
#   REQUIRED <on>            - Whether Boost is required. Default: ON
#   BUILD_SHARED_LIBS <on>   - Build Boost as shared libraries (for FETCH method).
#                              Default: ${BOOST_BUILD_SHARED_LIBS} (OFF)
#   BUILD_TESTING <on>       - Build Boost tests (for FETCH method).
#                              Default: ${BOOST_BUILD_TESTING} (OFF)
#   USE_BOOST_CMAKE <on>     - Use Boost.CMake build system (for FETCH method).
#                              Default: ${BOOST_USE_BOOST_CMAKE} (ON)
#   CUSTOM_CMAKE_ARGS <args> - Custom CMake arguments passed to Boost configuration (for FETCH method)
#
# Usage:
#   # Use defaults (FETCH method, version 1.84.0, system + filesystem)
#   add_boost_dependency()
#
#   # Specify version and components
#   add_boost_dependency(VERSION 1.84.0 COMPONENTS system filesystem thread chrono)
#
#   # Use system-installed Boost
#   add_boost_dependency(METHOD SYSTEM VERSION 1.82.0 COMPONENTS system filesystem)
#
#   # Use find_package with custom version
#   add_boost_dependency(METHOD FIND VERSION 1.84.0 COMPONENTS system filesystem REQUIRED ON)
#
#   # Custom Git repository and tag
#   add_boost_dependency(METHOD FETCH VERSION 1.84.0 GIT_TAG boost-1.84.0 COMPONENTS system)
#
#   # Build as shared libraries
#   add_boost_dependency(BUILD_SHARED_LIBS ON COMPONENTS system filesystem)
#
#   # Optional dependency
#   add_boost_dependency(REQUIRED OFF COMPONENTS system)
# =============================================================================
function(add_boost_dependency)
  # Parse arguments
  set(options "")
  set(oneValueArgs METHOD VERSION GIT_REPOSITORY GIT_TAG REQUIRED BUILD_SHARED_LIBS BUILD_TESTING USE_BOOST_CMAKE)
  set(multiValueArgs COMPONENTS CUSTOM_CMAKE_ARGS)
  cmake_parse_arguments(BOOST_DEP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default method
  if(NOT BOOST_DEP_METHOD)
    set(BOOST_DEP_METHOD "FETCH")
  endif()

  # Set default version
  if(NOT BOOST_DEP_VERSION)
    set(BOOST_DEP_VERSION "${BOOST_VERSION}")
  endif()

  # Set default components
  if(NOT BOOST_DEP_COMPONENTS)
    set(BOOST_DEP_COMPONENTS system filesystem)
  endif()

  # Set default for REQUIRED
  if(NOT DEFINED BOOST_DEP_REQUIRED)
    set(BOOST_DEP_REQUIRED ON)
  endif()

  # Set defaults for BUILD options (use cache values if not specified)
  if(NOT DEFINED BOOST_DEP_BUILD_SHARED_LIBS)
    set(BOOST_DEP_BUILD_SHARED_LIBS ${BOOST_BUILD_SHARED_LIBS})
  endif()

  if(NOT DEFINED BOOST_DEP_BUILD_TESTING)
    set(BOOST_DEP_BUILD_TESTING ${BOOST_BUILD_TESTING})
  endif()

  if(NOT DEFINED BOOST_DEP_USE_BOOST_CMAKE)
    set(BOOST_DEP_USE_BOOST_CMAKE ${BOOST_USE_BOOST_CMAKE})
  endif()

  # Set default Git repository
  if(NOT BOOST_DEP_GIT_REPOSITORY)
    set(BOOST_DEP_GIT_REPOSITORY "${BOOST_GIT_REPOSITORY}")
  endif()

  # Set default Git tag
  if(NOT BOOST_DEP_GIT_TAG)
    set(BOOST_DEP_GIT_TAG "boost-${BOOST_DEP_VERSION}")
  endif()

  # Validate method
  if(NOT BOOST_DEP_METHOD MATCHES "^(FETCH|FIND|SYSTEM)$")
    message(FATAL_ERROR "BoostConfig: Invalid METHOD '${BOOST_DEP_METHOD}'. Must be FETCH, FIND, or SYSTEM")
  endif()

  # Route to appropriate method handler
  if(BOOST_DEP_METHOD STREQUAL "FETCH")
    _add_boost_dependency_fetch(
      "${BOOST_DEP_VERSION}"
      "${BOOST_DEP_GIT_REPOSITORY}"
      "${BOOST_DEP_GIT_TAG}"
      "${BOOST_DEP_COMPONENTS}"
      "${BOOST_DEP_BUILD_SHARED_LIBS}"
      "${BOOST_DEP_BUILD_TESTING}"
      "${BOOST_DEP_USE_BOOST_CMAKE}"
      "${BOOST_DEP_CUSTOM_CMAKE_ARGS}"
    )
  elseif(BOOST_DEP_METHOD STREQUAL "FIND")
    _add_boost_dependency_find(
      "${BOOST_DEP_VERSION}"
      "${BOOST_DEP_COMPONENTS}"
      "${BOOST_DEP_REQUIRED}"
    )
  elseif(BOOST_DEP_METHOD STREQUAL "SYSTEM")
    _add_boost_dependency_system(
      "${BOOST_DEP_VERSION}"
      "${BOOST_DEP_COMPONENTS}"
      "${BOOST_DEP_REQUIRED}"
    )
  endif()

  # Create interface target for convenient usage
  _create_boost_interface_target("${BOOST_DEP_COMPONENTS}")

  # Log configuration summary
  message(STATUS "BoostConfig: Boost configured via ${BOOST_DEP_METHOD} method")
  message(STATUS "BoostConfig:   Version: ${BOOST_DEP_VERSION}")
  message(STATUS "BoostConfig:   Components: ${BOOST_DEP_COMPONENTS}")
  if(BOOST_DEP_METHOD STREQUAL "FETCH")
    message(STATUS "BoostConfig:   Shared libraries: ${BOOST_DEP_BUILD_SHARED_LIBS}")
    message(STATUS "BoostConfig:   Build testing: ${BOOST_DEP_BUILD_TESTING}")
    message(STATUS "BoostConfig:   Use Boost.CMake: ${BOOST_DEP_USE_BOOST_CMAKE}")
  endif()
endfunction()

# =============================================================================
# Internal function: _add_boost_dependency_fetch
#
# Adds Boost using FetchContent (downloads and builds Boost).
#
# Parameters:
#   version            - Boost version
#   git_repo           - Git repository URL
#   git_tag            - Git tag/commit/branch
#   components         - List of components
#   build_shared       - Build as shared libraries
#   build_testing      - Build tests
#   use_boost_cmake    - Use Boost.CMake
#   custom_cmake_args  - Custom CMake arguments
# =============================================================================
function(_add_boost_dependency_fetch version git_repo git_tag components build_shared build_testing use_boost_cmake custom_cmake_args)
  # Check CMake version
  if(CMAKE_VERSION VERSION_LESS "3.11")
    message(FATAL_ERROR "BoostConfig: CMake 3.11+ required for FetchContent. "
                        "Current version: ${CMAKE_VERSION}")
  endif()

  include(FetchContent)

  # Configure FetchContent for Boost
  FetchContent_Declare(
    Boost
    GIT_REPOSITORY ${git_repo}
    GIT_TAG ${git_tag}
    GIT_SHALLOW TRUE
    GIT_PROGRESS TRUE
  )

  # Configure Boost build options before fetching
  if(use_boost_cmake)
    set(Boost_BOOST_CMAKE ON CACHE BOOL "Use Boost.CMake build system" FORCE)
  else()
    set(Boost_BOOST_CMAKE OFF CACHE BOOL "Use Boost.CMake build system" FORCE)
  endif()

  set(BUILD_SHARED_LIBS ${build_shared} CACHE BOOL "Build shared libraries" FORCE)
  set(BUILD_TESTING ${build_testing} CACHE BOOL "Build tests" FORCE)

  # Apply custom CMake arguments if provided
  if(custom_cmake_args)
    foreach(arg ${custom_cmake_args})
      list(APPEND FETCHCONTENT_OVERRIDE_BOOST_CMAKE_ARGS ${arg})
    endforeach()
    set(FETCHCONTENT_OVERRIDE_BOOST_CMAKE_ARGS ${FETCHCONTENT_OVERRIDE_BOOST_CMAKE_ARGS} CACHE STRING "Custom CMake args for Boost" FORCE)
  endif()

  # Fetch and make available
  FetchContent_MakeAvailable(Boost)

  # Find Boost components
  if(components)
    find_package(Boost ${version} REQUIRED COMPONENTS ${components})
  else()
    find_package(Boost ${version} REQUIRED)
  endif()

  message(STATUS "BoostConfig: Boost ${version} fetched from ${git_repo} (${git_tag})")
endfunction()

# =============================================================================
# Internal function: _add_boost_dependency_find
#
# Adds Boost using find_package (locates installed Boost).
#
# Parameters:
#   version     - Boost version
#   components  - List of components
#   required    - Whether Boost is required
# =============================================================================
function(_add_boost_dependency_find version components required)
  if(required)
    if(components)
      find_package(Boost ${version} REQUIRED COMPONENTS ${components})
    else()
      find_package(Boost ${version} REQUIRED)
    endif()
  else()
    if(components)
      find_package(Boost ${version} QUIET COMPONENTS ${components})
    else()
      find_package(Boost ${version} QUIET)
    endif()
  endif()

  if(Boost_FOUND)
    message(STATUS "BoostConfig: Boost ${version} found via find_package")
    if(components)
      message(STATUS "BoostConfig:   Components: ${components}")
    endif()
  else()
    if(required)
      message(FATAL_ERROR "BoostConfig: Required Boost ${version} not found via find_package")
    else()
      message(STATUS "BoostConfig: Optional Boost ${version} not found via find_package")
    endif()
  endif()
endfunction()

# =============================================================================
# Internal function: _add_boost_dependency_system
#
# Adds Boost using system package manager.
#
# Parameters:
#   version     - Boost version (may be used for version checking)
#   components  - List of components
#   required    - Whether Boost is required
# =============================================================================
function(_add_boost_dependency_system version components required)
  # Try to find via pkg-config first (Linux/Unix)
  find_package(PkgConfig QUIET)

  if(PkgConfig_FOUND)
    # Try to find Boost via pkg-config
    if(components)
      set(pkg_components "")
      foreach(comp ${components})
        list(APPEND pkg_components "boost-${comp}")
      endforeach()
      pkg_check_modules(Boost ${required} ${pkg_components})
    else()
      pkg_check_modules(Boost ${required} boost)
    endif()

    if(Boost_FOUND)
      message(STATUS "BoostConfig: Boost found via pkg-config")
      if(components)
        message(STATUS "BoostConfig:   Components: ${components}")
      endif()
      return()
    endif()
  endif()

  # Fallback to find_package
  _add_boost_dependency_find("${version}" "${components}" "${required}")
endfunction()

# =============================================================================
# Internal function: _create_boost_interface_target
#
# Creates an interface target for convenient Boost usage.
#
# Parameters:
#   components - List of Boost components
# =============================================================================
function(_create_boost_interface_target components)
  # Use a generic interface target name that doesn't conflict with project names
  set(interface_target_name "BoostConfig::Boost")

  if(NOT TARGET ${interface_target_name})
    add_library(${interface_target_name} INTERFACE IMPORTED GLOBAL)

    # Set include directories
    if(Boost_INCLUDE_DIRS)
      set_target_properties(${interface_target_name} PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIRS}"
      )
    endif()

    # Link components if specified
    if(components AND Boost_FOUND)
      set(link_libraries "")
      foreach(component ${components})
        if(TARGET Boost::${component})
          list(APPEND link_libraries Boost::${component})
        elseif(Boost_${component}_LIBRARIES)
          list(APPEND link_libraries ${Boost_${component}_LIBRARIES})
        endif()
      endforeach()

      if(link_libraries)
        set_target_properties(${interface_target_name} PROPERTIES
          INTERFACE_LINK_LIBRARIES "${link_libraries}"
        )
      endif()
    elseif(Boost_LIBRARIES)
      # Fallback to all Boost libraries if components not specified
      set_target_properties(${interface_target_name} PROPERTIES
        INTERFACE_LINK_LIBRARIES "${Boost_LIBRARIES}"
      )
    endif()

    # Export target name for use by link_boost_to_target
    set(BOOST_CONFIG_INTERFACE_TARGET "${interface_target_name}" CACHE INTERNAL "Boost interface target name")
  endif()
endfunction()

# =============================================================================
# Function: link_boost_to_target
#
# Links Boost to a CMake target.
#
# Parameters:
#   <target>           - Target name (required)
#   COMPONENTS <...>    - List of specific Boost components to link.
#                        If not specified, uses all components from add_boost_dependency().
#   INTERFACE_TARGET <name> - Custom interface target name to use.
#                            Default: BoostConfig::Boost (created by add_boost_dependency)
#
# Usage:
#   # Link all components from add_boost_dependency()
#   link_boost_to_target(MyTarget)
#
#   # Link specific components
#   link_boost_to_target(MyTarget COMPONENTS system filesystem)
#
#   # Use custom interface target
#   link_boost_to_target(MyTarget INTERFACE_TARGET MyProject::Boost)
# =============================================================================
function(link_boost_to_target target)
  # Parse arguments
  set(options "")
  set(oneValueArgs INTERFACE_TARGET)
  set(multiValueArgs COMPONENTS)
  cmake_parse_arguments(BOOST_LINK "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Validate target exists
  if(NOT TARGET ${target})
    message(FATAL_ERROR "BoostConfig: Target '${target}' does not exist")
  endif()

  # Determine interface target name
  if(BOOST_LINK_INTERFACE_TARGET)
    set(interface_target ${BOOST_LINK_INTERFACE_TARGET})
  else()
    # Use the default interface target created by add_boost_dependency
    set(interface_target ${BOOST_CONFIG_INTERFACE_TARGET})
    if(NOT interface_target)
      set(interface_target "BoostConfig::Boost")
    endif()
  endif()

  # Link via components or interface target
  if(BOOST_LINK_COMPONENTS)
    # Link specific components
    foreach(component ${BOOST_LINK_COMPONENTS})
      if(TARGET Boost::${component})
        target_link_libraries(${target} PRIVATE Boost::${component})
      else()
        message(WARNING "BoostConfig: Component '${component}' not found, skipping")
      endif()
    endforeach()
    message(STATUS "BoostConfig: Linked Boost components to '${target}': ${BOOST_LINK_COMPONENTS}")
  else()
    # Link via interface target (if available)
    if(TARGET ${interface_target})
      target_link_libraries(${target} PRIVATE ${interface_target})
      message(STATUS "BoostConfig: Linked Boost to '${target}' via ${interface_target}")
    else()
      # Fallback: try to link individual components if Boost was found
      if(Boost_FOUND)
        if(Boost_LIBRARIES)
          target_link_libraries(${target} PRIVATE ${Boost_LIBRARIES})
          target_include_directories(${target} PRIVATE ${Boost_INCLUDE_DIRS})
          message(STATUS "BoostConfig: Linked Boost to '${target}' via Boost_LIBRARIES")
        else()
          message(WARNING "BoostConfig: Interface target '${interface_target}' not found and Boost_LIBRARIES is empty. "
                          "Call add_boost_dependency() first or specify COMPONENTS.")
        endif()
      else()
        message(FATAL_ERROR "BoostConfig: Boost not found. Call add_boost_dependency() first")
      endif()
    endif()
  endif()
endfunction()
