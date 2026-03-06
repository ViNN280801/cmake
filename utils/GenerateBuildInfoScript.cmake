# ==========================================================================
# GenerateBuildInfoScript.cmake
# ==========================================================================
# POST_BUILD script - re-generates the build-info report once the compiled
# binary exists, so that binary size, SHA-256/SHA-512 hashes, and dynamic
# dependency analysis can be included.
#
# Invoked via:
#   cmake -Dtarget_name=<name>
#         -Doutput_file=<path>
#         -Dtarget_properties_file=<path>
#         -DCMAKE_SOURCE_DIR=<source>
#         -DCMAKE_BINARY_DIR=<binary>
#         [-Dpython_executable=<python>]
#         [-Dpython_script=<GenerateBuildInfo.py>]
#         [-Dbuild_info_format=<txt|json|yaml|ini>]
#         [-Dtarget_binary_path=<compiled-binary>]
#         -P GenerateBuildInfoScript.cmake
# ==========================================================================

# --------------------------------------------------------------------------
# Validate mandatory arguments
# --------------------------------------------------------------------------
foreach(_required target_name output_file)
  if(NOT DEFINED ${_required})
    message(FATAL_ERROR
      "GenerateBuildInfoScript: required variable '${_required}' is not set.")
  endif()
endforeach()

# Resolve target properties file path
if(NOT DEFINED target_properties_file)
  if(DEFINED CMAKE_BINARY_DIR)
    set(target_properties_file
      "${CMAKE_BINARY_DIR}/${target_name}-target-properties.cmake")
  else()
    message(FATAL_ERROR
      "GenerateBuildInfoScript: neither 'target_properties_file' "
      "nor 'CMAKE_BINARY_DIR' is defined.")
  endif()
endif()

# Load target properties written during configure phase
if(EXISTS "${target_properties_file}")
  include("${target_properties_file}")
  message(STATUS
    "GenerateBuildInfoScript: loaded properties from ${target_properties_file}")
else()
  message(WARNING
    "GenerateBuildInfoScript: properties file not found: "
    "${target_properties_file} - some info may be incomplete.")
endif()

# --------------------------------------------------------------------------
# Determine output format (default: txt)
# --------------------------------------------------------------------------
if(NOT DEFINED build_info_format OR build_info_format STREQUAL "")
  set(build_info_format "txt")
endif()
string(TOLOWER "${build_info_format}" build_info_format)

# Adjust the output file extension to match the requested format
get_filename_component(_script_out_base "${output_file}" NAME_WE)
get_filename_component(_script_out_dir "${output_file}" DIRECTORY)
set(_effective_output "${_script_out_dir}/${_script_out_base}.${build_info_format}")

# --------------------------------------------------------------------------
# Python-accelerated path (preferred)
# --------------------------------------------------------------------------
set(_used_python FALSE)
set(_generated_output "")

if(DEFINED python_executable AND python_executable AND
  EXISTS "${python_executable}")

  # Locate the Python script relative to this script file
  if(NOT DEFINED python_script OR NOT EXISTS "${python_script}")
    get_filename_component(_script_dir
      "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
    set(python_script "${_script_dir}/GenerateBuildInfo.py")
  endif()

  if(EXISTS "${python_script}")
    # Context JSON path (written during configure; reused here)
    set(_ctx_file "${CMAKE_BINARY_DIR}/${target_name}-build-info-context.json")

    # If the context file was not written by the configure phase
    # (e.g., CMake-native was used), it won't exist - skip Python.
    if(EXISTS "${_ctx_file}")
      set(_py_cmd
        "${python_executable}" "${python_script}"
        "--context" "${_ctx_file}"
        "--output" "${_effective_output}"
        "--format" "${build_info_format}"
        "--source-dir" "${CMAKE_SOURCE_DIR}"
      )
      if(DEFINED target_binary_path AND EXISTS "${target_binary_path}")
        list(APPEND _py_cmd "--target-binary" "${target_binary_path}")
      endif()

      execute_process(
        COMMAND ${_py_cmd}
        RESULT_VARIABLE _py_exit
        OUTPUT_VARIABLE _py_stdout
        ERROR_VARIABLE _py_stderr
        OUTPUT_STRIP_TRAILING_WHITESPACE
      )

      if(_py_exit EQUAL 0)
        if(_py_stdout)
          message(STATUS "${_py_stdout}")
        endif()
        set(_used_python TRUE)
        set(_generated_output "${_effective_output}")
        message(STATUS
          "GenerateBuildInfoScript: Python report written -> "
          "${_effective_output}")
      else()
        message(WARNING
          "GenerateBuildInfoScript: Python script failed "
          "(exit ${_py_exit}) - falling back to CMake-native.\n"
          "${_py_stderr}")
      endif()
    else()
      message(STATUS
        "GenerateBuildInfoScript: context JSON not found (${_ctx_file}) - "
        "falling back to CMake-native implementation.")
    endif()
  else()
    message(WARNING
      "GenerateBuildInfoScript: Python script not found at "
      "'${python_script}' - falling back to CMake-native implementation.")
  endif()
endif()

# --------------------------------------------------------------------------
# CMake-native fallback
# --------------------------------------------------------------------------
if(NOT _used_python)
  # Include the CMake build info module
  get_filename_component(_script_dir
    "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)

  if(EXISTS "${_script_dir}/GenerateBuildInfo.cmake")
    include("${_script_dir}/GenerateBuildInfo.cmake")
  elseif(DEFINED CMAKE_SOURCE_DIR AND
    EXISTS "${CMAKE_SOURCE_DIR}/cmake/utils/GenerateBuildInfo.cmake")
    include("${CMAKE_SOURCE_DIR}/cmake/utils/GenerateBuildInfo.cmake")
  else()
    message(FATAL_ERROR
      "GenerateBuildInfoScript: cannot find GenerateBuildInfo.cmake")
  endif()

  # IMPORTANT:
  # We are running in script mode (-P), where target commands are not scriptable.
  # If generate_build_info_file() takes its Python path, it calls
  # _gbinfo_write_context_json(), which uses get_target_property() and fails.
  # Force CMake-native path here to avoid target API usage in script mode.
  set(GBINFO_PYTHON_EXECUTABLE "")

  # Use the output_file as-is (CMake native always writes .txt)
  generate_build_info_file("${target_name}" "${output_file}")
  set(_generated_output "${output_file}")
  message(STATUS
    "GenerateBuildInfoScript: CMake-native report written -> ${output_file}")
endif()

# --------------------------------------------------------------------------
# Copy generated build-info file next to compiled target binary
# --------------------------------------------------------------------------
if(_generated_output AND EXISTS "${_generated_output}" AND
  DEFINED target_binary_path AND target_binary_path AND EXISTS "${target_binary_path}")
  get_filename_component(_target_dir "${target_binary_path}" DIRECTORY)
  get_filename_component(_report_name "${_generated_output}" NAME)
  set(_report_near_target "${_target_dir}/${_report_name}")

  if(NOT _report_near_target STREQUAL _generated_output)
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${_generated_output}" "${_report_near_target}"
      RESULT_VARIABLE _copy_exit
      OUTPUT_QUIET
      ERROR_VARIABLE _copy_err
    )
    if(_copy_exit EQUAL 0)
      message(STATUS
        "GenerateBuildInfoScript: copied build-info next to target -> "
        "${_report_near_target}")
    else()
      message(WARNING
        "GenerateBuildInfoScript: failed to copy build-info next to target "
        "(exit ${_copy_exit}).\n${_copy_err}")
    endif()
  endif()
endif()
