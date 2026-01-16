# =============================================================================
# HardwareOptimization.cmake
# Universal hardware optimization configuration for all C/C++ compilers
# =============================================================================
#
# This module provides universal functions to configure hardware-specific
# optimizations: vectorization (SSE, AVX, AVX2, AVX-512), floating-point,
# CPU architecture (march, mtune), and other hardware optimizations.
#
# Functions:
#   configure_hardware_optimization(<target>
#     [OPTIMIZATIONS <opt1> <opt2> ...]
#     [ARCH <architecture>]
#     [TUNE <cpu>]
#     [VECTORIZATION <SSE|SSE2|SSE3|SSSE3|SSE4.1|SSE4.2|AVX|AVX2|AVX512|AUTO|NONE>]
#     [FLOATING_POINT <FAST|STRICT|PRECISE>]
#     [EXTRA_FLAGS <flags...>]
#     [MSVC_FLAGS <flags...>]
#     [GCC_FLAGS <flags...>]
#     [CLANG_FLAGS <flags...>]
#     [INTEL_FLAGS <flags...>]
#   )
#
# Usage:
#   include(HardwareOptimization)
#   # Apply all supported optimizations automatically
#   configure_hardware_optimization(MyTarget)
#
#   # Apply specific optimizations only
#   configure_hardware_optimization(MyTarget OPTIMIZATIONS AVX2 FAST_MATH TREE_VECTORIZE)
#
#   # Legacy usage (still supported)
#   configure_hardware_optimization(MyTarget ARCH native VECTORIZATION AVX2)
#
# Available optimizations:
#   NATIVE_ARCH      - Use native CPU architecture (march=native, /arch:AVX2)
#   NATIVE_TUNE      - Use native CPU tuning (mtune=native, GCC/Clang only)
#   SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, AVX2, AVX512 - SIMD instruction sets
#   FAST_MATH        - Fast floating-point math (may reduce precision)
#   TREE_VECTORIZE   - Enable tree vectorization
#   VECT_COST_MODEL_UNLIMITED - Unlimited vectorization cost model
#
# =============================================================================

# =============================================================================
# Function: configure_hardware_optimization
#
# Configures hardware-specific optimizations for a target.
#
# Parameters:
#   <target>          - Target name (required)
#   OPTIMIZATIONS <...> - List of specific optimizations to apply.
#                        If not specified, ALL supported optimizations are applied.
#                        Available: NATIVE_ARCH, NATIVE_TUNE, SSE, SSE2, SSE3, SSSE3,
#                        SSE4.1, SSE4.2, AVX, AVX2, AVX512, FAST_MATH, TREE_VECTORIZE,
#                        VECT_COST_MODEL_UNLIMITED
#   ARCH <arch>       - CPU architecture (legacy, overrides NATIVE_ARCH):
#                       native, x86-64, x86, armv7-a, armv8-a, aarch64, etc.
#                       Default: native (auto-detect)
#   TUNE <cpu>        - CPU tuning (legacy, overrides NATIVE_TUNE, GCC/Clang only):
#                       generic, native, core2, nehalem, sandybridge, haswell, skylake, etc.
#                       Default: generic
#   VECTORIZATION <vec> - Vectorization instruction set (legacy):
#                       SSE, SSE2, SSE3, SSSE3, SSE4.1, SSE4.2, AVX, AVX2, AVX512, AUTO, NONE
#                       Default: AUTO (auto-detect best available)
#   FLOATING_POINT <fp> - Floating-point optimization (legacy):
#                       FAST - Fast math (may reduce precision)
#                       STRICT - Strict IEEE compliance
#                       PRECISE - Precise math (no fast optimizations)
#                       Default: STRICT
#   EXTRA_FLAGS <...> - Extra hardware optimization flags
#   MSVC_FLAGS <...>  - MSVC-specific hardware flags
#   GCC_FLAGS <...>   - GCC-specific hardware flags
#   CLANG_FLAGS <...> - Clang-specific hardware flags
#   INTEL_FLAGS <...> - Intel ICC-specific hardware flags
#
# Usage:
#   # Apply all supported optimizations automatically
#   configure_hardware_optimization(MyTarget)
#
#   # Apply specific optimizations
#   configure_hardware_optimization(MyTarget OPTIMIZATIONS AVX2 FAST_MATH)
#
#   # Legacy usage
#   configure_hardware_optimization(MyApp ARCH native VECTORIZATION AVX2)
# =============================================================================
function(configure_hardware_optimization target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "HardwareOptimization: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs ARCH TUNE VECTORIZATION FLOATING_POINT)
  set(multiValueArgs OPTIMIZATIONS EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS INTEL_FLAGS)
  cmake_parse_arguments(HW_OPT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set defaults for legacy parameters
  if(NOT HW_OPT_ARCH)
    set(HW_OPT_ARCH "native")
  endif()

  if(NOT HW_OPT_TUNE)
    set(HW_OPT_TUNE "generic")
  endif()

  if(NOT HW_OPT_VECTORIZATION)
    set(HW_OPT_VECTORIZATION "AUTO")
  endif()

  if(NOT HW_OPT_FLOATING_POINT)
    set(HW_OPT_FLOATING_POINT "STRICT")
  endif()

  # Determine which optimizations to apply
  set(optimizations_to_apply "")

  if(HW_OPT_OPTIMIZATIONS)
    # User specified explicit optimizations
    set(optimizations_to_apply ${HW_OPT_OPTIMIZATIONS})
    message(STATUS "HardwareOptimization: Using user-specified optimizations: ${optimizations_to_apply}")
  else()
    # No optimizations specified - apply ALL possible optimizations
    _get_all_possible_optimizations(optimizations_to_apply)
    message(STATUS "HardwareOptimization: No optimizations specified, applying ALL supported optimizations")
  endif()

  # Filter optimizations by support (check compiler and architecture support)
  set(supported_optimizations "")
  foreach(opt ${optimizations_to_apply})
    if(_is_optimization_supported("${opt}" "${HW_OPT_ARCH}"))
      list(APPEND supported_optimizations ${opt})
    else()
      message(STATUS "HardwareOptimization: Skipping unsupported optimization '${opt}'")
    endif()
  endforeach()

  message(STATUS "HardwareOptimization: Applying optimizations: ${supported_optimizations}")

  # Apply extra flags to all compilers
  if(HW_OPT_EXTRA_FLAGS)
    target_compile_options(${target} PRIVATE ${HW_OPT_EXTRA_FLAGS})
  endif()

  # Configure based on compiler
  if(MSVC)
    _configure_msvc_hardware(${target} "${HW_OPT_ARCH}" "${supported_optimizations}" "${HW_OPT_FLOATING_POINT}" "${HW_OPT_MSVC_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    _configure_gcc_hardware(${target} "${HW_OPT_ARCH}" "${HW_OPT_TUNE}" "${supported_optimizations}" "${HW_OPT_FLOATING_POINT}" "${HW_OPT_GCC_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    _configure_clang_hardware(${target} "${HW_OPT_ARCH}" "${HW_OPT_TUNE}" "${supported_optimizations}" "${HW_OPT_FLOATING_POINT}" "${HW_OPT_CLANG_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
    _configure_intel_hardware(${target} "${HW_OPT_ARCH}" "${supported_optimizations}" "${HW_OPT_FLOATING_POINT}" "${HW_OPT_INTEL_FLAGS}")
  else()
    message(STATUS "HardwareOptimization: Unsupported compiler '${CMAKE_CXX_COMPILER_ID}', using default hardware flags")
  endif()
endfunction()

# =============================================================================
# Internal function: _get_all_possible_optimizations
#
# Returns list of all possible hardware optimizations.
# =============================================================================
function(_get_all_possible_optimizations result_var)
  set(all_opts
    NATIVE_ARCH
    NATIVE_TUNE
    SSE
    SSE2
    SSE3
    SSSE3
    SSE4.1
    SSE4.2
    AVX
    AVX2
    AVX512
    FAST_MATH
    TREE_VECTORIZE
    VECT_COST_MODEL_UNLIMITED
  )
  set(${result_var} ${all_opts} PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _is_optimization_supported
#
# Checks if an optimization is supported by the compiler and architecture.
#
# Parameters:
#   optimization - Optimization name (e.g., AVX2, SSE4.1, FAST_MATH)
#   arch         - Target architecture
#
# Returns: TRUE if supported, FALSE otherwise
# =============================================================================
function(_is_optimization_supported optimization arch result_var)
  set(is_supported FALSE)

  # Check compiler support
  if(MSVC)
    # MSVC supports: SSE, SSE2, AVX, AVX2, AVX512 (on x64), FAST_MATH, TREE_VECTORIZE
    if(optimization STREQUAL "NATIVE_ARCH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "NATIVE_TUNE")
      set(is_supported FALSE)  # MSVC doesn't support mtune
    elseif(optimization MATCHES "^(SSE|SSE2|AVX|AVX2|AVX512)$")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
        set(is_supported TRUE)
      elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|i[3-6]86" AND optimization MATCHES "^(SSE|SSE2)$")
        set(is_supported TRUE)
      endif()
    elseif(optimization STREQUAL "FAST_MATH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "TREE_VECTORIZE")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "VECT_COST_MODEL_UNLIMITED")
      set(is_supported FALSE)  # MSVC doesn't have this flag
    endif()
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    # GCC/Clang support all optimizations
    if(optimization STREQUAL "NATIVE_ARCH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "NATIVE_TUNE")
      set(is_supported TRUE)
    elseif(optimization MATCHES "^(SSE|SSE2|SSE3|SSSE3|SSE4\\.1|SSE4\\.2|AVX|AVX2|AVX512)$")
      # Check architecture support
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64|i[3-6]86|x86")
        set(is_supported TRUE)
      endif()
    elseif(optimization STREQUAL "FAST_MATH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "TREE_VECTORIZE")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "VECT_COST_MODEL_UNLIMITED")
      set(is_supported TRUE)
    endif()
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
    # Intel supports: NATIVE_ARCH, AVX512, AVX2, AVX, SSE4.2, FAST_MATH, TREE_VECTORIZE
    if(optimization STREQUAL "NATIVE_ARCH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "NATIVE_TUNE")
      set(is_supported FALSE)  # Intel uses -xHost instead
    elseif(optimization MATCHES "^(SSE4\\.2|AVX|AVX2|AVX512)$")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64|i[3-6]86|x86")
        set(is_supported TRUE)
      endif()
    elseif(optimization STREQUAL "FAST_MATH")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "TREE_VECTORIZE")
      set(is_supported TRUE)
    elseif(optimization STREQUAL "VECT_COST_MODEL_UNLIMITED")
      set(is_supported FALSE)  # Intel doesn't have this flag
    endif()
  endif()

  set(${result_var} ${is_supported} PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _configure_msvc_hardware
#
# Configures MSVC hardware optimizations based on optimization list.
# =============================================================================
function(_configure_msvc_hardware target arch optimizations floating_point extra_flags)
  set(msvc_flags "")

  # Process optimizations
  foreach(opt ${optimizations})
    if(opt STREQUAL "NATIVE_ARCH")
      # MSVC doesn't have native, use host architecture
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
        list(APPEND msvc_flags /arch:AVX2)
      elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|i[3-6]86")
        list(APPEND msvc_flags /arch:SSE2)
      endif()
    elseif(opt STREQUAL "AVX512")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
        list(APPEND msvc_flags /arch:AVX512)
      endif()
    elseif(opt STREQUAL "AVX2")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
        list(APPEND msvc_flags /arch:AVX2)
      endif()
    elseif(opt STREQUAL "AVX")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
        list(APPEND msvc_flags /arch:AVX)
      endif()
    elseif(opt STREQUAL "SSE2")
      list(APPEND msvc_flags /arch:SSE2)
    elseif(opt STREQUAL "SSE")
      if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86|i[3-6]86")
        list(APPEND msvc_flags /arch:SSE)
      endif()
    elseif(opt STREQUAL "FAST_MATH")
      list(APPEND msvc_flags /fp:fast)
    elseif(opt STREQUAL "TREE_VECTORIZE")
      list(APPEND msvc_flags
        $<$<CONFIG:Release>:/Qvec>
        $<$<CONFIG:RelWithDebInfo>:/Qvec>
      )
    endif()
  endforeach()

  # Legacy floating-point handling (if FAST_MATH not in optimizations)
  if(NOT "FAST_MATH" IN_LIST optimizations)
    if(floating_point STREQUAL "FAST")
      list(APPEND msvc_flags /fp:fast)
    elseif(floating_point STREQUAL "PRECISE")
      list(APPEND msvc_flags /fp:precise)
    endif()
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND msvc_flags ${extra_flags})
  endif()

  if(msvc_flags)
    target_compile_options(${target} PRIVATE ${msvc_flags})
    message(STATUS "HardwareOptimization: MSVC hardware flags applied to '${target}'")
    message(STATUS "HardwareOptimization:   Optimizations: ${optimizations}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_gcc_hardware
#
# Configures GCC hardware optimizations based on optimization list.
# =============================================================================
function(_configure_gcc_hardware target arch tune optimizations floating_point extra_flags)
  set(gcc_flags "")

  # Process optimizations
  foreach(opt ${optimizations})
    if(opt STREQUAL "NATIVE_ARCH")
      list(APPEND gcc_flags -march=native)
    elseif(opt STREQUAL "NATIVE_TUNE")
      list(APPEND gcc_flags -mtune=native)
    elseif(opt STREQUAL "AVX512")
      list(APPEND gcc_flags -mavx512f -mavx512cd -mavx512bw -mavx512dq -mavx512vl)
    elseif(opt STREQUAL "AVX2")
      list(APPEND gcc_flags -mavx2)
    elseif(opt STREQUAL "AVX")
      list(APPEND gcc_flags -mavx)
    elseif(opt STREQUAL "SSE4.2")
      list(APPEND gcc_flags -msse4.2)
    elseif(opt STREQUAL "SSE4.1")
      list(APPEND gcc_flags -msse4.1)
    elseif(opt STREQUAL "SSSE3")
      list(APPEND gcc_flags -mssse3)
    elseif(opt STREQUAL "SSE3")
      list(APPEND gcc_flags -msse3)
    elseif(opt STREQUAL "SSE2")
      list(APPEND gcc_flags -msse2)
    elseif(opt STREQUAL "SSE")
      list(APPEND gcc_flags -msse)
    elseif(opt STREQUAL "FAST_MATH")
      list(APPEND gcc_flags -ffast-math -ffinite-math-only -fno-math-errno)
    elseif(opt STREQUAL "TREE_VECTORIZE")
      list(APPEND gcc_flags -ftree-vectorize)
    elseif(opt STREQUAL "VECT_COST_MODEL_UNLIMITED")
      list(APPEND gcc_flags -fvect-cost-model=unlimited)
    endif()
  endforeach()

  # Legacy architecture handling (if NATIVE_ARCH not in optimizations)
  if(NOT "NATIVE_ARCH" IN_LIST optimizations)
    if(arch STREQUAL "native")
      list(APPEND gcc_flags -march=native)
    else()
      list(APPEND gcc_flags -march=${arch})
    endif()
  endif()

  # Legacy tune handling (if NATIVE_TUNE not in optimizations)
  if(NOT "NATIVE_TUNE" IN_LIST optimizations)
    if(tune STREQUAL "native")
      list(APPEND gcc_flags -mtune=native)
    else()
      list(APPEND gcc_flags -mtune=${tune})
    endif()
  endif()

  # Legacy floating-point handling (if FAST_MATH not in optimizations)
  if(NOT "FAST_MATH" IN_LIST optimizations)
    if(floating_point STREQUAL "FAST")
      list(APPEND gcc_flags -ffast-math -ffinite-math-only -fno-math-errno)
    elseif(floating_point STREQUAL "PRECISE")
      list(APPEND gcc_flags -fno-fast-math -fmath-errno)
    endif()
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND gcc_flags ${extra_flags})
  endif()

  if(gcc_flags)
    target_compile_options(${target} PRIVATE ${gcc_flags})
    message(STATUS "HardwareOptimization: GCC hardware flags applied to '${target}'")
    message(STATUS "HardwareOptimization:   Optimizations: ${optimizations}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_clang_hardware
#
# Configures Clang hardware optimizations based on optimization list.
# =============================================================================
function(_configure_clang_hardware target arch tune optimizations floating_point extra_flags)
  set(clang_flags "")

  # Process optimizations (same as GCC)
  foreach(opt ${optimizations})
    if(opt STREQUAL "NATIVE_ARCH")
      list(APPEND clang_flags -march=native)
    elseif(opt STREQUAL "NATIVE_TUNE")
      list(APPEND clang_flags -mtune=native)
    elseif(opt STREQUAL "AVX512")
      list(APPEND clang_flags -mavx512f -mavx512cd -mavx512bw -mavx512dq -mavx512vl)
    elseif(opt STREQUAL "AVX2")
      list(APPEND clang_flags -mavx2)
    elseif(opt STREQUAL "AVX")
      list(APPEND clang_flags -mavx)
    elseif(opt STREQUAL "SSE4.2")
      list(APPEND clang_flags -msse4.2)
    elseif(opt STREQUAL "SSE4.1")
      list(APPEND clang_flags -msse4.1)
    elseif(opt STREQUAL "SSSE3")
      list(APPEND clang_flags -mssse3)
    elseif(opt STREQUAL "SSE3")
      list(APPEND clang_flags -msse3)
    elseif(opt STREQUAL "SSE2")
      list(APPEND clang_flags -msse2)
    elseif(opt STREQUAL "SSE")
      list(APPEND clang_flags -msse)
    elseif(opt STREQUAL "FAST_MATH")
      list(APPEND clang_flags -ffast-math -ffinite-math-only -fno-math-errno)
    elseif(opt STREQUAL "TREE_VECTORIZE")
      list(APPEND clang_flags -ftree-vectorize)
    elseif(opt STREQUAL "VECT_COST_MODEL_UNLIMITED")
      list(APPEND clang_flags -fvect-cost-model=unlimited)
    endif()
  endforeach()

  # Legacy architecture handling (if NATIVE_ARCH not in optimizations)
  if(NOT "NATIVE_ARCH" IN_LIST optimizations)
    if(arch STREQUAL "native")
      list(APPEND clang_flags -march=native)
    else()
      list(APPEND clang_flags -march=${arch})
    endif()
  endif()

  # Legacy tune handling (if NATIVE_TUNE not in optimizations)
  if(NOT "NATIVE_TUNE" IN_LIST optimizations)
    if(tune STREQUAL "native")
      list(APPEND clang_flags -mtune=native)
    else()
      list(APPEND clang_flags -mtune=${tune})
    endif()
  endif()

  # Legacy floating-point handling (if FAST_MATH not in optimizations)
  if(NOT "FAST_MATH" IN_LIST optimizations)
    if(floating_point STREQUAL "FAST")
      list(APPEND clang_flags -ffast-math -ffinite-math-only -fno-math-errno)
    elseif(floating_point STREQUAL "PRECISE")
      list(APPEND clang_flags -fno-fast-math -fmath-errno)
    endif()
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND clang_flags ${extra_flags})
  endif()

  if(clang_flags)
    target_compile_options(${target} PRIVATE ${clang_flags})
    message(STATUS "HardwareOptimization: Clang hardware flags applied to '${target}'")
    message(STATUS "HardwareOptimization:   Optimizations: ${optimizations}")
  endif()
endfunction()

# =============================================================================
# Internal function: _configure_intel_hardware
#
# Configures Intel ICC hardware optimizations based on optimization list.
# =============================================================================
function(_configure_intel_hardware target arch optimizations floating_point extra_flags)
  set(intel_flags "")

  # Process optimizations
  foreach(opt ${optimizations})
    if(opt STREQUAL "NATIVE_ARCH")
      list(APPEND intel_flags -xHost)
    elseif(opt STREQUAL "AVX512")
      list(APPEND intel_flags -qopt-zmm-usage=high)
    elseif(opt STREQUAL "AVX2")
      list(APPEND intel_flags -xCORE-AVX2)
    elseif(opt STREQUAL "AVX")
      list(APPEND intel_flags -xAVX)
    elseif(opt STREQUAL "SSE4.2")
      list(APPEND intel_flags -xSSE4.2)
    elseif(opt STREQUAL "FAST_MATH")
      list(APPEND intel_flags -fp-model fast=2)
    elseif(opt STREQUAL "TREE_VECTORIZE")
      list(APPEND intel_flags
        -qopt-report=5
        -qopt-report-phase=vec
      )
    endif()
  endforeach()

  # Legacy architecture handling (if NATIVE_ARCH not in optimizations)
  if(NOT "NATIVE_ARCH" IN_LIST optimizations)
    if(arch STREQUAL "native")
      list(APPEND intel_flags -xHost)
    else()
      # Intel uses -x<arch> for architecture
      if(arch STREQUAL "skylake")
        list(APPEND intel_flags -xSKYLAKE-AVX512)
      elseif(arch STREQUAL "haswell")
        list(APPEND intel_flags -xCORE-AVX2)
      elseif(arch STREQUAL "sandybridge")
        list(APPEND intel_flags -xAVX)
      elseif(arch STREQUAL "nehalem")
        list(APPEND intel_flags -xSSE4.2)
      else()
        list(APPEND intel_flags -xHost)  # Fallback to host
      endif()
    endif()
  endif()

  # Legacy floating-point handling (if FAST_MATH not in optimizations)
  if(NOT "FAST_MATH" IN_LIST optimizations)
    if(floating_point STREQUAL "FAST")
      list(APPEND intel_flags -fp-model fast=2)
    elseif(floating_point STREQUAL "PRECISE")
      list(APPEND intel_flags -fp-model precise)
    else()
      list(APPEND intel_flags -fp-model strict)
    endif()
  endif()

  # Apply flags
  if(extra_flags)
    list(APPEND intel_flags ${extra_flags})
  endif()

  if(intel_flags)
    target_compile_options(${target} PRIVATE ${intel_flags})
    message(STATUS "HardwareOptimization: Intel hardware flags applied to '${target}'")
    message(STATUS "HardwareOptimization:   Optimizations: ${optimizations}")
  endif()
endfunction()
