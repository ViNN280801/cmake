# =============================================================================
# MaximumStandardCompliance.cmake
# ISO-oriented compiler diagnostics (GCC, Clang, AppleClang) - project-agnostic
# =============================================================================
#
# Use this module to apply a strong -W* set to *your* targets. It does not know
# about any specific product; all policy is passed via function arguments.
#
# Typical use with vendored C++ headers (e.g. Asio): set
#   DEPENDENCY_WARNING_MODE RELAX_VENDOR
# so flags that fire inside third-party headers are not enabled. C dependencies
# (e.g. HIDAPI) are usually pulled via SYSTEM includes; this module does not add
# include paths - configure those on the target separately.
#
# Mutually exclusive with another full warning profile on the same target if both
# inject overlapping -W options; the caller decides which module runs.
#
# Function
# --------
#   maximum_standard_compliance_configure(
#     TARGET <target>
#     [CXX_STANDARD <11|14|17|20|23|26>]
#     [ALLOWED_COMPILER_IDS <id> ...]   # default: GNU Clang AppleClang
#     [WERROR ON|OFF]
#     [PEDANTIC_ERRORS ON|OFF]
#     [DEPENDENCY_WARNING_MODE STRICT|RELAX_VENDOR|RELAX_VENDOR_AND_SWITCH]
#     [REQUIRE_TOPLEVEL_SOURCE_MATCH ON|OFF]
#     [TOPLEVEL_SOURCE_DIR <path>]     # required if REQUIRE_TOPLEVEL_SOURCE_MATCH ON
#     [EXTRA_COMPILE_OPTIONS <opt> ...]
#   )
#
# DEPENDENCY_WARNING_MODE
# -------------------------
#   STRICT                  - full diagnostic set (may break under -Werror with vendored C++).
#   RELAX_VENDOR            - omit -Wsuggest-override, -Wuseless-cast, -Wunused-template (Clang).
#   RELAX_VENDOR_AND_SWITCH - also omit -Wswitch-default and -Wswitch-enum (partial switches).
#
# =============================================================================

include_guard(GLOBAL)

include(CheckCXXCompilerFlag)

function(_maximum_standard_compliance_check_cxx_flag flag var)
  check_cxx_compiler_flag("${flag}" ${var})
endfunction()

function(maximum_standard_compliance_configure)
  set(_msc_options "")
  set(_msc_one
    TARGET
    CXX_STANDARD
    WERROR
    PEDANTIC_ERRORS
    DEPENDENCY_WARNING_MODE
    REQUIRE_TOPLEVEL_SOURCE_MATCH
    TOPLEVEL_SOURCE_DIR
  )
  set(_msc_multi ALLOWED_COMPILER_IDS EXTRA_COMPILE_OPTIONS)
  cmake_parse_arguments(_msc "${_msc_options}" "${_msc_one}" "${_msc_multi}" ${ARGN})

  if(DEFINED _msc_UNPARSED_ARGUMENTS AND _msc_UNPARSED_ARGUMENTS)
    message(WARNING "maximum_standard_compliance_configure: unknown keyword arguments: ${_msc_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT _msc_TARGET)
    message(FATAL_ERROR "maximum_standard_compliance_configure: TARGET is required")
  endif()
  if(NOT TARGET "${_msc_TARGET}")
    message(FATAL_ERROR "maximum_standard_compliance_configure: target '${_msc_TARGET}' does not exist")
  endif()

  if(NOT _msc_ALLOWED_COMPILER_IDS)
    set(_msc_ALLOWED_COMPILER_IDS GNU Clang AppleClang)
  endif()

  set(_id_ok FALSE)
  foreach(_id IN LISTS _msc_ALLOWED_COMPILER_IDS)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "${_id}")
      set(_id_ok TRUE)
      break()
    endif()
  endforeach()
  if(NOT _id_ok)
    message(FATAL_ERROR
      "maximum_standard_compliance_configure: compiler '${CMAKE_CXX_COMPILER_ID}' is not in ALLOWED_COMPILER_IDS: "
      "${_msc_ALLOWED_COMPILER_IDS}")
  endif()

  if("${_msc_REQUIRE_TOPLEVEL_SOURCE_MATCH}" STREQUAL "ON")
    if(NOT _msc_TOPLEVEL_SOURCE_DIR)
      message(FATAL_ERROR
        "maximum_standard_compliance_configure: TOPLEVEL_SOURCE_DIR is required when "
        "REQUIRE_TOPLEVEL_SOURCE_MATCH is ON")
    endif()
    get_filename_component(_msc_top "${CMAKE_SOURCE_DIR}" REALPATH)
    get_filename_component(_msc_here "${_msc_TOPLEVEL_SOURCE_DIR}" REALPATH)
    if(NOT _msc_top STREQUAL _msc_here)
      message(FATAL_ERROR
        "maximum_standard_compliance_configure: top-level check failed.\n"
        "  CMAKE_SOURCE_DIR: ${_msc_top}\n"
        "  expected root:      ${_msc_here}")
    endif()
  endif()

  if(_msc_CXX_STANDARD)
    set(_cxx_std "${_msc_CXX_STANDARD}")
  elseif(DEFINED CMAKE_CXX_STANDARD AND NOT "${CMAKE_CXX_STANDARD}" STREQUAL "")
    set(_cxx_std "${CMAKE_CXX_STANDARD}")
  else()
    set(_cxx_std "17")
  endif()

  set_property(TARGET "${_msc_TARGET}" PROPERTY CXX_STANDARD "${_cxx_std}")
  set_property(TARGET "${_msc_TARGET}" PROPERTY CXX_STANDARD_REQUIRED ON)
  set_property(TARGET "${_msc_TARGET}" PROPERTY CXX_EXTENSIONS OFF)

  if(NOT _msc_DEPENDENCY_WARNING_MODE)
    set(_msc_DEPENDENCY_WARNING_MODE STRICT)
  endif()

  set(_any_lang
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Wsign-conversion
    -Wshadow
    -Wformat=2
    -Wundef
    -Wcast-align
    -Wcast-qual
    -Wwrite-strings
    -Wmissing-declarations
    -Wredundant-decls
    -Wdouble-promotion
    -Wfloat-equal
    -Walloca
  )

  if(_msc_DEPENDENCY_WARNING_MODE STREQUAL STRICT)
    list(APPEND _any_lang -Wswitch-default -Wswitch-enum)
  elseif(_msc_DEPENDENCY_WARNING_MODE STREQUAL RELAX_VENDOR)
    list(APPEND _any_lang -Wswitch-default -Wswitch-enum)
  elseif(_msc_DEPENDENCY_WARNING_MODE STREQUAL RELAX_VENDOR_AND_SWITCH)
    # omit switch-default / switch-enum
  else()
    message(FATAL_ERROR
      "maximum_standard_compliance_configure: unknown DEPENDENCY_WARNING_MODE '${_msc_DEPENDENCY_WARNING_MODE}'. "
      "Use STRICT, RELAX_VENDOR, or RELAX_VENDOR_AND_SWITCH.")
  endif()

  set(_cxx_lang
    -Wold-style-cast
    -Woverloaded-virtual
    -Wnon-virtual-dtor
    -Wdelete-non-virtual-dtor
  )

  set(_opts)
  foreach(_f IN LISTS _any_lang)
    list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:${_f}>")
  endforeach()
  foreach(_f IN LISTS _cxx_lang)
    list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:${_f}>")
  endforeach()

  set(_relax_vendor FALSE)
  if(_msc_DEPENDENCY_WARNING_MODE STREQUAL RELAX_VENDOR
     OR _msc_DEPENDENCY_WARNING_MODE STREQUAL RELAX_VENDOR_AND_SWITCH)
    set(_relax_vendor TRUE)
  endif()

  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    _maximum_standard_compliance_check_cxx_flag(-Wlogical-op MAXSTDCOMP_HAVE_WLOGICAL_OP)
    if(MAXSTDCOMP_HAVE_WLOGICAL_OP)
      list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Wlogical-op>")
    endif()
    _maximum_standard_compliance_check_cxx_flag(-Wduplicated-cond MAXSTDCOMP_HAVE_WDUP_COND)
    if(MAXSTDCOMP_HAVE_WDUP_COND)
      list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Wduplicated-cond>")
    endif()
    _maximum_standard_compliance_check_cxx_flag(-Wduplicated-branches MAXSTDCOMP_HAVE_WDUP_BR)
    if(MAXSTDCOMP_HAVE_WDUP_BR)
      list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Wduplicated-branches>")
    endif()
    _maximum_standard_compliance_check_cxx_flag(-Wformat-signedness MAXSTDCOMP_HAVE_WFORMAT_SIGN)
    if(MAXSTDCOMP_HAVE_WFORMAT_SIGN)
      list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Wformat-signedness>")
    endif()
    if(NOT _relax_vendor)
      _maximum_standard_compliance_check_cxx_flag(-Wuseless-cast MAXSTDCOMP_HAVE_WUSELESS_CAST)
      if(MAXSTDCOMP_HAVE_WUSELESS_CAST)
        list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:-Wuseless-cast>")
      endif()
      _maximum_standard_compliance_check_cxx_flag(-Wsuggest-override MAXSTDCOMP_HAVE_WSUGGEST_OVERRIDE)
      if(MAXSTDCOMP_HAVE_WSUGGEST_OVERRIDE)
        list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:-Wsuggest-override>")
      endif()
    endif()
    _maximum_standard_compliance_check_cxx_flag(-Wplacement-new=2 MAXSTDCOMP_HAVE_WPLACEMENT_NEW)
    if(MAXSTDCOMP_HAVE_WPLACEMENT_NEW)
      list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:-Wplacement-new=2>")
    endif()
  elseif(CMAKE_CXX_COMPILER_ID MATCHES "^(Clang|AppleClang)$")
    if(NOT _relax_vendor)
      _maximum_standard_compliance_check_cxx_flag(-Wsuggest-override MAXSTDCOMP_CLANG_WSUGGEST_OVERRIDE)
      if(MAXSTDCOMP_CLANG_WSUGGEST_OVERRIDE)
        list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:-Wsuggest-override>")
      endif()
      _maximum_standard_compliance_check_cxx_flag(-Wunused-template MAXSTDCOMP_CLANG_WUNUSED_TEMPLATE)
      if(MAXSTDCOMP_CLANG_WUNUSED_TEMPLATE)
        list(APPEND _opts "$<$<COMPILE_LANGUAGE:CXX>:-Wunused-template>")
      endif()
    endif()
    _maximum_standard_compliance_check_cxx_flag(-Wimplicit-fallthrough MAXSTDCOMP_CLANG_WFALLTHROUGH)
    if(MAXSTDCOMP_CLANG_WFALLTHROUGH)
      list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Wimplicit-fallthrough>")
    endif()
  endif()

  if("${_msc_PEDANTIC_ERRORS}" STREQUAL "ON")
    list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-pedantic-errors>")
  endif()

  if("${_msc_WERROR}" STREQUAL "ON")
    list(APPEND _opts "$<$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>:-Werror>")
  endif()

  if(_msc_EXTRA_COMPILE_OPTIONS)
    list(APPEND _opts ${_msc_EXTRA_COMPILE_OPTIONS})
  endif()

  target_compile_options("${_msc_TARGET}" PRIVATE ${_opts})

  message(STATUS "MaximumStandardCompliance: target '${_msc_TARGET}' CXX_STANDARD=${_cxx_std} "
    "mode=${_msc_DEPENDENCY_WARNING_MODE} WERROR=${_msc_WERROR} PEDANTIC_ERRORS=${_msc_PEDANTIC_ERRORS}")
endfunction()
