# =============================================================================
# CompileCommandsConfig.cmake
# Universal compile_commands.json generation for clangd integration
# =============================================================================
#
# This module provides universal functions to configure CMake to generate
# compile_commands.json for clangd and other tools that use JSON Compilation Database.
#
# Functions:
#   configure_compile_commands(
#     [ENABLE <ON|OFF>]
#     [OUTPUT_DIR <directory>]
#     [CREATE_SYMLINK <ON|OFF>]
#     [SYMLINK_PATH <path>]
#   )
#
# Usage:
#   include(CompileCommandsConfig)
#   configure_compile_commands(ENABLE ON CREATE_SYMLINK ON)
#
# =============================================================================

# =============================================================================
# Function: configure_compile_commands
#
# Configures CMake to generate compile_commands.json for clangd integration.
# Creates symlink in project root if requested (cross-platform).
#
# Parameters:
#   ENABLE <ON|OFF>           - Enable/disable compile commands export. Default: ON
#   OUTPUT_DIR <directory>    - Directory where compile_commands.json will be generated.
#                               Default: ${CMAKE_BINARY_DIR}
#   CREATE_SYMLINK <ON|OFF>   - Create symlink in project root. Default: ON
#   SYMLINK_PATH <path>      - Path where symlink should be created.
#                               Default: ${CMAKE_SOURCE_DIR}/compile_commands.json
#
# Usage:
#   configure_compile_commands()
#   configure_compile_commands(ENABLE ON CREATE_SYMLINK ON)
#   configure_compile_commands(OUTPUT_DIR ${CMAKE_BINARY_DIR} CREATE_SYMLINK OFF)
# =============================================================================
function(configure_compile_commands)
  # Parse arguments
  set(options "")
  set(oneValueArgs ENABLE OUTPUT_DIR CREATE_SYMLINK SYMLINK_PATH)
  set(multiValueArgs "")
  cmake_parse_arguments(COMPILE_COMMANDS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Default values
  if(NOT DEFINED COMPILE_COMMANDS_ENABLE)
    set(COMPILE_COMMANDS_ENABLE ON)
  endif()

  if(NOT DEFINED COMPILE_COMMANDS_OUTPUT_DIR)
    set(COMPILE_COMMANDS_OUTPUT_DIR "${CMAKE_BINARY_DIR}")
  endif()

  if(NOT DEFINED COMPILE_COMMANDS_CREATE_SYMLINK)
    set(COMPILE_COMMANDS_CREATE_SYMLINK ON)
  endif()

  if(NOT DEFINED COMPILE_COMMANDS_SYMLINK_PATH)
    set(COMPILE_COMMANDS_SYMLINK_PATH "${CMAKE_SOURCE_DIR}/compile_commands.json")
  endif()

  # Enable compile commands export
  if(COMPILE_COMMANDS_ENABLE)
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON CACHE BOOL "Export compile commands for clangd" FORCE)
    message(STATUS "CompileCommandsConfig: Compile commands export enabled")
    message(STATUS "CompileCommandsConfig: Output directory: ${COMPILE_COMMANDS_OUTPUT_DIR}")
  else()
    set(CMAKE_EXPORT_COMPILE_COMMANDS OFF CACHE BOOL "Export compile commands for clangd" FORCE)
    message(STATUS "CompileCommandsConfig: Compile commands export disabled")
    return()
  endif()

  # Create symlink in project root (if requested)
  if(COMPILE_COMMANDS_CREATE_SYMLINK AND COMPILE_COMMANDS_ENABLE)
    set(compile_commands_source "${COMPILE_COMMANDS_OUTPUT_DIR}/compile_commands.json")
    set(compile_commands_link "${COMPILE_COMMANDS_SYMLINK_PATH}")

    # Calculate relative path from symlink location to source file
    file(RELATIVE_PATH relative_path
      "${CMAKE_SOURCE_DIR}"
      "${compile_commands_source}"
    )

    # Create symlink after CMake configuration (not during)
    # Use POST_BUILD or custom target to ensure file exists first
    if(CMAKE_VERSION VERSION_GREATER_EQUAL "3.14")
      # CMake 3.14+ supports create_symlink command
      if(UNIX OR (WIN32 AND CMAKE_SYMLINK_EXISTS))
        # Unix (Linux, macOS) or Windows with symlink support
        add_custom_command(
          OUTPUT "${compile_commands_link}"
          COMMAND ${CMAKE_COMMAND} -E create_symlink
            "${relative_path}"
            "${compile_commands_link}"
          COMMENT "Creating symlink: ${compile_commands_link} -> ${relative_path}"
          DEPENDS "${compile_commands_source}"
        )
        add_custom_target(compile_commands_symlink
          DEPENDS "${compile_commands_link}"
          COMMENT "CompileCommandsConfig: Symlink created at ${compile_commands_link}"
        )
        message(STATUS "CompileCommandsConfig: Symlink will be created at: ${compile_commands_link}")
      elseif(WIN32)
        # Windows without symlink support: copy file instead
        add_custom_command(
          OUTPUT "${compile_commands_link}"
          COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${compile_commands_source}"
            "${compile_commands_link}"
          COMMENT "Copying compile_commands.json to project root: ${compile_commands_link}"
          DEPENDS "${compile_commands_source}"
        )
        add_custom_target(compile_commands_symlink
          DEPENDS "${compile_commands_link}"
          COMMENT "CompileCommandsConfig: compile_commands.json copied to ${compile_commands_link}"
        )
        message(STATUS "CompileCommandsConfig: compile_commands.json will be copied to: ${compile_commands_link}")
        message(STATUS "CompileCommandsConfig: Note: Using copy instead of symlink on Windows")
      endif()
    else()
      # CMake < 3.14: use execute_process in a script
      message(WARNING "CompileCommandsConfig: CMake ${CMAKE_VERSION} detected. Symlink creation may not work.")
      message(WARNING "CompileCommandsConfig: Consider upgrading to CMake 3.14+ for better symlink support.")
      
      # Fallback: create a script that will be executed
      set(symlink_script "${CMAKE_BINARY_DIR}/create_compile_commands_symlink.cmake")
      if(UNIX)
        file(WRITE "${symlink_script}"
          "execute_process(\n"
          "  COMMAND ${CMAKE_COMMAND} -E create_symlink\n"
          "    \"${relative_path}\"\n"
          "    \"${compile_commands_link}\"\n"
          "  WORKING_DIRECTORY \"${CMAKE_SOURCE_DIR}\"\n"
          ")\n"
        )
      elseif(WIN32)
        file(WRITE "${symlink_script}"
          "execute_process(\n"
          "  COMMAND ${CMAKE_COMMAND} -E copy_if_different\n"
          "    \"${compile_commands_source}\"\n"
          "    \"${compile_commands_link}\"\n"
          ")\n"
        )
      endif()

      add_custom_target(compile_commands_symlink
        COMMAND ${CMAKE_COMMAND} -P "${symlink_script}"
        COMMENT "CompileCommandsConfig: Creating compile_commands.json link"
        DEPENDS "${compile_commands_source}"
      )
    endif()

    # Make symlink target depend on all targets (so it's created after compilation)
    # This ensures compile_commands.json is fully populated
    add_custom_target(compile_commands_all
      DEPENDS compile_commands_symlink
      COMMENT "CompileCommandsConfig: Ensuring compile_commands.json is available"
    )
  else()
    message(STATUS "CompileCommandsConfig: Symlink creation disabled")
    message(STATUS "CompileCommandsConfig: compile_commands.json will be at: ${compile_commands_source}")
  endif()

  # Print summary
  message(STATUS "CompileCommandsConfig: Configuration complete")
  message(STATUS "CompileCommandsConfig:   Export enabled: ${COMPILE_COMMANDS_ENABLE}")
  message(STATUS "CompileCommandsConfig:   Output: ${compile_commands_source}")
  if(COMPILE_COMMANDS_CREATE_SYMLINK)
    message(STATUS "CompileCommandsConfig:   Symlink: ${compile_commands_link}")
  endif()
endfunction()

# =============================================================================
# Function: ensure_compile_commands
#
# Ensures compile_commands.json exists and is accessible from project root.
# This is a convenience function that calls configure_compile_commands with
# sensible defaults.
#
# Usage:
#   ensure_compile_commands()
# =============================================================================
function(ensure_compile_commands)
  configure_compile_commands(
    ENABLE ON
    CREATE_SYMLINK ON
  )
endfunction()
