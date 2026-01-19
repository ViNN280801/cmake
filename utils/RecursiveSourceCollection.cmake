# =============================================================================
# RecursiveSourceCollection.cmake
# Universal recursive source file collection for C/C++ projects
# =============================================================================
#
# This module provides universal functions to recursively collect source files
# from directories with configurable filtering options.
#
# Functions:
#   collect_sources_recursive(<dir> <result_var>
#     [EXCLUDE_DIRS <dir1> <dir2> ...]
#     [EXCLUDE_PATTERNS <pattern1> <pattern2> ...]
#     [INCLUDE_EXAMPLES <ON|OFF>]
#     [INCLUDE_TESTS <ON|OFF>]
#     [EXTENSIONS <ext1> <ext2> ...]
#   )
#
# Usage:
#   include(RecursiveSourceCollection)
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES
#     EXCLUDE_DIRS "3rdparty" "tests"
#     INCLUDE_EXAMPLES OFF
#   )
#
# =============================================================================

# =============================================================================
# Function: collect_sources_recursive
#
# Recursively collects source files from a directory with configurable filtering.
#
# Parameters:
#   <dir>                    - Directory to search (required)
#   <result_var>             - Variable name to store collected files (required)
#   EXCLUDE_DIRS <dirs...>   - List of directory names to exclude from search.
#                              Files in these directories will be skipped.
#                              Default: "3rdparty", "tests", "test"
#   EXCLUDE_PATTERNS <pat...> - List of path patterns to exclude (substring matching).
#                              Default: none
#   INCLUDE_EXAMPLES <on>    - Include files from "examples" directories.
#                              Default: OFF
#   INCLUDE_TESTS <on>       - Include files from "tests" or "test" directories.
#                              Default: OFF
#   EXTENSIONS <exts...>     - List of file extensions to collect (without dot).
#                              Default: "cpp", "hpp", "c", "h", "cxx", "hxx", "cc", "hh"
#
# Output variables:
#   <result_var>             - List of collected source files
#   <result_var>_HEADERS    - List of collected header files (if applicable)
#
# Usage:
#   # Basic usage with defaults
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES)
#
#   # Custom exclude directories
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES
#     EXCLUDE_DIRS "3rdparty" "external" "vendor"
#   )
#
#   # Include examples
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES
#     INCLUDE_EXAMPLES ON
#   )
#
#   # Custom extensions (only .cpp and .hpp)
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES
#     EXTENSIONS "cpp" "hpp"
#   )
#
#   # Custom exclude patterns
#   collect_sources_recursive("${CMAKE_SOURCE_DIR}/src" SOURCES
#     EXCLUDE_PATTERNS "/build/" "/generated/"
#   )
# =============================================================================
function(collect_sources_recursive dir result_var)
    # Parse arguments
    set(options "")
    set(oneValueArgs INCLUDE_EXAMPLES INCLUDE_TESTS)
    set(multiValueArgs EXCLUDE_DIRS EXCLUDE_PATTERNS EXTENSIONS)
    cmake_parse_arguments(COLLECT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Validate required parameters
    if(NOT dir)
        message(FATAL_ERROR "RecursiveSourceCollection: Directory path is required")
    endif()

    if(NOT result_var)
        message(FATAL_ERROR "RecursiveSourceCollection: Result variable name is required")
    endif()

    # Set default exclude directories
    if(NOT COLLECT_EXCLUDE_DIRS)
        set(COLLECT_EXCLUDE_DIRS "3rdparty" "tests" "test")
    endif()

    # Set default extensions
    if(NOT COLLECT_EXTENSIONS)
        set(COLLECT_EXTENSIONS "cpp" "hpp" "c" "h" "cxx" "hxx" "cc" "hh")
    endif()

    # Set default for INCLUDE_EXAMPLES
    if(NOT DEFINED COLLECT_INCLUDE_EXAMPLES)
        set(COLLECT_INCLUDE_EXAMPLES OFF)
    endif()

    # Set default for INCLUDE_TESTS
    if(NOT DEFINED COLLECT_INCLUDE_TESTS)
        set(COLLECT_INCLUDE_TESTS OFF)
    endif()

    # Build glob patterns for all extensions
    set(glob_patterns "")
    foreach(ext ${COLLECT_EXTENSIONS})
        list(APPEND glob_patterns "${dir}/*.${ext}")
    endforeach()

    # Find all files matching extensions recursively
    set(all_files "")
    foreach(pattern ${glob_patterns})
        file(GLOB_RECURSE pattern_files "${pattern}")
        list(APPEND all_files ${pattern_files})
    endforeach()

    # Remove duplicates
    if(all_files)
        list(REMOVE_DUPLICATES all_files)
    endif()

    # Filter files
    set(filtered_files "")
    set(filtered_headers "")

    foreach(file ${all_files})
        set(should_exclude OFF)
        set(is_header OFF)
        set(is_example OFF)
        set(is_test OFF)

        # Check if file is a header (for separate header list)
        get_filename_component(file_ext "${file}" EXT)
        if(file_ext MATCHES "^\\.(h|hpp|hxx|hh)$")
            set(is_header ON)
        endif()

        # Check exclude directories
        foreach(exclude_dir ${COLLECT_EXCLUDE_DIRS})
            string(FIND "${file}" "/${exclude_dir}/" dir_pos)
            if(NOT dir_pos EQUAL -1)
                set(should_exclude ON)
                break()
            endif()
        endforeach()

        # Check exclude patterns
        if(NOT should_exclude)
            foreach(pattern ${COLLECT_EXCLUDE_PATTERNS})
                string(FIND "${file}" "${pattern}" pattern_pos)
                if(NOT pattern_pos EQUAL -1)
                    set(should_exclude ON)
                    break()
                endif()
            endforeach()
        endif()

        # Check if file is in examples directory
        if(NOT should_exclude)
            string(FIND "${file}" "/examples/" examples_pos)
            if(NOT examples_pos EQUAL -1)
                set(is_example ON)
                if(NOT COLLECT_INCLUDE_EXAMPLES)
                    set(should_exclude ON)
                endif()
            endif()
        endif()

        # Check if file is in tests/test directory
        if(NOT should_exclude)
            string(FIND "${file}" "/tests/" tests_pos)
            string(FIND "${file}" "/test/" test_pos)
            if(NOT tests_pos EQUAL -1 OR NOT test_pos EQUAL -1)
                set(is_test ON)
                if(NOT COLLECT_INCLUDE_TESTS)
                    set(should_exclude ON)
                endif()
            endif()
        endif()

        # Add file if not excluded
        if(NOT should_exclude)
            list(APPEND filtered_files "${file}")
            if(is_header)
                list(APPEND filtered_headers "${file}")
            endif()
        endif()
    endforeach()

    # Sort files for consistent ordering
    if(filtered_files)
        list(SORT filtered_files)
    endif()

    if(filtered_headers)
        list(SORT filtered_headers)
    endif()

    # Export to parent scope
    set(${result_var} "${filtered_files}" PARENT_SCOPE)
    set(${result_var}_HEADERS "${filtered_headers}" PARENT_SCOPE)

    # Log collection results
    list(LENGTH filtered_files file_count)
    list(LENGTH filtered_headers header_count)
    message(STATUS "RecursiveSourceCollection: Collected ${file_count} files (${header_count} headers) from '${dir}'")
endfunction()

# =============================================================================
# Function: collect_sources_recursive_multiple
#
# Collects source files from multiple directories and combines them.
#
# Parameters:
#   <result_var>             - Variable name to store collected files (required)
#   DIRS <dir1> <dir2> ...   - List of directories to search (required)
#   [All options from collect_sources_recursive]
#
# Output variables:
#   <result_var>             - Combined list of collected source files
#   <result_var>_HEADERS    - Combined list of collected header files
#
# Usage:
#   collect_sources_recursive_multiple(ALL_SOURCES
#     DIRS "${CMAKE_SOURCE_DIR}/src/api" "${CMAKE_SOURCE_DIR}/src/core"
#     EXCLUDE_DIRS "3rdparty" "tests"
#   )
# =============================================================================
function(collect_sources_recursive_multiple result_var)
    # Parse arguments
    set(options "")
    set(oneValueArgs INCLUDE_EXAMPLES INCLUDE_TESTS)
    set(multiValueArgs DIRS EXCLUDE_DIRS EXCLUDE_PATTERNS EXTENSIONS)
    cmake_parse_arguments(COLLECT "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Validate required parameters
    if(NOT result_var)
        message(FATAL_ERROR "RecursiveSourceCollection: Result variable name is required")
    endif()

    if(NOT COLLECT_DIRS)
        message(FATAL_ERROR "RecursiveSourceCollection: DIRS parameter is required")
    endif()

    # Collect from each directory
    set(all_files "")
    set(all_headers "")

    foreach(dir ${COLLECT_DIRS})
        # Build arguments for collect_sources_recursive
        set(collect_args "")
        if(COLLECT_EXCLUDE_DIRS)
            list(APPEND collect_args "EXCLUDE_DIRS" ${COLLECT_EXCLUDE_DIRS})
        endif()
        if(COLLECT_EXCLUDE_PATTERNS)
            list(APPEND collect_args "EXCLUDE_PATTERNS" ${COLLECT_EXCLUDE_PATTERNS})
        endif()
        if(DEFINED COLLECT_INCLUDE_EXAMPLES)
            list(APPEND collect_args "INCLUDE_EXAMPLES" ${COLLECT_INCLUDE_EXAMPLES})
        endif()
        if(DEFINED COLLECT_INCLUDE_TESTS)
            list(APPEND collect_args "INCLUDE_TESTS" ${COLLECT_INCLUDE_TESTS})
        endif()
        if(COLLECT_EXTENSIONS)
            list(APPEND collect_args "EXTENSIONS" ${COLLECT_EXTENSIONS})
        endif()

        # Collect from this directory
        collect_sources_recursive("${dir}" TEMP_COLLECT ${collect_args})

        # Combine results
        list(APPEND all_files ${TEMP_COLLECT})
        list(APPEND all_headers ${TEMP_COLLECT_HEADERS})
    endforeach()

    # Remove duplicates
    if(all_files)
        list(REMOVE_DUPLICATES all_files)
        list(SORT all_files)
    endif()

    if(all_headers)
        list(REMOVE_DUPLICATES all_headers)
        list(SORT all_headers)
    endif()

    # Export to parent scope
    set(${result_var} "${all_files}" PARENT_SCOPE)
    set(${result_var}_HEADERS "${all_headers}" PARENT_SCOPE)

    # Log total results
    list(LENGTH all_files total_count)
    list(LENGTH all_headers header_count)
    message(STATUS "RecursiveSourceCollection: Total collected ${total_count} files (${header_count} headers) from ${COLLECT_DIRS}")
endfunction()
