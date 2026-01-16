# =============================================================================
# QtDeployment.cmake
# Universal Qt deployment utility for Windows (windeployqt)
# =============================================================================
#
# This module provides universal functions to find and use windeployqt
# for deploying Qt dependencies on Windows.
#
# Functions:
#   find_windeployqt([CUSTOM_PATH <path>])
#   deploy_qt_dependencies(<target>
#     [QML_DIR <qml_directory>]
#     [RELEASE_ONLY <ON|OFF>]
#     [QT_VERSION <5|6>]
#     [WINDEPLOYQT_EXECUTABLE <path>]
#     [CUSTOM_FLAGS <flags...>]
#   )
#
# Usage:
#   include(QtDeployment)
#   find_windeployqt()
#   if(WINDEPLOYQT_FOUND)
#     deploy_qt_dependencies(MyApp QML_DIR ${CMAKE_SOURCE_DIR}/qml)
#   endif()
#
# =============================================================================

# =============================================================================
# Function: find_windeployqt
#
# Recursively searches for windeployqt.exe in CMAKE_PREFIX_PATH and Qt directories.
#
# Parameters:
#   CUSTOM_PATH <path> - Custom path to windeployqt.exe. If specified, skips search.
#
# Output variables:
#   WINDEPLOYQT_EXECUTABLE - Full path to windeployqt.exe (or "windeployqt" if not found)
#   WINDEPLOYQT_FOUND      - TRUE if windeployqt.exe was found, FALSE otherwise
#
# Usage:
#   find_windeployqt()
#   find_windeployqt(CUSTOM_PATH "C:/Qt/6.5.0/msvc2022_64/bin/windeployqt.exe")
#   if(WINDEPLOYQT_FOUND)
#     message(STATUS "Found windeployqt: ${WINDEPLOYQT_EXECUTABLE}")
#   endif()
# =============================================================================
function(find_windeployqt)
  # Parse arguments
  set(options "")
  set(oneValueArgs CUSTOM_PATH)
  set(multiValueArgs "")
  cmake_parse_arguments(WINDEPLOYQT_FIND "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # If custom path provided, use it directly
  if(WINDEPLOYQT_FIND_CUSTOM_PATH)
    if(EXISTS "${WINDEPLOYQT_FIND_CUSTOM_PATH}")
      set(WINDEPLOYQT_EXECUTABLE "${WINDEPLOYQT_FIND_CUSTOM_PATH}" PARENT_SCOPE)
      set(WINDEPLOYQT_FOUND TRUE PARENT_SCOPE)
      message(STATUS "QtDeployment: Using custom windeployqt path: ${WINDEPLOYQT_FIND_CUSTOM_PATH}")
      return()
    else()
      message(FATAL_ERROR "QtDeployment: Custom windeployqt path does not exist: ${WINDEPLOYQT_FIND_CUSTOM_PATH}")
    endif()
  endif()
  # Reset output variables
  set(WINDEPLOYQT_EXECUTABLE "" PARENT_SCOPE)
  set(WINDEPLOYQT_FOUND FALSE PARENT_SCOPE)

  if(NOT WIN32)
    message(STATUS "QtDeployment: windeployqt is Windows-only, skipping search")
    return()
  endif()

  # Internal function to recursively search for windeployqt.exe
  function(_find_windeployqt_recursive search_path found_var exe_var)
    # Check direct bin directory
    if(EXISTS "${search_path}/bin/windeployqt.exe")
      set(${found_var} TRUE PARENT_SCOPE)
      set(${exe_var} "${search_path}/bin/windeployqt.exe" PARENT_SCOPE)
      return()
    endif()

    # Check subdirectories (for Qt6 structure like msvc2022_64/bin)
    file(GLOB subdirs LIST_DIRECTORIES true "${search_path}/*")

    foreach(subdir ${subdirs})
      if(IS_DIRECTORY "${subdir}")
        if(EXISTS "${subdir}/bin/windeployqt.exe")
          set(${found_var} TRUE PARENT_SCOPE)
          set(${exe_var} "${subdir}/bin/windeployqt.exe" PARENT_SCOPE)
          return()
        endif()
      endif()
    endforeach()
  endfunction()

  # Search in CMAKE_PREFIX_PATH
  if(CMAKE_PREFIX_PATH)
    # Split CMAKE_PREFIX_PATH into a list of paths
    string(REPLACE ";" " " CMAKE_PREFIX_PATH_LIST "${CMAKE_PREFIX_PATH}")
    separate_arguments(CMAKE_PREFIX_PATH_LIST)

    # Search in all CMAKE_PREFIX_PATH entries
    foreach(path IN LISTS CMAKE_PREFIX_PATH_LIST)
      _find_windeployqt_recursive("${path}" FOUND EXECUTABLE)

      if(FOUND)
        set(WINDEPLOYQT_EXECUTABLE "${EXECUTABLE}" PARENT_SCOPE)
        set(WINDEPLOYQT_FOUND TRUE PARENT_SCOPE)
        message(STATUS "QtDeployment: Found windeployqt recursively: ${EXECUTABLE}")
        return()
      endif()
    endforeach()
  endif()

  # Try to find via Qt5/Qt6_DIR if available
  if(DEFINED Qt6_DIR)
    get_filename_component(QT6_ROOT "${Qt6_DIR}/../.." ABSOLUTE)
    _find_windeployqt_recursive("${QT6_ROOT}" FOUND EXECUTABLE)

    if(FOUND)
      set(WINDEPLOYQT_EXECUTABLE "${EXECUTABLE}" PARENT_SCOPE)
      set(WINDEPLOYQT_FOUND TRUE PARENT_SCOPE)
      message(STATUS "QtDeployment: Found windeployqt via Qt6_DIR: ${EXECUTABLE}")
      return()
    endif()
  endif()

  if(DEFINED Qt5_DIR)
    get_filename_component(QT5_ROOT "${Qt5_DIR}/../.." ABSOLUTE)
    _find_windeployqt_recursive("${QT5_ROOT}" FOUND EXECUTABLE)

    if(FOUND)
      set(WINDEPLOYQT_EXECUTABLE "${EXECUTABLE}" PARENT_SCOPE)
      set(WINDEPLOYQT_FOUND TRUE PARENT_SCOPE)
      message(STATUS "QtDeployment: Found windeployqt via Qt5_DIR: ${EXECUTABLE}")
      return()
    endif()
  endif()

  # Fallback: try standard find_program
  find_program(WINDEPLOYQT_EXECUTABLE
    NAMES windeployqt windeployqt.exe
    HINTS ${CMAKE_PREFIX_PATH}
    PATHS
    "C:/Qt/*/bin"
    "C:/Qt/*/*/bin"
    "$ENV{QTDIR}/bin"
    DOC "Qt windeployqt tool for deploying Qt DLLs"
  )

  if(WINDEPLOYQT_EXECUTABLE)
    set(WINDEPLOYQT_FOUND TRUE PARENT_SCOPE)
    message(STATUS "QtDeployment: Found windeployqt via find_program: ${WINDEPLOYQT_EXECUTABLE}")
  else()
    # Last resort: assume it's in PATH
    set(WINDEPLOYQT_EXECUTABLE "windeployqt" PARENT_SCOPE)
    set(WINDEPLOYQT_FOUND FALSE PARENT_SCOPE)
    message(WARNING "QtDeployment: windeployqt.exe not found. Falling back to PATH search.")
    message(WARNING "QtDeployment: Ensure windeployqt is in PATH or set CMAKE_PREFIX_PATH to Qt installation")
  endif()
endfunction()

# =============================================================================
# Function: deploy_qt_dependencies
#
# Adds a POST_BUILD command to deploy Qt dependencies using windeployqt.
#
# Parameters:
#   <target>          - Target name (required)
#   QML_DIR <dir>     - Optional QML directory path (for --qmldir option)
#   RELEASE_ONLY <on> - Only deploy in Release/RelWithDebInfo builds. Default: ON
#   QT_VERSION <ver>  - Qt version (5 or 6). Auto-detected if not specified
#   WINDEPLOYQT_EXECUTABLE <path> - Custom path to windeployqt.exe. If not specified, uses find_windeployqt()
#   CUSTOM_FLAGS <...> - Additional custom flags for windeployqt (e.g., --no-compiler-runtime, --no-opengl-sw)
#
# Usage:
#   # Use defaults
#   deploy_qt_dependencies(MyApp QML_DIR ${CMAKE_SOURCE_DIR}/qml)
#
#   # Use custom windeployqt path
#   deploy_qt_dependencies(MyApp WINDEPLOYQT_EXECUTABLE "C:/Qt/6.5.0/msvc2022_64/bin/windeployqt.exe")
#
#   # Use custom flags
#   deploy_qt_dependencies(MyApp CUSTOM_FLAGS --no-compiler-runtime --no-opengl-sw)
# =============================================================================
function(deploy_qt_dependencies target)
  if(NOT WIN32)
    message(STATUS "QtDeployment: Qt deployment is Windows-only, skipping")
    return()
  endif()

  if(NOT TARGET ${target})
    message(FATAL_ERROR "QtDeployment: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options RELEASE_ONLY)
  set(oneValueArgs QML_DIR QT_VERSION WINDEPLOYQT_EXECUTABLE)
  set(multiValueArgs CUSTOM_FLAGS)
  cmake_parse_arguments(QT_DEPLOY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Default to RELEASE_ONLY if not specified
  if(NOT DEFINED QT_DEPLOY_RELEASE_ONLY)
    set(QT_DEPLOY_RELEASE_ONLY ON)
  endif()

  # Find or use provided windeployqt
  if(QT_DEPLOY_WINDEPLOYQT_EXECUTABLE)
    if(EXISTS "${QT_DEPLOY_WINDEPLOYQT_EXECUTABLE}")
      set(WINDEPLOYQT_EXECUTABLE "${QT_DEPLOY_WINDEPLOYQT_EXECUTABLE}")
      set(WINDEPLOYQT_FOUND TRUE)
      message(STATUS "QtDeployment: Using provided windeployqt: ${QT_DEPLOY_WINDEPLOYQT_EXECUTABLE}")
    else()
      message(FATAL_ERROR "QtDeployment: Provided windeployqt path does not exist: ${QT_DEPLOY_WINDEPLOYQT_EXECUTABLE}")
    endif()
  else()
    find_windeployqt()
    if(NOT WINDEPLOYQT_FOUND AND WINDEPLOYQT_EXECUTABLE STREQUAL "windeployqt")
      message(WARNING "QtDeployment: windeployqt not found, deployment command will rely on PATH")
    endif()
  endif()

  # Auto-detect Qt version if not specified
  if(NOT QT_DEPLOY_QT_VERSION)
    if(DEFINED Qt6_DIR)
      set(QT_DEPLOY_QT_VERSION 6)
    elseif(DEFINED Qt5_DIR)
      set(QT_DEPLOY_QT_VERSION 5)
    else()
      # Try to detect from windeployqt path
      if(WINDEPLOYQT_FOUND)
        get_filename_component(QT_BIN_DIR "${WINDEPLOYQT_EXECUTABLE}" DIRECTORY)
        get_filename_component(QT_ROOT_DIR "${QT_BIN_DIR}" DIRECTORY)
        if(EXISTS "${QT_ROOT_DIR}/lib/cmake/Qt6")
          set(QT_DEPLOY_QT_VERSION 6)
        elseif(EXISTS "${QT_ROOT_DIR}/lib/cmake/Qt5")
          set(QT_DEPLOY_QT_VERSION 5)
        else()
          set(QT_DEPLOY_QT_VERSION 6)  # Default to Qt6
        endif()
      else()
        set(QT_DEPLOY_QT_VERSION 6)  # Default to Qt6
      endif()
    endif()
  endif()

  # Get Qt bin and root directories from windeployqt path
  if(WINDEPLOYQT_FOUND)
    get_filename_component(QT_BIN_DIR "${WINDEPLOYQT_EXECUTABLE}" DIRECTORY)
    get_filename_component(QT_ROOT_DIR "${QT_BIN_DIR}" DIRECTORY)
  else()
    # Fallback: try to get from Qt variables
    if(QT_DEPLOY_QT_VERSION EQUAL 6)
      if(DEFINED Qt6_DIR)
        get_filename_component(QT_ROOT_DIR "${Qt6_DIR}/../.." ABSOLUTE)
        set(QT_BIN_DIR "${QT_ROOT_DIR}/bin")
      endif()
    else()
      if(DEFINED Qt5_DIR)
        get_filename_component(QT_ROOT_DIR "${Qt5_DIR}/../.." ABSOLUTE)
        set(QT_BIN_DIR "${QT_ROOT_DIR}/bin")
      endif()
    endif()
  endif()

  # Create clean PATH with only essential Windows paths and Qt
  set(CLEAN_PATH "C:\\Windows\\System32")

  if(EXISTS "${QT_BIN_DIR}")
    set(CLEAN_PATH "${CLEAN_PATH};${QT_BIN_DIR}")
  endif()

  # Build deployment command
  set(windeployqt_args
    --verbose 2
    --release
  )

  if(QT_DEPLOY_QML_DIR)
    list(APPEND windeployqt_args --qmldir ${QT_DEPLOY_QML_DIR})
  endif()

  # Qt5-specific flags
  if(QT_DEPLOY_QT_VERSION EQUAL 5)
    list(APPEND windeployqt_args --sql)
  endif()

  # Add custom flags if provided
  if(QT_DEPLOY_CUSTOM_FLAGS)
    list(APPEND windeployqt_args ${QT_DEPLOY_CUSTOM_FLAGS})
  endif()

  # Build command based on RELEASE_ONLY setting
  if(QT_DEPLOY_RELEASE_ONLY)
    # Only deploy in Release/RelWithDebInfo builds
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E env
      --unset=QT_PLUGIN_PATH
      --unset=QML2_IMPORT_PATH
      --unset=QTDIR
      "PATH=${CLEAN_PATH}"
      "QTDIR=${QT_ROOT_DIR}"
      ${WINDEPLOYQT_EXECUTABLE}
      ${windeployqt_args}
      $<TARGET_FILE:${target}>
      WORKING_DIRECTORY $<TARGET_FILE_DIR:${target}>
      COMMENT "QtDeployment: Deploying Qt${QT_DEPLOY_QT_VERSION} dependencies for ${target}..."
      VERBATIM
    )
  else()
    # Deploy in all build types
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E env
      --unset=QT_PLUGIN_PATH
      --unset=QML2_IMPORT_PATH
      --unset=QTDIR
      "PATH=${CLEAN_PATH}"
      "QTDIR=${QT_ROOT_DIR}"
      ${WINDEPLOYQT_EXECUTABLE}
      ${windeployqt_args}
      $<TARGET_FILE:${target}>
      WORKING_DIRECTORY $<TARGET_FILE_DIR:${target}>
      COMMENT "QtDeployment: Deploying Qt${QT_DEPLOY_QT_VERSION} dependencies for ${target}..."
      VERBATIM
    )
  endif()

  message(STATUS "QtDeployment: Qt deployment configured for target '${target}'")
  message(STATUS "QtDeployment:   Using windeployqt: ${WINDEPLOYQT_EXECUTABLE}")
  message(STATUS "QtDeployment:   Qt version: ${QT_DEPLOY_QT_VERSION}")

  if(QT_DEPLOY_QML_DIR)
    message(STATUS "QtDeployment:   QML directory: ${QT_DEPLOY_QML_DIR}")
  endif()

  if(QT_DEPLOY_RELEASE_ONLY)
    message(STATUS "QtDeployment:   Deployment: Release/RelWithDebInfo builds only")
  else()
    message(STATUS "QtDeployment:   Deployment: All build types")
  endif()
endfunction()
