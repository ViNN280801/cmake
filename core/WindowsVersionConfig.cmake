# =============================================================================
# WindowsVersionConfig.cmake
# Universal Windows version configuration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to configure Windows version
# compatibility flags (WIN32_WINNT) for any C/C++ project.
#
# Functions:
#   configure_windows_version([VERSION <version>] [CUSTOM_WIN32_WINNT <hex_value>] [TARGET <target>])
#
# Usage:
#   include(WindowsVersionConfig)
#   configure_windows_version(VERSION TENELEVEN)
#   # Or with custom WIN32_WINNT value:
#   configure_windows_version(CUSTOM_WIN32_WINNT 0x0601)
#   # Or for a specific target:
#   configure_windows_version(VERSION SEVEN TARGET MyApp)
#
# =============================================================================

# =============================================================================
# Function: configure_windows_version
#
# Configures Windows version compatibility flags (WIN32_WINNT) for the project
# or a specific target.
#
# Parameters:
#   VERSION <version>      - Windows version (XP|VISTA|SEVEN|EIGHT|EIGHTDOTONE|TENELEVEN)
#                            Default: TENELEVEN (Windows 10/11)
#                            Ignored if CUSTOM_WIN32_WINNT is specified
#   CUSTOM_WIN32_WINNT <hex> - Custom WIN32_WINNT hex value (e.g., "0x0601", "0x0A00")
#                            If specified, VERSION parameter is ignored
#                            Must be a valid hex value (0x#### format)
#   TARGET <target>        - Optional target name. If not specified, applies globally
#
# Output variables:
#   WIN32_WINNT_VALUE      - Hex code for WIN32_WINNT (e.g., "0x0A00")
#   WINDOWS_VERSION        - Selected version name or "Custom" if CUSTOM_WIN32_WINNT used
#
# Usage:
#   # Use predefined version
#   configure_windows_version(VERSION TENELEVEN)
#
#   # Use custom WIN32_WINNT value
#   configure_windows_version(CUSTOM_WIN32_WINNT 0x0601)
#
#   # Apply to specific target
#   configure_windows_version(VERSION SEVEN TARGET MyApp)
# =============================================================================
function(configure_windows_version)
  if(NOT WIN32)
    message(STATUS "WindowsVersionConfig: Not a Windows platform, skipping configuration")
    return()
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs VERSION CUSTOM_WIN32_WINNT TARGET)
  set(multiValueArgs "")
  cmake_parse_arguments(WIN_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # If CUSTOM_WIN32_WINNT is specified, use it directly
  if(WIN_CONFIG_CUSTOM_WIN32_WINNT)
    # Validate hex format
    if(NOT WIN_CONFIG_CUSTOM_WIN32_WINNT MATCHES "^0x[0-9A-Fa-f]+$")
      message(FATAL_ERROR "WindowsVersionConfig: CUSTOM_WIN32_WINNT must be in hex format (e.g., 0x0601, 0x0A00). "
        "Got: '${WIN_CONFIG_CUSTOM_WIN32_WINNT}'")
    endif()
    set(WIN32_WINNT_VALUE "${WIN_CONFIG_CUSTOM_WIN32_WINNT}")
    set(WINDOWS_VERSION_NAME "Custom (${WIN_CONFIG_CUSTOM_WIN32_WINNT})")
    set(WINDOWS_VERSION "CUSTOM")
  else()
    # Use predefined version
    # Set default version if not specified
    if(NOT WIN_CONFIG_VERSION)
      set(WIN_CONFIG_VERSION "TENELEVEN")
    endif()

    # Set valid choices for cache variable
    set(WINDOWS_VERSION "${WIN_CONFIG_VERSION}" CACHE STRING
      "Windows version compatibility (XP|VISTA|SEVEN|EIGHT|EIGHTDOTONE|TENELEVEN)")

    set_property(CACHE WINDOWS_VERSION PROPERTY STRINGS
      "XP" "VISTA" "SEVEN" "EIGHT" "EIGHTDOTONE" "TENELEVEN")

    # Map version names to hex codes
    set(WIN32_WINNT_VALUE "")
    set(WINDOWS_VERSION_NAME "")

    if(WINDOWS_VERSION STREQUAL "XP")
      set(WIN32_WINNT_VALUE "0x0501")
      set(WINDOWS_VERSION_NAME "Windows XP")
    elseif(WINDOWS_VERSION STREQUAL "VISTA")
      set(WIN32_WINNT_VALUE "0x0600")
      set(WINDOWS_VERSION_NAME "Windows Vista")
    elseif(WINDOWS_VERSION STREQUAL "SEVEN")
      set(WIN32_WINNT_VALUE "0x0601")
      set(WINDOWS_VERSION_NAME "Windows 7")
    elseif(WINDOWS_VERSION STREQUAL "EIGHT")
      set(WIN32_WINNT_VALUE "0x0602")
      set(WINDOWS_VERSION_NAME "Windows 8")
    elseif(WINDOWS_VERSION STREQUAL "EIGHTDOTONE")
      set(WIN32_WINNT_VALUE "0x0603")
      set(WINDOWS_VERSION_NAME "Windows 8.1")
    elseif(WINDOWS_VERSION STREQUAL "TENELEVEN")
      set(WIN32_WINNT_VALUE "0x0A00")
      set(WINDOWS_VERSION_NAME "Windows 10/11")
    else()
      # Fallback to default (Windows 10+)
      set(WIN32_WINNT_VALUE "0x0A00")
      set(WINDOWS_VERSION_NAME "Windows 10/11 (default)")
      message(WARNING "WindowsVersionConfig: Unknown version '${WINDOWS_VERSION}', defaulting to Windows 10/11")
    endif()
  endif()

  # Export to parent scope
  set(WIN32_WINNT_VALUE "${WIN32_WINNT_VALUE}" PARENT_SCOPE)
  set(WINDOWS_VERSION "${WINDOWS_VERSION}" PARENT_SCOPE)

  # Apply to target or globally
  if(WIN_CONFIG_TARGET)
    if(TARGET ${WIN_CONFIG_TARGET})
      target_compile_definitions(${WIN_CONFIG_TARGET} PRIVATE
        WIN32_WINNT=${WIN32_WINNT_VALUE}
        _WIN32_WINNT=${WIN32_WINNT_VALUE}
      )
      message(STATUS "WindowsVersionConfig: Applied ${WINDOWS_VERSION_NAME} (${WIN32_WINNT_VALUE}) to target '${WIN_CONFIG_TARGET}'")
    else()
      message(WARNING "WindowsVersionConfig: Target '${WIN_CONFIG_TARGET}' does not exist")
    endif()
  else()
    # Apply globally
    add_compile_definitions(
      WIN32_WINNT=${WIN32_WINNT_VALUE}
      _WIN32_WINNT=${WIN32_WINNT_VALUE}
    )
    message(STATUS "WindowsVersionConfig: Applied ${WINDOWS_VERSION_NAME} (${WIN32_WINNT_VALUE}) globally")
  endif()
endfunction()

# =============================================================================
# Function: get_windows_version_info
#
# Returns information about configured Windows version.
#
# Output variables:
#   WIN32_WINNT_VALUE - Hex code for WIN32_WINNT
#   WINDOWS_VERSION_NAME - Human-readable version name
#
# Usage:
#   get_windows_version_info()
#   message(STATUS "WIN32_WINNT: ${WIN32_WINNT_VALUE}")
# =============================================================================
function(get_windows_version_info)
  if(NOT WIN32)
    set(WIN32_WINNT_VALUE "" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "N/A (Not Windows)" PARENT_SCOPE)
    return()
  endif()

  # Get current cache value
  get_property(WINDOWS_VERSION CACHE WINDOWS_VERSION PROPERTY VALUE)

  if(NOT WINDOWS_VERSION)
    set(WINDOWS_VERSION "TENELEVEN")
  endif()

  # Map to hex code
  if(WINDOWS_VERSION STREQUAL "XP")
    set(WIN32_WINNT_VALUE "0x0501" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows XP" PARENT_SCOPE)
  elseif(WINDOWS_VERSION STREQUAL "VISTA")
    set(WIN32_WINNT_VALUE "0x0600" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows Vista" PARENT_SCOPE)
  elseif(WINDOWS_VERSION STREQUAL "SEVEN")
    set(WIN32_WINNT_VALUE "0x0601" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows 7" PARENT_SCOPE)
  elseif(WINDOWS_VERSION STREQUAL "EIGHT")
    set(WIN32_WINNT_VALUE "0x0602" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows 8" PARENT_SCOPE)
  elseif(WINDOWS_VERSION STREQUAL "EIGHTDOTONE")
    set(WIN32_WINNT_VALUE "0x0603" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows 8.1" PARENT_SCOPE)
  elseif(WINDOWS_VERSION STREQUAL "TENELEVEN")
    set(WIN32_WINNT_VALUE "0x0A00" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows 10/11" PARENT_SCOPE)
  else()
    set(WIN32_WINNT_VALUE "0x0A00" PARENT_SCOPE)
    set(WINDOWS_VERSION_NAME "Windows 10/11 (default)" PARENT_SCOPE)
  endif()
endfunction()
