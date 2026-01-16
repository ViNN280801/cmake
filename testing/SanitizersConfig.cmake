# =============================================================================
# SanitizersConfig.cmake
# Universal sanitizers configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure sanitizers
# (AddressSanitizer, MemorySanitizer, ThreadSanitizer, UndefinedBehaviorSanitizer)
# for MSVC, GCC, Clang, and Intel ICC.
#
# Functions:
#   configure_sanitizers(<target>
#     [ADDRESS <ON|OFF>]
#     [MEMORY <ON|OFF>]
#     [THREAD <ON|OFF>]
#     [UNDEFINED <ON|OFF>]
#     [LEAK <ON|OFF>]
#     [USE_DEFAULT_FLAGS <ON|OFF>]
#     [CUSTOM_FLAGS <flags...>]
#     [OPTIONS <options...>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#   )
#
# Usage:
#   include(SanitizersConfig)
#   configure_sanitizers(MyApp ADDRESS ON UNDEFINED ON)
#
# =============================================================================

# =============================================================================
# Function: configure_sanitizers
#
# Configures sanitizers for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   ADDRESS <on>      - Enable AddressSanitizer (ASan). Default: OFF
#   MEMORY <on>       - Enable MemorySanitizer (MSan, Clang-only). Default: OFF
#   THREAD <on>       - Enable ThreadSanitizer (TSan). Default: OFF
#   UNDEFINED <on>    - Enable UndefinedBehaviorSanitizer (UBSan). Default: OFF
#   LEAK <on>         - Enable LeakSanitizer (LSan). Default: OFF
#   USE_DEFAULT_FLAGS <on> - Use default sanitizer flags. Default: ON
#                          If OFF, only user-specified flags are applied.
#                          If CUSTOM_FLAGS is specified, this option is ignored.
#   CUSTOM_FLAGS <...> - Completely override all default sanitizer flags with custom ones.
#                        If specified, USE_DEFAULT_FLAGS is ignored.
#                        If not specified and USE_DEFAULT_FLAGS is OFF, error is raised.
#   OPTIONS <...>     - Sanitizer-specific options (e.g., ASAN_OPTIONS, TSAN_OPTIONS)
#   EXTRA_FLAGS <...> - Extra sanitizer flags (added to defaults or custom)
#   MSVC_FLAGS <...>  - MSVC-specific sanitizer flags (added to defaults or custom)
#   GCC_FLAGS <...>   - GCC-specific sanitizer flags (added to defaults or custom)
#   CLANG_FLAGS <...> - Clang-specific sanitizer flags (added to defaults or custom)
#
# Usage:
#   # Use defaults
#   configure_sanitizers(MyApp ADDRESS ON UNDEFINED ON)
#
#   # Use only custom flags
#   configure_sanitizers(MyApp USE_DEFAULT_FLAGS OFF CUSTOM_FLAGS -fsanitize=address)
#
#   # Completely override with custom flags
#   configure_sanitizers(MyApp CUSTOM_FLAGS -fsanitize=address -fsanitize=undefined)
# =============================================================================
function(configure_sanitizers target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "SanitizersConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs ADDRESS MEMORY THREAD UNDEFINED LEAK USE_DEFAULT_FLAGS)
  set(multiValueArgs CUSTOM_FLAGS OPTIONS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS)
  cmake_parse_arguments(SANITIZER "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default for USE_DEFAULT_FLAGS
  if(NOT DEFINED SANITIZER_USE_DEFAULT_FLAGS)
    set(SANITIZER_USE_DEFAULT_FLAGS ON)
  endif()

  # Validate: if USE_DEFAULT_FLAGS is OFF and CUSTOM_FLAGS is not specified, raise error
  if(NOT SANITIZER_USE_DEFAULT_FLAGS AND NOT SANITIZER_CUSTOM_FLAGS)
    message(FATAL_ERROR "SanitizersConfig: USE_DEFAULT_FLAGS is OFF but CUSTOM_FLAGS is not specified. "
      "Either set USE_DEFAULT_FLAGS ON or provide CUSTOM_FLAGS.")
  endif()

  # If CUSTOM_FLAGS specified, use only them (ignore defaults)
  if(SANITIZER_CUSTOM_FLAGS)
    target_compile_options(${target} PRIVATE ${SANITIZER_CUSTOM_FLAGS})
    target_link_options(${target} PRIVATE ${SANITIZER_CUSTOM_FLAGS})
    message(STATUS "SanitizersConfig: Using custom sanitizer flags only for '${target}'")
    return()
  endif()

  # Set defaults
  if(NOT DEFINED SANITIZER_ADDRESS)
    set(SANITIZER_ADDRESS OFF)
  endif()
  if(NOT DEFINED SANITIZER_MEMORY)
    set(SANITIZER_MEMORY OFF)
  endif()
  if(NOT DEFINED SANITIZER_THREAD)
    set(SANITIZER_THREAD OFF)
  endif()
  if(NOT DEFINED SANITIZER_UNDEFINED)
    set(SANITIZER_UNDEFINED OFF)
  endif()
  if(NOT DEFINED SANITIZER_LEAK)
    set(SANITIZER_LEAK OFF)
  endif()

  # Configure based on compiler
  if(SANITIZER_USE_DEFAULT_FLAGS)
    if(MSVC)
      _configure_msvc_sanitizers(${target} "${SANITIZER_ADDRESS}" "${SANITIZER_UNDEFINED}" "${SANITIZER_OPTIONS}" "${SANITIZER_EXTRA_FLAGS}" "${SANITIZER_MSVC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
      _configure_gcc_sanitizers(${target} "${SANITIZER_ADDRESS}" "${SANITIZER_THREAD}" "${SANITIZER_UNDEFINED}" "${SANITIZER_LEAK}" "${SANITIZER_OPTIONS}" "${SANITIZER_EXTRA_FLAGS}" "${SANITIZER_GCC_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
      _configure_clang_sanitizers(${target} "${SANITIZER_ADDRESS}" "${SANITIZER_MEMORY}" "${SANITIZER_THREAD}" "${SANITIZER_UNDEFINED}" "${SANITIZER_LEAK}" "${SANITIZER_OPTIONS}" "${SANITIZER_EXTRA_FLAGS}" "${SANITIZER_CLANG_FLAGS}")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
      message(WARNING "SanitizersConfig: Intel ICC has limited sanitizer support")
    else()
      message(WARNING "SanitizersConfig: Sanitizers not supported for compiler '${CMAKE_CXX_COMPILER_ID}'")
    endif()
  else()
    # Only user-specified flags (already validated that CUSTOM_FLAGS or compiler-specific flags exist)
    if(SANITIZER_EXTRA_FLAGS)
      target_compile_options(${target} PRIVATE ${SANITIZER_EXTRA_FLAGS})
      target_link_options(${target} PRIVATE ${SANITIZER_EXTRA_FLAGS})
    endif()
    if(SANITIZER_MSVC_FLAGS)
      target_compile_options(${target} PRIVATE ${SANITIZER_MSVC_FLAGS})
      target_link_options(${target} PRIVATE ${SANITIZER_MSVC_FLAGS})
    endif()
    if(SANITIZER_GCC_FLAGS)
      target_compile_options(${target} PRIVATE ${SANITIZER_GCC_FLAGS})
      target_link_options(${target} PRIVATE ${SANITIZER_GCC_FLAGS})
    endif()
    if(SANITIZER_CLANG_FLAGS)
      target_compile_options(${target} PRIVATE ${SANITIZER_CLANG_FLAGS})
      target_link_options(${target} PRIVATE ${SANITIZER_CLANG_FLAGS})
    endif()
    message(STATUS "SanitizersConfig: Using user-specified flags only (no defaults) for '${target}'")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_msvc_sanitizers
# MSVC: /fsanitize=address (VS 2019 16.9+)
# =============================================================================
function(_configure_msvc_sanitizers target address undefined options)
  set(msvc_flags "")

  # AddressSanitizer
  if(address)
    # Check MSVC version (requires VS 2019 16.9+)
    if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.29")
      list(APPEND msvc_flags /fsanitize=address)
      message(STATUS "SanitizersConfig: MSVC AddressSanitizer enabled for '${target}'")
    else()
      message(WARNING "SanitizersConfig: MSVC AddressSanitizer requires Visual Studio 2019 16.9+ (current: ${CMAKE_CXX_COMPILER_VERSION})")
    endif()
  endif()

  # UndefinedBehaviorSanitizer (limited support in MSVC)
  if(undefined)
    message(WARNING "SanitizersConfig: MSVC has limited UBSan support. Consider using /analyze for static analysis")
  endif()

  # Apply flags
  if(msvc_flags)
    target_compile_options(${target} PRIVATE ${msvc_flags})
    target_link_options(${target} PRIVATE ${msvc_flags})
  endif()
  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_gcc_sanitizers
# GCC: -fsanitize=address, -fsanitize=thread, -fsanitize=undefined, -fsanitize=leak
# =============================================================================
function(_configure_gcc_sanitizers target address thread undefined leak options)
  set(gcc_flags "")

  # Build sanitizer list
  set(sanitizers "")

  if(address)
    list(APPEND sanitizers "address")
  endif()

  if(thread)
    if(address)
      message(WARNING "SanitizersConfig: AddressSanitizer and ThreadSanitizer cannot be used together")
    else()
      list(APPEND sanitizers "thread")
    endif()
  endif()

  if(undefined)
    list(APPEND sanitizers "undefined")
  endif()

  if(leak)
    if(address)
      message(STATUS "SanitizersConfig: LeakSanitizer is included in AddressSanitizer")
    else()
      list(APPEND sanitizers "leak")
    endif()
  endif()

  # Apply sanitizer flags
  if(sanitizers)
    string(REPLACE ";" "," sanitizer_list "${sanitizers}")
    list(APPEND gcc_flags -fsanitize=${sanitizer_list})
    list(APPEND gcc_flags -fno-omit-frame-pointer)  # Required for proper stack traces
    list(APPEND gcc_flags -g)  # Debug symbols required

    target_compile_options(${target} PRIVATE ${gcc_flags})
    target_link_options(${target} PRIVATE ${gcc_flags})
    message(STATUS "SanitizersConfig: GCC sanitizers enabled for '${target}': ${sanitizer_list}")
  endif()
  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_clang_sanitizers
# Clang: -fsanitize=address, -fsanitize=memory, -fsanitize=thread, -fsanitize=undefined, -fsanitize=leak
# =============================================================================
function(_configure_clang_sanitizers target address memory thread undefined leak options)
  set(clang_flags "")

  # Build sanitizer list
  set(sanitizers "")

  if(address)
    list(APPEND sanitizers "address")
  endif()

  if(memory)
    if(address OR thread)
      message(WARNING "SanitizersConfig: MemorySanitizer cannot be used with AddressSanitizer or ThreadSanitizer")
    else()
      list(APPEND sanitizers "memory")
    endif()
  endif()

  if(thread)
    if(address)
      message(WARNING "SanitizersConfig: AddressSanitizer and ThreadSanitizer cannot be used together")
    else()
      list(APPEND sanitizers "thread")
    endif()
  endif()

  if(undefined)
    list(APPEND sanitizers "undefined")
  endif()

  if(leak)
    if(address)
      message(STATUS "SanitizersConfig: LeakSanitizer is included in AddressSanitizer")
    else()
      list(APPEND sanitizers "leak")
    endif()
  endif()

  # Apply sanitizer flags
  if(sanitizers)
    string(REPLACE ";" "," sanitizer_list "${sanitizers}")
    list(APPEND clang_flags -fsanitize=${sanitizer_list})
    list(APPEND clang_flags -fno-omit-frame-pointer)  # Required for proper stack traces
    list(APPEND clang_flags -g)  # Debug symbols required

    # MemorySanitizer requires special flags
    if(memory)
      list(APPEND clang_flags -fno-optimize-sibling-calls)
      list(APPEND clang_flags -fno-omit-frame-pointer)
    endif()

    target_compile_options(${target} PRIVATE ${clang_flags})
    target_link_options(${target} PRIVATE ${clang_flags})
    message(STATUS "SanitizersConfig: Clang sanitizers enabled for '${target}': ${sanitizer_list}")
  endif()
  # Apply extra flags
  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
    target_link_options(${target} PRIVATE ${extra_flags})
  endif()
  # Apply compiler-specific flags
  if(compiler_flags)
    target_compile_options(${target} PRIVATE ${compiler_flags})
    target_link_options(${target} PRIVATE ${compiler_flags})
  endif()
endfunction()
