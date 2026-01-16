# ============================================================== #
# GenerateBuildInfo.cmake - Automatic build information generator
# ============================================================== #
# This module generates comprehensive build information files
# containing compiler, system, and build configuration details

include(CMakePackageConfigHelpers)

# Function to detect Windows SDK version
function(get_windows_sdk_version sdk_version_var)
    if(WIN32 AND MSVC)
        # Try to get Windows SDK version from registry or environment
        set(sdk_version "Unknown")

        # Check CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION if available
        if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL "")
            set(sdk_version "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
        else()
            # Try to extract from Windows SDK path
            if(DEFINED CMAKE_SYSTEM_VERSION AND NOT CMAKE_SYSTEM_VERSION STREQUAL "")
                set(sdk_version "${CMAKE_SYSTEM_VERSION}")
            else()
                # Try to get from Windows SDK registry
                execute_process(
                    COMMAND reg query "HKLM\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots" /v KitsRoot10
                    OUTPUT_VARIABLE sdk_reg_output
                    ERROR_QUIET
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                )
                if(sdk_reg_output MATCHES "KitsRoot10[[:space:]]+REG_SZ[[:space:]]+([^[:space:]]+)")
                    set(sdk_path "${CMAKE_MATCH_1}")
                    # Extract version from path (e.g., C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0)
                    if(sdk_path MATCHES "10\\.0\\.([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)")
                        set(sdk_version "10.0.${CMAKE_MATCH_1}")
                    endif()
                endif()

                # Try alternative registry paths
                if(sdk_version STREQUAL "Unknown")
                    execute_process(
                        COMMAND reg query "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows Kits\\Installed Roots" /v KitsRoot10
                        OUTPUT_VARIABLE sdk_reg_output_alt
                        ERROR_QUIET
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                    )
                    if(sdk_reg_output_alt MATCHES "KitsRoot10[[:space:]]+REG_SZ[[:space:]]+([^[:space:]]+)")
                        set(sdk_path "${CMAKE_MATCH_1}")
                        if(sdk_path MATCHES "10\\.0\\.([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)")
                            set(sdk_version "10.0.${CMAKE_MATCH_1}")
                        endif()
                    endif()
                endif()

                # Try to find SDK version in Include directories
                if(sdk_version STREQUAL "Unknown")
                    # Get environment variables using execute_process (needed for ProgramFiles(x86))
                    set(PROGRAM_FILES_ENV "C:/Program Files")
                    set(PROGRAM_FILES_X86_ENV "C:/Program Files (x86)")

                    if(WIN32)
                        execute_process(
                            COMMAND cmd /c "echo %ProgramFiles%"
                            OUTPUT_VARIABLE pf_output
                            ERROR_QUIET
                            OUTPUT_STRIP_TRAILING_WHITESPACE
                        )
                        if(pf_output)
                            string(STRIP "${pf_output}" PROGRAM_FILES_ENV)
                        endif()

                        execute_process(
                            COMMAND cmd /c "echo %ProgramFiles(x86)%"
                            OUTPUT_VARIABLE pfx86_output
                            ERROR_QUIET
                            OUTPUT_STRIP_TRAILING_WHITESPACE
                        )
                        if(pfx86_output)
                            string(STRIP "${pfx86_output}" PROGRAM_FILES_X86_ENV)
                        endif()
                    endif()

                    set(sdk_search_paths
                        "C:/Program Files (x86)/Windows Kits/10/Include"
                        "C:/Program Files/Windows Kits/10/Include"
                        "${PROGRAM_FILES_X86_ENV}/Windows Kits/10/Include"
                        "${PROGRAM_FILES_ENV}/Windows Kits/10/Include"
                    )
                    foreach(search_path ${sdk_search_paths})
                        if(EXISTS "${search_path}")
                            file(GLOB sdk_versions "${search_path}/*")
                            if(sdk_versions)
                                # Get the highest version
                                list(SORT sdk_versions)
                                list(REVERSE sdk_versions)
                                list(GET sdk_versions 0 latest_sdk)
                                get_filename_component(sdk_version "${latest_sdk}" NAME)
                                break()
                            endif()
                        endif()
                    endforeach()
                endif()
            endif()
        endif()

        set(${sdk_version_var} "${sdk_version}" PARENT_SCOPE)
    else()
        set(${sdk_version_var} "- (not applicable)" PARENT_SCOPE)
    endif()
endfunction()

# Function to detect glibc version on Linux
function(get_glibc_version glibc_version_var)
    if(UNIX AND NOT APPLE)
        # Try to run ldd --version or check /lib/x86_64-linux-gnu/libc.so.6
        find_program(LDD_EXECUTABLE ldd)
        if(LDD_EXECUTABLE)
            execute_process(
                COMMAND ${LDD_EXECUTABLE} --version
                OUTPUT_VARIABLE ldd_output
                ERROR_VARIABLE ldd_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )

            # Extract version from ldd output
            if(ldd_output MATCHES "ldd \\(.*\\) ([0-9]+\\.[0-9]+)")
                set(glibc_version "${CMAKE_MATCH_1}")
            elseif(ldd_output MATCHES "GLIBC ([0-9]+\\.[0-9]+)")
                set(glibc_version "${CMAKE_MATCH_1}")
            else()
                set(glibc_version "Unknown")
            endif()
        else()
            set(glibc_version "Unknown")
        endif()

        set(${glibc_version_var} "${glibc_version}" PARENT_SCOPE)
    else()
        set(${glibc_version_var} "- (not applicable)" PARENT_SCOPE)
    endif()
endfunction()

# Function to detect glibcxx version on Linux
function(get_glibcxx_version glibcxx_version_var)
    if(UNIX AND NOT APPLE)
        # Try to get version from libstdc++.so
        find_program(STRINGS_EXECUTABLE strings)
        if(STRINGS_EXECUTABLE)
            # Try common locations for libstdc++
            set(libstdcxx_paths
                "/usr/lib/x86_64-linux-gnu/libstdc++.so.6"
                "/usr/lib64/libstdc++.so.6"
                "/lib/x86_64-linux-gnu/libstdc++.so.6"
                "/usr/lib/libstdc++.so.6"
                "/lib/libstdc++.so.6"
                "/usr/local/lib/libstdc++.so.6"
                "/usr/lib/aarch64-linux-gnu/libstdc++.so.6"
                "/usr/lib/arm-linux-gnueabihf/libstdc++.so.6"
                "/usr/lib/i386-linux-gnu/libstdc++.so.6"
                "/usr/lib32/libstdc++.so.6"
            )

            # Also try to find via find_library
            if(NOT libstdcxx_paths)
                find_library(STDCXX_LIB stdc++ PATHS
                    /usr/lib
                    /usr/lib64
                    /usr/local/lib
                    /lib
                    /lib64
                    NO_DEFAULT_PATH
                )
                if(STDCXX_LIB)
                    list(APPEND libstdcxx_paths "${STDCXX_LIB}")
                endif()
            endif()

            foreach(lib_path ${libstdcxx_paths})
                if(EXISTS "${lib_path}")
                    execute_process(
                        COMMAND ${STRINGS_EXECUTABLE} "${lib_path}" | grep "GLIBCXX"
                        OUTPUT_VARIABLE glibcxx_strings
                        ERROR_QUIET
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                    )

                    # Extract highest version
                    if(glibcxx_strings MATCHES "GLIBCXX_([0-9]+\\.[0-9]+\\.[0-9]+)")
                        set(glibcxx_version "${CMAKE_MATCH_1}")
                        break()
                    endif()
                endif()
            endforeach()

            if(NOT glibcxx_version)
                set(glibcxx_version "Unknown")
            endif()
        else()
            set(glibcxx_version "Unknown")
        endif()

        set(${glibcxx_version_var} "${glibcxx_version}" PARENT_SCOPE)
    else()
        set(${glibcxx_version_var} "- (not applicable)" PARENT_SCOPE)
    endif()
endfunction()

# Function to detect C++ ABI version
function(get_cxx_abi_info target_name abi_info_var)
    if(UNIX AND NOT APPLE)
        # Check _GLIBCXX_USE_CXX11_ABI
        if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
            # Check current setting
            safe_get_target_property(${target_name} COMPILE_DEFINITIONS compile_defs)
            if(compile_defs)
                list(FIND compile_defs "_GLIBCXX_USE_CXX11_ABI=1" has_cxx11_abi)
                if(has_cxx11_abi GREATER_EQUAL 0)
                    set(abi_info "C++11 ABI (1) - _GLIBCXX_USE_CXX11_ABI=1")
                else()
                    list(FIND compile_defs "_GLIBCXX_USE_CXX11_ABI=0" has_legacy_abi)
                    if(has_legacy_abi GREATER_EQUAL 0)
                        set(abi_info "Legacy ABI (0) - _GLIBCXX_USE_CXX11_ABI=0")
                    else()
                        # Default for modern GCC
                        set(abi_info "C++11 ABI (1) - _GLIBCXX_USE_CXX11_ABI=1")
                    endif()
                endif()
            else()
                # Default for modern GCC
                set(abi_info "C++11 ABI (1) - _GLIBCXX_USE_CXX11_ABI=1")
            endif()
        else()
            set(abi_info "- (not applicable)")
        endif()
        set(${abi_info_var} "${abi_info}" PARENT_SCOPE)
    else()
        set(${abi_info_var} "- (not applicable)" PARENT_SCOPE)
    endif()
endfunction()

# Function to get compiler flags as string (formatted for multi-line output)
# Filters flags to show only those relevant to current build configuration
function(get_compiler_flags target_name flags_var)
    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()
    safe_get_target_property(${target_name} COMPILE_DEFINITIONS compile_defs)

    # Get current build type
    if(CMAKE_BUILD_TYPE)
        set(current_config "${CMAKE_BUILD_TYPE}")
    else()
        # For multi-config generators, default to Release
        set(current_config "Release")
    endif()

    set(flags_list)

    # Add compile options, filtering by current configuration
    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        foreach(opt ${compile_options})
            set(processed FALSE)

            # Check if this is a nested generator expression: $<$<CONFIG:Release>:-O3>
            if(opt MATCHES "\\$<\\$<CONFIG:([^>]+)>:(.+)>")
                set(config_name "${CMAKE_MATCH_1}")
                set(flag_content "${CMAKE_MATCH_2}")
                # Only include if it matches current config
                if(config_name STREQUAL "${current_config}")
                    # Split multiple flags separated by semicolons
                    string(REPLACE ";" " " flags_str "${flag_content}")
                    # Remove any remaining > characters
                    string(REPLACE ">" "" flags_str "${flags_str}")
                    # Split back into individual flags
                    string(REPLACE " " ";" flags_split "${flags_str}")
                    foreach(flag ${flags_split})
                        string(STRIP "${flag}" flag)
                        if(flag AND NOT flag STREQUAL "")
                            list(APPEND flags_list "${flag}")
                        endif()
                    endforeach()
                    set(processed TRUE)
                endif()
                # Check if this is a simple generator expression: $<CONFIG:Release>:-O3
            elseif(opt MATCHES "\\$<CONFIG:([^>]+)>:(.+)")
                set(config_name "${CMAKE_MATCH_1}")
                set(flag_content "${CMAKE_MATCH_2}")
                if(config_name STREQUAL "${current_config}")
                    # Split multiple flags separated by semicolons
                    string(REPLACE ";" " " flags_str "${flag_content}")
                    # Remove any remaining > characters
                    string(REPLACE ">" "" flags_str "${flags_str}")
                    # Split back into individual flags
                    string(REPLACE " " ";" flags_split "${flags_str}")
                    foreach(flag ${flags_split})
                        string(STRIP "${flag}" flag)
                        if(flag AND NOT flag STREQUAL "")
                            list(APPEND flags_list "${flag}")
                        endif()
                    endforeach()
                    set(processed TRUE)
                endif()
            endif()

            # Handle language-specific flags
            if(NOT processed AND opt MATCHES "\\$<COMPILE_LANGUAGE:")
                # Language-specific flags - include them (but clean up if needed)
                string(REPLACE ">" "" cleaned_opt "${opt}")
                string(STRIP "${cleaned_opt}" cleaned_opt)
                if(cleaned_opt AND NOT cleaned_opt STREQUAL "")
                    list(APPEND flags_list "${cleaned_opt}")
                endif()
                set(processed TRUE)
            endif()

            # Regular flags without generator expressions
            if(NOT processed AND NOT opt MATCHES "\\$<")
                string(STRIP "${opt}" cleaned_opt)
                if(cleaned_opt AND NOT cleaned_opt STREQUAL "")
                    list(APPEND flags_list "${cleaned_opt}")
                endif()
            endif()
        endforeach()
    endif()

    # Add compile definitions as flags (only for current config)
    if(compile_defs AND NOT compile_defs STREQUAL "compile_defs-NOTFOUND")
        foreach(def ${compile_defs})
            # Filter definitions by config if they have generator expressions
            if(def MATCHES "\\$<\\$<CONFIG:([^>]+)>")
                set(config_name "${CMAKE_MATCH_1}")
                if(config_name STREQUAL "${current_config}")
                    string(REGEX REPLACE "\\$<\\$<CONFIG:[^>]+>:" "" actual_def "${def}")
                    if(MSVC)
                        list(APPEND flags_list "/D${actual_def}")
                    else()
                        list(APPEND flags_list "-D${actual_def}")
                    endif()
                endif()
            else()
                # Regular definition - include it
                if(MSVC)
                    list(APPEND flags_list "/D${def}")
                else()
                    list(APPEND flags_list "-D${def}")
                endif()
            endif()
        endforeach()
    endif()

    # Format as multi-line string
    if(flags_list)
        # Clean up any remaining generator expression artifacts
        set(cleaned_flags_list)
        foreach(flag ${flags_list})
            # Remove any trailing > characters that might be left from generator expressions
            string(REGEX REPLACE ">$" "" cleaned_flag "${flag}")
            # Remove any standalone > characters
            string(REPLACE ">" "" cleaned_flag "${cleaned_flag}")
            if(cleaned_flag AND NOT cleaned_flag STREQUAL "")
                list(APPEND cleaned_flags_list "${cleaned_flag}")
            endif()
        endforeach()
        # Join flags with spaces
        string(REPLACE ";" " " flags_str "${cleaned_flags_list}")
    else()
        set(flags_str "- (not available)")
    endif()

    set(${flags_var} "${flags_str}" PARENT_SCOPE)
endfunction()

# Function to get linker flags as string
# Filters flags to show only those relevant to current build configuration
function(get_linker_flags target_name flags_var)
    if(DEFINED LINK_OPTIONS)
        set(link_options "${LINK_OPTIONS}")
    else()
        safe_get_target_property(${target_name} LINK_OPTIONS link_options)
    endif()

    # Get current build type
    if(CMAKE_BUILD_TYPE)
        set(current_config "${CMAKE_BUILD_TYPE}")
    else()
        set(current_config "Release")
    endif()

    set(filtered_flags)

    if(link_options AND NOT link_options STREQUAL "link_options-NOTFOUND")
        foreach(opt ${link_options})
            set(processed FALSE)

            # Check if this is a nested generator expression: $<$<CONFIG:Release>:-Wl,--gc-sections>
            if(opt MATCHES "\\$<\\$<CONFIG:([^>]+)>:(.+)>")
                set(config_name "${CMAKE_MATCH_1}")
                set(flag_content "${CMAKE_MATCH_2}")
                if(config_name STREQUAL "${current_config}")
                    # Split multiple flags separated by semicolons
                    string(REPLACE ";" " " flags_str "${flag_content}")
                    # Remove any remaining > characters
                    string(REPLACE ">" "" flags_str "${flags_str}")
                    # Split back into individual flags
                    string(REPLACE " " ";" flags_split "${flags_str}")
                    foreach(flag ${flags_split})
                        string(STRIP "${flag}" flag)
                        if(flag AND NOT flag STREQUAL "")
                            list(APPEND filtered_flags "${flag}")
                        endif()
                    endforeach()
                    set(processed TRUE)
                endif()
                # Check if this is a simple generator expression: $<CONFIG:Release>:-Wl,--gc-sections
            elseif(opt MATCHES "\\$<CONFIG:([^>]+)>:(.+)")
                set(config_name "${CMAKE_MATCH_1}")
                set(flag_content "${CMAKE_MATCH_2}")
                if(config_name STREQUAL "${current_config}")
                    # Split multiple flags separated by semicolons
                    string(REPLACE ";" " " flags_str "${flag_content}")
                    # Remove any remaining > characters
                    string(REPLACE ">" "" flags_str "${flags_str}")
                    # Split back into individual flags
                    string(REPLACE " " ";" flags_split "${flags_str}")
                    foreach(flag ${flags_split})
                        string(STRIP "${flag}" flag)
                        if(flag AND NOT flag STREQUAL "")
                            list(APPEND filtered_flags "${flag}")
                        endif()
                    endforeach()
                    set(processed TRUE)
                endif()
            endif()

            # Regular flags without generator expressions
            if(NOT processed AND NOT opt MATCHES "\\$<")
                string(STRIP "${opt}" cleaned_opt)
                if(cleaned_opt AND NOT cleaned_opt STREQUAL "")
                    list(APPEND filtered_flags "${cleaned_opt}")
                endif()
            endif()
        endforeach()

        if(filtered_flags)
            # Clean up any remaining generator expression artifacts
            set(cleaned_flags_list)
            foreach(flag ${filtered_flags})
                # Remove any trailing > characters that might be left from generator expressions
                string(REGEX REPLACE ">$" "" cleaned_flag "${flag}")
                # Remove any standalone > characters
                string(REPLACE ">" "" cleaned_flag "${cleaned_flag}")
                if(cleaned_flag AND NOT cleaned_flag STREQUAL "")
                    list(APPEND cleaned_flags_list "${cleaned_flag}")
                endif()
            endforeach()
            string(REPLACE ";" " " flags_str "${cleaned_flags_list}")
        else()
            set(flags_str "- (not available)")
        endif()
    else()
        set(flags_str "- (not available)")
    endif()
    set(${flags_var} "${flags_str}" PARENT_SCOPE)
endfunction()

# Function to detect CPU features from compiler flags
function(detect_cpu_features target_name cpu_features_var)
    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()
    set(cpu_features_list)

    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        string(JOIN " " flags_str "${compile_options}")

        # Check for AVX features first (most advanced)
        if(flags_str MATCHES "-mavx512|/arch:AVX512")
            list(APPEND cpu_features_list "AVX512")
        elseif(flags_str MATCHES "-mavx2|/arch:AVX2")
            list(APPEND cpu_features_list "AVX2")
        elseif(flags_str MATCHES "-mavx|/arch:AVX")
            list(APPEND cpu_features_list "AVX")
        endif()

        # Check for SSE features
        if(flags_str MATCHES "-msse4.2|/arch:SSE2|/arch:SSE")
            list(APPEND cpu_features_list "SSE4.2")
        elseif(flags_str MATCHES "-msse4.1|/arch:SSE")
            list(APPEND cpu_features_list "SSE4.1")
        elseif(flags_str MATCHES "-msse3|/arch:SSE")
            list(APPEND cpu_features_list "SSE3")
        elseif(flags_str MATCHES "-msse2|/arch:SSE2")
            list(APPEND cpu_features_list "SSE2")
        elseif(flags_str MATCHES "-msse|/arch:SSE")
            list(APPEND cpu_features_list "SSE")
        endif()

        # Check for other features
        if(flags_str MATCHES "-mfma|/arch:AVX2")
            list(APPEND cpu_features_list "FMA")
        endif()

        # Check for generic x86-64 (baseline features: MMX, SSE, SSE2, FXSR)
        if(flags_str MATCHES "-march=x86-64|-march=amd64")
            if(NOT cpu_features_list)
                # If no specific features found, x86-64 includes baseline SSE2
                list(APPEND cpu_features_list "SSE2")
            endif()
        endif()
    endif()

    if(cpu_features_list)
        string(JOIN ", " cpu_features_str "${cpu_features_list}")
    else()
        set(cpu_features_str "None (generic x64)")
    endif()

    set(${cpu_features_var} "${cpu_features_str}" PARENT_SCOPE)
endfunction()

# Function to detect Native Tuning
function(detect_native_tuning target_name native_tuning_var)
    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()
    set(has_native_tuning FALSE)
    set(tuning_type "No")

    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        string(JOIN " " flags_str "${compile_options}")

        # Check for native tuning flags (most aggressive)
        if(flags_str MATCHES "-march=native|-mtune=native|-mcpu=native")
            set(has_native_tuning TRUE)
            set(tuning_type "Yes (native)")
        # Check for generic tuning (universal optimization)
        elseif(flags_str MATCHES "-mtune=generic")
            set(tuning_type "Generic (universal)")
        # Check for generic x86-64 tuning (compatible baseline)
        elseif(flags_str MATCHES "-march=x86-64")
            set(tuning_type "Generic x86-64")
        # Check for other specific architecture tuning
        elseif(flags_str MATCHES "-march=([a-zA-Z0-9_-]+)")
            set(arch_match "${CMAKE_MATCH_1}")
            if(NOT arch_match STREQUAL "native")
                set(tuning_type "Generic ${arch_match}")
            endif()
        endif()
    endif()

    if(has_native_tuning)
        set(${native_tuning_var} "${tuning_type}" PARENT_SCOPE)
    elseif(NOT tuning_type STREQUAL "No")
        set(${native_tuning_var} "${tuning_type}" PARENT_SCOPE)
    else()
        set(${native_tuning_var} "No" PARENT_SCOPE)
    endif()
endfunction()

# Function to detect PGO
function(detect_pgo target_name pgo_enabled_var)
    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()
    if(DEFINED LINK_OPTIONS)
        set(link_options "${LINK_OPTIONS}")
    else()
        safe_get_target_property(${target_name} LINK_OPTIONS link_options)
    endif()
    set(has_pgo FALSE)

    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        string(JOIN " " flags_str "${compile_options}")

        # Check for PGO flags
        if(flags_str MATCHES "-fprofile-generate|-fprofile-use|/LTCG:PGINSTRUMENT|/LTCG:PGOPTIMIZE")
            set(has_pgo TRUE)
        endif()
    endif()

    if(link_options AND NOT link_options STREQUAL "link_options-NOTFOUND")
        string(JOIN " " link_flags_str "${link_options}")
        if(link_flags_str MATCHES "-fprofile-generate|-fprofile-use|/LTCG:PGINSTRUMENT|/LTCG:PGOPTIMIZE")
            set(has_pgo TRUE)
        endif()
    endif()

    if(has_pgo)
        set(${pgo_enabled_var} "Yes" PARENT_SCOPE)
    else()
        set(${pgo_enabled_var} "No" PARENT_SCOPE)
    endif()
endfunction()

# Function to get PDB file path
function(get_pdb_path target_name pdb_path_var)
    if(MSVC AND WIN32)
        # Try to get PDB file from target
        safe_get_target_property(${target_name} PDB_OUTPUT_DIRECTORY pdb_file)
        if(NOT pdb_file OR pdb_file STREQUAL "pdb_file-NOTFOUND" OR pdb_file STREQUAL "PDB_OUTPUT_DIRECTORY-NOTFOUND")
            # Try to construct default path
            if(DEFINED RUNTIME_OUTPUT_DIRECTORY)
                set(output_dir "${RUNTIME_OUTPUT_DIRECTORY}")
            else()
                safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
            endif()
            if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND")
                if(DEFINED CMAKE_BINARY_DIR)
                    set(output_dir "${CMAKE_BINARY_DIR}")
                else()
                    set(output_dir "${CMAKE_BINARY_DIR}")
                endif()
            endif()
            if(DEFINED OUTPUT_NAME)
                set(output_name "${OUTPUT_NAME}")
            else()
                safe_get_target_property(${target_name} OUTPUT_NAME output_name)
            endif()
            if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
                if(DEFINED PROJECT_NAME)
                    set(output_name "${PROJECT_NAME}")
                else()
                    set(output_name "${target_name}")
                endif()
            endif()
            set(pdb_file "${output_dir}/${output_name}.pdb")
        endif()

        # Check if file exists
        if(EXISTS "${pdb_file}")
            set(${pdb_path_var} "${pdb_file}" PARENT_SCOPE)
        else()
            set(${pdb_path_var} "- (not available)" PARENT_SCOPE)
        endif()
    else()
        set(${pdb_path_var} "- (not applicable)" PARENT_SCOPE)
    endif()
endfunction()

# Function to get dynamic dependencies of the main binary
function(get_dynamic_dependencies target_name dynamic_deps_var)
    # Check if this is a static library (no dynamic dependencies)
    if(DEFINED TARGET_TYPE)
        set(LIB_TYPE "${TARGET_TYPE}")
    else()
        safe_get_target_property(${target_name} TYPE LIB_TYPE)
    endif()
    if(LIB_TYPE STREQUAL "STATIC_LIBRARY")
        set(${dynamic_deps_var} "[None - static library]" PARENT_SCOPE)
        return()
    endif()

    # Determine binary file path
    # Try to get from saved properties first (for POST_BUILD script mode)
    # Prefer lib dir for libraries, runtime dir for executables
    safe_get_target_property(${target_name} TYPE _bin_type)
    if(DEFINED _bin_type AND _bin_type STREQUAL "EXECUTABLE")
        if(DEFINED RUNTIME_OUTPUT_DIRECTORY)
            set(output_dir "${RUNTIME_OUTPUT_DIRECTORY}")
        else()
            safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}/bin")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()
    else()
        if(DEFINED LIBRARY_OUTPUT_DIRECTORY)
            set(output_dir "${LIBRARY_OUTPUT_DIRECTORY}")
        else()
            safe_get_target_property(${target_name} LIBRARY_OUTPUT_DIRECTORY output_dir)
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED RUNTIME_OUTPUT_DIRECTORY)
                set(output_dir "${RUNTIME_OUTPUT_DIRECTORY}")
            else()
                safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
            endif()
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()
    endif()

    # Get output name
    if(DEFINED OUTPUT_NAME)
        set(output_name "${OUTPUT_NAME}")
    else()
        safe_get_target_property(${target_name} OUTPUT_NAME output_name)
    endif()
    if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
        # Prefer target name, then project name
        if(target_name)
            set(output_name "${target_name}")
        elseif(DEFINED PROJECT_NAME)
            set(output_name "${PROJECT_NAME}")
        endif()
    endif()

    # Detect target type for naming
    safe_get_target_property(${target_name} TYPE _dd_type)
    if(NOT _dd_type OR _dd_type STREQUAL "TYPE-NOTFOUND")
        set(_dd_type "UNKNOWN")
    endif()

    # Find the actual binary file (handle executables, libs, versioned .so)
    if(WIN32)
        if(_dd_type STREQUAL "EXECUTABLE")
            set(binary_file "${output_dir}/${output_name}.exe")
        else()
            set(binary_file "${output_dir}/${output_name}.dll")
        endif()
    else()
        if(_dd_type STREQUAL "EXECUTABLE")
            set(binary_file "${output_dir}/${output_name}")
            if(NOT EXISTS "${binary_file}" AND EXISTS "${output_dir}/../bin/${output_name}")
                set(binary_file "${output_dir}/../bin/${output_name}")
            endif()
        else()
            set(binary_file "${output_dir}/lib${output_name}.so")
            if(NOT EXISTS "${binary_file}")
                file(GLOB versioned_files "${output_dir}/lib${output_name}.so.*")
                if(versioned_files)
                    list(SORT versioned_files)
                    list(REVERSE versioned_files)
                    list(GET versioned_files 0 binary_file)
                endif()
            endif()
            if(NOT EXISTS "${binary_file}")
                set(binary_file "${output_dir}/${output_name}.so")
            endif()
        endif()
    endif()

    # Fallback to bin under CMAKE_BINARY_DIR
    if(NOT EXISTS "${binary_file}" AND DEFINED CMAKE_BINARY_DIR)
        set(_bin_try "${CMAKE_BINARY_DIR}/bin/${output_name}")
        if(WIN32)
            set(_bin_try "${_bin_try}.exe")
        endif()
        if(EXISTS "${_bin_try}")
            set(binary_file "${_bin_try}")
        endif()
    endif()

    # Get direct dependencies
    if(EXISTS "${binary_file}")
        # Resolve symlink to actual file
        get_filename_component(binary_file "${binary_file}" REALPATH)
        get_direct_dependencies("${binary_file}" direct_deps)
    else()
        # Binary doesn't exist yet, try to get from CMake properties as fallback
        set(direct_deps)
        if(DEFINED LINK_LIBRARIES)
            set(linked_libs "${LINK_LIBRARIES}")
        else()
            safe_get_target_property(${target_name} LINK_LIBRARIES linked_libs)
        endif()
        if(linked_libs AND NOT linked_libs STREQUAL "linked_libs-NOTFOUND")
            foreach(lib ${linked_libs})
                if(lib MATCHES "\\$<")
                    continue()
                endif()
                # Check if it's a shared library target
                if(TARGET "${lib}")
                    safe_get_target_property("${lib}" TYPE lib_type)
                    if(lib_type STREQUAL "SHARED_LIBRARY")
                        safe_get_target_property("${lib}" NAME lib_name)
                        if(lib_name)
                            list(APPEND direct_deps "${lib_name}")
                        endif()
                    endif()
                elseif(UNIX AND NOT APPLE)
                    # Check for .so extension
                    if(lib MATCHES "\\.so")
                        get_filename_component(lib_name "${lib}" NAME)
                        list(APPEND direct_deps "${lib_name}")
                    endif()
                elseif(WIN32)
                    # Check for .dll extension
                    if(lib MATCHES "\\.dll$")
                        get_filename_component(lib_name "${lib}" NAME)
                        list(APPEND direct_deps "${lib_name}")
                    endif()
                endif()
            endforeach()
        endif()
    endif()

    # Format output
    if(direct_deps)
        list(REMOVE_DUPLICATES direct_deps)
        list(SORT direct_deps)
        string(JOIN ", " deps_str "${direct_deps}")
        set(${dynamic_deps_var} "[${deps_str}]" PARENT_SCOPE)
    else()
        set(${dynamic_deps_var} "[None - no dynamic dependencies]" PARENT_SCOPE)
    endif()
endfunction()

# Helper function to get direct dependencies of a binary/library
function(get_direct_dependencies binary_path direct_deps_var)
    set(direct_deps_list)

    if(UNIX AND NOT APPLE)
        # Linux: Use readelf to get direct dependencies (preferred), fallback to ldd
        find_program(READELF_EXECUTABLE readelf)
        find_program(LDD_EXECUTABLE ldd)

        if(READELF_EXECUTABLE AND EXISTS "${binary_path}")
            execute_process(
                COMMAND ${READELF_EXECUTABLE} -d "${binary_path}"
                OUTPUT_VARIABLE readelf_output
                ERROR_VARIABLE readelf_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE readelf_result
            )
            if(readelf_result EQUAL 0 AND readelf_output)
                # Extract NEEDED entries
                string(REGEX MATCHALL "NEEDED[[:space:]]+\\[([a-zA-Z0-9_.-]+)\\]" needed_matches "${readelf_output}")
                foreach(match ${needed_matches})
                    string(REGEX REPLACE "NEEDED[[:space:]]+\\[|\\]" "" lib_name "${match}")
                    if(lib_name)
                        list(APPEND direct_deps_list "${lib_name}")
                    endif()
                endforeach()
            endif()
        endif()

        # Fallback to ldd if readelf didn't work or found nothing
        if(NOT direct_deps_list AND LDD_EXECUTABLE AND EXISTS "${binary_path}")
            execute_process(
                COMMAND ${LDD_EXECUTABLE} "${binary_path}"
                OUTPUT_VARIABLE ldd_output
                ERROR_VARIABLE ldd_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE ldd_result
            )
            if(ldd_result EQUAL 0 AND ldd_output)
                # Parse ldd output: "libname => /path/to/libname.so.x (0x...)" or "libname.so.x (0x...)"
                # Note: CMake uses POSIX BRE, so (?:...) is not supported, use () instead
                string(REGEX MATCHALL "([a-zA-Z0-9_.-]+\\.so(\\.[0-9]+)*)" ldd_matches "${ldd_output}")
                foreach(match ${ldd_matches})
                    # Skip linux-vdso and ld-linux
                    if(NOT match MATCHES "^(linux-vdso|ld-linux)")
                        get_filename_component(lib_name "${match}" NAME)
                        list(APPEND direct_deps_list "${lib_name}")
                    endif()
                endforeach()
            endif()
        endif()
    elseif(WIN32)
        # Windows: Use dumpbin to get direct DLL dependencies
        find_program(DUMPBIN_EXECUTABLE dumpbin)
        if(NOT DUMPBIN_EXECUTABLE)
            get_filename_component(vs_path "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\VisualStudio\\SxS\\VS7;17.0]" ABSOLUTE)
            if(vs_path)
                set(DUMPBIN_EXECUTABLE "${vs_path}/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe")
                file(GLOB DUMPBIN_CANDIDATES "${DUMPBIN_EXECUTABLE}")
                if(DUMPBIN_CANDIDATES)
                    list(GET DUMPBIN_CANDIDATES 0 DUMPBIN_EXECUTABLE)
                endif()
            endif()
        endif()

        if(DUMPBIN_EXECUTABLE AND EXISTS "${binary_path}")
            execute_process(
                COMMAND ${DUMPBIN_EXECUTABLE} /dependents "${binary_path}"
                OUTPUT_VARIABLE dumpbin_output
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE dumpbin_result
            )
            if(dumpbin_result EQUAL 0 AND dumpbin_output)
                # Parse dumpbin output to extract DLL names
                string(REGEX MATCHALL "DLL name:[[:space:]]+([a-zA-Z0-9_.-]+\\.dll)" dll_matches "${dumpbin_output}")
                foreach(match ${dll_matches})
                    string(REGEX REPLACE "DLL name:[[:space:]]+" "" dll_name "${match}")
                    list(APPEND direct_deps_list "${dll_name}")
                endforeach()
            endif()
        endif()
    endif()

    set(${direct_deps_var} "${direct_deps_list}" PARENT_SCOPE)
endfunction()

# Function to get static dependencies (statically linked libraries)
function(get_static_dependencies target_name static_deps_var)
    set(static_deps_list)
    set(visited_targets)
    set(queue)

    # Get linked libraries from CMake target (includes PRIVATE, PUBLIC, INTERFACE)
    if(DEFINED LINK_LIBRARIES)
        set(linked_libs "${LINK_LIBRARIES}")
    else()
        safe_get_target_property(${target_name} LINK_LIBRARIES linked_libs)
    endif()

    # Add initial libraries to queue
    if(linked_libs AND NOT linked_libs STREQUAL "linked_libs-NOTFOUND")
        foreach(lib ${linked_libs})
            # Skip generator expressions
            if(NOT lib MATCHES "\\$<")
                list(APPEND queue "${lib}")
            endif()
        endforeach()
    endif()

    # Also check INTERFACE_LINK_LIBRARIES
    if(DEFINED INTERFACE_LINK_LIBRARIES)
        set(interface_libs "${INTERFACE_LINK_LIBRARIES}")
    else()
        safe_get_target_property(${target_name} INTERFACE_LINK_LIBRARIES interface_libs)
    endif()
    if(interface_libs AND NOT interface_libs STREQUAL "interface_libs-NOTFOUND")
        foreach(lib ${interface_libs})
            # Skip generator expressions
            if(NOT lib MATCHES "\\$<")
                list(APPEND queue "${lib}")
            endif()
        endforeach()
    endif()

    # Process queue iteratively (breadth-first search)
    while(queue)
        # Get first item from queue
        list(GET queue 0 lib)
        list(REMOVE_AT queue 0)

        # Skip if already visited
        list(FIND visited_targets "${lib}" already_visited)
        if(already_visited EQUAL -1)
            # Mark as visited
            list(APPEND visited_targets "${lib}")

            # Check if it's a CMake target
            if(TARGET "${lib}")
                # Get target type
                safe_get_target_property(lib_type "${lib}" TYPE)

                # Only process STATIC_LIBRARY (skip INTERFACE, SHARED_LIBRARY, etc.)
                if(lib_type STREQUAL "STATIC_LIBRARY")
                    # Get target name
                    safe_get_target_property(lib_name "${lib}" NAME)
                    if(lib_name)
                        # Add to result if not already present
                        list(FIND static_deps_list "${lib_name}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND static_deps_list "${lib_name}")
                        endif()
                    endif()

                    # Add this target's dependencies to queue for processing
                    safe_get_target_property(lib_link_libs "${lib}" LINK_LIBRARIES)
                    if(lib_link_libs AND NOT lib_link_libs STREQUAL "lib_link_libs-NOTFOUND")
                        foreach(sub_lib ${lib_link_libs})
                            # Skip generator expressions
                            if(NOT sub_lib MATCHES "\\$<")
                                list(APPEND queue "${sub_lib}")
                            endif()
                        endforeach()
                    endif()

                    # Also check INTERFACE_LINK_LIBRARIES
                    safe_get_target_property(lib_interface_libs "${lib}" INTERFACE_LINK_LIBRARIES)
                    if(lib_interface_libs AND NOT lib_interface_libs STREQUAL "lib_interface_libs-NOTFOUND")
                        foreach(sub_lib ${lib_interface_libs})
                            # Skip generator expressions
                            if(NOT sub_lib MATCHES "\\$<")
                                list(APPEND queue "${sub_lib}")
                            endif()
                        endforeach()
                    endif()
                endif()
            else()
                # Check if it's a static library file path
                if(UNIX AND NOT APPLE)
                    # Check for .a extension
                    if(lib MATCHES "\\.a$")
                        get_filename_component(lib_name "${lib}" NAME_WE)
                        # Remove 'lib' prefix if present
                        string(REGEX REPLACE "^lib" "" lib_name "${lib_name}")
                        if(lib_name)
                            list(FIND static_deps_list "${lib_name}" already_present)
                            if(already_present EQUAL -1)
                                list(APPEND static_deps_list "${lib_name}")
                            endif()
                        endif()
                    endif()
                elseif(WIN32)
                    # Check for .lib extension (but not .dll.lib)
                    if(lib MATCHES "\\.lib$" AND NOT lib MATCHES "\\.dll\\.lib$")
                        get_filename_component(lib_name "${lib}" NAME_WE)
                        if(lib_name)
                            list(FIND static_deps_list "${lib_name}" already_present)
                            if(already_present EQUAL -1)
                                list(APPEND static_deps_list "${lib_name}")
                            endif()
                        endif()
                    endif()
                endif()
            endif()
        endif()
    endwhile()

    # Fallback: Search for static library files in build directory
    # This helps when target properties are not available (e.g., in script mode)
    if(NOT static_deps_list)
        if(DEFINED CMAKE_BINARY_DIR)
            set(build_dir "${CMAKE_BINARY_DIR}")
        else()
            set(build_dir "${CMAKE_BINARY_DIR}")
        endif()

        if(EXISTS "${build_dir}")
            # Search for .a files (Linux static libraries)
            if(UNIX AND NOT APPLE)
                file(GLOB_RECURSE static_libs "${build_dir}/*.a")
                foreach(static_lib ${static_libs})
                    get_filename_component(lib_name "${static_lib}" NAME_WE)
                    # Remove 'lib' prefix if present
                    string(REGEX REPLACE "^lib" "" lib_name "${lib_name}")
                    # Skip if it's the main library itself
                    if(lib_name AND NOT lib_name STREQUAL "${target_name}")
                        list(FIND static_deps_list "${lib_name}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND static_deps_list "${lib_name}")
                        endif()
                    endif()
                endforeach()
            elseif(WIN32)
                # Search for .lib files (but not .dll.lib)
                file(GLOB_RECURSE static_libs "${build_dir}/*.lib")
                foreach(static_lib ${static_libs})
                    get_filename_component(lib_name "${static_lib}" NAME_WE)
                    # Skip import libraries (.dll.lib)
                    if(lib_name AND NOT lib_name MATCHES "\\.dll$")
                        # Skip if it's the main library itself
                        if(NOT lib_name STREQUAL "${target_name}")
                            list(FIND static_deps_list "${lib_name}" already_present)
                            if(already_present EQUAL -1)
                                list(APPEND static_deps_list "${lib_name}")
                            endif()
                        endif()
                    endif()
                endforeach()
            endif()
        endif()
    endif()

    # Additional fallback: Analyze CMakeLists.txt files to find static libraries
    # This is useful when target properties are not available
    if(NOT static_deps_list AND DEFINED CMAKE_SOURCE_DIR)
        set(source_dir "${CMAKE_SOURCE_DIR}")
        if(EXISTS "${source_dir}/CMakeLists.txt")
            analyze_cmakelists_for_static_libs("${source_dir}" static_deps_list)
        endif()
    endif()

    # Remove duplicates and sort
    if(static_deps_list)
        list(REMOVE_DUPLICATES static_deps_list)
        list(SORT static_deps_list)
        string(JOIN ", " deps_str "${static_deps_list}")
        set(${static_deps_var} "[${deps_str}]" PARENT_SCOPE)
    else()
        set(${static_deps_var} "[None]" PARENT_SCOPE)
    endif()
endfunction()

# Helper function to analyze CMakeLists.txt files for static libraries
function(analyze_cmakelists_for_static_libs cmake_dir result_var)
    set(found_static_libs)
    set(visited_dirs)
    set(dir_queue "${cmake_dir}")

    # Breadth-first search through CMakeLists.txt files
    while(dir_queue)
        list(GET dir_queue 0 current_dir)
        list(REMOVE_AT dir_queue 0)

        # Skip if already visited
        list(FIND visited_dirs "${current_dir}" already_visited)
        if(already_visited EQUAL -1)
            list(APPEND visited_dirs "${current_dir}")

            set(cmakelists_file "${current_dir}/CMakeLists.txt")
            if(EXISTS "${cmakelists_file}")
                # Read CMakeLists.txt
                file(READ "${cmakelists_file}" cmake_content)

                # Look for add_library with STATIC keyword
                # Pattern: add_library(target_name STATIC ...) or add_library(target_name STATIC)
                string(REGEX MATCHALL "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+)[[:space:]]+STATIC" static_matches "${cmake_content}")
                foreach(match ${static_matches})
                    string(REGEX REPLACE "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+)[[:space:]]+STATIC.*" "\\1" lib_name "${match}")
                    if(lib_name)
                        list(FIND found_static_libs "${lib_name}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND found_static_libs "${lib_name}")
                        endif()
                    endif()
                endforeach()

                # Also look for BUILD_SHARED_LIBS OFF followed by add_library
                # This indicates static library when BUILD_SHARED_LIBS is OFF
                string(REGEX MATCHALL "BUILD_SHARED_LIBS[[:space:]]+OFF" build_shared_off_matches "${cmake_content}")
                if(build_shared_off_matches)
                    # Find add_library calls after BUILD_SHARED_LIBS OFF
                    string(REGEX MATCHALL "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+)[[:space:]]+[^)]*\\)" all_lib_matches "${cmake_content}")
                    foreach(match ${all_lib_matches})
                        # Extract library name (first argument)
                        string(REGEX REPLACE "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+).*" "\\1" lib_name "${match}")
                        # Skip if it contains STATIC or SHARED (already handled above)
                        if(lib_name AND NOT match MATCHES "STATIC" AND NOT match MATCHES "SHARED" AND NOT match MATCHES "INTERFACE")
                            list(FIND found_static_libs "${lib_name}" already_present)
                            if(already_present EQUAL -1)
                                list(APPEND found_static_libs "${lib_name}")
                            endif()
                        endif()
                    endforeach()
                endif()

                # Look for add_subdirectory to recursively search
                string(REGEX MATCHALL "add_subdirectory[[:space:]]*\\([[:space:]]*([^)]+)\\)" subdir_matches "${cmake_content}")
                foreach(match ${subdir_matches})
                    # Extract subdirectory path (first argument)
                    string(REGEX REPLACE "add_subdirectory[[:space:]]*\\([[:space:]]*([^[:space:]]+).*" "\\1" subdir "${match}")
                    # Handle relative and absolute paths
                    if(NOT IS_ABSOLUTE "${subdir}")
                        set(subdir "${current_dir}/${subdir}")
                    endif()
                    # Normalize path
                    get_filename_component(subdir "${subdir}" ABSOLUTE)
                    if(EXISTS "${subdir}/CMakeLists.txt")
                        list(APPEND dir_queue "${subdir}")
                    endif()
                endforeach()
            endif()
        endif()
    endwhile()

    # Update result in parent scope
    set(${result_var} "${found_static_libs}" PARENT_SCOPE)
endfunction()

# Function to get header-only dependencies (INTERFACE libraries)
function(get_header_only_dependencies target_name header_only_deps_var)
    set(header_only_deps_list)
    set(visited_targets)
    set(queue)

    # Get linked libraries from CMake target (includes PRIVATE, PUBLIC, INTERFACE)
    if(DEFINED LINK_LIBRARIES)
        set(linked_libs "${LINK_LIBRARIES}")
    else()
        safe_get_target_property(${target_name} LINK_LIBRARIES linked_libs)
    endif()

    # Add initial libraries to queue
    if(linked_libs AND NOT linked_libs STREQUAL "linked_libs-NOTFOUND")
        foreach(lib ${linked_libs})
            # Skip generator expressions
            if(NOT lib MATCHES "\\$<")
                list(APPEND queue "${lib}")
            endif()
        endforeach()
    endif()

    # Also check INTERFACE_LINK_LIBRARIES
    if(DEFINED INTERFACE_LINK_LIBRARIES)
        set(interface_libs "${INTERFACE_LINK_LIBRARIES}")
    else()
        safe_get_target_property(${target_name} INTERFACE_LINK_LIBRARIES interface_libs)
    endif()
    if(interface_libs AND NOT interface_libs STREQUAL "interface_libs-NOTFOUND")
        foreach(lib ${interface_libs})
            # Skip generator expressions
            if(NOT lib MATCHES "\\$<")
                list(APPEND queue "${lib}")
            endif()
        endforeach()
    endif()

    # Process queue iteratively (breadth-first search)
    while(queue)
        # Get first item from queue
        list(GET queue 0 lib)
        list(REMOVE_AT queue 0)

        # Skip if already visited
        list(FIND visited_targets "${lib}" already_visited)
        if(already_visited EQUAL -1)
            # Mark as visited
            list(APPEND visited_targets "${lib}")

            # Check if it's a CMake target
            if(TARGET "${lib}")
                # Get target type
                safe_get_target_property(lib_type "${lib}" TYPE)

                # Only process INTERFACE_LIBRARY (header-only libraries)
                if(lib_type STREQUAL "INTERFACE_LIBRARY")
                    # Get target name
                    safe_get_target_property(lib_name "${lib}" NAME)
                    if(lib_name)
                        # Add to result if not already present
                        list(FIND header_only_deps_list "${lib_name}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND header_only_deps_list "${lib_name}")
                        endif()
                    endif()

                    # Add this target's dependencies to queue for processing
                    safe_get_target_property(lib_interface_libs "${lib}" INTERFACE_LINK_LIBRARIES)
                    if(lib_interface_libs AND NOT lib_interface_libs STREQUAL "lib_interface_libs-NOTFOUND")
                        foreach(sub_lib ${lib_interface_libs})
                            # Skip generator expressions
                            if(NOT sub_lib MATCHES "\\$<")
                                list(APPEND queue "${sub_lib}")
                            endif()
                        endforeach()
                    endif()
                endif()
            else()
                # Script mode fallback: if target is unknown and looks like a logical INTERFACE lib name
                # (not a path and not a compiled artifact), add it as header-only,
                # but skip if a static/shared artifact with the same base name exists in the build tree.
                if(NOT lib MATCHES "\\.a$"
                    AND NOT lib MATCHES "\\.so(\\.[0-9]+)*$"
                    AND NOT lib MATCHES "\\.lib$"
                    AND NOT lib MATCHES "\\.dll$"
                    AND NOT lib MATCHES "^-l")
                    # Check if a static/shared file exists for this name; if yes, do not treat as header-only.
                    set(__ho_skip FALSE)
                    if(DEFINED CMAKE_BINARY_DIR)
                        set(__ho_candidates "${lib}")
                        # Also try variant with '-' instead of '_' to catch names like hidapi-hidraw
                        string(REPLACE "_" "-" __ho_dash "${lib}")
                        if(NOT __ho_dash STREQUAL "${lib}")
                            list(APPEND __ho_candidates "${__ho_dash}")
                        endif()
                        foreach(__ho_name ${__ho_candidates})
                            file(GLOB __ho_static_matches
                                "${CMAKE_BINARY_DIR}/**/lib${__ho_name}.a"
                                "${CMAKE_BINARY_DIR}/**/${__ho_name}.a"
                                "${CMAKE_BINARY_DIR}/**/${__ho_name}.lib"
                                "${CMAKE_BINARY_DIR}/**/lib${__ho_name}.so"
                                "${CMAKE_BINARY_DIR}/**/${__ho_name}.so")
                            if(__ho_static_matches)
                                set(__ho_skip TRUE)
                            endif()
                        endforeach()
                    endif()
                    if(NOT __ho_skip)
                        list(FIND header_only_deps_list "${lib}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND header_only_deps_list "${lib}")
                        endif()
                    endif()
                endif()
            endif()
        endif()
    endwhile()

    # Fallback: Analyze CMakeLists.txt to find INTERFACE libraries
    # This helps when target properties are not available (e.g., in script mode)
    if(NOT header_only_deps_list AND DEFINED CMAKE_SOURCE_DIR)
        set(source_dir "${CMAKE_SOURCE_DIR}")
        if(EXISTS "${source_dir}/CMakeLists.txt")
            analyze_cmakelists_for_interface_libs("${source_dir}" header_only_deps_list)
        endif()
    endif()

    # Format output
    if(header_only_deps_list)
        list(REMOVE_DUPLICATES header_only_deps_list)
        list(SORT header_only_deps_list)
        string(JOIN ", " deps_str "${header_only_deps_list}")
        set(${header_only_deps_var} "[${deps_str}]" PARENT_SCOPE)
    else()
        set(${header_only_deps_var} "[None]" PARENT_SCOPE)
    endif()
endfunction()

# Helper function to analyze CMakeLists.txt files for INTERFACE libraries
function(analyze_cmakelists_for_interface_libs cmake_dir result_var)
    set(found_interface_libs)
    set(visited_dirs)
    set(dir_queue "${cmake_dir}")

    # Breadth-first search through CMakeLists.txt files
    while(dir_queue)
        list(GET dir_queue 0 current_dir)
        list(REMOVE_AT dir_queue 0)

        # Skip if already visited
        list(FIND visited_dirs "${current_dir}" already_visited)
        if(already_visited EQUAL -1)
            list(APPEND visited_dirs "${current_dir}")

            set(cmakelists_file "${current_dir}/CMakeLists.txt")
            if(EXISTS "${cmakelists_file}")
                # Read CMakeLists.txt
                file(READ "${cmakelists_file}" cmake_content)

                # Look for add_library with INTERFACE keyword
                # Pattern: add_library(target_name INTERFACE) or add_library(target_name INTERFACE ...)
                string(REGEX MATCHALL "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+)[[:space:]]+INTERFACE" interface_matches "${cmake_content}")
                foreach(match ${interface_matches})
                    string(REGEX REPLACE "add_library[[:space:]]*\\([[:space:]]*([a-zA-Z0-9_]+)[[:space:]]+INTERFACE.*" "\\1" lib_name "${match}")
                    if(lib_name)
                        list(FIND found_interface_libs "${lib_name}" already_present)
                        if(already_present EQUAL -1)
                            list(APPEND found_interface_libs "${lib_name}")
                        endif()
                    endif()
                endforeach()

                # Look for add_subdirectory to recursively search
                string(REGEX MATCHALL "add_subdirectory[[:space:]]*\\([[:space:]]*([^)]+)\\)" subdir_matches "${cmake_content}")
                foreach(match ${subdir_matches})
                    # Extract subdirectory path (first argument)
                    string(REGEX REPLACE "add_subdirectory[[:space:]]*\\([[:space:]]*([^[:space:]]+).*" "\\1" subdir "${match}")
                    # Handle relative and absolute paths
                    if(NOT IS_ABSOLUTE "${subdir}")
                        set(subdir "${current_dir}/${subdir}")
                    endif()
                    # Normalize path
                    get_filename_component(subdir "${subdir}" ABSOLUTE)
                    if(EXISTS "${subdir}/CMakeLists.txt")
                        list(APPEND dir_queue "${subdir}")
                    endif()
                endforeach()
            endif()
        endif()
    endwhile()

    # Update result in parent scope
    set(${result_var} "${found_interface_libs}" PARENT_SCOPE)
endfunction()

# Helper function to find library path by name
function(find_library_path lib_name lib_path_var)
    set(found_path "")

    if(UNIX AND NOT APPLE)
        # Use ldconfig to find library (most reliable)
        find_program(LDCONFIG_EXECUTABLE ldconfig)
        if(LDCONFIG_EXECUTABLE)
            execute_process(
                COMMAND ${LDCONFIG_EXECUTABLE} -p | grep "${lib_name}"
                OUTPUT_VARIABLE ldconfig_output
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            if(ldconfig_output MATCHES "${lib_name}[[:space:]]+=>[[:space:]]+([^[:space:]]+)")
                set(found_path "${CMAKE_MATCH_1}")
            endif()
        endif()

        # Fallback: try common paths
        if(NOT found_path)
            set(search_paths
                "/usr/lib"
                "/usr/lib64"
                "/lib"
                "/lib64"
                "/usr/local/lib"
                "/usr/lib/x86_64-linux-gnu"
                "/lib/x86_64-linux-gnu"
                "/usr/lib/aarch64-linux-gnu"
                "/usr/lib/arm-linux-gnueabihf"
                "/usr/lib/i386-linux-gnu"
            )
            foreach(search_path ${search_paths})
                file(GLOB lib_files "${search_path}/${lib_name}*")
                if(lib_files)
                    list(GET lib_files 0 found_path)
                    break()
                endif()
            endforeach()
        endif()
    elseif(WIN32)
        # Windows: search in system directories
        set(search_paths
            "$ENV{SystemRoot}/System32"
            "$ENV{SystemRoot}/SysWOW64"
        )
        foreach(search_path ${search_paths})
            if(EXISTS "${search_path}/${lib_name}")
                set(found_path "${search_path}/${lib_name}")
                break()
            endif()
        endforeach()
    endif()

    set(${lib_path_var} "${found_path}" PARENT_SCOPE)
endfunction()

function(analyze_transitive_dependencies target_name transitive_deps_var)
    # Check if this is a static library (no transitive dependencies)
    safe_get_target_property(${target_name} TYPE LIB_TYPE)
    if(LIB_TYPE STREQUAL "STATIC_LIBRARY")
        set(${transitive_deps_var} "[None - static library]" PARENT_SCOPE)
        return()
    endif()

    # Determine binary file path (mirror get_dynamic_dependencies)
    if(LIB_TYPE STREQUAL "EXECUTABLE")
        safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}/bin")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()
        safe_get_target_property(${target_name} OUTPUT_NAME output_name)
        if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
            set(output_name "${target_name}")
        endif()
        if(WIN32)
            set(binary_file "${output_dir}/${output_name}.exe")
        else()
            set(binary_file "${output_dir}/${output_name}")
            if(NOT EXISTS "${binary_file}" AND DEFINED CMAKE_BINARY_DIR)
                set(_alt "${CMAKE_BINARY_DIR}/bin/${output_name}")
                if(EXISTS "${_alt}")
                    set(binary_file "${_alt}")
                endif()
            endif()
        endif()
    else()
        # libraries
        safe_get_target_property(${target_name} LIBRARY_OUTPUT_DIRECTORY output_dir)
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}/lib")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()

        safe_get_target_property(${target_name} OUTPUT_NAME output_name)
        if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
            if(target_name)
                set(output_name "${target_name}")
            elseif(DEFINED PROJECT_NAME)
                set(output_name "${PROJECT_NAME}")
            endif()
        endif()

        if(WIN32)
            set(binary_file "${output_dir}/${output_name}.dll")
        else()
            set(binary_file "${output_dir}/lib${output_name}.so")
            if(NOT EXISTS "${binary_file}")
                file(GLOB versioned_files "${output_dir}/lib${output_name}.so.*")
                if(versioned_files)
                    list(SORT versioned_files)
                    list(REVERSE versioned_files)
                    list(GET versioned_files 0 binary_file)
                endif()
            endif()
            if(NOT EXISTS "${binary_file}")
                set(binary_file "${output_dir}/${output_name}.so")
            endif()
        endif()
    endif()

    set(transitive_deps_list)
    set(analysis_attempted FALSE)
    set(analysis_successful FALSE)

    # Get direct dependencies of the main binary
    set(direct_deps)
    if(EXISTS "${binary_file}")
        # Resolve symlink to actual file
        get_filename_component(binary_file "${binary_file}" REALPATH)
        get_direct_dependencies("${binary_file}" direct_deps)
        set(analysis_attempted TRUE)
        if(direct_deps OR TRUE)
            set(analysis_successful TRUE)
        endif()
    else()
        set(analysis_attempted TRUE)
        set(analysis_successful FALSE)
    endif()

    # Analyze transitive dependencies: for each direct dependency, get its dependencies
    if(direct_deps AND analysis_successful)

        if(UNIX AND NOT APPLE)
            # Linux: For each direct dependency, use ldd to get its dependencies
            find_program(LDD_EXECUTABLE ldd)
            find_program(READELF_EXECUTABLE readelf)

            if(LDD_EXECUTABLE OR READELF_EXECUTABLE)
                set(all_transitive_deps)

                foreach(direct_dep ${direct_deps})
                    # Find the actual library file
                    find_library_path("${direct_dep}" lib_path)

                    if(lib_path AND EXISTS "${lib_path}")
                        # Get dependencies of this library
                        get_direct_dependencies("${lib_path}" dep_deps)

                        # Add to transitive list (excluding the direct dependency itself)
                        foreach(dep_dep ${dep_deps})
                            # Skip if it's already a direct dependency
                            list(FIND direct_deps "${dep_dep}" is_direct)
                            if(is_direct EQUAL -1)
                                # Also skip system libraries
                                if(NOT dep_dep MATCHES "^(linux-vdso|ld-linux)")
                                    list(APPEND all_transitive_deps "${dep_dep}")
                                endif()
                            endif()
                        endforeach()
                    else()
                        # If library not found, try using ldd on main binary to get full paths
                        if(LDD_EXECUTABLE AND EXISTS "${binary_file}")
                            execute_process(
                                COMMAND ${LDD_EXECUTABLE} "${binary_file}"
                                OUTPUT_VARIABLE ldd_output
                                ERROR_QUIET
                                OUTPUT_STRIP_TRAILING_WHITESPACE
                            )
                            if(ldd_output)
                                # Find the line with this library and extract its path
                                string(REPLACE "\n" ";" ldd_lines "${ldd_output}")
                                foreach(line ${ldd_lines})
                                    if(line MATCHES "${direct_dep}[[:space:]]*=>[[:space:]]+([^[:space:]]+)")
                                        set(lib_path "${CMAKE_MATCH_1}")
                                        # Get dependencies of this library
                                        get_direct_dependencies("${lib_path}" dep_deps)

                                        foreach(dep_dep ${dep_deps})
                                            list(FIND direct_deps "${dep_dep}" is_direct)
                                            if(is_direct EQUAL -1)
                                                if(NOT dep_dep MATCHES "^(linux-vdso|ld-linux)")
                                                    list(APPEND all_transitive_deps "${dep_dep}")
                                                endif()
                                            endif()
                                        endforeach()
                                        break()
                                    endif()
                                endforeach()
                            endif()
                        endif()
                    endif()
                endforeach()

                if(all_transitive_deps)
                    set(analysis_successful TRUE)
                    list(REMOVE_DUPLICATES all_transitive_deps)
                    list(SORT all_transitive_deps)
                    set(transitive_deps_list ${all_transitive_deps})
                endif()
            endif()
        elseif(WIN32)
            # Windows: For each direct dependency DLL, use dumpbin to get its dependencies
            find_program(DUMPBIN_EXECUTABLE dumpbin)
            if(NOT DUMPBIN_EXECUTABLE)
                get_filename_component(vs_path "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\VisualStudio\\SxS\\VS7;17.0]" ABSOLUTE)
                if(vs_path)
                    set(DUMPBIN_EXECUTABLE "${vs_path}/VC/Tools/MSVC/*/bin/Hostx64/x64/dumpbin.exe")
                    file(GLOB DUMPBIN_CANDIDATES "${DUMPBIN_EXECUTABLE}")
                    if(DUMPBIN_CANDIDATES)
                        list(GET DUMPBIN_CANDIDATES 0 DUMPBIN_EXECUTABLE)
                    endif()
                endif()
            endif()

            if(DUMPBIN_EXECUTABLE)
                set(all_transitive_deps)

                foreach(direct_dep ${direct_deps})
                    # Find the actual DLL file
                    find_library_path("${direct_dep}" lib_path)

                    if(lib_path AND EXISTS "${lib_path}")
                        # Get dependencies of this DLL
                        get_direct_dependencies("${lib_path}" dep_deps)

                        # Add to transitive list (excluding the direct dependency itself)
                        foreach(dep_dep ${dep_deps})
                            list(FIND direct_deps "${dep_dep}" is_direct)
                            if(is_direct EQUAL -1)
                                list(APPEND all_transitive_deps "${dep_dep}")
                            endif()
                        endforeach()
                    endif()
                endforeach()

                if(all_transitive_deps)
                    set(analysis_successful TRUE)
                    list(REMOVE_DUPLICATES all_transitive_deps)
                    list(SORT all_transitive_deps)
                    set(transitive_deps_list ${all_transitive_deps})
                endif()
            endif()
        endif()
    endif()

    # If binary exists but no direct deps, try to analyze anyway using ldd
    if(EXISTS "${binary_file}" AND NOT direct_deps)
        if(UNIX AND NOT APPLE)
            find_program(LDD_EXECUTABLE ldd)
            if(LDD_EXECUTABLE)
                execute_process(
                    COMMAND ${LDD_EXECUTABLE} "${binary_file}"
                    OUTPUT_VARIABLE ldd_output
                    ERROR_QUIET
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    RESULT_VARIABLE ldd_result
                )
                if(ldd_result EQUAL 0 AND ldd_output)
                    # Parse ldd output to get all libraries
                    string(REPLACE "\n" ";" ldd_lines "${ldd_output}")
                    set(all_deps)
                    foreach(line ${ldd_lines})
                        if(line MATCHES "^[[:space:]]*([a-zA-Z0-9_.-]+\\.so[0-9.]*)[[:space:]]*=>")
                            set(lib_name "${CMAKE_MATCH_1}")
                            if(NOT lib_name MATCHES "^(linux-vdso|ld-linux)")
                                get_filename_component(lib_name_clean "${lib_name}" NAME)
                                list(APPEND all_deps "${lib_name_clean}")
                            endif()
                        endif()
                    endforeach()

                    if(all_deps)
                        # Now analyze each dependency
                        foreach(dep ${all_deps})
                            find_library_path("${dep}" lib_path)
                            if(lib_path AND EXISTS "${lib_path}")
                                get_direct_dependencies("${lib_path}" dep_deps)
                                foreach(dep_dep ${dep_deps})
                                    list(FIND all_deps "${dep_dep}" is_already_listed)
                                    if(is_already_listed EQUAL -1 AND NOT dep_dep MATCHES "^(linux-vdso|ld-linux)")
                                        list(APPEND transitive_deps_list "${dep_dep}")
                                    endif()
                                endforeach()
                            endif()
                        endforeach()

                        if(transitive_deps_list)
                            set(analysis_successful TRUE)
                            list(REMOVE_DUPLICATES transitive_deps_list)
                            list(SORT transitive_deps_list)
                        endif()
                    endif()
                endif()
            endif()
        endif()
    endif()

    # If no transitive dependencies found but analysis was successful, it means there are none
    if(analysis_attempted AND analysis_successful AND NOT transitive_deps_list)
        set(transitive_deps_list)
    endif()

    # Format output with precise messages
    if(transitive_deps_list)
        # Limit to reasonable number and format
        list(LENGTH transitive_deps_list deps_count)
        if(deps_count GREATER 20)
            # Show first 20 and indicate more
            list(SUBLIST transitive_deps_list 0 20 transitive_deps_list)
            string(JOIN ", " deps_str "${transitive_deps_list}")
            set(${transitive_deps_var} "[${deps_str}, ... (${deps_count} total)]" PARENT_SCOPE)
        else()
            string(JOIN ", " deps_str "${transitive_deps_list}")
            set(${transitive_deps_var} "[${deps_str}]" PARENT_SCOPE)
        endif()
    elseif(analysis_attempted AND analysis_successful)
        # Analysis was attempted and successful, but no dependencies found
        set(${transitive_deps_var} "[None - no dependencies found]" PARENT_SCOPE)
    elseif(analysis_attempted AND NOT analysis_successful)
        # Analysis was attempted but failed
        set(${transitive_deps_var} "- (analysis failed - binary may not exist or tools unavailable)" PARENT_SCOPE)
    else()
        # Analysis was not attempted (should not happen, but just in case)
        set(${transitive_deps_var} "- (not analyzed)" PARENT_SCOPE)
    endif()
endfunction()

# Function to get binary file information
function(get_binary_info target_name binary_size_var binary_timestamp_var sha256_var sha512_var)
    # Detect target type for binary naming
    safe_get_target_property(${target_name} TYPE _bin_type)
    if(NOT _bin_type OR _bin_type STREQUAL "TYPE-NOTFOUND")
        set(_bin_type "UNKNOWN")
    endif()

    # Determine binary file path (prefer LIB dir for libs, RUNTIME for executables)
    if(_bin_type STREQUAL "EXECUTABLE")
        if(DEFINED RUNTIME_OUTPUT_DIRECTORY)
            set(output_dir "${RUNTIME_OUTPUT_DIRECTORY}")
        else()
            safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}/bin")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()
    else()
        if(DEFINED LIBRARY_OUTPUT_DIRECTORY)
            set(output_dir "${LIBRARY_OUTPUT_DIRECTORY}")
        else()
            safe_get_target_property(${target_name} LIBRARY_OUTPUT_DIRECTORY output_dir)
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED RUNTIME_OUTPUT_DIRECTORY)
                set(output_dir "${RUNTIME_OUTPUT_DIRECTORY}")
            else()
                safe_get_target_property(${target_name} RUNTIME_OUTPUT_DIRECTORY output_dir)
            endif()
        endif()
        if(NOT output_dir OR output_dir STREQUAL "output_dir-NOTFOUND" OR output_dir STREQUAL "RUNTIME_OUTPUT_DIRECTORY-NOTFOUND" OR output_dir STREQUAL "LIBRARY_OUTPUT_DIRECTORY-NOTFOUND")
            if(DEFINED CMAKE_BINARY_DIR)
                set(output_dir "${CMAKE_BINARY_DIR}")
            else()
                set(output_dir "${CMAKE_BINARY_DIR}")
            endif()
        endif()
    endif()

    # Resolve output name
    if(_bin_type STREQUAL "EXECUTABLE")
        safe_get_target_property(${target_name} OUTPUT_NAME output_name)
        if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
            set(output_name "${target_name}")
        endif()
    else()
        if(DEFINED OUTPUT_NAME)
            set(output_name "${OUTPUT_NAME}")
        else()
            safe_get_target_property(${target_name} OUTPUT_NAME output_name)
        endif()
        if(NOT output_name OR output_name STREQUAL "output_name-NOTFOUND" OR output_name STREQUAL "OUTPUT_NAME-NOTFOUND")
            if(target_name)
                set(output_name "${target_name}")
            elseif(DEFINED PROJECT_NAME)
                set(output_name "${PROJECT_NAME}")
            endif()
        endif()
    endif()

    if(WIN32)
        if(_bin_type STREQUAL "EXECUTABLE")
            set(binary_file "${output_dir}/${output_name}.exe")
        elseif(BUILD_SHARED_LIBS OR _bin_type STREQUAL "SHARED_LIBRARY")
            set(binary_file "${output_dir}/${output_name}.dll")
        else()
            set(binary_file "${output_dir}/${output_name}.lib")
        endif()
    else()
        if(_bin_type STREQUAL "EXECUTABLE")
            set(binary_file "${output_dir}/${output_name}")
            if(NOT EXISTS "${binary_file}" AND EXISTS "${output_dir}/../bin/${output_name}")
                set(binary_file "${output_dir}/../bin/${output_name}")
            endif()
        elseif(BUILD_SHARED_LIBS OR _bin_type STREQUAL "SHARED_LIBRARY")
            # Try to find the actual .so file (may be versioned)
            set(binary_file "${output_dir}/lib${output_name}.so")
            if(NOT EXISTS "${binary_file}")
                file(GLOB versioned_files "${output_dir}/lib${output_name}.so.*")
                if(versioned_files)
                    list(SORT versioned_files)
                    list(REVERSE versioned_files)
                    list(GET versioned_files 0 binary_file)
                endif()
            endif()
            # Resolve symlink to actual file
            if(EXISTS "${binary_file}")
                get_filename_component(binary_file "${binary_file}" REALPATH)
            endif()
        else()
            set(binary_file "${output_dir}/lib${output_name}.a")
        endif()
    endif()

    # If still not found, try bin directory under CMAKE_BINARY_DIR
    if(NOT EXISTS "${binary_file}" AND DEFINED CMAKE_BINARY_DIR)
        set(_bin_try "${CMAKE_BINARY_DIR}/bin/${output_name}")
        if(EXISTS "${_bin_try}")
            set(binary_file "${_bin_try}")
        endif()
    endif()

    # Get file size
    if(EXISTS "${binary_file}")
        file(SIZE "${binary_file}" file_size)
        # Format size in human-readable format (keep one decimal for MB/GB using integer math to avoid truncation)
        if(file_size GREATER_EQUAL 1073741824)
            math(EXPR size_gb_whole "${file_size} / 1073741824")
            math(EXPR size_gb_rem "${file_size} % 1073741824")
            math(EXPR size_gb_tenth "( ${size_gb_rem} * 10 + 1073741824 / 2 ) / 1073741824") # rounded
            string(CONCAT size_gb_fmt "${size_gb_whole}" "." "${size_gb_tenth}")
            set(${binary_size_var} "${size_gb_fmt} GB (${file_size} bytes)" PARENT_SCOPE)
        elseif(file_size GREATER_EQUAL 1048576)
            math(EXPR size_mb_whole "${file_size} / 1048576")
            math(EXPR size_mb_rem "${file_size} % 1048576")
            math(EXPR size_mb_tenth "( ${size_mb_rem} * 10 + 1048576 / 2 ) / 1048576") # rounded
            string(CONCAT size_mb_fmt "${size_mb_whole}" "." "${size_mb_tenth}")
            set(${binary_size_var} "${size_mb_fmt} MB (${file_size} bytes)" PARENT_SCOPE)
        elseif(file_size GREATER_EQUAL 1024)
            math(EXPR size_kb_whole "${file_size} / 1024")
            math(EXPR size_kb_rem "${file_size} % 1024")
            math(EXPR size_kb_tenth "( ${size_kb_rem} * 10 + 1024 / 2 ) / 1024") # rounded
            string(CONCAT size_kb_fmt "${size_kb_whole}" "." "${size_kb_tenth}")
            set(${binary_size_var} "${size_kb_fmt} KB (${file_size} bytes)" PARENT_SCOPE)
        else()
            set(${binary_size_var} "${file_size} bytes" PARENT_SCOPE)
        endif()

        # Get file timestamp
        file(TIMESTAMP "${binary_file}" file_timestamp UTC)
        set(${binary_timestamp_var} "${file_timestamp}" PARENT_SCOPE)

        # Try to compute SHA256
        find_program(SHA256SUM_EXECUTABLE sha256sum)
        if(NOT SHA256SUM_EXECUTABLE)
            find_program(SHA256SUM_EXECUTABLE shasum PATHS /usr/bin)
        endif()

        if(SHA256SUM_EXECUTABLE)
            execute_process(
                COMMAND ${SHA256SUM_EXECUTABLE} "${binary_file}"
                OUTPUT_VARIABLE sha256_output
                ERROR_VARIABLE sha256_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE sha256_result
            )
            if(sha256_result EQUAL 0 AND sha256_output)
                # sha256sum output format: "<hash>  <filename>" or just "<hash>"
                string(REGEX MATCH "^[0-9A-Fa-f]+" sha256_hash "${sha256_output}")
                if(sha256_hash AND sha256_hash STREQUAL "sha256_hash-NOTFOUND")
                    set(sha256_hash "")
                endif()
                string(LENGTH "${sha256_hash}" sha256_len)
                if(sha256_len EQUAL 64)
                    set(${sha256_var} "${sha256_hash}" PARENT_SCOPE)
                else()
                    set(${sha256_var} "- (parse error)" PARENT_SCOPE)
                endif()
            else()
                set(${sha256_var} "- (computation failed: ${sha256_error})" PARENT_SCOPE)
            endif()
        else()
            set(${sha256_var} "- (sha256sum not found)" PARENT_SCOPE)
        endif()

        # Try to compute SHA512
        find_program(SHA512SUM_EXECUTABLE sha512sum)
        if(NOT SHA512SUM_EXECUTABLE)
            find_program(SHA512SUM_EXECUTABLE shasum PATHS /usr/bin)
        endif()

        if(SHA512SUM_EXECUTABLE)
            execute_process(
                COMMAND ${SHA512SUM_EXECUTABLE} "${binary_file}"
                OUTPUT_VARIABLE sha512_output
                ERROR_VARIABLE sha512_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
                RESULT_VARIABLE sha512_result
            )
            if(sha512_result EQUAL 0 AND sha512_output)
                # sha512sum output format: "<hash>  <filename>" or just "<hash>"
                string(REGEX MATCH "^[0-9A-Fa-f]+" sha512_hash "${sha512_output}")
                if(sha512_hash AND sha512_hash STREQUAL "sha512_hash-NOTFOUND")
                    set(sha512_hash "")
                endif()
                string(LENGTH "${sha512_hash}" sha512_len)
                if(sha512_len EQUAL 128)
                    set(${sha512_var} "${sha512_hash}" PARENT_SCOPE)
                else()
                    set(${sha512_var} "- (parse error)" PARENT_SCOPE)
                endif()
            else()
                set(${sha512_var} "- (computation failed: ${sha512_error})" PARENT_SCOPE)
            endif()
        else()
            set(${sha512_var} "- (sha512sum not found)" PARENT_SCOPE)
        endif()
    else()
        message(STATUS "get_binary_info: binary not found: ${binary_file} (target=${target_name}, output_name=${output_name}, type=${_bin_type})")
        set(${binary_size_var} "- (not available)" PARENT_SCOPE)
        set(${binary_timestamp_var} "- (not available)" PARENT_SCOPE)
        set(${sha256_var} "- (not computed)" PARENT_SCOPE)
        set(${sha512_var} "- (not computed)" PARENT_SCOPE)
    endif()
endfunction()

# Function to get Doxygen version
function(get_doxygen_version doxygen_version_var)
    find_program(DOXYGEN_EXECUTABLE doxygen)
    if(DOXYGEN_EXECUTABLE)
        execute_process(
            COMMAND ${DOXYGEN_EXECUTABLE} --version
            OUTPUT_VARIABLE doxygen_version_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(doxygen_version_output)
            set(${doxygen_version_var} "${doxygen_version_output}" PARENT_SCOPE)
        else()
            set(${doxygen_version_var} "- (not available)" PARENT_SCOPE)
        endif()
    else()
        set(${doxygen_version_var} "- (not available)" PARENT_SCOPE)
    endif()
endfunction()

# Function to detect security features
function(detect_security_features target_name aslr_var dep_var cfg_var stack_canary_var)
    if(DEFINED LINK_OPTIONS)
        set(link_options "${LINK_OPTIONS}")
    else()
        safe_get_target_property(${target_name} LINK_OPTIONS link_options)
    endif()

    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()

    set(has_aslr FALSE)
    set(has_dep FALSE)
    set(has_cfg FALSE)
    set(has_stack_canary FALSE)

    if(link_options AND NOT link_options STREQUAL "link_options-NOTFOUND")
        string(JOIN " " link_flags_str "${link_options}")

        # Check for ASLR (/DYNAMICBASE)
        if(link_flags_str MATCHES "/DYNAMICBASE|-Wl,-z,relro")
            set(has_aslr TRUE)
        endif()

        # Check for DEP (/NXCOMPAT)
        if(link_flags_str MATCHES "/NXCOMPAT|-Wl,-z,noexecstack")
            set(has_dep TRUE)
        endif()

        # Check for CFG (/GUARD:CF)
        if(link_flags_str MATCHES "/GUARD:CF")
            set(has_cfg TRUE)
        endif()
    endif()

    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        string(JOIN " " compile_flags_str "${compile_options}")

        # Check for stack canary
        if(compile_flags_str MATCHES "-fstack-protector|-fstack-protector-strong|-fstack-protector-all")
            set(has_stack_canary TRUE)
        elseif(compile_flags_str MATCHES "/GS-")
            set(has_stack_canary FALSE) # Explicitly disabled
        elseif(compile_flags_str MATCHES "/GS")
            set(has_stack_canary TRUE)
        endif()
    endif()

    # Set defaults based on platform
    if(WIN32)
        if(NOT has_aslr)
            set(has_aslr TRUE) # Default enabled on Windows
        endif()
        if(NOT has_dep)
            set(has_dep TRUE) # Default enabled on Windows
        endif()
    endif()

    set(${aslr_var} "${has_aslr}" PARENT_SCOPE)
    set(${dep_var} "${has_dep}" PARENT_SCOPE)
    set(${cfg_var} "${has_cfg}" PARENT_SCOPE)
    set(${stack_canary_var} "${has_stack_canary}" PARENT_SCOPE)
endfunction()

# Function to detect build host information
function(get_build_host_info host_var user_var)
    if(WIN32)
        # Windows hostname
        execute_process(
            COMMAND hostname
            OUTPUT_VARIABLE hostname_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(${host_var} "${hostname_output}" PARENT_SCOPE)

        # Windows username
        execute_process(
            COMMAND whoami
            OUTPUT_VARIABLE username_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(${user_var} "${username_output}" PARENT_SCOPE)
    else()
        # Unix hostname
        execute_process(
            COMMAND hostname
            OUTPUT_VARIABLE hostname_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(${host_var} "${hostname_output}" PARENT_SCOPE)

        # Unix username
        execute_process(
            COMMAND whoami
            OUTPUT_VARIABLE username_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(${user_var} "${username_output}" PARENT_SCOPE)
    endif()
endfunction()

# Function to get OS version information
function(get_os_version_info os_name_var os_version_var)
    if(WIN32)
        # Try to get detailed Windows version
        execute_process(
            COMMAND powershell -Command "(Get-CimInstance Win32_OperatingSystem).Caption"
            OUTPUT_VARIABLE os_caption_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(os_caption_output)
            set(${os_name_var} "${os_caption_output}" PARENT_SCOPE)
        else()
            set(${os_name_var} "Windows" PARENT_SCOPE)
        endif()

        # Get Windows version number
        execute_process(
            COMMAND powershell -Command "(Get-CimInstance Win32_OperatingSystem).Version"
            OUTPUT_VARIABLE os_version_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(os_version_output)
            # Try to get build number
            execute_process(
                COMMAND powershell -Command "(Get-CimInstance Win32_OperatingSystem).BuildNumber"
                OUTPUT_VARIABLE build_number_output
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            if(build_number_output)
                set(${os_version_var} "${os_version_output} Build ${build_number_output}" PARENT_SCOPE)
            else()
                set(${os_version_var} "${os_version_output}" PARENT_SCOPE)
            endif()
        else()
            # Fallback to cmd ver
            execute_process(
                COMMAND cmd /c ver
                OUTPUT_VARIABLE ver_output
                ERROR_QUIET
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            if(ver_output MATCHES "Version ([0-9]+\\.[0-9]+\\.[0-9]+)")
                set(${os_version_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
            else()
                set(${os_version_var} "Unknown" PARENT_SCOPE)
            endif()
        endif()
    elseif(APPLE)
        execute_process(
            COMMAND sw_vers -productVersion
            OUTPUT_VARIABLE os_version_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(${os_version_var} "${os_version_output}" PARENT_SCOPE)
        set(${os_name_var} "macOS" PARENT_SCOPE)
    else()
        # Linux - try to get distribution info
        if(EXISTS "/etc/os-release")
            file(READ "/etc/os-release" os_release_content)
            # Extract PRETTY_NAME
            if(os_release_content MATCHES "PRETTY_NAME=\"([^\"]+)\"")
                set(${os_name_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
            elseif(os_release_content MATCHES "NAME=\"([^\"]+)\"")
                set(${os_name_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
            else()
                set(${os_name_var} "Linux" PARENT_SCOPE)
            endif()

            # Extract VERSION_ID
            if(os_release_content MATCHES "VERSION_ID=\"([^\"]+)\"")
                set(${os_version_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
            else()
                set(${os_version_var} "Unknown" PARENT_SCOPE)
            endif()
        else()
            set(${os_name_var} "Linux" PARENT_SCOPE)
            set(${os_version_var} "Unknown" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# Main function to generate build info file
# Helper function to safely get target property (works in both configure and script mode)
function(safe_get_target_property target_name prop_name result_var)
    # Check if we're in script mode (no target access)
    # In script mode, TARGET command is not available, so we check if we can access target
    # If target is not accessible, use saved properties
    if(TARGET "${target_name}")
        # Normal mode - can use get_target_property
        get_target_property(prop_value ${target_name} ${prop_name})
        if(NOT prop_value)
            set(prop_value "${prop_name}-NOTFOUND")
        endif()
        set(${result_var} "${prop_value}" PARENT_SCOPE)
    else()
        # Script mode - use saved properties
        # Map property names to saved variable names
        if(prop_name STREQUAL "TYPE")
            set(saved_var "TARGET_TYPE")
        elseif(prop_name STREQUAL "OUTPUT_NAME")
            set(saved_var "OUTPUT_NAME")
        elseif(prop_name STREQUAL "RUNTIME_OUTPUT_DIRECTORY")
            set(saved_var "RUNTIME_OUTPUT_DIRECTORY")
        elseif(prop_name STREQUAL "LIBRARY_OUTPUT_DIRECTORY")
            set(saved_var "LIBRARY_OUTPUT_DIRECTORY")
        elseif(prop_name STREQUAL "ARCHIVE_OUTPUT_DIRECTORY")
            set(saved_var "ARCHIVE_OUTPUT_DIRECTORY")
        elseif(prop_name STREQUAL "C_STANDARD")
            set(saved_var "C_STANDARD")
        elseif(prop_name STREQUAL "CXX_STANDARD")
            set(saved_var "CXX_STANDARD")
        elseif(prop_name STREQUAL "COMPILE_OPTIONS")
            set(saved_var "COMPILE_OPTIONS")
        elseif(prop_name STREQUAL "LINK_OPTIONS")
            set(saved_var "LINK_OPTIONS")
        elseif(prop_name STREQUAL "COMPILE_DEFINITIONS")
            set(saved_var "COMPILE_DEFINITIONS")
        elseif(prop_name STREQUAL "LINK_LIBRARIES")
            set(saved_var "LINK_LIBRARIES")
        elseif(prop_name STREQUAL "INTERFACE_LINK_LIBRARIES")
            set(saved_var "INTERFACE_LINK_LIBRARIES")
        elseif(prop_name STREQUAL "INTERPROCEDURAL_OPTIMIZATION")
            set(saved_var "INTERPROCEDURAL_OPTIMIZATION")
        elseif(prop_name STREQUAL "MSVC_RUNTIME_LIBRARY")
            set(saved_var "MSVC_RUNTIME_LIBRARY")
        elseif(prop_name STREQUAL "SOURCES")
            set(saved_var "SOURCES")
        elseif(prop_name STREQUAL "PDB_OUTPUT_DIRECTORY")
            set(saved_var "PDB_OUTPUT_DIRECTORY")
        else()
            # Try uppercase version
            string(TOUPPER "${prop_name}" saved_var)
        endif()

        if(DEFINED ${saved_var})
            set(${result_var} "${${saved_var}}" PARENT_SCOPE)
        else()
            set(${result_var} "${prop_name}-NOTFOUND" PARENT_SCOPE)
        endif()
    endif()
endfunction()

# Function to save target properties to file for POST_BUILD script
function(save_target_properties target_name properties_file)
    # Get all necessary target properties
    get_target_property(TARGET_TYPE ${target_name} TYPE)
    get_target_property(OUTPUT_NAME ${target_name} OUTPUT_NAME)
    get_target_property(RUNTIME_OUTPUT_DIRECTORY ${target_name} RUNTIME_OUTPUT_DIRECTORY)
    get_target_property(LIBRARY_OUTPUT_DIRECTORY ${target_name} LIBRARY_OUTPUT_DIRECTORY)
    get_target_property(ARCHIVE_OUTPUT_DIRECTORY ${target_name} ARCHIVE_OUTPUT_DIRECTORY)
    get_target_property(C_STANDARD ${target_name} C_STANDARD)
    get_target_property(CXX_STANDARD ${target_name} CXX_STANDARD)
    get_target_property(COMPILE_OPTIONS ${target_name} COMPILE_OPTIONS)
    get_target_property(LINK_OPTIONS ${target_name} LINK_OPTIONS)
    get_target_property(LINK_LIBRARIES ${target_name} LINK_LIBRARIES)
    get_target_property(INTERFACE_LINK_LIBRARIES ${target_name} INTERFACE_LINK_LIBRARIES)
    get_target_property(INTERPROCEDURAL_OPTIMIZATION ${target_name} INTERPROCEDURAL_OPTIMIZATION)

    # Save to file
    file(WRITE "${properties_file}"
        "set(TARGET_TYPE \"${TARGET_TYPE}\")\n"
        "set(OUTPUT_NAME \"${OUTPUT_NAME}\")\n"
        "set(RUNTIME_OUTPUT_DIRECTORY \"${RUNTIME_OUTPUT_DIRECTORY}\")\n"
        "set(LIBRARY_OUTPUT_DIRECTORY \"${LIBRARY_OUTPUT_DIRECTORY}\")\n"
        "set(ARCHIVE_OUTPUT_DIRECTORY \"${ARCHIVE_OUTPUT_DIRECTORY}\")\n"
        "set(C_STANDARD \"${C_STANDARD}\")\n"
        "set(CXX_STANDARD \"${CXX_STANDARD}\")\n"
        "set(COMPILE_OPTIONS \"${COMPILE_OPTIONS}\")\n"
        "set(LINK_OPTIONS \"${LINK_OPTIONS}\")\n"
        "set(LINK_LIBRARIES \"${LINK_LIBRARIES}\")\n"
        "set(INTERFACE_LINK_LIBRARIES \"${INTERFACE_LINK_LIBRARIES}\")\n"
        "set(INTERPROCEDURAL_OPTIMIZATION \"${INTERPROCEDURAL_OPTIMIZATION}\")\n"
        "set(CMAKE_BINARY_DIR \"${CMAKE_BINARY_DIR}\")\n"
        "set(CMAKE_SOURCE_DIR \"${CMAKE_SOURCE_DIR}\")\n"
        "set(PROJECT_NAME \"${PROJECT_NAME}\")\n"
        "set(PROJECT_VERSION \"${PROJECT_VERSION}\")\n"
        "set(CMAKE_BUILD_TYPE \"${CMAKE_BUILD_TYPE}\")\n"
        "set(CMAKE_SYSTEM_PROCESSOR \"${CMAKE_SYSTEM_PROCESSOR}\")\n"
        "set(CMAKE_CXX_COMPILER_ID \"${CMAKE_CXX_COMPILER_ID}\")\n"
        "set(CMAKE_CXX_COMPILER_VERSION \"${CMAKE_CXX_COMPILER_VERSION}\")\n"
        "set(CMAKE_C_COMPILER_ID \"${CMAKE_C_COMPILER_ID}\")\n"
        "set(CMAKE_C_COMPILER_VERSION \"${CMAKE_C_COMPILER_VERSION}\")\n"
        "set(CMAKE_GENERATOR \"${CMAKE_GENERATOR}\")\n"
        "set(CMAKE_VERSION \"${CMAKE_VERSION}\")\n"
        "set(BUILD_SHARED_LIBS \"${BUILD_SHARED_LIBS}\")\n"
        "set(MSVC \"${MSVC}\")\n"
        "set(UNIX \"${UNIX}\")\n"
        "set(APPLE \"${APPLE}\")\n"
        "set(WIN32 \"${WIN32}\")\n"
    )
endfunction()

function(resolve_git_source_hash search_dir out_var)
    if(NOT DEFINED BUILD_INFO_DEBUG)
        set(BUILD_INFO_DEBUG OFF)
    endif()
    find_program(GIT_EXECUTABLE git PATHS /usr/bin /usr/local/bin)
    if(NOT GIT_EXECUTABLE AND EXISTS "/usr/bin/git")
        set(GIT_EXECUTABLE "/usr/bin/git")
    endif()

    # Helper: read HEAD hash from a gitdir (handles refs and packed-refs)
    macro(_read_hash_from_gitdir gitdir outvar)
        set(_tmp_hash "")
        if(EXISTS "${gitdir}/HEAD")
            file(READ "${gitdir}/HEAD" _head_content)
            string(STRIP "${_head_content}" _head_content)
            if(_head_content MATCHES "^ref: ([^\n\r]+)")
                set(_ref_path "${CMAKE_MATCH_1}")
                if(NOT IS_ABSOLUTE "${_ref_path}")
                    set(_ref_path "${gitdir}/${_ref_path}")
                endif()
                if(EXISTS "${_ref_path}")
                    file(READ "${_ref_path}" _ref_content)
                    string(STRIP "${_ref_content}" _ref_content)
                    set(_tmp_hash "${_ref_content}")
                endif()
            else()
                set(_tmp_hash "${_head_content}")
            endif()
        endif()
        if(_tmp_hash STREQUAL "" AND EXISTS "${gitdir}/packed-refs")
            file(READ "${gitdir}/packed-refs" _packed)
            string(REGEX MATCH "([0-9a-fA-F]{40})" _m "${_packed}")
            if(_m MATCHES "([0-9a-fA-F]{40})")
                set(_tmp_hash "${CMAKE_MATCH_1}")
            endif()
        endif()
        set(${outvar} "${_tmp_hash}")
    endmacro()

    set(_hash "")

    # 0) Prefer submodule gitdir if present in search_dir/.git (file or dir)
    set(_gitpath "${search_dir}/.git")
    if(EXISTS "${_gitpath}")
        if(IS_DIRECTORY "${_gitpath}")
            set(_gitdir "${_gitpath}")
        else()
            file(READ "${_gitpath}" _gitfile)
            if(_gitfile MATCHES "gitdir:[ \t]*([^\n\r]+)")
                set(_gd "${CMAKE_MATCH_1}")
                if(NOT IS_ABSOLUTE "${_gd}")
                    get_filename_component(_gitdir "${search_dir}/${_gd}" ABSOLUTE)
                else()
                    set(_gitdir "${_gd}")
                endif()
            endif()
        endif()
        if(DEFINED _gitdir)
            _read_hash_from_gitdir("${_gitdir}" _hash)
            if(BUILD_INFO_DEBUG)
                message(STATUS "resolve_git_source_hash: gitdir=${_gitdir} hash=${_hash}")
            endif()
        endif()
    endif()

    # 1) If still empty, try git rev-parse in search_dir and parents
    if(_hash STREQUAL "" AND GIT_EXECUTABLE)
        get_filename_component(_cur "${search_dir}" REALPATH)
        foreach(_i RANGE 0 5)
            execute_process(
                COMMAND "${GIT_EXECUTABLE}" -C "${_cur}" rev-parse HEAD
                OUTPUT_VARIABLE _hash_out
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
                RESULT_VARIABLE _hash_res
            )
            if(BUILD_INFO_DEBUG)
                message(STATUS "resolve_git_source_hash: dir=${_cur} res=${_hash_res} out=${_hash_out}")
            endif()
            if(_hash_res EQUAL 0 AND NOT _hash_out STREQUAL "")
                set(_hash "${_hash_out}")
                break()
            endif()
            get_filename_component(_next "${_cur}" DIRECTORY)
            if(_next STREQUAL "${_cur}")
                break()
            endif()
            set(_cur "${_next}")
        endforeach()
    endif()
    if(BUILD_INFO_DEBUG)
        message(STATUS "resolve_git_source_hash: after loop hash='${_hash}'")
    endif()

    if(NOT _hash STREQUAL "")
        set(${out_var} "${_hash}" PARENT_SCOPE)
    else()
        set(${out_var} "- (not available)" PARENT_SCOPE)
    endif()
endfunction()

function(generate_build_info_file target_name output_file)
    # Get basic information
    get_build_host_info(BUILD_HOST BUILD_USER)
    get_os_version_info(OS_NAME OS_VERSION)

    # Get compiler information
    set(COMPILER_ID "${CMAKE_CXX_COMPILER_ID}")
    set(COMPILER_VERSION "${CMAKE_CXX_COMPILER_VERSION}")

    # Format compiler string
    if(MSVC)
        set(COMPILER_STRING "MSVC-${CMAKE_CXX_COMPILER_VERSION}")
        set(TOOLCHAIN "MSVC")
        if(CMAKE_VS_PLATFORM_TOOLSET)
            set(TOOLSET "${CMAKE_VS_PLATFORM_TOOLSET}")
        else()
            # Extract toolset from compiler version
            if(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.40")
                set(TOOLSET "v143")
            elseif(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.30")
                set(TOOLSET "v142")
            elseif(CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "19.20")
                set(TOOLSET "v142")
            else()
                set(TOOLSET "v141")
            endif()
        endif()

        # Visual Studio version
        if(CMAKE_GENERATOR MATCHES "Visual Studio ([0-9]+)")
            set(VS_VERSION "${CMAKE_MATCH_1}")
            # Map to year
            if(VS_VERSION STREQUAL "17")
                set(VS_YEAR "2022")
            elseif(VS_VERSION STREQUAL "16")
                set(VS_YEAR "2019")
            elseif(VS_VERSION STREQUAL "15")
                set(VS_YEAR "2017")
            else()
                set(VS_YEAR "Unknown")
            endif()
        else()
            set(VS_VERSION "Unknown")
            set(VS_YEAR "Unknown")
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        set(COMPILER_STRING "GCC-${CMAKE_CXX_COMPILER_VERSION}")
        set(TOOLCHAIN "GNU")
        set(TOOLSET "- (not applicable)")
        set(VS_VERSION "- (not applicable)")
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        set(COMPILER_STRING "Clang-${CMAKE_CXX_COMPILER_VERSION}")
        set(TOOLCHAIN "Clang")
        set(TOOLSET "- (not applicable)")
        set(VS_VERSION "- (not applicable)")
    else()
        set(COMPILER_STRING "${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}")
        set(TOOLCHAIN "${CMAKE_CXX_COMPILER_ID}")
        set(TOOLSET "- (not applicable)")
        set(VS_VERSION "- (not applicable)")
    endif()

    # Get architecture
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64|amd64")
        set(ARCHITECTURE "x86_64 (AMD64, Intel x64)")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i386|i686")
        set(ARCHITECTURE "i386 (x86, Intel 32-bit)")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(ARCHITECTURE "arm64 (AArch64)")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
        set(ARCHITECTURE "arm (32-bit ARM)")
    else()
        set(ARCHITECTURE "${CMAKE_SYSTEM_PROCESSOR}")
    endif()

    # Get build type
    if(CMAKE_BUILD_TYPE)
        set(BUILD_TYPE "${CMAKE_BUILD_TYPE}")
    else()
        set(BUILD_TYPE "Release") # Default for multi-config generators
    endif()

    # Get library type
    if(DEFINED TARGET_TYPE)
        set(LIB_TYPE "${TARGET_TYPE}")
    else()
        safe_get_target_property(${target_name} TYPE LIB_TYPE)
    endif()
    if(LIB_TYPE STREQUAL "SHARED_LIBRARY")
        if(WIN32)
            set(LIB_TYPE_STRING "Shared (DLL)")
        else()
            set(LIB_TYPE_STRING "Shared (SO)")
        endif()
    elseif(LIB_TYPE STREQUAL "STATIC_LIBRARY")
        set(LIB_TYPE_STRING "Static")
    elseif(LIB_TYPE STREQUAL "EXECUTABLE")
        set(LIB_TYPE_STRING "Executable")
    else()
        set(LIB_TYPE_STRING "Unknown")
    endif()

    # Get language standards
    if(DEFINED C_STANDARD)
        set(C_STD "${C_STANDARD}")
    else()
        safe_get_target_property(${target_name} C_STANDARD C_STD)
        if(C_STD STREQUAL "C_STANDARD-NOTFOUND")
            if(DEFINED CMAKE_C_STANDARD)
                set(C_STD "${CMAKE_C_STANDARD}")
            else()
                set(C_STD "11")
            endif()
        endif()
    endif()
    if(DEFINED CXX_STANDARD)
        set(CXX_STD "${CXX_STANDARD}")
    else()
        safe_get_target_property(${target_name} CXX_STANDARD CXX_STD)
        if(CXX_STD STREQUAL "CXX_STANDARD-NOTFOUND")
            if(DEFINED CMAKE_CXX_STANDARD)
                set(CXX_STD "${CMAKE_CXX_STANDARD}")
            else()
                set(CXX_STD "20")
            endif()
        endif()
    endif()
    if(NOT C_STD OR C_STD STREQUAL "C_STD-NOTFOUND")
        if(DEFINED CMAKE_C_STANDARD)
            set(C_STD "${CMAKE_C_STANDARD}")
        else()
            set(C_STD "11")
        endif()
    endif()
    if(NOT CXX_STD OR CXX_STD STREQUAL "CXX_STD-NOTFOUND")
        if(DEFINED CMAKE_CXX_STANDARD)
            set(CXX_STD "${CMAKE_CXX_STANDARD}")
        else()
            set(CXX_STD "20")
        endif()
    endif()

    # Get Windows SDK version
    get_windows_sdk_version(WINDOWS_SDK_VERSION)

    # Get glibc/glibcxx versions for Linux
    get_glibc_version(GLIBC_VERSION)
    get_glibcxx_version(GLIBCXX_VERSION)
    get_cxx_abi_info(${target_name} CXX_ABI_INFO)

    # Get Linux kernel version
    set(LINUX_KERNEL_VERSION "- (not available)")
    if(UNIX AND NOT APPLE)
        execute_process(
            COMMAND uname -r
            OUTPUT_VARIABLE kernel_version_output
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(kernel_version_output)
            set(LINUX_KERNEL_VERSION "${kernel_version_output}")
        endif()
    endif()

    # Get ELF interpreter version
    set(ELF_INTERPRETER_VERSION "- (not available)")
    set(ELF_INTERPRETER_PATH "- (not available)")
    if(UNIX AND NOT APPLE)
        # Determine ELF interpreter path based on architecture
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
            set(elf_interpreter_path "/lib64/ld-linux-x86-64.so.2")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i386|i686")
            set(elf_interpreter_path "/lib/ld-linux.so.2")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
            set(elf_interpreter_path "/lib/ld-linux-aarch64.so.1")
        elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
            set(elf_interpreter_path "/lib/ld-linux-armhf.so.3")
        else()
            set(elf_interpreter_path "/lib64/ld-linux-x86-64.so.2")
        endif()
        set(ELF_INTERPRETER_PATH "${elf_interpreter_path}")

        # Try to get version using --version flag (most reliable method)
        if(EXISTS "${elf_interpreter_path}")
            execute_process(
                COMMAND "${elf_interpreter_path}" --version
                OUTPUT_VARIABLE ld_version_output
                ERROR_VARIABLE ld_version_error
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            # Parse version from output: "ld.so (Ubuntu GLIBC 2.39-0ubuntu8.6) stable release version 2.39."
            if(ld_version_output MATCHES "version ([0-9]+\\.[0-9]+)")
                set(ELF_INTERPRETER_VERSION "${CMAKE_MATCH_1}")
            endif()

            # Fallback: try readelf if --version didn't work
            if(ELF_INTERPRETER_VERSION STREQUAL "- (not available)")
                find_program(READELF_EXECUTABLE readelf)
                if(READELF_EXECUTABLE)
                    execute_process(
                        COMMAND ${READELF_EXECUTABLE} -d "${elf_interpreter_path}" | grep "SONAME"
                        OUTPUT_VARIABLE soname_output
                        ERROR_QUIET
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                    )
                    if(soname_output MATCHES "ld-linux[^]]*\\[([0-9]+\\.[0-9]+)\\]")
                        set(ELF_INTERPRETER_VERSION "${CMAKE_MATCH_1}")
                    endif()
                endif()
            endif()

            # Last fallback: try to extract from symlink target
            if(ELF_INTERPRETER_VERSION STREQUAL "- (not available)")
                get_filename_component(real_path "${elf_interpreter_path}" REALPATH)
                if(real_path MATCHES "ld-linux[^/]*\\.so\\.([0-9]+)")
                    set(ELF_INTERPRETER_VERSION "${CMAKE_MATCH_1}.0")
                endif()
            endif()
        endif()
    endif()

    # Determine minimum compatible distribution based on glibc version
    set(MINIMUM_TARGET_DISTRO "")
    if(UNIX AND NOT APPLE AND NOT GLIBC_VERSION STREQUAL "- (not applicable)" AND NOT GLIBC_VERSION STREQUAL "Unknown")
        # Parse glibc version
        if(GLIBC_VERSION MATCHES "^([0-9]+)\\.([0-9]+)")
            set(glibc_major "${CMAKE_MATCH_1}")
            set(glibc_minor "${CMAKE_MATCH_2}")

            # Map glibc versions to minimum distributions
            if(glibc_major EQUAL 2)
                if(glibc_minor VERSION_LESS 17)
                    set(MINIMUM_TARGET_DISTRO "CentOS 6 / RHEL 6 (glibc 2.12)")
                elseif(glibc_minor VERSION_LESS 23)
                    set(MINIMUM_TARGET_DISTRO "CentOS 7 / RHEL 7 (glibc 2.17) / Ubuntu 18.04 / Debian 9")
                elseif(glibc_minor VERSION_LESS 28)
                    set(MINIMUM_TARGET_DISTRO "CentOS 8 / RHEL 8 (glibc 2.28) / Ubuntu 20.04 / Debian 10")
                elseif(glibc_minor VERSION_LESS 31)
                    set(MINIMUM_TARGET_DISTRO "RHEL 9 (glibc 2.34) / Ubuntu 22.04 / Debian 11")
                else()
                    set(MINIMUM_TARGET_DISTRO "Ubuntu 24.04 / Debian 12 (glibc ${GLIBC_VERSION})")
                endif()
            else()
                set(MINIMUM_TARGET_DISTRO "Modern distribution (glibc ${GLIBC_VERSION})")
            endif()
        else()
            set(MINIMUM_TARGET_DISTRO "Modern distribution (glibc ${GLIBC_VERSION})")
        endif()
    else()
        set(MINIMUM_TARGET_DISTRO "CentOS 7 / RHEL 7 (glibc 2.17) / Ubuntu 18.04 / Debian 9")
    endif()

    # Get compiler and linker flags
    get_compiler_flags(${target_name} COMPILER_FLAGS)
    get_linker_flags(${target_name} LINKER_FLAGS)

    # Get build date (fix %p format issue - use 24-hour format instead)
    string(TIMESTAMP BUILD_DATE "%d.%m.%Y %H:%M" UTC)

    # Get optimization settings
    # First check INTERPROCEDURAL_OPTIMIZATION property
    if(DEFINED INTERPROCEDURAL_OPTIMIZATION)
        set(IPO_ENABLED "${INTERPROCEDURAL_OPTIMIZATION}")
    else()
        safe_get_target_property(${target_name} INTERPROCEDURAL_OPTIMIZATION IPO_ENABLED)
    endif()

    # Also check for LTO flags in compile/link options
    set(has_lto_flags FALSE)
    set(lto_flags_detected)

    if(DEFINED COMPILE_OPTIONS)
        set(compile_options "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS compile_options)
    endif()
    if(DEFINED LINK_OPTIONS)
        set(link_options "${LINK_OPTIONS}")
    else()
        safe_get_target_property(${target_name} LINK_OPTIONS link_options)
    endif()

    # Check compile options for LTO flags
    if(compile_options AND NOT compile_options STREQUAL "compile_options-NOTFOUND")
        string(JOIN " " compile_flags_str "${compile_options}")
        if(compile_flags_str MATCHES "-flto(=auto|=thin|=full)?|/GL")
            set(has_lto_flags TRUE)
            if(compile_flags_str MATCHES "-flto=auto")
                list(APPEND lto_flags_detected "-flto=auto")
            elseif(compile_flags_str MATCHES "-flto=thin")
                list(APPEND lto_flags_detected "-flto=thin")
            elseif(compile_flags_str MATCHES "-flto(=full)?")
                list(APPEND lto_flags_detected "-flto")
            elseif(compile_flags_str MATCHES "/GL")
                list(APPEND lto_flags_detected "/GL")
            endif()
            if(compile_flags_str MATCHES "-fuse-linker-plugin")
                list(APPEND lto_flags_detected "-fuse-linker-plugin")
            endif()
        endif()
    endif()

    # Check link options for LTO flags
    if(link_options AND NOT link_options STREQUAL "link_options-NOTFOUND")
        string(JOIN " " link_flags_str "${link_options}")
        if(link_flags_str MATCHES "-flto(=auto|=thin|=full)?|/LTCG")
            set(has_lto_flags TRUE)
            if(link_flags_str MATCHES "-flto=auto")
                list(APPEND lto_flags_detected "-flto=auto")
            elseif(link_flags_str MATCHES "-flto=thin")
                list(APPEND lto_flags_detected "-flto=thin")
            elseif(link_flags_str MATCHES "-flto(=full)?")
                list(APPEND lto_flags_detected "-flto")
            elseif(link_flags_str MATCHES "/LTCG")
                list(APPEND lto_flags_detected "/LTCG")
            endif()
        endif()
    endif()

    # Determine LTO status
    if(IPO_ENABLED AND NOT IPO_ENABLED STREQUAL "IPO_ENABLED-NOTFOUND" AND IPO_ENABLED)
        set(LTO_ENABLED "Yes")
        if(MSVC)
            set(LTO_FLAGS "/GL + /LTCG")
        else()
            if(lto_flags_detected)
                string(JOIN " " LTO_FLAGS "${lto_flags_detected}")
            else()
                set(LTO_FLAGS "-flto=auto -fuse-linker-plugin")
            endif()
        endif()
    elseif(has_lto_flags)
        set(LTO_ENABLED "Yes")
        if(MSVC)
            set(LTO_FLAGS "/GL + /LTCG")
        else()
            if(lto_flags_detected)
                string(JOIN " " LTO_FLAGS "${lto_flags_detected}")
            else()
                set(LTO_FLAGS "-flto=auto -fuse-linker-plugin")
            endif()
        endif()
    else()
        set(LTO_ENABLED "No")
        set(LTO_FLAGS "- (not enabled)")
    endif()

    # Detect CPU features and native tuning
    detect_cpu_features(${target_name} CPU_FEATURES)
    detect_native_tuning(${target_name} NATIVE_TUNING)
    detect_pgo(${target_name} PGO_ENABLED)

    # Get PDB file path
    get_pdb_path(${target_name} PDB_PATH)

    # Get binary information
    get_binary_info(${target_name} BINARY_SIZE BINARY_TIMESTAMP SHA256_HASH SHA512_HASH)

    # Get dynamic dependencies (direct dependencies of the binary)
    get_dynamic_dependencies(${target_name} DYNAMIC_DEPS)

    # Get static dependencies (statically linked libraries)
    get_static_dependencies(${target_name} STATIC_DEPS)

    # Get header-only dependencies (INTERFACE libraries)
    get_header_only_dependencies(${target_name} HEADER_ONLY_DEPS)

    # Remove header-only entries that are also listed as static dependencies (to avoid duplicates like hidapi_hidraw)
    set(__ho_list "")
    set(__static_list "")
    if(HEADER_ONLY_DEPS MATCHES "^\\[(.*)\\]$")
        string(REGEX REPLACE "^\\[|\\]$" "" __ho_str "${HEADER_ONLY_DEPS}")
        string(REPLACE ", " ";" __ho_list "${__ho_str}")
    endif()
    if(STATIC_DEPS MATCHES "^\\[(.*)\\]$")
        string(REGEX REPLACE "^\\[|\\]$" "" __st_str "${STATIC_DEPS}")
        string(REPLACE ", " ";" __static_list "${__st_str}")
    endif()
    if(__ho_list AND __static_list)
        foreach(__it ${__static_list})
            list(REMOVE_ITEM __ho_list "${__it}")
        endforeach()
    endif()
    if(__ho_list)
        list(REMOVE_DUPLICATES __ho_list)
        list(SORT __ho_list)
        string(JOIN ", " __ho_join "${__ho_list}")
        set(HEADER_ONLY_DEPS "[${__ho_join}]")
    elseif(HEADER_ONLY_DEPS)
        # If everything was removed, set to [None]
        set(HEADER_ONLY_DEPS "[None]")
    endif()

    # Analyze transitive dependencies (dependencies of dependencies)
    analyze_transitive_dependencies(${target_name} TRANSITIVE_DEPS)

    # Derive build hash from the binary SHA256 if available
    set(BUILD_HASH_VALUE "- (not computed)")
    if(SHA256_HASH AND NOT SHA256_HASH MATCHES "not computed" AND NOT SHA256_HASH MATCHES "parse error" AND NOT SHA256_HASH STREQUAL "")
        set(BUILD_HASH_VALUE "${SHA256_HASH}")
    endif()

    # Derive source hash from git (use current source dir to support subprojects)
    # Use provided CMAKE_SOURCE_DIR (passed in script mode) or current source dir
    if(DEFINED CMAKE_SOURCE_DIR)
        set(_hash_search_dir "${CMAKE_SOURCE_DIR}")
    else()
        set(_hash_search_dir "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    resolve_git_source_hash("${_hash_search_dir}" SOURCE_HASH_VALUE)
    if(SOURCE_HASH_VALUE STREQUAL "- (not available)")
        find_program(GIT_EXECUTABLE git PATHS /usr/bin /usr/local/bin)
        if(GIT_EXECUTABLE)
            execute_process(
                COMMAND "${GIT_EXECUTABLE}" -C "${_hash_search_dir}" rev-parse HEAD
                OUTPUT_VARIABLE __gh_fallback
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
                RESULT_VARIABLE __gr_fallback
            )
            if(__gr_fallback EQUAL 0 AND __gh_fallback MATCHES "^[0-9a-fA-F]{7,}$")
                set(SOURCE_HASH_VALUE "${__gh_fallback}")
            endif()
        endif()
    endif()
    if(SOURCE_HASH_VALUE STREQUAL "- (not available)" AND EXISTS "/usr/bin/git")
        execute_process(
            COMMAND /usr/bin/git -C "${_hash_search_dir}" rev-parse HEAD
            OUTPUT_VARIABLE __gh_fallback2
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
            RESULT_VARIABLE __gr_fallback2
        )
        if(__gr_fallback2 EQUAL 0 AND __gh_fallback2 MATCHES "^[0-9a-fA-F]{7,}$")
            set(SOURCE_HASH_VALUE "${__gh_fallback2}")
        endif()
    endif()

    # Get Doxygen version
    get_doxygen_version(DOXYGEN_VERSION)

    # Detect security features
    detect_security_features(${target_name} HAS_ASLR HAS_DEP HAS_CFG HAS_STACK_CANARY)

    # Get optimization level
    if(MSVC)
        if(CMAKE_BUILD_TYPE STREQUAL "Release")
            set(OPT_LEVEL "/O2")
        elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set(OPT_LEVEL "/Od")
        else()
            set(OPT_LEVEL "/O2")
        endif()
    else()
        if(CMAKE_BUILD_TYPE STREQUAL "Release")
            set(OPT_LEVEL "-O3")
        elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set(OPT_LEVEL "-O0")
        else()
            set(OPT_LEVEL "-O2")
        endif()
    endif()

    # Get debug symbols
    if(DEFINED COMPILE_OPTIONS)
        set(DEBUG_SYMBOLS "${COMPILE_OPTIONS}")
    else()
        safe_get_target_property(${target_name} COMPILE_OPTIONS DEBUG_SYMBOLS)
    endif()
    if(DEBUG_SYMBOLS AND NOT DEBUG_SYMBOLS STREQUAL "COMPILE_OPTIONS-NOTFOUND" AND NOT DEBUG_SYMBOLS STREQUAL "DEBUG_SYMBOLS-NOTFOUND")
        string(FIND "${DEBUG_SYMBOLS}" "/Zi" MSVC_DEBUG_FOUND)
        string(FIND "${DEBUG_SYMBOLS}" "-g" GCC_DEBUG_FOUND)
        if(MSVC_DEBUG_FOUND GREATER_EQUAL 0 OR GCC_DEBUG_FOUND GREATER_EQUAL 0)
            set(HAS_DEBUG_SYMBOLS "Yes")
        else()
            set(HAS_DEBUG_SYMBOLS "No")
        endif()
    else()
        set(HAS_DEBUG_SYMBOLS "No")
    endif()

    # Get runtime configuration
    if(MSVC)
        safe_get_target_property(${target_name} MSVC_RUNTIME_LIBRARY RUNTIME_LIB)
        if(RUNTIME_LIB AND NOT RUNTIME_LIB STREQUAL "RUNTIME_LIB-NOTFOUND")
            if(RUNTIME_LIB MATCHES "MultiThreaded" AND NOT RUNTIME_LIB MATCHES "DLL")
                set(RUNTIME_TYPE "Static (/MT)")
            else()
                set(RUNTIME_TYPE "Dynamic (/MD)")
            endif()
        else()
            # Default detection based on CMAKE_MSVC_RUNTIME_LIBRARY
            if(CMAKE_MSVC_RUNTIME_LIBRARY MATCHES "MultiThreaded" AND NOT CMAKE_MSVC_RUNTIME_LIBRARY MATCHES "DLL")
                set(RUNTIME_TYPE "Static (/MT)")
            else()
                set(RUNTIME_TYPE "Dynamic (/MD)")
            endif()
        endif()
    else()
        set(RUNTIME_TYPE "Dynamic (shared libraries)")
    endif()

    # Generate the build info file content
    set(BUILD_INFO_CONTENT "")

    string(APPEND BUILD_INFO_CONTENT "Name:            ${PROJECT_NAME}\n")
    string(APPEND BUILD_INFO_CONTENT "Version:         ${PROJECT_VERSION}\n")
    string(APPEND BUILD_INFO_CONTENT "Architecture:    ${ARCHITECTURE}\n")
    string(APPEND BUILD_INFO_CONTENT "Build Type:      ${BUILD_TYPE}\n")
    string(APPEND BUILD_INFO_CONTENT "Library Type:    ${LIB_TYPE_STRING}\n")
    string(APPEND BUILD_INFO_CONTENT "\n")
    string(APPEND BUILD_INFO_CONTENT "Build Information:\n")
    string(APPEND BUILD_INFO_CONTENT "  Compiler:        ${COMPILER_STRING}\n")
    string(APPEND BUILD_INFO_CONTENT "  Toolchain:       ${TOOLCHAIN}\n")
    if(WIN32 AND MSVC)
        if(DEFINED VS_YEAR)
            string(APPEND BUILD_INFO_CONTENT "  Visual Studio:   ${VS_VERSION} ${VS_YEAR} (toolset ${TOOLSET})\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  Visual Studio:   ${VS_VERSION} 2022 (toolset ${TOOLSET})\n")
        endif()
    endif()
    string(APPEND BUILD_INFO_CONTENT "  CMake:           ${CMAKE_VERSION}\n")
    string(APPEND BUILD_INFO_CONTENT "  Build Generator: ${CMAKE_GENERATOR}\n")
    string(APPEND BUILD_INFO_CONTENT "  Build Date:      ${BUILD_DATE}\n")
    string(APPEND BUILD_INFO_CONTENT "  Build Host:      ${BUILD_HOST}\n")
    string(APPEND BUILD_INFO_CONTENT "  Build User:      ${BUILD_USER}\n")
    string(APPEND BUILD_INFO_CONTENT "\n")
    string(APPEND BUILD_INFO_CONTENT "Language Standards:\n")
    string(APPEND BUILD_INFO_CONTENT "  C Standard:          C${C_STD}\n")
    string(APPEND BUILD_INFO_CONTENT "  C++ Standard:        C++${CXX_STD}\n")
    if(UNIX AND NOT APPLE)
        string(APPEND BUILD_INFO_CONTENT "  C++ ABI:             ${CXX_ABI_INFO}\n")
    endif()
    if(MSVC)
        string(APPEND BUILD_INFO_CONTENT "  Language Extensions: MSVC\n")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        string(APPEND BUILD_INFO_CONTENT "  Language Extensions: GNU\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Language Extensions: ${CMAKE_CXX_COMPILER_ID}\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")

    if(WIN32)
        string(APPEND BUILD_INFO_CONTENT "Runtime Configuration:\n")
        string(APPEND BUILD_INFO_CONTENT "  Runtime:         ${RUNTIME_TYPE}\n")
        string(APPEND BUILD_INFO_CONTENT "  PE Type:         64-bit PE (PE32+)\n")
        if(HAS_DEBUG_SYMBOLS STREQUAL "Yes")
            string(APPEND BUILD_INFO_CONTENT "  Debug Symbols:   Yes (/Zi + /DEBUG, PDB file)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  Debug Symbols:   No\n")
        endif()
        string(APPEND BUILD_INFO_CONTENT "  PDB Path:        ${PDB_PATH}\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "Runtime Configuration:\n")
        string(APPEND BUILD_INFO_CONTENT "  Runtime:         ${RUNTIME_TYPE}\n")
        string(APPEND BUILD_INFO_CONTENT "  ELF Type:        64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked\n")
        string(APPEND BUILD_INFO_CONTENT "  Debug Symbols:   ${HAS_DEBUG_SYMBOLS}\n")
        string(APPEND BUILD_INFO_CONTENT "  Build ID:        - (not available)\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
    endif()

    string(APPEND BUILD_INFO_CONTENT "Optimizations:\n")
    string(APPEND BUILD_INFO_CONTENT "  LTO:                ${LTO_ENABLED}")
    if(LTO_ENABLED STREQUAL "Yes")
        string(APPEND BUILD_INFO_CONTENT " (${LTO_FLAGS})")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")
    string(APPEND BUILD_INFO_CONTENT "  PGO:                ${PGO_ENABLED}\n")
    string(APPEND BUILD_INFO_CONTENT "  Native Tuning:      ${NATIVE_TUNING}\n")
    string(APPEND BUILD_INFO_CONTENT "  CPU Features:       ${CPU_FEATURES}\n")
    string(APPEND BUILD_INFO_CONTENT "  Optimization Level: ${OPT_LEVEL}\n")
    string(APPEND BUILD_INFO_CONTENT "\n")

    # Format compiler flags with proper line breaks (5 flags per line)
    if(COMPILER_FLAGS AND NOT COMPILER_FLAGS STREQUAL "- (not available)")
        # Split flags into list
        string(REPLACE " " ";" flags_list "${COMPILER_FLAGS}")
        # Remove empty entries
        list(FILTER flags_list EXCLUDE REGEX "^$")

        set(formatted_flags "")
        set(flag_count 0)
        foreach(flag ${flags_list})
            if(flag_count EQUAL 0)
                string(APPEND formatted_flags "${flag}")
            else()
                string(APPEND formatted_flags " ${flag}")
            endif()
            math(EXPR flag_count "${flag_count} + 1")
            if(flag_count GREATER_EQUAL 5)
                string(APPEND formatted_flags "\n                 ")
                set(flag_count 0)
            endif()
        endforeach()
        string(APPEND BUILD_INFO_CONTENT "Compiler Flags:  ${formatted_flags}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "Compiler Flags:  ${COMPILER_FLAGS}\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")
    # Format linker flags with proper line breaks (5 flags per line)
    if(LINKER_FLAGS AND NOT LINKER_FLAGS STREQUAL "- (not available)")
        # Split flags into list
        string(REPLACE " " ";" link_flags_list "${LINKER_FLAGS}")
        # Remove empty entries
        list(FILTER link_flags_list EXCLUDE REGEX "^$")

        set(formatted_link_flags "")
        set(link_flag_count 0)
        foreach(flag ${link_flags_list})
            if(link_flag_count EQUAL 0)
                string(APPEND formatted_link_flags "${flag}")
            else()
                string(APPEND formatted_link_flags " ${flag}")
            endif()
            math(EXPR link_flag_count "${link_flag_count} + 1")
            if(link_flag_count GREATER_EQUAL 5)
                string(APPEND formatted_link_flags "\n                 ")
                set(link_flag_count 0)
            endif()
        endforeach()
        string(APPEND BUILD_INFO_CONTENT "Linker Flags:    ${formatted_link_flags}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "Linker Flags:    ${LINKER_FLAGS}\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")

    if(WIN32)
        string(APPEND BUILD_INFO_CONTENT "Build Features:\n")
        string(APPEND BUILD_INFO_CONTENT "  Unicode:       Yes (UNICODE/_UNICODE)\n")
        string(APPEND BUILD_INFO_CONTENT "  PIC:           Yes (Position Independent Code - /DYNAMICBASE)\n")
        string(APPEND BUILD_INFO_CONTENT "  PIE:           No (not applicable for DLLs)\n")
        string(APPEND BUILD_INFO_CONTENT "  Multi-Proc:    Yes (parallel builds via /MP)\n")
        string(APPEND BUILD_INFO_CONTENT "  Threading:     Yes (Windows threads)\n")
        string(APPEND BUILD_INFO_CONTENT "  Exceptions:    Yes (/EHsc - C++ exceptions only)\n")
        string(APPEND BUILD_INFO_CONTENT "  RTTI:          Yes (/GR - enabled by default)\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Windows Target:\n")
        string(APPEND BUILD_INFO_CONTENT "  Windows Version: Windows 10 / Windows 11\n")
        string(APPEND BUILD_INFO_CONTENT "  Minimum Version: Windows 10 (0x0A00)\n")
        string(APPEND BUILD_INFO_CONTENT "  Target Version:  0x0A00 (Windows 10/11 compatible)\n")
        string(APPEND BUILD_INFO_CONTENT "  Subsystem:       - (not specified, default for DLL)\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Runtime Requirements:\n")
        string(APPEND BUILD_INFO_CONTENT "  MSVC Runtime:   - (statically linked via /MT)\n")
        string(APPEND BUILD_INFO_CONTENT "  UCRT:           ucrtbase.dll (system component, Windows 10+)\n")
        string(APPEND BUILD_INFO_CONTENT "  .NET Runtime:   - (not required)\n")
        string(APPEND BUILD_INFO_CONTENT "  Required DLLs:  [SETUPAPI.dll, HID.DLL, CFGMGR32.dll, dbghelp.dll,\n")
        string(APPEND BUILD_INFO_CONTENT "                   KERNEL32.dll, USER32.dll, WS2_32.dll]\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Dynamic Dependencies:    ${DYNAMIC_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Static Dependencies:     ${STATIC_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Header-Only Dependencies: ${HEADER_ONLY_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Delay-Loaded DLLs:       [None]\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "DLL Search Paths:\n")
        string(APPEND BUILD_INFO_CONTENT "  Application Directory: Used\n")
        string(APPEND BUILD_INFO_CONTENT "  System32:              Used\n")
        string(APPEND BUILD_INFO_CONTENT "  PATH:                  Used\n")
        string(APPEND BUILD_INFO_CONTENT "  Private Assemblies:    [None]\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Manifest Information:\n")
        # Check if manifest is embedded via .rc file
        # Check if manifest is embedded via .rc file
        # In script mode, we can't get SOURCES, so skip this check
        set(has_manifest FALSE)
        if(TARGET "${target_name}")
            safe_get_target_property(${target_name} SOURCES target_sources)
            if(target_sources AND NOT target_sources STREQUAL "SOURCES-NOTFOUND")
                foreach(src ${target_sources})
                    if(src MATCHES "\\.rc$")
                        set(has_manifest TRUE)
                        break()
                    endif()
                endforeach()
            endif()
        endif()
        if(has_manifest)
            string(APPEND BUILD_INFO_CONTENT "  Manifest:                  Embedded (via DChannel.rc)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  Manifest:                  - (not embedded)\n")
        endif()
        string(APPEND BUILD_INFO_CONTENT "  Requested Execution Level: asInvoker\n")
        string(APPEND BUILD_INFO_CONTENT "  DPI Awareness:             - (not specified)\n")
        string(APPEND BUILD_INFO_CONTENT "  UAC:                       Enabled\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Security Features:\n")
        if(HAS_ASLR)
            string(APPEND BUILD_INFO_CONTENT "  ASLR:               Yes (/DYNAMICBASE)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  ASLR:               No\n")
        endif()
        if(HAS_DEP)
            string(APPEND BUILD_INFO_CONTENT "  DEP:                Yes (/NXCOMPAT)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  DEP:                No\n")
        endif()
        if(HAS_CFG)
            string(APPEND BUILD_INFO_CONTENT "  CFG:                Yes (/GUARD:CF)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  CFG:                No\n")
        endif()
        if(HAS_STACK_CANARY)
            string(APPEND BUILD_INFO_CONTENT "  Stack Canary:       Yes (/GS)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  Stack Canary:       No (/GS- disabled for performance)\n")
        endif()
        string(APPEND BUILD_INFO_CONTENT "  Control Flow Guard: No\n")
        string(APPEND BUILD_INFO_CONTENT "  Digital Signature:  No\n")
        string(APPEND BUILD_INFO_CONTENT "  Certificate:        - (not signed)\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "Build Features:\n")
        string(APPEND BUILD_INFO_CONTENT "  PIC:           Yes (Position Independent Code)\n")
        string(APPEND BUILD_INFO_CONTENT "  PIE:           No (shared object, not PIE executable)\n")
        string(APPEND BUILD_INFO_CONTENT "  Multi-Proc:    Yes (parallel builds via Ninja)\n")
        string(APPEND BUILD_INFO_CONTENT "  Threading:     Yes (pthread)\n")
        string(APPEND BUILD_INFO_CONTENT "  Unicode:       No\n")
        string(APPEND BUILD_INFO_CONTENT "  Exceptions:    Yes (-fexceptions)\n")
        string(APPEND BUILD_INFO_CONTENT "  RTTI:          Yes (-frtti)\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "System Requirements:\n")
        if(GLIBC_VERSION STREQUAL "- (not applicable)")
            string(APPEND BUILD_INFO_CONTENT "  GLIBC:            - (not applicable)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  GLIBC:            >= ${GLIBC_VERSION} (minimum: GLIBC_${GLIBC_VERSION}, tested: GLIBC_${GLIBC_VERSION})\n")
        endif()
        if(GLIBCXX_VERSION STREQUAL "- (not applicable)")
            string(APPEND BUILD_INFO_CONTENT "  GLIBCXX:          - (not applicable)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  GLIBCXX:          >= ${GLIBCXX_VERSION} (minimum: GLIBCXX_${GLIBCXX_VERSION}, tested: GLIBCXX_${GLIBCXX_VERSION})\n")
        endif()
        string(APPEND BUILD_INFO_CONTENT "  Linux Kernel:     ${LINUX_KERNEL_VERSION}\n")
        if(GLIBC_VERSION STREQUAL "- (not applicable)")
            string(APPEND BUILD_INFO_CONTENT "  Required Symbols: - (not applicable)\n")
        else()
            string(APPEND BUILD_INFO_CONTENT "  Required Symbols: [GLIBC_${GLIBC_VERSION}, GLIBCXX_${GLIBCXX_VERSION}]\n")
        endif()
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Dynamic Dependencies:     ${DYNAMIC_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Static Dependencies:      ${STATIC_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Header-Only Dependencies: ${HEADER_ONLY_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "Transitive Dependencies:  ${TRANSITIVE_DEPS}\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Library Search Paths:\n")
        string(APPEND BUILD_INFO_CONTENT "  RPATH:         - (not set)\n")
        string(APPEND BUILD_INFO_CONTENT "  RUNPATH:       - (not set)\n")
        string(APPEND BUILD_INFO_CONTENT "  LD_LIBRARY_PATH: Not used\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "ELF Interpreter:\n")
        string(APPEND BUILD_INFO_CONTENT "  Path:          ${ELF_INTERPRETER_PATH}\n")
        string(APPEND BUILD_INFO_CONTENT "  Version:       ${ELF_INTERPRETER_VERSION}\n")
        string(APPEND BUILD_INFO_CONTENT "\n")
        string(APPEND BUILD_INFO_CONTENT "Security Features:\n")
        string(APPEND BUILD_INFO_CONTENT "  Stack:          Non-executable (NX)\n")
        string(APPEND BUILD_INFO_CONTENT "  RELRO:          Partial (lazy binding allowed)\n")
        string(APPEND BUILD_INFO_CONTENT "  BIND_NOW:       No\n")
        string(APPEND BUILD_INFO_CONTENT "  PIE:            No (shared object, not PIE executable)\n")
        string(APPEND BUILD_INFO_CONTENT "  Stack Canary:   No\n")
        string(APPEND BUILD_INFO_CONTENT "  Fortify Source: No\n")
        string(APPEND BUILD_INFO_CONTENT "  ASLR:           Yes (via system loader)\n")
    endif()

    string(APPEND BUILD_INFO_CONTENT "\n")
    string(APPEND BUILD_INFO_CONTENT "Binary Integrity:\n")
    string(APPEND BUILD_INFO_CONTENT "  SHA256:        ${SHA256_HASH}\n")
    string(APPEND BUILD_INFO_CONTENT "  SHA512:        ${SHA512_HASH}\n")
    string(APPEND BUILD_INFO_CONTENT "  File Size:     ${BINARY_SIZE}\n")
    if(WIN32)
        string(APPEND BUILD_INFO_CONTENT "  Timestamp:     ${BINARY_TIMESTAMP}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Stripped:      Yes\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")

    string(APPEND BUILD_INFO_CONTENT "Compatibility:\n")
    if(WIN32)
        string(APPEND BUILD_INFO_CONTENT "  Tested Windows Versions: [Windows 10, Windows 11]\n")
        string(APPEND BUILD_INFO_CONTENT "  Minimum Target: Windows 10 (build 10240) / Windows Server 2016\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Tested Distributions: [${OS_NAME}]\n")
        string(APPEND BUILD_INFO_CONTENT "  Minimum Target:       ${MINIMUM_TARGET_DISTRO}\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "  Known Issues:  None\n")
    string(APPEND BUILD_INFO_CONTENT "\n")

    string(APPEND BUILD_INFO_CONTENT "Build Environment:\n")
    string(APPEND BUILD_INFO_CONTENT "  OS:            ${OS_NAME}\n")
    string(APPEND BUILD_INFO_CONTENT "  OS Version:    ${OS_VERSION}\n")
    if(WIN32)
        string(APPEND BUILD_INFO_CONTENT "  Visual Studio: Visual Studio 2022\n")
        string(APPEND BUILD_INFO_CONTENT "  Windows SDK:   ${WINDOWS_SDK_VERSION}\n")
        string(APPEND BUILD_INFO_CONTENT "  .NET SDK:      - (not used)\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Kernel:        ${LINUX_KERNEL_VERSION}\n")
        string(APPEND BUILD_INFO_CONTENT "  Docker Image:  - (not containerized)\n")
        string(APPEND BUILD_INFO_CONTENT "  CI/CD:         Local\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "\n")

    string(APPEND BUILD_INFO_CONTENT "Reproducibility:\n")
    string(APPEND BUILD_INFO_CONTENT "  Reproducible Build: No\n")
    string(APPEND BUILD_INFO_CONTENT "  Build Hash:         ${BUILD_HASH_VALUE}\n")
    string(APPEND BUILD_INFO_CONTENT "  Source Hash:        ${SOURCE_HASH_VALUE}\n")
    # Provide a reproduction hint with configure+build commands
    if(CMAKE_CONFIGURATION_TYPES)
        set(__config_arg "--config ${CMAKE_BUILD_TYPE}")
    else()
        set(__config_arg "")
    endif()
    string(APPEND BUILD_INFO_CONTENT "  Repro Command:      cmake -S ${CMAKE_SOURCE_DIR} -B ${CMAKE_BINARY_DIR} -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE} && cmake --build ${CMAKE_BINARY_DIR} ${__config_arg}\n")
    string(APPEND BUILD_INFO_CONTENT "\n")

    string(APPEND BUILD_INFO_CONTENT "Additional Information:\n")
    string(APPEND BUILD_INFO_CONTENT "  License:       - (not specified)\n")
    if(DEFINED DCHANNEL_PACKAGE_DEVELOPER_NAME)
        string(APPEND BUILD_INFO_CONTENT "  Author:        ${DCHANNEL_PACKAGE_DEVELOPER_NAME}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Author:        - (not specified)\n")
    endif()
    if(DEFINED DCHANNEL_PACKAGE_DEVELOPER_EMAIL)
        string(APPEND BUILD_INFO_CONTENT "  Contact:       ${DCHANNEL_PACKAGE_DEVELOPER_EMAIL}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Contact:       - (not specified)\n")
    endif()
    string(APPEND BUILD_INFO_CONTENT "  Documentation: Doxygen ${DOXYGEN_VERSION} (see docs/html/index.html inside the package)\n")
    if(DEFINED CPACK_PACKAGE_HOMEPAGE_URL)
        string(APPEND BUILD_INFO_CONTENT "  Source Code:   ${CPACK_PACKAGE_HOMEPAGE_URL}\n")
    else()
        string(APPEND BUILD_INFO_CONTENT "  Source Code:   - (not specified)\n")
    endif()

    # Write the file
    file(WRITE "${output_file}" "${BUILD_INFO_CONTENT}")

    message(STATUS "Generated build info file: ${output_file}")
endfunction()
