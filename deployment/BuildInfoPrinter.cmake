# =============================================================================
# BuildInfoPrinter.cmake
# Universal build information printer for C/C++ projects
# =============================================================================
#
# This module provides universal functions to print all build configuration
# information to the console, including compiler flags, linker flags, hardware
# optimizations, Windows version, PGO settings, and more.
#
# Functions:
#   print_build_info([TARGET <target>])
#
# Usage:
#   include(BuildInfoPrinter)
#   print_build_info()
#   # Or for a specific target:
#   print_build_info(TARGET MyApp)
#
# =============================================================================

# =============================================================================
# Function: print_build_info
#
# Prints comprehensive build configuration information to the console.
#
# Parameters:
#   TARGET <target> - Optional target name. If specified, prints target-specific info.
#                     If not specified, prints global build information.
#
# Usage:
#   print_build_info()
#   print_build_info(TARGET MyApp)
# =============================================================================
function(print_build_info)
  # Parse arguments
  set(options "")
  set(oneValueArgs TARGET)
  set(multiValueArgs "")
  cmake_parse_arguments(BUILD_INFO "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  message(STATUS "")
  message(STATUS "==============================================================================")
  message(STATUS "Build Configuration Information")
  message(STATUS "==============================================================================")
  message(STATUS "")

  # ===========================================================================
  # Platform Information
  # ===========================================================================
  message(STATUS "Platform:")
  message(STATUS "  System: ${CMAKE_SYSTEM_NAME}")
  message(STATUS "  Processor: ${CMAKE_SYSTEM_PROCESSOR}")
  if(WIN32)
    message(STATUS "  Platform: Windows")
    # Get Windows version info if available
    if(DEFINED WINDOWS_VERSION)
      get_windows_version_info()
      message(STATUS "  Windows Version: ${WINDOWS_VERSION_NAME} (${WIN32_WINNT_VALUE})")
    endif()
  elseif(UNIX AND NOT APPLE)
    message(STATUS "  Platform: Linux")
  elseif(APPLE)
    message(STATUS "  Platform: macOS")
  endif()
  message(STATUS "")

  # ===========================================================================
  # Compiler Information
  # ===========================================================================
  message(STATUS "Compiler:")
  message(STATUS "  C++ Compiler ID: ${CMAKE_CXX_COMPILER_ID}")
  message(STATUS "  C++ Compiler: ${CMAKE_CXX_COMPILER}")
  if(CMAKE_CXX_COMPILER_VERSION)
    message(STATUS "  C++ Compiler Version: ${CMAKE_CXX_COMPILER_VERSION}")
  endif()
  message(STATUS "  C Compiler ID: ${CMAKE_C_COMPILER_ID}")
  message(STATUS "  C Compiler: ${CMAKE_C_COMPILER}")
  if(CMAKE_C_COMPILER_VERSION)
    message(STATUS "  C Compiler Version: ${CMAKE_C_COMPILER_VERSION}")
  endif()
  message(STATUS "")

  # ===========================================================================
  # Build Type and Standard
  # ===========================================================================
  message(STATUS "Build Configuration:")
  message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
  if(CMAKE_CXX_STANDARD)
    message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
  endif()
  if(CMAKE_C_STANDARD)
    message(STATUS "  C Standard: ${CMAKE_C_STANDARD}")
  endif()
  message(STATUS "")

  # ===========================================================================
  # Target-Specific Information
  # ===========================================================================
  if(BUILD_INFO_TARGET)
    if(TARGET ${BUILD_INFO_TARGET})
      message(STATUS "Target: ${BUILD_INFO_TARGET}")
      message(STATUS "  Type: ${CMAKE_TARGET_TYPE_${BUILD_INFO_TARGET}}")

      # Get target properties
      get_target_property(target_type ${BUILD_INFO_TARGET} TYPE)
      get_target_property(target_std ${BUILD_INFO_TARGET} CXX_STANDARD)
      get_target_property(target_compile_options ${BUILD_INFO_TARGET} COMPILE_OPTIONS)
      get_target_property(target_link_options ${BUILD_INFO_TARGET} LINK_OPTIONS)
      get_target_property(target_compile_definitions ${BUILD_INFO_TARGET} COMPILE_DEFINITIONS)

      if(target_type)
        message(STATUS "  Target Type: ${target_type}")
      endif()

      if(target_std)
        message(STATUS "  C++ Standard: ${target_std}")
      endif()

      if(target_compile_options)
        message(STATUS "  Compile Options:")
        foreach(opt ${target_compile_options})
          message(STATUS "    ${opt}")
        endforeach()
      endif()

      if(target_link_options)
        message(STATUS "  Link Options:")
        foreach(opt ${target_link_options})
          message(STATUS "    ${opt}")
        endforeach()
      endif()

      if(target_compile_definitions)
        message(STATUS "  Compile Definitions:")
        foreach(def ${target_compile_definitions})
          message(STATUS "    ${def}")
        endforeach()
      endif()

      message(STATUS "")
    else()
      message(WARNING "BuildInfoPrinter: Target '${BUILD_INFO_TARGET}' does not exist")
    endif()
  endif()

  # ===========================================================================
  # Global Compiler Flags
  # ===========================================================================
  message(STATUS "Global Compiler Flags:")
  if(CMAKE_CXX_FLAGS)
    message(STATUS "  C++ Flags: ${CMAKE_CXX_FLAGS}")
  endif()
  if(CMAKE_CXX_FLAGS_DEBUG)
    message(STATUS "  C++ Debug Flags: ${CMAKE_CXX_FLAGS_DEBUG}")
  endif()
  if(CMAKE_CXX_FLAGS_RELEASE)
    message(STATUS "  C++ Release Flags: ${CMAKE_CXX_FLAGS_RELEASE}")
  endif()
  if(CMAKE_C_FLAGS)
    message(STATUS "  C Flags: ${CMAKE_C_FLAGS}")
  endif()
  message(STATUS "")

  # ===========================================================================
  # Global Linker Flags
  # ===========================================================================
  message(STATUS "Global Linker Flags:")
  if(CMAKE_EXE_LINKER_FLAGS)
    message(STATUS "  Executable Linker Flags: ${CMAKE_EXE_LINKER_FLAGS}")
  endif()
  if(CMAKE_SHARED_LINKER_FLAGS)
    message(STATUS "  Shared Library Linker Flags: ${CMAKE_SHARED_LINKER_FLAGS}")
  endif()
  if(CMAKE_STATIC_LINKER_FLAGS)
    message(STATUS "  Static Library Linker Flags: ${CMAKE_STATIC_LINKER_FLAGS}")
  endif()
  message(STATUS "")

  # ===========================================================================
  # Optimization Flags
  # ===========================================================================
  message(STATUS "Optimization:")
  
  # Проверяем оптимизацию уровня компиляции
  if(CMAKE_CXX_FLAGS_RELEASE MATCHES "-O[0-3]|/O[0-9]")
    message(STATUS "  Release Optimization: Enabled")
  else()
    message(STATUS "  Release Optimization: Not explicitly set")
  endif()

  # Проверяем LTO: сначала в target properties (приоритет), затем в глобальных флагах
  set(lto_enabled FALSE)
  if(BUILD_INFO_TARGET AND TARGET ${BUILD_INFO_TARGET})
    get_target_property(target_link_opts ${BUILD_INFO_TARGET} LINK_OPTIONS)
    get_target_property(target_compile_opts ${BUILD_INFO_TARGET} COMPILE_OPTIONS)
    if(target_link_opts AND "${target_link_opts}" MATCHES "-flto|/LTCG")
      set(lto_enabled TRUE)
    elseif(target_compile_opts AND "${target_compile_opts}" MATCHES "/GL")
      set(lto_enabled TRUE)
    endif()
  endif()
  # Fallback: проверяем глобальные флаги
  if(NOT lto_enabled AND CMAKE_CXX_FLAGS_RELEASE MATCHES "-flto|/LTCG|/GL")
    set(lto_enabled TRUE)
  endif()
  if(lto_enabled)
    message(STATUS "  Link-Time Optimization (LTO): Enabled")
  else()
    message(STATUS "  Link-Time Optimization (LTO): Disabled")
  endif()

  # Проверяем PGO: target properties, затем глобальные
  set(pgo_enabled FALSE)
  if(BUILD_INFO_TARGET AND TARGET ${BUILD_INFO_TARGET})
    get_target_property(target_link_opts ${BUILD_INFO_TARGET} LINK_OPTIONS)
    get_target_property(target_compile_opts ${BUILD_INFO_TARGET} COMPILE_OPTIONS)
    if(target_link_opts AND "${target_link_opts}" MATCHES "-fprofile|/GENPROFILE|/USEPROFILE")
      set(pgo_enabled TRUE)
    elseif(target_compile_opts AND "${target_compile_opts}" MATCHES "-fprofile|/GENPROFILE|/USEPROFILE")
      set(pgo_enabled TRUE)
    endif()
  endif()
  if(NOT pgo_enabled AND CMAKE_CXX_FLAGS_RELEASE MATCHES "-fprofile|/GENPROFILE|/USEPROFILE")
    set(pgo_enabled TRUE)
  endif()
  if(pgo_enabled)
    message(STATUS "  Profile-Guided Optimization (PGO): Enabled")
  else()
    message(STATUS "  Profile-Guided Optimization (PGO): Disabled")
  endif()

  # Проверяем векторизацию
  if(CMAKE_CXX_FLAGS_RELEASE MATCHES "-mavx|-msse|/arch:")
    message(STATUS "  Hardware Vectorization: Enabled")
  else()
    message(STATUS "  Hardware Vectorization: Not explicitly set")
  endif()
  message(STATUS "")

  # ===========================================================================
  # CMake Configuration
  # ===========================================================================
  message(STATUS "CMake Configuration:")
  message(STATUS "  CMake Version: ${CMAKE_VERSION}")
  message(STATUS "  CMake Generator: ${CMAKE_GENERATOR}")
  message(STATUS "  Source Directory: ${CMAKE_SOURCE_DIR}")
  message(STATUS "  Binary Directory: ${CMAKE_BINARY_DIR}")
  message(STATUS "")

  # ===========================================================================
  # Qt Information (if available)
  # ===========================================================================
  if(DEFINED Qt6_DIR OR DEFINED Qt5_DIR)
    message(STATUS "Qt Configuration:")
    if(DEFINED Qt6_DIR)
      message(STATUS "  Qt Version: 6")
      message(STATUS "  Qt6_DIR: ${Qt6_DIR}")
    endif()
    if(DEFINED Qt5_DIR)
      message(STATUS "  Qt Version: 5")
      message(STATUS "  Qt5_DIR: ${Qt5_DIR}")
    endif()
    if(WINDEPLOYQT_FOUND)
      message(STATUS "  windeployqt: ${WINDEPLOYQT_EXECUTABLE}")
    else()
      message(STATUS "  windeployqt: Not found")
    endif()
    message(STATUS "")
  endif()

  message(STATUS "==============================================================================")
  message(STATUS "")
endfunction()
