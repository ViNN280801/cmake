# =============================================================================
# LinkerFlags.cmake
# Universal linker flags configuration and LTO setup for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure linker flags
# and Link-Time Optimization (LTO) for MSVC, GCC, Clang, and Intel ICC.
#
# Functions:
#   configure_linker_flags(<target>
#     [LTO <ON|OFF|THIN>]
#     [USE_DEFAULT_FLAGS <ON|OFF>]
#     [CUSTOM_FLAGS <flags...>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#     [INTEL_FLAGS <flags...>]
#   )
#
# Usage:
#   include(LinkerFlags)
#   configure_linker_flags(MyTarget LTO ON)
#
# =============================================================================

# =============================================================================
# Function: configure_linker_flags
#
# Configures linker flags for a target with universal support for all compilers.
#
# Parameters:
#   <target>          - Target name (required)
#   LTO <mode>        - Link-Time Optimization (ON|OFF|THIN). Default: OFF
#                       THIN is only available for GCC/Clang
#   USE_DEFAULT_FLAGS <on> - Use default linker flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...> - Completely override all default flags with custom ones.
#                        If specified, USE_DEFAULT_FLAGS is ignored.
#                        If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   EXTRA_FLAGS <...> - Extra flags applied to all linkers (added to defaults or custom)
#   MSVC_FLAGS <...>  - MSVC-specific linker flags (added to defaults or custom)
#   GCC_FLAGS <...>   - GCC-specific linker flags (added to defaults or custom)
#   CLANG_FLAGS <...> - Clang-specific linker flags (added to defaults or custom)
#   INTEL_FLAGS <...> - Intel ICC-specific linker flags (added to defaults or custom)
#
# Usage:
#   # Use defaults with custom additions
#   configure_linker_flags(MyApp LTO ON)
#
#   # Use only custom flags (no defaults)
#   configure_linker_flags(MyApp USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS -Wl,--as-needed)
#
#   # Completely override with custom flags
#   configure_linker_flags(MyApp CUSTOM_FLAGS -Wl,--as-needed -Wl,--gc-sections)
# =============================================================================
function(configure_linker_flags target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "LinkerFlags: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs LTO USE_DEFAULT_FLAGS)
  set(multiValueArgs CUSTOM_FLAGS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS INTEL_FLAGS)
  cmake_parse_arguments(LINKER_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED LINKER_CONFIG_USE_DEFAULT_FLAGS)
    set(LINKER_CONFIG_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT LINKER_CONFIG_USE_DEFAULT_FLAGS AND NOT LINKER_CONFIG_CUSTOM_FLAGS)
    message(FATAL_ERROR "LinkerFlags: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(LINKER_CONFIG_CUSTOM_FLAGS)
    target_link_options(${target} PRIVATE ${LINKER_CONFIG_CUSTOM_FLAGS})
    message(STATUS "LinkerFlags: Using custom flags only for '${target}'")
    return()
  endif()

  # Apply extra flags to all linkers (if defaults are enabled)
  if(LINKER_CONFIG_EXTRA_FLAGS)
    target_link_options(${target} PRIVATE ${LINKER_CONFIG_EXTRA_FLAGS})
  endif()

  # Configure linker-specific flags
  if(LINKER_CONFIG_USE_DEFAULT_FLAGS)
    # MSVC linker configuration
    if(MSVC)
      _configure_msvc_linker(${target} "${LINKER_CONFIG_LTO}" "${LINKER_CONFIG_MSVC_FLAGS}")
    # GCC linker configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      _configure_gcc_linker(${target} "${LINKER_CONFIG_LTO}" "${LINKER_CONFIG_GCC_FLAGS}")
    # Clang linker configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      _configure_clang_linker(${target} "${LINKER_CONFIG_LTO}" "${LINKER_CONFIG_CLANG_FLAGS}")
    # Intel ICC linker configuration
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
      _configure_intel_linker(${target} "${LINKER_CONFIG_LTO}" "${LINKER_CONFIG_INTEL_FLAGS}")
    else()
      message(STATUS "LinkerFlags: Unsupported compiler '${CMAKE_CXX_COMPILER_ID}', using default linker flags")
    endif()
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(LINKER_CONFIG_MSVC_FLAGS)
      target_link_options(${target} PRIVATE ${LINKER_CONFIG_MSVC_FLAGS})
    endif()
    if(LINKER_CONFIG_GCC_FLAGS)
      target_link_options(${target} PRIVATE ${LINKER_CONFIG_GCC_FLAGS})
    endif()
    if(LINKER_CONFIG_CLANG_FLAGS)
      target_link_options(${target} PRIVATE ${LINKER_CONFIG_CLANG_FLAGS})
    endif()
    if(LINKER_CONFIG_INTEL_FLAGS)
      target_link_options(${target} PRIVATE ${LINKER_CONFIG_INTEL_FLAGS})
    endif()
    message(STATUS "LinkerFlags: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_msvc_linker
# =============================================================================
function(_configure_msvc_linker target lto_mode extra_flags)
  set(msvc_linker_flags "")

  # LTO configuration (MSVC: /LTCG)
  if(lto_mode STREQUAL "ON")
    list(APPEND msvc_linker_flags
      $<$<CONFIG:Release>:/LTCG>
      $<$<CONFIG:RelWithDebInfo>:/LTCG>
    )
    # Enable LTO in compiler too
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/GL>
      $<$<CONFIG:RelWithDebInfo>:/GL>
    )
    message(STATUS "LinkerFlags: MSVC LTO enabled for '${target}'")
  endif()

  # Common MSVC linker optimizations
  list(APPEND msvc_linker_flags
    $<$<CONFIG:Release>:/OPT:REF>      # Remove unreferenced functions
    $<$<CONFIG:Release>:/OPT:ICF>      # Identical COMDAT folding
    $<$<CONFIG:RelWithDebInfo>:/OPT:REF>
    $<$<CONFIG:RelWithDebInfo>:/OPT:ICF>
    /INCREMENTAL:NO                    # Disable incremental linking
  )

  # Subsystem (default: CONSOLE, can be overridden)
  if(NOT extra_flags MATCHES "/SUBSYSTEM")
    list(APPEND msvc_linker_flags /SUBSYSTEM:CONSOLE)
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND msvc_linker_flags ${extra_flags})
  endif()

  target_link_options(${target} PRIVATE ${msvc_linker_flags})

  message(STATUS "LinkerFlags: MSVC linker flags applied to '${target}'")
endfunction()

# =============================================================================
# Internal function: _configure_gcc_linker
# =============================================================================
function(_configure_gcc_linker target lto_mode extra_flags)
  set(gcc_linker_flags "")

  # LTO configuration
  if(lto_mode STREQUAL "ON")
    list(APPEND gcc_linker_flags -flto)
    # Enable LTO in compiler too
    target_compile_options(${target} PRIVATE -flto)
    message(STATUS "LinkerFlags: GCC LTO enabled for '${target}'")
  elseif(lto_mode STREQUAL "THIN")
    list(APPEND gcc_linker_flags -flto=auto)
    # Enable thin LTO in compiler too
    target_compile_options(${target} PRIVATE -flto=auto)
    message(STATUS "LinkerFlags: GCC Thin LTO enabled for '${target}'")
  endif()

  # Common GCC linker flags
  list(APPEND gcc_linker_flags
    -rdynamic                           # Export dynamic symbols for backtrace
  )

  # Apply flags
  if(extra_flags)
    list(APPEND gcc_linker_flags ${extra_flags})
  endif()

  target_link_options(${target} PRIVATE ${gcc_linker_flags})

  message(STATUS "LinkerFlags: GCC linker flags applied to '${target}'")
endfunction()

# =============================================================================
# Internal function: _configure_clang_linker
# =============================================================================
function(_configure_clang_linker target lto_mode extra_flags)
  set(clang_linker_flags "")

  # LTO configuration
  if(lto_mode STREQUAL "ON")
    list(APPEND clang_linker_flags -flto)
    # Enable LTO in compiler too
    target_compile_options(${target} PRIVATE -flto)
    message(STATUS "LinkerFlags: Clang LTO enabled for '${target}'")
  elseif(lto_mode STREQUAL "THIN")
    list(APPEND clang_linker_flags -flto=thin)
    # Enable thin LTO in compiler too
    target_compile_options(${target} PRIVATE -flto=thin)
    message(STATUS "LinkerFlags: Clang Thin LTO enabled for '${target}'")
  endif()

  # Common Clang linker flags
  list(APPEND clang_linker_flags
    -rdynamic                           # Export dynamic symbols for backtrace
  )

  # Apply flags
  if(extra_flags)
    list(APPEND clang_linker_flags ${extra_flags})
  endif()

  target_link_options(${target} PRIVATE ${clang_linker_flags})

  message(STATUS "LinkerFlags: Clang linker flags applied to '${target}'")
endfunction()

# =============================================================================
# Internal function: _configure_intel_linker
# =============================================================================
function(_configure_intel_linker target lto_mode extra_flags)
  set(intel_linker_flags "")

  # LTO configuration (Intel: -ipo)
  if(lto_mode STREQUAL "ON")
    list(APPEND intel_linker_flags -ipo)
    # Enable IPO in compiler too
    target_compile_options(${target} PRIVATE -ipo)
    message(STATUS "LinkerFlags: Intel IPO enabled for '${target}'")
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND intel_linker_flags ${extra_flags})
  endif()

  target_link_options(${target} PRIVATE ${intel_linker_flags})

  message(STATUS "LinkerFlags: Intel linker flags applied to '${target}'")
endfunction()
