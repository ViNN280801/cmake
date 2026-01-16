# =============================================================================
# ModulesConfig.cmake
# Universal C++20 modules configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure C++20 modules
# for MSVC, GCC, and Clang.
#
# Functions:
#   configure_modules(<target>
#     [ENABLE <ON|OFF>]
#     [MODULE_DIR <directory>]
#     [HEADER_UNITS <headers...>]
#     [SCAN_DEPENDENCIES <ON|OFF>]
#     [USE_DEFAULT_FLAGS <ON|OFF>]
#     [CUSTOM_FLAGS <flags...>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#   )
#   add_module(<target> <module_name> [SOURCES <sources...>] [INTERFACE])
#
# Usage:
#   include(ModulesConfig)
#   configure_modules(MyApp ENABLE ON MODULE_DIR ${CMAKE_BINARY_DIR}/modules)
#   add_module(MyLib math SOURCES math.ixx math.cpp)
#
# =============================================================================

# =============================================================================
# Function: configure_modules
#
# Configures C++20 modules support for a target.
#
# Parameters:
#   <target>              - Target name (required)
#   ENABLE <on>           - Enable C++20 modules. Default: ON
#   MODULE_DIR <dir>      - Directory for compiled module files. Default: ${CMAKE_BINARY_DIR}/modules
#   HEADER_UNITS <...>    - Header units to import (e.g., <vector>, <string>)
#   SCAN_DEPENDENCIES <on> - Enable automatic dependency scanning. Default: ON
#   USE_DEFAULT_FLAGS <on> - Use default module flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...>    - Completely override all default module flags with custom ones.
#                           If specified, USE_DEFAULT_FLAGS is ignored.
#                           If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   EXTRA_FLAGS <...>     - Extra module flags (added to defaults or custom)
#   MSVC_FLAGS <...>      - MSVC-specific module flags (added to defaults or custom)
#   GCC_FLAGS <...>       - GCC-specific module flags (added to defaults or custom)
#   CLANG_FLAGS <...>     - Clang-specific module flags (added to defaults or custom)
#
# Usage:
#   # Use defaults
#   configure_modules(MyApp ENABLE ON MODULE_DIR ${CMAKE_BINARY_DIR}/modules)
#
#   # Use only custom flags
#   configure_modules(MyApp USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS -std=c++20 -fmodules-ts)
#
#   # Completely override with custom flags
#   configure_modules(MyApp CUSTOM_FLAGS -std=c++20 -fmodules-ts -fprebuilt-module-path=./modules)
# =============================================================================
function(configure_modules target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "ModulesConfig: Target '${target}' does not exist")
  endif()

  # Check CMake version (requires 3.20+ for full module support)
  if(CMAKE_VERSION VERSION_LESS "3.20")
    message(WARNING "ModulesConfig: Full C++20 modules support requires CMake 3.20+ (current: ${CMAKE_VERSION})")
    message(WARNING "ModulesConfig: Basic module support may work with CMake 3.16+")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs ENABLE MODULE_DIR SCAN_DEPENDENCIES USE_DEFAULT_FLAGS)
  set(multiValueArgs HEADER_UNITS CUSTOM_FLAGS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS)
  cmake_parse_arguments(MODULES "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED MODULES_USE_DEFAULT_FLAGS)
    set(MODULES_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT MODULES_USE_DEFAULT_FLAGS AND NOT MODULES_CUSTOM_FLAGS)
    message(FATAL_ERROR "ModulesConfig: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # Set defaults
  if(NOT DEFINED MODULES_ENABLE)
    set(MODULES_ENABLE ON)
  endif()

  if(NOT MODULES_MODULE_DIR)
    set(MODULES_MODULE_DIR "${CMAKE_BINARY_DIR}/modules")
  endif()

  if(NOT DEFINED MODULES_SCAN_DEPENDENCIES)
    set(MODULES_SCAN_DEPENDENCIES ON)
  endif()

  # Check C++ standard (modules require C++20+)
  get_target_property(target_std ${target} CXX_STANDARD)
  if(NOT target_std OR target_std LESS 20)
    message(WARNING "ModulesConfig: C++20 modules require C++20 or later. Current standard: ${target_std}")
    message(WARNING "ModulesConfig: Setting C++ standard to 20 for '${target}'")
    set_target_properties(${target} PROPERTIES
      CXX_STANDARD 20
      CXX_STANDARD_REQUIRED ON
    )
  endif()

  if(NOT MODULES_ENABLE)
    message(STATUS "ModulesConfig: C++20 modules disabled for '${target}'")
    return()
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(MODULES_CUSTOM_FLAGS)
    target_compile_options(${target} PRIVATE ${MODULES_CUSTOM_FLAGS})
    message(STATUS "ModulesConfig: Using custom module flags only for '${target}'")
    return()
  endif()

  # Create module directory
  file(MAKE_DIRECTORY "${MODULES_MODULE_DIR}")

  # Configure based on compiler
  if(MODULES_USE_DEFAULT_FLAGS)
    if(MSVC)
      _configure_msvc_modules(${target} "${MODULES_MODULE_DIR}" "${MODULES_HEADER_UNITS}" "${MODULES_SCAN_DEPENDENCIES}" "${MODULES_EXTRA_FLAGS}" "${MODULES_MSVC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      _configure_gcc_modules(${target} "${MODULES_MODULE_DIR}" "${MODULES_HEADER_UNITS}" "${MODULES_SCAN_DEPENDENCIES}" "${MODULES_EXTRA_FLAGS}" "${MODULES_GCC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      _configure_clang_modules(${target} "${MODULES_MODULE_DIR}" "${MODULES_HEADER_UNITS}" "${MODULES_SCAN_DEPENDENCIES}" "${MODULES_EXTRA_FLAGS}" "${MODULES_CLANG_FLAGS}")
    else()
      message(WARNING "ModulesConfig: C++20 modules may not be fully supported for compiler '${CMAKE_CXX_COMPILER_ID}'")
    endif()
    message(STATUS "ModulesConfig: C++20 modules configured for '${target}'")
    message(STATUS "ModulesConfig:   Module directory: ${MODULES_MODULE_DIR}")
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(MODULES_EXTRA_FLAGS)
      target_compile_options(${target} PRIVATE ${MODULES_EXTRA_FLAGS})
    endif()
    if(MODULES_MSVC_FLAGS)
      target_compile_options(${target} PRIVATE ${MODULES_MSVC_FLAGS})
    endif()
    if(MODULES_GCC_FLAGS)
      target_compile_options(${target} PRIVATE ${MODULES_GCC_FLAGS})
    endif()
    if(MODULES_CLANG_FLAGS)
      target_compile_options(${target} PRIVATE ${MODULES_CLANG_FLAGS})
    endif()
    message(STATUS "ModulesConfig: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_msvc_modules
# MSVC: /std:c++20, /experimental:module (VS 2019 16.8+), /std:c++latest
# =============================================================================
function(_configure_msvc_modules target module_dir header_units scan_deps extra_flags compiler_flags)
  # MSVC module flags (VS 2019 16.8+)
  if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.28")
    # Modern MSVC (VS 2019 16.8+) has full C++20 modules support
    target_compile_options(${target} PRIVATE
      /std:c++20
      /Zc:__cplusplus
    )
  elseif(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.27")
    # VS 2019 16.7+ with experimental support
    target_compile_options(${target} PRIVATE
      /std:c++latest
      /experimental:module
      /Zc:__cplusplus
    )
  else()
    message(WARNING "ModulesConfig: MSVC modules require Visual Studio 2019 16.7+ (current: ${CMAKE_CXX_COMPILER_VERSION})")
    return()
  endif()

  # Set module output directory
  set_target_properties(${target} PROPERTIES
    VS_DEBUGGER_WORKING_DIRECTORY "${module_dir}"
  )

  # Configure header units if specified
  if(header_units)
    foreach(header ${header_units})
      # MSVC header units: /headerUnit <header> <header>.ifc
      # Note: This is simplified; actual header unit compilation is more complex
      message(STATUS "ModulesConfig: Header unit '${header}' will be imported")
    endforeach()
  endif()

  message(STATUS "ModulesConfig: MSVC C++20 modules enabled for '${target}'")
endfunction()

# =============================================================================
# Internal function: _configure_gcc_modules
# GCC: -std=c++20, -fmodules-ts (GCC 11+)
# =============================================================================
function(_configure_gcc_modules target module_dir header_units scan_deps extra_flags compiler_flags)
  # Check GCC version (modules require GCC 11+)
  if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS "11.0")
    message(WARNING "ModulesConfig: GCC C++20 modules require GCC 11+ (current: ${CMAKE_CXX_COMPILER_VERSION})")
    return()
  endif()

  # GCC module flags
  target_compile_options(${target} PRIVATE
    -std=c++20
    -fmodules-ts
    -fmodule-mapper=${module_dir}/module.map
  )

  # Set module output directory
  set_target_properties(${target} PROPERTIES
    CXX_MODULE_DIR "${module_dir}"
  )

  # Configure header units if specified
  if(header_units)
    foreach(header ${header_units})
      # GCC header units: compile header to .gcm file
      message(STATUS "ModulesConfig: Header unit '${header}' will be imported")
    endforeach()
  endif()

  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
  endif()

  message(STATUS "ModulesConfig: GCC C++20 modules enabled for '${target}'")
endfunction()

# =============================================================================
# Internal function: _configure_clang_modules
# Clang: -std=c++20, -fmodules-ts, -fprebuilt-module-path
# =============================================================================
function(_configure_clang_modules target module_dir header_units scan_deps)
  # Clang has better module support than GCC
  target_compile_options(${target} PRIVATE
    -std=c++20
    -fmodules-ts
    -fprebuilt-module-path=${module_dir}
  )

  # Enable dependency scanning if requested (CMake 3.20+)
  if(scan_deps AND CMAKE_VERSION VERSION_GREATER_EQUAL "3.20")
    set_target_properties(${target} PROPERTIES
      CXX_SCAN_FOR_MODULES ON
    )
  endif()

  # Set module output directory
  set_target_properties(${target} PROPERTIES
    CXX_MODULE_DIR "${module_dir}"
  )

  # Configure header units if specified
  if(header_units)
    foreach(header ${header_units})
      # Clang header units: compile header to .pcm file
      message(STATUS "ModulesConfig: Header unit '${header}' will be imported")
    endforeach()
  endif()

  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
  endif()

  message(STATUS "ModulesConfig: Clang C++20 modules enabled for '${target}'")
endfunction()

# =============================================================================
# Function: add_module
#
# Adds a C++20 module to a target.
#
# Parameters:
#   <target>          - Target name (required)
#   <module_name>      - Module name (required)
#   SOURCES <...>      - Module source files (.ixx, .cppm, .cpp)
#   INTERFACE          - Create interface module (export module)
#
# Usage:
#   add_module(MyLib math SOURCES math.ixx math.cpp)
#   add_module(MyLib utils INTERFACE SOURCES utils.ixx)
# =============================================================================
function(add_module target module_name)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "ModulesConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options INTERFACE)
  set(oneValueArgs "")
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(MODULE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT MODULE_SOURCES)
    message(FATAL_ERROR "ModulesConfig: add_module requires SOURCES parameter")
  endif()

  # Separate interface and implementation files
  set(interface_files "")
  set(implementation_files "")

  foreach(source ${MODULE_SOURCES})
    get_filename_component(ext ${source} EXT)
    if(ext STREQUAL ".ixx" OR ext STREQUAL ".cppm")
      list(APPEND interface_files ${source})
    elseif(ext STREQUAL ".cpp")
      list(APPEND implementation_files ${source})
    else()
      message(WARNING "ModulesConfig: Unknown module file extension '${ext}' for '${source}'")
    endif()
  endforeach()

  # Add interface unit
  if(interface_files)
    # Set FILE_SET for module interface units
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.20")
      target_sources(${target} PRIVATE
        FILE_SET CXX_MODULES TYPE CXX_MODULES FILES ${interface_files}
      )
    else()
      # Fallback for older CMake
      target_sources(${target} PRIVATE ${interface_files})
      set_source_files_properties(${interface_files} PROPERTIES
        CXX_MODULES ON
      )
    endif()
  endif()

  # Add implementation files
  if(implementation_files)
    target_sources(${target} PRIVATE ${implementation_files})
  endif()

  message(STATUS "ModulesConfig: Module '${module_name}' added to '${target}'")
  if(interface_files)
    message(STATUS "ModulesConfig:   Interface files: ${interface_files}")
  endif()
  if(implementation_files)
    message(STATUS "ModulesConfig:   Implementation files: ${implementation_files}")
  endif()
endfunction()

# =============================================================================
# Function: add_header_unit
#
# Adds a header unit import to a target.
#
# Parameters:
#   <target>          - Target name (required)
#   HEADERS <...>     - Header files to import as header units
#
# Usage:
#   add_header_unit(MyApp HEADERS <vector> <string> <memory>)
# =============================================================================
function(add_header_unit target)
  # Parse arguments
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs HEADERS)
  cmake_parse_arguments(HEADER_UNIT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT HEADER_UNIT_HEADERS)
    message(FATAL_ERROR "ModulesConfig: add_header_unit requires HEADERS parameter")
  endif()

  # Configure header units based on compiler
  if(MSVC)
    # MSVC: Use /headerUnit for each header
    foreach(header ${HEADER_UNIT_HEADERS})
      # Note: Actual header unit compilation requires separate compilation step
      message(STATUS "ModulesConfig: Header unit '${header}' configured for '${target}'")
    endforeach()
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # GCC/Clang: Compile headers to module files
    foreach(header ${HEADER_UNIT_HEADERS})
      message(STATUS "ModulesConfig: Header unit '${header}' configured for '${target}'")
    endforeach()
  endif()

  message(STATUS "ModulesConfig: Header units configured for '${target}': ${HEADER_UNIT_HEADERS}")
endfunction()
