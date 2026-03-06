# =============================================================================
# OptimizationLevelConfig.cmake
# Universal per-target optimization level configuration for all C/C++ compilers
# =============================================================================
#
# Provides a single function that selects per-config optimization flags
# (O-level, architecture baseline, LTO, PGO, debug symbols, and dead-code
# elimination linker flags) for a named optimization preset.
#
# This module handles the "how fast" dimension of compilation.
# For warnings and language standards, use core/CompilerFlags.cmake.
# For SIMD instruction-set selection, use optimizations/HardwareOptimization.cmake.
#
# Functions:
#   configure_optimization_level(<target>
#     [LEVEL         <PORTABLE|STANDARD|AGGRESSIVE|MAXIMUM|MINSIZE>]
#     [ENABLE_LTO    <ON|OFF>]
#     [DEBUG_SYMBOLS <ON|OFF>]
#     [ENABLE_PGO    <ON|OFF>]
#     [PGO_MODE      <GENERATE|USE>]
#     [PGO_DIR       <path>]
#     [EXTRA_FLAGS   <flags...>]
#     [MSVC_FLAGS    <flags...>]
#     [GCC_FLAGS     <flags...>]
#     [CLANG_FLAGS   <flags...>]
#     [INTEL_FLAGS   <flags...>]
#   )
#
# Optimization LEVELS (controls flags for the Release build type):
#   STANDARD   - O1 + x86-64 baseline; quick build, minimal opt (doc Level 1)
#   PORTABLE   - O2 + x86-64 + generic; portable Release (doc Level 2, DEFAULT)
#   AGGRESSIVE - O3 + x86-64-v2 + optional LTO; portable speed (doc Level 3)
#   MAXIMUM    - O3 + native + fast-math + LTO; max speed, non-portable (doc Level 4)
#   MINSIZE    - Os + no-unroll; minimum binary size (doc Level 5)
#
# Build type ---> optimization level mapping (fixed, independent of LEVEL parameter):
#   Debug          ---> doc Level 0: O0 + full debug info; all optimizations disabled
#   RelWithDebInfo ---> doc Level 6: Og/-g or /O1; debug-oriented opt, always x86-64 baseline
#   MinSizeRel     ---> doc Level 5: Os; size-optimized (same as MINSIZE)
#   Release        ---> determined by LEVEL parameter (PORTABLE by default ---> Level 2)
#
# LTO behavior:
#   - ENABLE_LTO is silently ignored for PORTABLE level (binary compatibility)
#   - LTO is NOT applied to RelWithDebInfo (Level 6 is debug-oriented)
#   - MSVC: /GL compile + /LTCG link flags
#   - GCC:  -flto=auto -fuse-linker-plugin (fallback to -flto on older toolchains)
#   - Clang: -flto=thin
#   - Intel: -ipo (Interprocedural Optimization)
#
# PGO behavior:
#   - GENERATE mode: instruments the binary to collect profile data
#   - USE mode:      applies collected profile data for optimization
#   - MSVC:  /GL + /LTCG:PGINSTRUMENT or /LTCG:PGOPTIMIZE
#   - GCC/Clang: -fprofile-generate / -fprofile-use
#   - Intel: -prof-gen / -prof-use
#
# Debug symbols:
#   - MSVC:      /Zi compile + /DEBUG link (+ /DEBUG:FULL + /Zo in Release)
#   - GCC/Clang: added on top of per-config -g3 (Debug) / -g (RelWithDebInfo)
#
# References: docs/compiler_optimizations.md (sections 2-7, levels 0-6)
# Minimum CMake: 3.16
# Compilers: MSVC 2019+, GCC 7+, Clang 10+, IntelLLVM, Intel ICC
#
# Usage:
#   include(OptimizationLevelConfig)
#   configure_optimization_level(MyLib
#     LEVEL PORTABLE
#     ENABLE_LTO ON
#     DEBUG_SYMBOLS ON
#   )
# =============================================================================

# =============================================================================
# Function: configure_optimization_level
# =============================================================================
function(_opt_lvl_emit_warning title details mitigation)
  message(WARNING
    "\n"
    "OptimizationLevelConfig [RISK WARNING]: ${title}\n"
    "------------------------------------------------------------\n"
    "Risk details:\n"
    "${details}\n"
    "\n"
    "Recommended mitigation:\n"
    "${mitigation}\n"
    "------------------------------------------------------------\n"
  )
endfunction()

function(_opt_lvl_emit_danger_warnings target level enable_lto enable_pgo pgo_mode debug_symbols)
  if(level STREQUAL "MAXIMUM")
    _opt_lvl_emit_warning(
      "MAXIMUM level selected for target '${target}'"
      [=[
- This mode prioritizes peak benchmark speed over safety, portability, and diagnosability.
- On GCC/Clang it enables aggressive FP assumptions (-ffast-math), which can change numerical results,
  break NaN/Inf-sensitive logic, and violate strict IEEE 754 expectations.
- It may emit instructions tied to the build machine ISA (native/AVX2 class), causing runtime crashes
  (illegal instruction) on older or different CPUs.
- Debuggability is reduced due to stronger optimization and code motion.
]=]
      [=[
- Use MAXIMUM only for controlled environments where CPU model and numeric tolerance are known.
- For production binaries distributed to unknown hardware, prefer PORTABLE or AGGRESSIVE.
- For numerically sensitive domains (finance, metrology, scientific reproducibility), avoid MAXIMUM.
]=]
    )
  elseif(level STREQUAL "AGGRESSIVE")
    _opt_lvl_emit_warning(
      "AGGRESSIVE level selected for target '${target}'"
      [=[
- This mode increases optimization pressure (O3 class), which can enlarge binary size and increase
  compile/link time.
- It may expose latent undefined behavior that did not manifest at lower optimization levels.
- It can complicate post-mortem debugging due to inlining and code reordering.
]=]
      [=[
- Validate AGGRESSIVE with full regression, sanitizer, and long-running stability tests.
- If stability/debuggability is more important than speed, use PORTABLE.
]=]
    )
  endif()

  if(enable_lto)
    _opt_lvl_emit_warning(
      "LTO enabled for target '${target}'"
      [=[
- Link-Time Optimization increases whole-program optimization aggressiveness and can significantly
  increase RAM usage and link duration (sometimes by multiple times on large projects).
- It can make symbol-level debugging and profiling less predictable due to cross-TU inlining.
- It may surface ODR violations and ABI inconsistencies that were previously hidden.
- Incremental build turnaround can become noticeably slower.
]=]
      [=[
- Keep LTO for release/profile builds only; disable it for local fast iteration.
- Ensure CI has enough memory and timeout budget for LTO links.
- Maintain a non-LTO profile for troubleshooting regressions.
]=]
    )
  endif()

  if(enable_pgo)
    _opt_lvl_emit_warning(
      "PGO enabled for target '${target}' (mode=${pgo_mode})"
      [=[
- Profile-Guided Optimization quality depends entirely on profile representativeness.
- If training workload is biased, stale, or incomplete, PGO can make hot real-world paths slower
  while over-optimizing rare paths.
- Profile artifacts become part of the build trust chain; stale profiles can silently degrade output.
- PGO introduces additional process complexity (instrumentation, run training, merge/apply profile).
]=]
      [=[
- Rebuild profiles regularly from realistic production-like workloads.
- Version and invalidate profile data together with major code changes.
- Keep fallback non-PGO release artifacts for A/B comparison.
]=]
    )
  endif()

endfunction()

function(configure_optimization_level target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "OptimizationLevelConfig: Target '${target}' does not exist")
  endif()

  include(CheckCXXCompilerFlag)

  set(options "")
  set(oneValueArgs LEVEL ENABLE_LTO DEBUG_SYMBOLS ENABLE_PGO PGO_MODE PGO_DIR)
  set(multiValueArgs EXTRA_FLAGS MSVC_FLAGS GCC_FLAGS CLANG_FLAGS INTEL_FLAGS)
  cmake_parse_arguments(OPT_LVL "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # ---- Defaults ----
  if(NOT OPT_LVL_LEVEL)
    set(OPT_LVL_LEVEL "PORTABLE")
  endif()
  string(TOUPPER "${OPT_LVL_LEVEL}" _level)

  if(NOT DEFINED OPT_LVL_ENABLE_LTO OR OPT_LVL_ENABLE_LTO STREQUAL "")
    set(OPT_LVL_ENABLE_LTO OFF)
  endif()

  if(NOT DEFINED OPT_LVL_DEBUG_SYMBOLS OR OPT_LVL_DEBUG_SYMBOLS STREQUAL "")
    set(OPT_LVL_DEBUG_SYMBOLS ON)
  endif()

  if(NOT DEFINED OPT_LVL_ENABLE_PGO OR OPT_LVL_ENABLE_PGO STREQUAL "")
    set(OPT_LVL_ENABLE_PGO OFF)
  endif()

  if(NOT OPT_LVL_PGO_MODE)
    set(OPT_LVL_PGO_MODE "GENERATE")
  endif()
  string(TOUPPER "${OPT_LVL_PGO_MODE}" _pgo_mode)

  if(NOT OPT_LVL_PGO_DIR)
    set(OPT_LVL_PGO_DIR "${CMAKE_BINARY_DIR}/pgo_profile")
  endif()

  # LTO is not meaningful for PORTABLE (binary compatibility across x86-64)
  if(_level STREQUAL "PORTABLE" AND OPT_LVL_ENABLE_LTO)
    message(STATUS
      "OptimizationLevelConfig: LTO disabled for PORTABLE level "
      "(binary compatibility). Use STANDARD or higher to enable LTO.")
    set(OPT_LVL_ENABLE_LTO OFF)
  endif()

  message(STATUS
    "OptimizationLevelConfig: target='${target}' level=${_level} "
    "lto=${OPT_LVL_ENABLE_LTO} debugsym=${OPT_LVL_DEBUG_SYMBOLS} "
    "pgo=${OPT_LVL_ENABLE_PGO}")
  _opt_lvl_emit_danger_warnings(
    "${target}"
    "${_level}"
    "${OPT_LVL_ENABLE_LTO}"
    "${OPT_LVL_ENABLE_PGO}"
    "${_pgo_mode}"
    "${OPT_LVL_DEBUG_SYMBOLS}"
  )

  # ---- Dispatch ----
  if(MSVC)
    _opt_lvl_msvc(${target} "${_level}"
      "${OPT_LVL_ENABLE_LTO}" "${OPT_LVL_DEBUG_SYMBOLS}"
      "${OPT_LVL_ENABLE_PGO}" "${_pgo_mode}" "${OPT_LVL_PGO_DIR}"
      "${OPT_LVL_MSVC_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    _opt_lvl_gcc(${target} "${_level}"
      "${OPT_LVL_ENABLE_LTO}" "${OPT_LVL_DEBUG_SYMBOLS}"
      "${OPT_LVL_ENABLE_PGO}" "${_pgo_mode}" "${OPT_LVL_PGO_DIR}"
      "${OPT_LVL_GCC_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    _opt_lvl_clang(${target} "${_level}"
      "${OPT_LVL_ENABLE_LTO}" "${OPT_LVL_DEBUG_SYMBOLS}"
      "${OPT_LVL_ENABLE_PGO}" "${_pgo_mode}" "${OPT_LVL_PGO_DIR}"
      "${OPT_LVL_CLANG_FLAGS}")
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Intel"
    OR CMAKE_CXX_COMPILER_ID STREQUAL "IntelLLVM")
    _opt_lvl_intel(${target} "${_level}"
      "${OPT_LVL_ENABLE_LTO}" "${OPT_LVL_DEBUG_SYMBOLS}"
      "${OPT_LVL_ENABLE_PGO}" "${_pgo_mode}" "${OPT_LVL_PGO_DIR}"
      "${OPT_LVL_INTEL_FLAGS}")
  else()
    message(WARNING
      "OptimizationLevelConfig: Unknown compiler '${CMAKE_CXX_COMPILER_ID}' "
      "for target '${target}'. Applying minimal fallback flags.")
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Debug>:-O0;-g3>
      $<$<CONFIG:Release>:-O2;-DNDEBUG>
      $<$<CONFIG:RelWithDebInfo>:-Og;-g;-DNDEBUG>
      $<$<CONFIG:MinSizeRel>:-Os;-DNDEBUG>
    )
  endif()

  if(OPT_LVL_EXTRA_FLAGS)
    target_compile_options(${target} PRIVATE ${OPT_LVL_EXTRA_FLAGS})
  endif()
endfunction()

# =============================================================================
# Internal: MSVC
# =============================================================================
function(_opt_lvl_msvc target level enable_lto debug_symbols
  enable_pgo pgo_mode pgo_dir extra_flags)

  # Function-level linking required for /OPT:REF dead-code elimination.
  # /Gy is implied by /O2 but set explicitly for clarity and MinSizeRel/MINSIZE (/O1).
  target_compile_options(${target} PRIVATE /Gy)

  # ---- Universal per-config flags (all levels) ----
  target_compile_options(${target} PRIVATE
    # ----------------------------------------------------------------
    # doc Level 0 - Debug
    # /Od:   disable all optimizations (maximum debuggability)
    # /Ob0:  disable inline expansion (every function is its own frame)
    # /RTC1: stack-frame + uninitialized-variable runtime checks
    # /sdl:  Security Development Lifecycle extra checks
    # /GS:   stack cookie buffer-security checks
    # ----------------------------------------------------------------
    $<$<CONFIG:Debug>:/Od>
    $<$<CONFIG:Debug>:/Ob0>
    $<$<CONFIG:Debug>:/RTC1>
    $<$<CONFIG:Debug>:/sdl>
    $<$<CONFIG:Debug>:/GS>
    $<$<CONFIG:Debug>:/DDEBUG>
    $<$<CONFIG:Debug>:/D_DEBUG>

    # ----------------------------------------------------------------
    # doc Level 6 - RelWithDebInfo (debug-oriented optimization)
    # /O1:   minimal optimization: smaller code, preserves debuggability
    #        (doc allows /Od or /O1 - /O1 is more useful for profiling)
    # /DNDEBUG: disable assert() in user code
    # Debug info (/Zi) is added separately by the debug_symbols block.
    # ----------------------------------------------------------------
    $<$<CONFIG:RelWithDebInfo>:/O1>
    $<$<CONFIG:RelWithDebInfo>:/DNDEBUG>

    # ----------------------------------------------------------------
    # doc Level 5 - MinSizeRel
    # /O1: minimize code size and maximize speed simultaneously
    # /Os: prefers small code over speed when trade-off exists
    # /GF: string pooling - remove duplicate string literals
    # ----------------------------------------------------------------
    $<$<CONFIG:MinSizeRel>:/O1>
    $<$<CONFIG:MinSizeRel>:/Os>
    $<$<CONFIG:MinSizeRel>:/Gy>
    $<$<CONFIG:MinSizeRel>:/GF>
    $<$<CONFIG:MinSizeRel>:/DNDEBUG>
  )

  # ---- Level-specific Release flags (Release only) ----
  set(_use_ltcg FALSE)

  if(level STREQUAL "MAXIMUM")
    # doc Level 4 - Maximum performance (non-portable)
    # /O2:      maximize speed (/Og /Oi /Ot /Oy /Ob2 /GF /Gy)
    # /Oi:      generate intrinsic functions
    # /Ot:      favor fast code over small code
    # /Oy:      omit frame pointer (frees a register)
    # /fp:fast: aggressive FP - may violate IEEE 754
    # /arch:AVX2: target Haswell (2013)+ AVX2 ISA (non-portable)
    # /GF:      string pooling
    # /GS-:     disable buffer-security checks for maximum speed
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/O2;/Oi;/Ot;/Oy;/Gy;/GF;/DNDEBUG;/arch:AVX2;/fp:fast;/GS->
    )
    _opt_lvl_emit_warning(
      "MSVC MAXIMUM enables /GS- for target '${target}'"
      [=[
- /GS- disables stack-cookie buffer overrun checks.
- This reduces a key runtime mitigation against stack-based memory corruption.
- Security incident impact can be significantly worse in case of latent memory bugs.
]=]
      [=[
- Use this mode only in trusted, controlled performance-lab scenarios.
- For production and user-facing binaries, keep /GS enabled (use PORTABLE or AGGRESSIVE).
]=]
    )
    if(enable_lto)
      set(_use_ltcg TRUE)
    endif()

  elseif(level STREQUAL "AGGRESSIVE")
    # doc Level 3 - Aggressive Release (portable)
    # /O2 /Ox:  maximize speed; /Ox adds /Ob2 on top of /O2
    # /Oi /Ot /Oy: intrinsics, speed preference, omit frame pointer
    # /arch:SSE2: x64 baseline (universally supported)
    # /GL:      whole-program optimization compile-side (LTO when enabled)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/O2;/Ox;/Oi;/Ot;/Oy;/Gy;/GF;/DNDEBUG;/arch:SSE2>
    )
    if(enable_lto)
      set(_use_ltcg TRUE)
    endif()

  elseif(level STREQUAL "STANDARD")
    # doc Level 1 - Quick Build (minimal optimization)
    # /O1:      minimize size + basic speed opts; fast incremental builds
    # /arch:SSE2: x64 baseline
    # No LTO, no advanced inlining - prioritizes compilation speed
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/O1;/arch:SSE2;/DNDEBUG>
    )
    # STANDARD deliberately has no LTO even if ENABLE_LTO is requested
    # (its purpose is fast builds, not maximum performance)

  elseif(level STREQUAL "MINSIZE")
    # doc Level 5 - Minimal binary size (Release variant)
    # /O1 /Os: size-optimized flags; same as MinSizeRel universal block
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/O1;/Os;/Gy;/GF;/DNDEBUG>
    )

  else()
    # PORTABLE (default) - doc Level 2: Standard Release (portable)
    # /O2: recommended MSVC Release flag - balanced speed/size
    # /Oi /Ot /Oy: intrinsics, speed preference, omit frame pointer
    # /arch:SSE2: x64 SSE2 baseline; safe on any x86-64 machine (since 2003)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/O2;/Oi;/Ot;/Oy;/Gy;/GF;/DNDEBUG;/arch:SSE2>
    )
  endif()

  # LTO: /GL (Whole Program Optimization) at compile + /LTCG at link.
  # /GL is incompatible with /ZI (Edit and Continue) and managed code (/clr).
  # LTO is NOT applied to RelWithDebInfo (Level 6 is debug-oriented).
  if(_use_ltcg)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:/GL>
    )
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:/LTCG>
      $<$<CONFIG:MinSizeRel>:/LTCG>
    )
    message(STATUS "OptimizationLevelConfig: MSVC LTO (/GL + /LTCG) for '${target}'")
  endif()

  # Common MSVC linker optimizations for all non-Debug configs.
  # /OPT:REF removes unreferenced functions; /OPT:ICF folds identical COMDATs.
  # /INCREMENTAL:NO is required when /OPT:REF or /OPT:ICF is active.
  target_link_options(${target} PRIVATE
    $<$<CONFIG:Release>:/OPT:REF>
    $<$<CONFIG:Release>:/OPT:ICF>
    $<$<CONFIG:Release>:/INCREMENTAL:NO>
    $<$<CONFIG:RelWithDebInfo>:/OPT:REF>
    $<$<CONFIG:RelWithDebInfo>:/OPT:ICF>
    $<$<CONFIG:RelWithDebInfo>:/DEBUG>
    $<$<CONFIG:RelWithDebInfo>:/INCREMENTAL:NO>
    $<$<CONFIG:MinSizeRel>:/OPT:REF>
    $<$<CONFIG:MinSizeRel>:/OPT:ICF>
    $<$<CONFIG:MinSizeRel>:/INCREMENTAL:NO>
  )

  # Debug symbols: /Zi produces a separate PDB; /Zo preserves variable info
  # under optimization so that the debugger can display more locals.
  if(debug_symbols)
    target_compile_options(${target} PRIVATE
      /Zi
      $<$<CONFIG:Release>:/Zo>
    )
    target_link_options(${target} PRIVATE
      /DEBUG
      $<$<CONFIG:Release>:/DEBUG:FULL>
    )
    message(STATUS "OptimizationLevelConfig: MSVC debug symbols for '${target}'")
  endif()

  # PGO (Profile-Guided Optimization).
  # GENERATE: link with /LTCG:PGINSTRUMENT to produce .pgd/.pgc files.
  # USE:      link with /LTCG:PGOPTIMIZE to apply collected profile.
  if(enable_pgo)
    target_compile_options(${target} PRIVATE /GL)
    if(pgo_mode STREQUAL "GENERATE")
      target_link_options(${target} PRIVATE /LTCG:PGINSTRUMENT)
    else()
      target_link_options(${target} PRIVATE /LTCG:PGOPTIMIZE)
    endif()
    message(STATUS "OptimizationLevelConfig: MSVC PGO ${pgo_mode} for '${target}'")
  endif()

  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()

  message(STATUS "OptimizationLevelConfig: MSVC level=${level} applied to '${target}'")
endfunction()

# =============================================================================
# Internal helper: detect x86/ARM architecture for GCC/Clang
# Sets _march_default, _mtune_default, _native_arch_flag, _native_tune_flag,
# _use_march in the calling scope.
# =============================================================================
macro(_opt_lvl_detect_arch)
  set(_use_march TRUE)
  set(_march_default "")
  set(_mtune_default "")
  set(_native_arch_flag "")
  set(_native_tune_flag "")

  if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64|i386|i686|x86")
    set(_native_arch_flag "-march=native")
    set(_native_tune_flag "-mtune=native")
    set(_march_default "-march=x86-64")
    set(_mtune_default "-mtune=generic")
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|ARM64|arm64")
    set(_native_arch_flag "-mcpu=native")
    set(_native_tune_flag "")
    set(_use_march FALSE)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm|ARM")
    set(_native_arch_flag "-mcpu=native")
    set(_native_tune_flag "")
    set(_use_march FALSE)
  else()
    set(_use_march FALSE)
  endif()

  if(_native_arch_flag)
    check_cxx_compiler_flag("${_native_arch_flag}" _opt_lvl_supports_native_arch)
  else()
    set(_opt_lvl_supports_native_arch FALSE)
  endif()

  if(_native_tune_flag)
    check_cxx_compiler_flag("${_native_tune_flag}" _opt_lvl_supports_native_tune)
  else()
    set(_opt_lvl_supports_native_tune FALSE)
  endif()

  # x86-64-v2: SSE3/SSSE3/SSE4.1/SSE4.2/POPCNT (~Nehalem 2009+).
  # Requires GCC 11+ / Clang 12+. Falls back to x86-64 baseline on older toolchains.
  set(_opt_lvl_march_v2 "${_march_default}")
  set(_opt_lvl_mtune_v2 "${_mtune_default}")
  if(_use_march)
    check_cxx_compiler_flag("-march=x86-64-v2" _opt_lvl_supports_x86_64_v2)
    if(_opt_lvl_supports_x86_64_v2)
      set(_opt_lvl_march_v2 "-march=x86-64-v2")
    endif()
  endif()
endmacro()

# =============================================================================
# Internal helper: apply dead-code elimination linker flags for GCC/Clang.
# Platform-aware: ld64 on Apple uses -dead_strip; GNU ld/gold/lld use --gc-sections.
# --strip-all removes all symbols from Release/MinSizeRel to reduce binary size.
# =============================================================================
macro(_opt_lvl_apply_dce_linker target)
  if(APPLE)
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:-Wl,-dead_strip>
      $<$<CONFIG:MinSizeRel>:-Wl,-dead_strip>
    )
  else()
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:-Wl,--gc-sections>
      $<$<CONFIG:Release>:-Wl,--strip-all>
      $<$<CONFIG:RelWithDebInfo>:-Wl,--gc-sections>
      $<$<CONFIG:MinSizeRel>:-Wl,--gc-sections>
      $<$<CONFIG:MinSizeRel>:-Wl,--strip-all>
    )
  endif()
endmacro()

# =============================================================================
# Internal: GCC
# =============================================================================
function(_opt_lvl_gcc target level enable_lto debug_symbols
  enable_pgo pgo_mode pgo_dir extra_flags)

  include(CheckCXXCompilerFlag)
  _opt_lvl_detect_arch()

  # ---- Universal per-config flags (applied to all levels) ----
  target_compile_options(${target} PRIVATE
    # ----------------------------------------------------------------
    # doc Level 0 - Debug
    # -O0:                   no optimization - consistent machine-code layout
    # -g3:                   full DWARF info including macro definitions
    # -ggdb:                 GDB-specific DWARF extensions (variable tracking)
    # -fno-omit-frame-pointer: keeps call stack readable in profilers/debuggers
    # -fno-optimize-sibling-calls: disables tail-call opt that confuses backtraces
    # -fno-inline:           each function is its own frame (step-through debugging)
    # -fstack-protector-strong: stack canaries to catch overflows early
    # ----------------------------------------------------------------
    $<$<CONFIG:Debug>:-O0>
    $<$<CONFIG:Debug>:-g3>
    $<$<CONFIG:Debug>:-ggdb>
    $<$<CONFIG:Debug>:-fno-omit-frame-pointer>
    $<$<CONFIG:Debug>:-fno-optimize-sibling-calls>
    $<$<CONFIG:Debug>:-fno-inline>
    $<$<CONFIG:Debug>:-fstack-protector-strong>
    $<$<CONFIG:Debug>:-DDEBUG>
    $<$<CONFIG:Debug>:-D_DEBUG>

    # ----------------------------------------------------------------
    # doc Level 6 - RelWithDebInfo (debug-oriented optimization)
    # -Og: GCC's "optimize for debugging" level - enables optimizations that
    #      do NOT eliminate variables, inline unexpectedly, or reorder code in
    #      ways that confuse a debugger. Strictly weaker than -O1.
    # -g:  standard DWARF debug info (line numbers + types + variables)
    # Architecture is fixed to portable x86-64 baseline regardless of LEVEL,
    # so that debug sessions are reproducible across machines.
    # ----------------------------------------------------------------
    $<$<CONFIG:RelWithDebInfo>:-Og>
    $<$<CONFIG:RelWithDebInfo>:-g>
    $<$<CONFIG:RelWithDebInfo>:-DNDEBUG>

    # ----------------------------------------------------------------
    # doc Level 5 - MinSizeRel
    # -Os:                   O2 minus size-increasing passes
    # -ffunction-sections:   each function in its own ELF section (--gc-sections)
    # -fdata-sections:       same for data - dead data can be stripped
    # -fno-unroll-loops:     loop unrolling increases size; explicitly disable
    # -fno-inline-small-functions: more aggressive than -Os alone
    # ----------------------------------------------------------------
    $<$<CONFIG:MinSizeRel>:-Os>
    $<$<CONFIG:MinSizeRel>:-DNDEBUG>
    $<$<CONFIG:MinSizeRel>:-ffunction-sections>
    $<$<CONFIG:MinSizeRel>:-fdata-sections>
    $<$<CONFIG:MinSizeRel>:-fno-unroll-loops>
    $<$<CONFIG:MinSizeRel>:-fno-inline-small-functions>
  )

  # RelWithDebInfo: architecture is always the portable x86-64 baseline (Level 6).
  # This is independent of the selected LEVEL's architecture choice.
  if(_use_march AND _march_default AND _mtune_default)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:RelWithDebInfo>:${_march_default}>
      $<$<CONFIG:RelWithDebInfo>:${_mtune_default}>
    )
  endif()

  # ---- Level-specific Release flags (Release build type only) ----
  if(level STREQUAL "MAXIMUM")
    # doc Level 4 - Maximum performance (non-portable)
    # -O3:               all O2 passes + loop interchange, unswitching, vectorization
    # -march=native:     target current CPU's exact ISA (SIGILL risk on other machines!)
    # -mtune=native:     schedule instructions for current CPU micro-arch
    # -ffast-math:       aggressive FP: no-math-errno, finite-only, unsafe-math-opts
    # -funroll-loops:    full loop unrolling (NOT in O3 by default; Level 4 specific)
    # -fprefetch-loop-arrays: prefetch hints for loop arrays
    # -falign-functions=32 / -falign-loops=32: L1 cache-line alignment
    # -fomit-frame-pointer: free a register (safe without debugging)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
      $<$<CONFIG:Release>:-ffast-math>
      $<$<CONFIG:Release>:-funroll-loops>
      $<$<CONFIG:Release>:-fprefetch-loop-arrays>
    )
    if(_opt_lvl_supports_native_arch AND _native_arch_flag)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_native_arch_flag}>
      )
    endif()
    if(_opt_lvl_supports_native_tune AND _native_tune_flag)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_native_tune_flag}>
      )
    endif()
    # GCC 7+: function/loop alignment for performance
    if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "7.0")
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-falign-functions=32>
        $<$<CONFIG:Release>:-falign-loops=32>
      )
    endif()
    # Extra maximum-level flags - verified before use
    foreach(_flag -finline-functions -fmodulo-sched -ftracer)
      string(REGEX REPLACE "[-=+]" "_" _flag_var "${_flag}")
      check_cxx_compiler_flag("${_flag}" "_opt_lvl_supports${_flag_var}")
      if("_opt_lvl_supports${_flag_var}")
        target_compile_options(${target} PRIVATE $<$<CONFIG:Release>:${_flag}>)
      endif()
    endforeach()
    # GCC 4.9+: profile-correction tolerance
    if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "4.9")
      check_cxx_compiler_flag("-fprofile-correction" _opt_lvl_supports_profile_correction)
      if(_opt_lvl_supports_profile_correction)
        target_compile_options(${target} PRIVATE
          $<$<CONFIG:Release>:-fprofile-correction>)
      endif()
    endif()

  elseif(level STREQUAL "AGGRESSIVE")
    # doc Level 3 - Aggressive Release (portable)
    # -O3:           all optimization passes including loop distribution, unswitching
    # -march=x86-64-v2: SSE4.2 baseline (Nehalem 2009+) - portable and fast
    # -ffunction-sections / -fdata-sections: dead-code stripping via --gc-sections
    # NOTE: -funroll-loops is NOT included here (that is Level 4 / MAXIMUM only)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
    )
    if(_opt_lvl_march_v2 AND _opt_lvl_mtune_v2)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_opt_lvl_march_v2}>
        $<$<CONFIG:Release>:${_opt_lvl_mtune_v2}>
      )
    endif()

  elseif(level STREQUAL "STANDARD")
    # doc Level 1 - Quick Build (minimal optimization)
    # -O1:           basic optimizations only (dead code, constant folding, CSE)
    # No ffunction-sections/fdata-sections (not needed at O1 - fast build focus)
    # No LTO (build speed focus)
    # -march=x86-64 baseline - conservative ISA
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O1>
      $<$<CONFIG:Release>:-DNDEBUG>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()

  elseif(level STREQUAL "MINSIZE")
    # doc Level 5 - Minimal binary size (Release variant)
    # Same flags as MinSizeRel universal block, but applied to Release config.
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-Os>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
      $<$<CONFIG:Release>:-fno-unroll-loops>
      $<$<CONFIG:Release>:-fno-inline-small-functions>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()

  else()
    # PORTABLE (default) - doc Level 2: Standard Release (portable)
    # -O2:           all standard optimizations: inlining, CSE, vectorization,
    #                devirtualization, scheduling, strict-aliasing
    # -march=x86-64: x64 baseline (SSE2 always available, safe everywhere)
    # -mtune=generic: schedule for a typical modern x86-64 (not tied to one µarch)
    # -ffunction-sections / -fdata-sections: enables linker --gc-sections
    # -fomit-frame-pointer: free a register (safe in Release)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O2>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()
  endif()

  # LTO (disabled for PORTABLE and STANDARD - enforced by caller / design).
  # -flto=auto: parallel LTO using make jobserver (GCC 10+). Falls back to -flto.
  # -fuse-linker-plugin: required for slim LTO objects (GCC default in plugin mode).
  # LTO is NOT applied to RelWithDebInfo (Level 6 debug-oriented build).
  if(enable_lto)
    check_cxx_compiler_flag("-flto=auto" _opt_lvl_gcc_lto_auto)
    if(_opt_lvl_gcc_lto_auto)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-flto=auto>
        $<$<CONFIG:Release>:-fuse-linker-plugin>
      )
      target_link_options(${target} PRIVATE
        $<$<CONFIG:Release>:-flto=auto>
      )
    else()
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-flto>
        $<$<CONFIG:Release>:-fuse-linker-plugin>
      )
      target_link_options(${target} PRIVATE
        $<$<CONFIG:Release>:-flto>
      )
    endif()
    # GCC 7+: function alignment improves LTO inlining at call sites
    if(level STREQUAL "MAXIMUM" OR level STREQUAL "AGGRESSIVE")
      if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "7.0")
        target_compile_options(${target} PRIVATE
          $<$<CONFIG:Release>:-falign-functions=32>
        )
      endif()
    endif()
    message(STATUS "OptimizationLevelConfig: GCC LTO (-flto=auto) for '${target}'")
  endif()

  # Dead-code elimination linker flags (platform-aware)
  _opt_lvl_apply_dce_linker(${target})

  # Extra debug symbols in Release (on top of per-config flags already applied)
  if(debug_symbols)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-g>
    )
    message(STATUS "OptimizationLevelConfig: GCC extra debug symbols for '${target}'")
  endif()

  # PGO (Profile-Guided Optimization)
  # GENERATE: compile + link with instrumentation to collect .gcda profile files.
  # USE: recompile with collected profile for targeted optimizations.
  if(enable_pgo)
    if(pgo_mode STREQUAL "GENERATE")
      target_compile_options(${target} PRIVATE
        -fprofile-generate=${pgo_dir}
        -fprofile-arcs
      )
      target_link_options(${target} PRIVATE
        -fprofile-generate=${pgo_dir}
      )
    else()
      target_compile_options(${target} PRIVATE
        -fprofile-use=${pgo_dir}
        -fprofile-correction
      )
      target_link_options(${target} PRIVATE
        -fprofile-use=${pgo_dir}
      )
    endif()
    message(STATUS "OptimizationLevelConfig: GCC PGO ${pgo_mode} for '${target}'")
  endif()

  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()

  message(STATUS "OptimizationLevelConfig: GCC level=${level} applied to '${target}'")
endfunction()

# =============================================================================
# Internal: Clang (including AppleClang)
# =============================================================================
function(_opt_lvl_clang target level enable_lto debug_symbols
  enable_pgo pgo_mode pgo_dir extra_flags)

  include(CheckCXXCompilerFlag)
  _opt_lvl_detect_arch()

  # libc++ is preferred on Clang for full C++20/23 support on non-GNU systems.
  # On Linux with GCC's libstdc++, this is optional; on macOS/FreeBSD it's the default.
  check_cxx_compiler_flag("-stdlib=libc++" _opt_lvl_clang_libcxx)
  if(_opt_lvl_clang_libcxx)
    target_compile_options(${target} PRIVATE -stdlib=libc++)
    target_link_options(${target} PRIVATE -stdlib=libc++)
    if(CMAKE_CXX_STANDARD GREATER_EQUAL 20)
      target_compile_options(${target} PRIVATE -fexperimental-library)
      message(STATUS "OptimizationLevelConfig: Clang libc++ + experimental for C++${CMAKE_CXX_STANDARD}")
    else()
      message(STATUS "OptimizationLevelConfig: Clang libc++")
    endif()
  endif()

  # ---- Universal per-config flags (applied to all levels) ----
  target_compile_options(${target} PRIVATE
    # ----------------------------------------------------------------
    # doc Level 0 - Debug
    # Identical rationale to GCC. Clang's -fno-optimize-sibling-calls
    # prevents tail-call elimination that hides callers from backtraces.
    # ----------------------------------------------------------------
    $<$<CONFIG:Debug>:-O0>
    $<$<CONFIG:Debug>:-g3>
    $<$<CONFIG:Debug>:-ggdb>
    $<$<CONFIG:Debug>:-fno-omit-frame-pointer>
    $<$<CONFIG:Debug>:-fno-optimize-sibling-calls>
    $<$<CONFIG:Debug>:-fno-inline>
    $<$<CONFIG:Debug>:-fstack-protector-strong>
    $<$<CONFIG:Debug>:-DDEBUG>
    $<$<CONFIG:Debug>:-D_DEBUG>

    # ----------------------------------------------------------------
    # doc Level 6 - RelWithDebInfo (debug-oriented optimization)
    # -Og: Clang supports -Og; maps to -O1 with additional debug-safety
    #      semantics (variables are preserved, fewer transformations).
    # -g:  standard DWARF debug info
    # Architecture is always the portable x86-64 baseline.
    # ----------------------------------------------------------------
    $<$<CONFIG:RelWithDebInfo>:-Og>
    $<$<CONFIG:RelWithDebInfo>:-g>
    $<$<CONFIG:RelWithDebInfo>:-DNDEBUG>

    # ----------------------------------------------------------------
    # doc Level 5 - MinSizeRel
    # -fno-inline-small-functions: extra size reduction beyond -Os.
    # ----------------------------------------------------------------
    $<$<CONFIG:MinSizeRel>:-Os>
    $<$<CONFIG:MinSizeRel>:-DNDEBUG>
    $<$<CONFIG:MinSizeRel>:-ffunction-sections>
    $<$<CONFIG:MinSizeRel>:-fdata-sections>
    $<$<CONFIG:MinSizeRel>:-fno-unroll-loops>
    $<$<CONFIG:MinSizeRel>:-fno-inline-small-functions>
  )

  # RelWithDebInfo: architecture is always the portable x86-64 baseline (Level 6).
  if(_use_march AND _march_default AND _mtune_default)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:RelWithDebInfo>:${_march_default}>
      $<$<CONFIG:RelWithDebInfo>:${_mtune_default}>
    )
  endif()

  # ---- Level-specific Release flags (Release build type only) ----
  if(level STREQUAL "MAXIMUM")
    # doc Level 4 - Maximum performance (non-portable)
    # -fvectorize: Clang's explicit SLP+loop vectorization (enabled by -O2+ but explicit)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
      $<$<CONFIG:Release>:-ffast-math>
      $<$<CONFIG:Release>:-funroll-loops>
      $<$<CONFIG:Release>:-fprefetch-loop-arrays>
    )
    if(_opt_lvl_supports_native_arch AND _native_arch_flag)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_native_arch_flag}>
      )
    endif()
    if(_opt_lvl_supports_native_tune AND _native_tune_flag)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_native_tune_flag}>
      )
    endif()
    check_cxx_compiler_flag("-fvectorize" _opt_lvl_clang_vectorize)
    if(_opt_lvl_clang_vectorize)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-fvectorize>
      )
    endif()

  elseif(level STREQUAL "AGGRESSIVE")
    # doc Level 3 - Aggressive Release (portable)
    # -O3 + x86-64-v2 + -fvectorize.
    # NOTE: -funroll-loops is NOT included (Level 4 / MAXIMUM only per doc).
    check_cxx_compiler_flag("-fvectorize" _opt_lvl_clang_vectorize)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
    )
    if(_opt_lvl_march_v2 AND _opt_lvl_mtune_v2)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_opt_lvl_march_v2}>
        $<$<CONFIG:Release>:${_opt_lvl_mtune_v2}>
      )
    endif()
    if(_opt_lvl_clang_vectorize)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:-fvectorize>
      )
    endif()

  elseif(level STREQUAL "STANDARD")
    # doc Level 1 - Quick Build (minimal optimization)
    # -O1: basic optimizations; fast compilation focus, no LTO, no sections
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O1>
      $<$<CONFIG:Release>:-DNDEBUG>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()

  elseif(level STREQUAL "MINSIZE")
    # doc Level 5 - Minimal binary size (Release variant)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-Os>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
      $<$<CONFIG:Release>:-fno-unroll-loops>
      $<$<CONFIG:Release>:-fno-inline-small-functions>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()

  else()
    # PORTABLE (default) - doc Level 2: Standard Release (portable)
    # Clang's -O2 matches GCC's -O2 semantics closely.
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O2>
      $<$<CONFIG:Release>:-DNDEBUG>
      $<$<CONFIG:Release>:-fomit-frame-pointer>
      $<$<CONFIG:Release>:-ffunction-sections>
      $<$<CONFIG:Release>:-fdata-sections>
    )
    if(_use_march AND _march_default AND _mtune_default)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Release>:${_march_default}>
        $<$<CONFIG:Release>:${_mtune_default}>
      )
    endif()
  endif()

  # LTO: Clang uses -flto=thin (LLVM ThinLTO) - parallel, less memory than full LTO.
  # LTO is NOT applied to RelWithDebInfo (Level 6 debug-oriented build).
  if(enable_lto)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-flto=thin>
    )
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:-flto=thin>
    )
    message(STATUS "OptimizationLevelConfig: Clang LTO (-flto=thin) for '${target}'")
  endif()

  # Dead-code elimination linker flags (platform-aware)
  _opt_lvl_apply_dce_linker(${target})

  # Extra debug symbols in Release
  if(debug_symbols)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-g>
    )
    message(STATUS "OptimizationLevelConfig: Clang extra debug symbols for '${target}'")
  endif()

  # PGO: Clang uses LLVM instrumentation (.profraw files).
  # USE mode requires merging: llvm-profdata merge -output=merged.profdata *.profraw
  if(enable_pgo)
    if(pgo_mode STREQUAL "GENERATE")
      target_compile_options(${target} PRIVATE
        -fprofile-generate=${pgo_dir}
        -fprofile-arcs
      )
      target_link_options(${target} PRIVATE
        -fprofile-generate=${pgo_dir}
      )
    else()
      set(_merged_profile "${pgo_dir}/merged.profdata")
      if(EXISTS "${_merged_profile}")
        target_compile_options(${target} PRIVATE
          -fprofile-use=${_merged_profile}
        )
        target_link_options(${target} PRIVATE
          -fprofile-use=${_merged_profile}
        )
      else()
        target_compile_options(${target} PRIVATE
          -fprofile-use=${pgo_dir}
          -fprofile-correction
        )
        target_link_options(${target} PRIVATE
          -fprofile-use=${pgo_dir}
        )
      endif()
    endif()
    message(STATUS "OptimizationLevelConfig: Clang PGO ${pgo_mode} for '${target}'")
  endif()

  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()

  message(STATUS "OptimizationLevelConfig: Clang level=${level} applied to '${target}'")
endfunction()

# =============================================================================
# Internal: Intel ICC / IntelLLVM (oneAPI DPC++)
# =============================================================================
function(_opt_lvl_intel target level enable_lto debug_symbols
  enable_pgo pgo_mode pgo_dir extra_flags)

  # ---- Universal per-config flags ----
  target_compile_options(${target} PRIVATE
    # ----------------------------------------------------------------
    # doc Level 0 - Debug
    # -g3:       full debug info including macros
    # -traceback: Intel source-location tracing in error messages
    # -check=all: comprehensive runtime bounds/pointer checks
    # ----------------------------------------------------------------
    $<$<CONFIG:Debug>:-O0>
    $<$<CONFIG:Debug>:-g3>
    $<$<CONFIG:Debug>:-traceback>
    $<$<CONFIG:Debug>:-check=all>
    $<$<CONFIG:Debug>:-DDEBUG>
    $<$<CONFIG:Debug>:-D_DEBUG>

    # ----------------------------------------------------------------
    # doc Level 6 - RelWithDebInfo (debug-oriented optimization)
    # -O1: minimal optimization; preserves variable locations for debugging
    # -g1: line numbers only - appropriate when optimizer is active,
    #      gives enough info for profiler attribution without overhead
    # ----------------------------------------------------------------
    $<$<CONFIG:RelWithDebInfo>:-O1>
    $<$<CONFIG:RelWithDebInfo>:-g1>
    $<$<CONFIG:RelWithDebInfo>:-DNDEBUG>

    # ----------------------------------------------------------------
    # doc Level 5 - MinSizeRel
    # Intel -Os uses similar semantics to GCC -Os
    # ----------------------------------------------------------------
    $<$<CONFIG:MinSizeRel>:-Os>
    $<$<CONFIG:MinSizeRel>:-DNDEBUG>
  )

  # ---- Level-specific Release flags (Release build type only) ----
  if(level STREQUAL "MAXIMUM")
    # doc Level 4 - Maximum performance (non-portable)
    # -xHost:           use all ISA features of the compile machine (-march=native analog)
    # -fp-model fast=2: most aggressive FP optimizations (violates IEEE 754)
    # -unroll-aggressive: Intel's aggressive loop unrolling heuristic
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3;-DNDEBUG;-xHost;-fp-model fast=2;-unroll-aggressive>
    )
  elseif(level STREQUAL "AGGRESSIVE")
    # doc Level 3 - Aggressive Release (portable)
    # -xCORE-AVX2: optimize for Intel Core with AVX2 (Haswell 2013+)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O3;-DNDEBUG;-xCORE-AVX2>
    )
  elseif(level STREQUAL "STANDARD")
    # doc Level 1 - Quick Build (minimal optimization)
    # -O1: basic optimizations; fast compilation
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O1;-DNDEBUG>
    )
  elseif(level STREQUAL "MINSIZE")
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-Os;-DNDEBUG>
    )
  else()
    # PORTABLE (default) - doc Level 2: Standard Release
    # -O2: Intel's recommended Release flag; no explicit -x arch (conservative default)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-O2;-DNDEBUG>
    )
  endif()

  # LTO: Intel uses -ipo (Interprocedural Optimization) = whole-program analysis.
  # LTO is NOT applied to RelWithDebInfo (Level 6 is debug-oriented).
  if(enable_lto)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Release>:-ipo>
    )
    target_link_options(${target} PRIVATE
      $<$<CONFIG:Release>:-ipo>
    )
    message(STATUS "OptimizationLevelConfig: Intel IPO (LTO) for '${target}'")
  endif()

  # Debug symbols
  if(debug_symbols)
    target_compile_options(${target} PRIVATE -g)
    message(STATUS "OptimizationLevelConfig: Intel debug symbols for '${target}'")
  endif()

  # PGO: Intel uses -prof-gen (instrument) / -prof-use (optimize).
  # -prof-gen=srcpos: collect source-position profile data (more precise)
  if(enable_pgo)
    if(pgo_mode STREQUAL "GENERATE")
      target_compile_options(${target} PRIVATE -prof-gen=srcpos -prof-dir=${pgo_dir})
      target_link_options(${target} PRIVATE -prof-gen=srcpos)
    else()
      target_compile_options(${target} PRIVATE -prof-use -prof-dir=${pgo_dir})
      target_link_options(${target} PRIVATE -prof-use)
    endif()
    message(STATUS "OptimizationLevelConfig: Intel PGO ${pgo_mode} for '${target}'")
  endif()

  if(extra_flags)
    target_compile_options(${target} PRIVATE ${extra_flags})
  endif()

  message(STATUS "OptimizationLevelConfig: Intel level=${level} applied to '${target}'")
endfunction()
