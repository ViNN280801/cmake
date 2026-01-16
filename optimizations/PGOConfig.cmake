# =============================================================================
# PGOConfig.cmake
# Universal Profile-Guided Optimization (PGO) configuration for all compilers
# =============================================================================
#
# This module provides universal functions to configure Profile-Guided Optimization
# for MSVC, GCC, Clang, and Intel ICC.
#
# Functions:
#   configure_pgo(<target>
#     [MODE <GENERATE|USE|AUTO>]
#     [PROFILE_DIR <directory>]
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
#   include(PGOConfig)
#   # Generate profile:
#   configure_pgo(MyApp MODE GENERATE)
#   # Use profile:
#   configure_pgo(MyApp MODE USE PROFILE_DIR ${CMAKE_BINARY_DIR}/pgo)
#
# =============================================================================

# =============================================================================
# Function: configure_pgo
#
# Configures Profile-Guided Optimization (PGO) for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   MODE <mode>       - PGO mode:
#                       GENERATE - Generate profile data (instrumented build)
#                       USE      - Use existing profile data (optimized build)
#                       AUTO     - Auto-detect: GENERATE if profile missing, USE if exists
#                       Default: AUTO
#   PROFILE_DIR <dir> - Directory for profile data files. Default: ${CMAKE_BINARY_DIR}/pgo
#   USE_DEFAULT_FLAGS <on> - Use default PGO flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...> - Completely override all default PGO flags with custom ones.
#                        If specified, USE_DEFAULT_FLAGS is ignored.
#                        If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   EXTRA_FLAGS <...> - Extra PGO-related flags (added to defaults or custom)
#   MSVC_FLAGS <...>  - MSVC-specific PGO flags (added to defaults or custom)
#   GCC_FLAGS <...>   - GCC-specific PGO flags (added to defaults or custom)
#   CLANG_FLAGS <...> - Clang-specific PGO flags (added to defaults or custom)
#   INTEL_FLAGS <...> - Intel ICC-specific PGO flags (added to defaults or custom)
#
# Usage:
#   # Use defaults
#   configure_pgo(MyApp MODE GENERATE)
#
#   # Use only custom flags
#   configure_pgo(MyApp MODE GENERATE USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS -fprofile-generate=./pgo)
#
#   # Completely override with custom flags
#   configure_pgo(MyApp MODE USE CUSTOM_FLAGS -fprofile-use=./pgo)
# =============================================================================
function(configure_pgo target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "PGOConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs MODE PROFILE_DIR USE_DEFAULT_FLAGS)
  set(multiValueArgs CUSTOM_FLAGS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS INTEL_FLAGS)
  cmake_parse_arguments(PGO_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED PGO_CONFIG_USE_DEFAULT_FLAGS)
    set(PGO_CONFIG_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT PGO_CONFIG_USE_DEFAULT_FLAGS AND NOT PGO_CONFIG_CUSTOM_FLAGS)
    message(FATAL_ERROR "PGOConfig: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # Set default mode
  if(NOT PGO_CONFIG_MODE)
    set(PGO_CONFIG_MODE "AUTO")
  endif()

  # Set default profile directory
  if(NOT PGO_CONFIG_PROFILE_DIR)
    set(PGO_CONFIG_PROFILE_DIR "${CMAKE_BINARY_DIR}/pgo")
  endif()

  # Create profile directory if needed
  file(MAKE_DIRECTORY "${PGO_CONFIG_PROFILE_DIR}")

  # Auto-detect mode
  if(PGO_CONFIG_MODE STREQUAL "AUTO")
    # Check if profile data exists
    if(MSVC)
      # MSVC: .pgc files
      file(GLOB pgo_files "${PGO_CONFIG_PROFILE_DIR}/*.pgc")
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      # GCC/Clang: .gcda files
      file(GLOB pgo_files "${PGO_CONFIG_PROFILE_DIR}/*.gcda")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
      # Intel: .dyn files
      file(GLOB pgo_files "${PGO_CONFIG_PROFILE_DIR}/*.dyn")
    else()
      set(pgo_files "")
    endif()

    if(pgo_files)
      set(PGO_CONFIG_MODE "USE")
      message(STATUS "PGOConfig: Auto-detected USE mode (profile data found)")
    else()
      set(PGO_CONFIG_MODE "GENERATE")
      message(STATUS "PGOConfig: Auto-detected GENERATE mode (no profile data found)")
    endif()
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(PGO_CONFIG_CUSTOM_FLAGS)
    target_compile_options(${target} PRIVATE ${PGO_CONFIG_CUSTOM_FLAGS})
    target_link_options(${target} PRIVATE ${PGO_CONFIG_CUSTOM_FLAGS})
    message(STATUS "PGOConfig: Using custom PGO flags only for '${target}'")
    return()
  endif()

  # Configure based on compiler
  if(PGO_CONFIG_USE_DEFAULT_FLAGS)
    if(MSVC)
      _configure_msvc_pgo(${target} "${PGO_CONFIG_MODE}" "${PGO_CONFIG_PROFILE_DIR}" "${PGO_CONFIG_EXTRA_FLAGS}" "${PGO_CONFIG_MSVC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      _configure_gcc_pgo(${target} "${PGO_CONFIG_MODE}" "${PGO_CONFIG_PROFILE_DIR}" "${PGO_CONFIG_EXTRA_FLAGS}" "${PGO_CONFIG_GCC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      _configure_clang_pgo(${target} "${PGO_CONFIG_MODE}" "${PGO_CONFIG_PROFILE_DIR}" "${PGO_CONFIG_EXTRA_FLAGS}" "${PGO_CONFIG_CLANG_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
      _configure_intel_pgo(${target} "${PGO_CONFIG_MODE}" "${PGO_CONFIG_PROFILE_DIR}" "${PGO_CONFIG_EXTRA_FLAGS}" "${PGO_CONFIG_INTEL_FLAGS}")
    else()
      message(WARNING "PGOConfig: PGO not supported for compiler '${CMAKE_CXX_COMPILER_ID}'")
    endif()
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(PGO_CONFIG_EXTRA_FLAGS)
      target_compile_options(${target} PRIVATE ${PGO_CONFIG_EXTRA_FLAGS})
      target_link_options(${target} PRIVATE ${PGO_CONFIG_EXTRA_FLAGS})
    endif()
    if(PGO_CONFIG_MSVC_FLAGS)
      target_compile_options(${target} PRIVATE ${PGO_CONFIG_MSVC_FLAGS})
      target_link_options(${target} PRIVATE ${PGO_CONFIG_MSVC_FLAGS})
    endif()
    if(PGO_CONFIG_GCC_FLAGS)
      target_compile_options(${target} PRIVATE ${PGO_CONFIG_GCC_FLAGS})
      target_link_options(${target} PRIVATE ${PGO_CONFIG_GCC_FLAGS})
    endif()
    if(PGO_CONFIG_CLANG_FLAGS)
      target_compile_options(${target} PRIVATE ${PGO_CONFIG_CLANG_FLAGS})
      target_link_options(${target} PRIVATE ${PGO_CONFIG_CLANG_FLAGS})
    endif()
    if(PGO_CONFIG_INTEL_FLAGS)
      target_compile_options(${target} PRIVATE ${PGO_CONFIG_INTEL_FLAGS})
      target_link_options(${target} PRIVATE ${PGO_CONFIG_INTEL_FLAGS})
    endif()
    message(STATUS "PGOConfig: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_msvc_pgo
# MSVC PGO: /GENPROFILE (generate) and /USEPROFILE (use)
# =============================================================================
function(_configure_msvc_pgo target mode profile_dir extra_flags compiler_flags)
  if(mode STREQUAL "GENERATE")
    # Generate profile: /GENPROFILE
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/GL>                    # Whole program optimization
      $<$<CONFIG:RelWithDebInfo>:/GL>
    )
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:/LTCG /GENPROFILE:${profile_dir}/%t.pgc>
      $<$<CONFIG:RelWithDebInfo>:/LTCG /GENPROFILE:${profile_dir}/%t.pgc>
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: MSVC profile generation enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
    message(STATUS "PGOConfig:   Run the application to generate profile data (.pgc files)")
  elseif(mode STREQUAL "USE")
    # Use profile: /USEPROFILE
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/GL>
      $<$<CONFIG:RelWithDebInfo>:/GL>
    )
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:/LTCG /USEPROFILE:${profile_dir}/%t.pgc>
      $<$<CONFIG:RelWithDebInfo>:/LTCG /USEPROFILE:${profile_dir}/%t.pgc>
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: MSVC profile usage enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_gcc_pgo
# GCC PGO: -fprofile-generate (generate) and -fprofile-use (use)
# =============================================================================
function(_configure_gcc_pgo target mode profile_dir extra_flags compiler_flags)
  if(mode STREQUAL "GENERATE")
    # Generate profile: -fprofile-generate
    target_compile_options(${target} PRIVATE
      -fprofile-generate=${profile_dir}
      -fprofile-arcs
    )
    target_link_options(${target} PRIVATE
      -fprofile-generate=${profile_dir}
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: GCC profile generation enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
    message(STATUS "PGOConfig:   Run the application to generate profile data (.gcda files)")
  elseif(mode STREQUAL "USE")
    # Use profile: -fprofile-use
    target_compile_options(${target} PRIVATE
      -fprofile-use=${profile_dir}
      -fprofile-correction
    )
    target_link_options(${target} PRIVATE
      -fprofile-use=${profile_dir}
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: GCC profile usage enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_clang_pgo
# Clang PGO: -fprofile-generate (generate) and -fprofile-use (use)
# =============================================================================
function(_configure_clang_pgo target mode profile_dir extra_flags)
  if(mode STREQUAL "GENERATE")
    # Generate profile: -fprofile-generate
    target_compile_options(${target} PRIVATE
      -fprofile-generate=${profile_dir}
      -fprofile-arcs
    )
    target_link_options(${target} PRIVATE
      -fprofile-generate=${profile_dir}
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: Clang profile generation enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
    message(STATUS "PGOConfig:   Run the application to generate profile data (.profraw files)")
  elseif(mode STREQUAL "USE")
    # Use profile: -fprofile-use (requires merged .profdata file)
    # Note: Clang requires llvm-profdata merge step
    set(merged_profile "${profile_dir}/merged.profdata")
    if(EXISTS "${merged_profile}")
      target_compile_options(${target} PRIVATE
        -fprofile-use=${merged_profile}
      )
      target_link_options(${target} PRIVATE
        -fprofile-use=${merged_profile}
      )
      if(extra_flags)
        target_compile_options(${target} PRIVATE ${extra_flags})
        target_link_options(${target} PRIVATE ${extra_flags})
      endif()
      message(STATUS "PGOConfig: Clang profile usage enabled for '${target}'")
      message(STATUS "PGOConfig:   Using merged profile: ${merged_profile}")
    else()
      message(WARNING "PGOConfig: Merged profile not found: ${merged_profile}")
      message(WARNING "PGOConfig:   Run: llvm-profdata merge -output=${merged_profile} ${profile_dir}/*.profraw")
    endif()
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_intel_pgo
# Intel PGO: -prof-gen (generate) and -prof-use (use)
# =============================================================================
function(_configure_intel_pgo target mode profile_dir extra_flags compiler_flags)
  if(mode STREQUAL "GENERATE")
    # Generate profile: -prof-gen
    target_compile_options(${target} PRIVATE
      -prof-gen=dir=${profile_dir}
    )
    target_link_options(${target} PRIVATE
      -prof-gen=dir=${profile_dir}
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: Intel profile generation enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
    message(STATUS "PGOConfig:   Run the application to generate profile data (.dyn files)")
  elseif(mode STREQUAL "USE")
    # Use profile: -prof-use
    target_compile_options(${target} PRIVATE
      -prof-use=${profile_dir}
    )
    target_link_options(${target} PRIVATE
      -prof-use=${profile_dir}
    )
    if(extra_flags)
      target_compile_options(${target} PRIVATE ${extra_flags})
      target_link_options(${target} PRIVATE ${extra_flags})
    endif()
    message(STATUS "PGOConfig: Intel profile usage enabled for '${target}'")
    message(STATUS "PGOConfig:   Profile directory: ${profile_dir}")
  endif()
endfunction()
