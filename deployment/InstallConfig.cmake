# =============================================================================
# InstallConfig.cmake
# Universal installation rules configuration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to configure installation rules
# for executables, libraries, headers, and other files across all platforms.
#
# Functions:
#   configure_install_rules(<target>
#     [EXECUTABLE_DEST <dir>]
#     [LIBRARY_DEST <dir>]
#     [ARCHIVE_DEST <dir>]
#     [INCLUDE_DEST <dir>]
#     [INCLUDE_DIRS <dirs...>]
#     [CONFIG_FILES <files...>]
#     [DOCS <files...>]
#   )
#
# Usage:
#   include(InstallConfig)
#   configure_install_rules(MyApp INCLUDE_DIRS include/)
#
# =============================================================================

# =============================================================================
# Function: configure_install_rules
#
# Configures installation rules for a target.
#
# Parameters:
#   <target>              - Target name (required)
#   EXECUTABLE_DEST <dir> - Destination for executables. Default: bin
#   LIBRARY_DEST <dir>    - Destination for shared libraries. Default: lib
#   ARCHIVE_DEST <dir>    - Destination for static libraries. Default: lib
#   INCLUDE_DEST <dir>    - Destination for headers. Default: include/${PROJECT_NAME}
#   INCLUDE_DIRS <...>    - Include directories to install
#   CONFIG_FILES <...>    - Configuration files to install
#   DOCS <...>           - Documentation files to install
#
# Usage:
#   configure_install_rules(MyApp INCLUDE_DIRS include/ CONFIG_FILES config/app.conf)
# =============================================================================
function(configure_install_rules target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "InstallConfig: Target '${target}' does not exist")
  endif()

  # Include GNUInstallDirs for standard directories
  include(GNUInstallDirs)

  # Parse arguments
  set(options "")
  set(oneValueArgs EXECUTABLE_DEST LIBRARY_DEST ARCHIVE_DEST INCLUDE_DEST)
  set(multiValueArgs INCLUDE_DIRS CONFIG_FILES DOCS)
  cmake_parse_arguments(INSTALL "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults
  if(NOT INSTALL_EXECUTABLE_DEST)
    set(INSTALL_EXECUTABLE_DEST ${CMAKE_INSTALL_BINDIR})
  endif()

  if(NOT INSTALL_LIBRARY_DEST)
    set(INSTALL_LIBRARY_DEST ${CMAKE_INSTALL_LIBDIR})
  endif()

  if(NOT INSTALL_ARCHIVE_DEST)
    set(INSTALL_ARCHIVE_DEST ${CMAKE_INSTALL_LIBDIR})
  endif()

  if(NOT INSTALL_INCLUDE_DEST)
    if(PROJECT_NAME)
      set(INSTALL_INCLUDE_DEST ${CMAKE_INSTALL_INCLUDEDIR}/${PROJECT_NAME})
    else()
      set(INSTALL_INCLUDE_DEST ${CMAKE_INSTALL_INCLUDEDIR})
    endif()
  endif()

  # Get target type
  get_target_property(target_type ${target} TYPE)

  # Install target
  if(target_type STREQUAL "EXECUTABLE")
    install(TARGETS ${target}
      RUNTIME DESTINATION ${INSTALL_EXECUTABLE_DEST}
      COMPONENT Runtime
    )
  elseif(target_type STREQUAL "SHARED_LIBRARY")
    install(TARGETS ${target}
      LIBRARY DESTINATION ${INSTALL_LIBRARY_DEST}
      RUNTIME DESTINATION ${INSTALL_EXECUTABLE_DEST}
      COMPONENT Runtime
    )
  elseif(target_type STREQUAL "STATIC_LIBRARY")
    install(TARGETS ${target}
      ARCHIVE DESTINATION ${INSTALL_ARCHIVE_DEST}
      COMPONENT Development
    )
  elseif(target_type STREQUAL "OBJECT_LIBRARY")
    install(TARGETS ${target}
      ARCHIVE DESTINATION ${INSTALL_ARCHIVE_DEST}
      COMPONENT Development
    )
  endif()

  # Install headers
  if(INSTALL_INCLUDE_DIRS)
    foreach(include_dir ${INSTALL_INCLUDE_DIRS})
      install(DIRECTORY ${include_dir}
        DESTINATION ${INSTALL_INCLUDE_DEST}
        FILES_MATCHING
        PATTERN "*.h"
        PATTERN "*.hpp"
        PATTERN "*.hxx"
        PATTERN "*.inl"
        COMPONENT Development
      )
    endforeach()
  endif()

  # Install config files
  if(INSTALL_CONFIG_FILES)
    install(FILES ${INSTALL_CONFIG_FILES}
      DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/${PROJECT_NAME}
      COMPONENT Configuration
    )
  endif()

  # Install documentation
  if(INSTALL_DOCS)
    install(FILES ${INSTALL_DOCS}
      DESTINATION ${CMAKE_INSTALL_DOCDIR}/${PROJECT_NAME}
      COMPONENT Documentation
    )
  endif()

  message(STATUS "InstallConfig: Installation rules configured for '${target}'")
  message(STATUS "InstallConfig:   Executable: ${INSTALL_EXECUTABLE_DEST}")
  message(STATUS "InstallConfig:   Library: ${INSTALL_LIBRARY_DEST}")
  message(STATUS "InstallConfig:   Archive: ${INSTALL_ARCHIVE_DEST}")
  message(STATUS "InstallConfig:   Include: ${INSTALL_INCLUDE_DEST}")
endfunction()
