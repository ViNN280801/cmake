# Script to generate build info file
# This script is called as POST_BUILD command after the target is built
# This ensures that binary files exist for dependency analysis

# Set up variables from command line arguments
if(NOT DEFINED target_name)
    message(FATAL_ERROR "target_name not defined")
endif()

if(NOT DEFINED output_file)
    message(FATAL_ERROR "output_file not defined")
endif()

# Determine properties file path
if(NOT DEFINED target_properties_file)
    # Try to construct path from CMAKE_BINARY_DIR
    if(DEFINED CMAKE_BINARY_DIR)
        set(target_properties_file "${CMAKE_BINARY_DIR}/${target_name}-target-properties.cmake")
    else()
        message(FATAL_ERROR "Neither target_properties_file nor CMAKE_BINARY_DIR defined")
    endif()
endif()

# Load target properties from file
if(EXISTS "${target_properties_file}")
    include("${target_properties_file}")
    message(STATUS "Loaded target properties from: ${target_properties_file}")
else()
    message(WARNING "Target properties file not found: ${target_properties_file}")
    # Try alternative path
    if(DEFINED CMAKE_BINARY_DIR)
        set(alt_properties_file "${CMAKE_BINARY_DIR}/${target_name}-target-properties.cmake")
        if(EXISTS "${alt_properties_file}")
            include("${alt_properties_file}")
            message(STATUS "Loaded properties from alternative path: ${alt_properties_file}")
        else()
            message(WARNING "Alternative path also not found: ${alt_properties_file}")
            message(WARNING "Some information may be incomplete")
        endif()
    else()
        message(WARNING "CMAKE_BINARY_DIR not defined, some information may be incomplete")
    endif()
endif()

# Include the build info generation module
# Use CMAKE_CURRENT_LIST_DIR to find the module relative to this script
get_filename_component(SCRIPT_DIR "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
include(${SCRIPT_DIR}/GenerateBuildInfo.cmake)

# Generate the build info file (now with access to built binaries)
# This will properly analyze dynamic and transitive dependencies
generate_build_info_file(${target_name} "${output_file}")

message(STATUS "Build info file regenerated: ${output_file}")
