# =============================================================================
# PackageConfig.cmake
# Universal CPack packaging configuration for Windows/Linux/macOS
# =============================================================================
#
# This module provides universal functions to configure CPack for creating
# packages (installers, archives) on Windows, Linux, and macOS.
#
# Functions:
#   configure_packaging(
#     [GENERATORS <generators...>]
#     [VERSION <version>]
#     [VENDOR <vendor>]
#     [DESCRIPTION <description>]
#     [LICENSE_FILE <file>]
#     [COMPONENTS <components...>]
#   )
#
# Usage:
#   include(PackageConfig)
#   configure_packaging(GENERATORS NSIS ZIP VERSION 1.0.0)
#
# =============================================================================

# =============================================================================
# Function: configure_packaging
#
# Configures CPack for creating packages.
#
# Parameters:
#   GENERATORS <...>    - CPack generators (NSIS, DEB, RPM, ZIP, TGZ, DragNDrop, etc.)
#                         Default: Platform-specific (NSIS on Windows, DEB/RPM on Linux, DragNDrop on macOS)
#   VERSION <version>   - Package version. Default: ${PROJECT_VERSION}
#   VENDOR <vendor>     - Package vendor. Default: ${PROJECT_NAME}
#   DESCRIPTION <desc> - Package description
#   LICENSE_FILE <file>  - License file path
#   COMPONENTS <...>     - Package components
#
# Usage:
#   configure_packaging(GENERATORS NSIS ZIP VERSION 1.0.0 VENDOR "MyCompany")
#   configure_packaging(GENERATORS DEB RPM VERSION ${PROJECT_VERSION})
# =============================================================================
function(configure_packaging)
  # Include CPack
  include(CPack)

  # Parse arguments
  set(options "")
  set(oneValueArgs VERSION VENDOR DESCRIPTION LICENSE_FILE)
  set(multiValueArgs GENERATORS COMPONENTS)
  cmake_parse_arguments(PACKAGE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default generators based on platform
  if(NOT PACKAGE_GENERATORS)
    if(WIN32)
      set(PACKAGE_GENERATORS "NSIS;ZIP")
    elseif(APPLE)
      set(PACKAGE_GENERATORS "DragNDrop;TGZ")
    elseif(UNIX)
      set(PACKAGE_GENERATORS "DEB;RPM;TGZ")
    else()
      set(PACKAGE_GENERATORS "TGZ;ZIP")
    endif()
  endif()

  # Basic package information
  if(PROJECT_NAME)
    set(CPACK_PACKAGE_NAME "${PROJECT_NAME}")
  else()
    message(FATAL_ERROR "PackageConfig: PROJECT_NAME is not set. Set it before calling configure_packaging()")
  endif()
  
  if(PACKAGE_VERSION)
    set(CPACK_PACKAGE_VERSION "${PACKAGE_VERSION}")
  elseif(PROJECT_VERSION)
    set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
  else()
    message(WARNING "PackageConfig: No version specified. Using default '1.0.0'")
    set(CPACK_PACKAGE_VERSION "1.0.0")
  endif()

  if(PACKAGE_VENDOR)
    set(CPACK_PACKAGE_VENDOR "${PACKAGE_VENDOR}")
  elseif(PROJECT_NAME)
    set(CPACK_PACKAGE_VENDOR "${PROJECT_NAME}")
  else()
    set(CPACK_PACKAGE_VENDOR "Unknown")
  endif()

  if(PACKAGE_DESCRIPTION)
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PACKAGE_DESCRIPTION}")
  endif()

  if(PACKAGE_LICENSE_FILE)
    set(CPACK_RESOURCE_FILE_LICENSE "${PACKAGE_LICENSE_FILE}")
  endif()

  # Set generators
  set(CPACK_GENERATOR "${PACKAGE_GENERATORS}")

  # Platform-specific configuration
  if(WIN32)
    _configure_windows_packaging()
  elseif(APPLE)
    _configure_macos_packaging()
  elseif(UNIX)
    _configure_linux_packaging()
  endif()

  message(STATUS "PackageConfig: CPack configured")
  message(STATUS "PackageConfig:   Generators: ${PACKAGE_GENERATORS}")
  message(STATUS "PackageConfig:   Version: ${CPACK_PACKAGE_VERSION}")
  message(STATUS "PackageConfig:   Vendor: ${CPACK_PACKAGE_VENDOR}")
endfunction()

# =============================================================================
# Internal function: _configure_windows_packaging
# =============================================================================
function(_configure_windows_packaging)
  # NSIS configuration
  set(CPACK_NSIS_DISPLAY_NAME "${PROJECT_NAME}")
  set(CPACK_NSIS_PACKAGE_NAME "${PROJECT_NAME}")
  set(CPACK_NSIS_MODIFY_PATH ON)
  set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)

  # WiX configuration (if available)
  find_program(CPACK_WIX_CANDLE_EXECUTABLE candle.exe)
  find_program(CPACK_WIX_LIGHT_EXECUTABLE light.exe)

  if(CPACK_WIX_CANDLE_EXECUTABLE AND CPACK_WIX_LIGHT_EXECUTABLE)
    list(APPEND CPACK_GENERATOR "WIX")
    set(CPACK_WIX_PRODUCT_GUID "PUT-GUID-HERE")
    set(CPACK_WIX_UPGRADE_GUID "PUT-GUID-HERE")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_macos_packaging
# =============================================================================
function(_configure_macos_packaging)
  set(CPACK_DMG_VOLUME_NAME "${PROJECT_NAME}")
  set(CPACK_DMG_FORMAT "UDZO")
  set(CPACK_PACKAGEMAKER_BUNDLE_IDENTIFIER "com.${PROJECT_NAME}.${PROJECT_NAME}")
endfunction()

# =============================================================================
# Internal function: _configure_linux_packaging
# =============================================================================
function(_configure_linux_packaging)
  # DEB configuration
  set(CPACK_DEBIAN_PACKAGE_MAINTAINER "${CPACK_PACKAGE_VENDOR}")
  set(CPACK_DEBIAN_FILE_TYPE "DEB")

  # RPM configuration
  set(CPACK_RPM_PACKAGE_LICENSE "MIT")
  set(CPACK_RPM_FILE_TYPE "RPM")
endfunction()
