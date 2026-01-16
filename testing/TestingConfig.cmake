# =============================================================================
# TestingConfig.cmake
# Universal testing framework configuration for C/C++ projects
# =============================================================================
#
# This module provides universal functions to configure testing frameworks
# (Google Test, Catch2, Boost.Test) and integrate them with CTest.
#
# Functions:
#   configure_testing(
#     [FRAMEWORK <framework>]
#     [ENABLE_TESTING <ON|OFF>]
#     [GOOGLETEST_GIT_REPOSITORY <url>]
#     [GOOGLETEST_GIT_TAG <tag>]
#     [CATCH2_GIT_REPOSITORY <url>]
#     [CATCH2_GIT_TAG <tag>]
#   )
#   add_test_executable(<target> [SOURCES <sources...>] [FRAMEWORK <framework>])
#   discover_tests(<target> [FRAMEWORK <framework>])
#
# Usage:
#   include(TestingConfig)
#   configure_testing(FRAMEWORK GOOGLETEST)
#   add_test_executable(MyTests SOURCES test_main.cpp test_foo.cpp FRAMEWORK GOOGLETEST)
#   discover_tests(MyTests)
#
# =============================================================================

# =============================================================================
# Function: configure_testing
#
# Configures testing infrastructure for the project.
#
# Parameters:
#   FRAMEWORK <framework> - Testing framework (GOOGLETEST|CATCH2|BOOST_TEST|NONE)
#                           Default: GOOGLETEST
#   ENABLE_TESTING <on>   - Enable CTest. Default: ON
#   GOOGLETEST_GIT_REPOSITORY <url> - Custom Git repository for GoogleTest
#                                     Default: https://github.com/google/googletest.git
#   GOOGLETEST_GIT_TAG <tag> - Custom Git tag for GoogleTest. Default: v1.14.0
#   CATCH2_GIT_REPOSITORY <url> - Custom Git repository for Catch2
#                                  Default: https://github.com/catchorg/Catch2.git
#   CATCH2_GIT_TAG <tag> - Custom Git tag for Catch2. Default: v3.5.0
#
# Usage:
#   # Use defaults
#   configure_testing(FRAMEWORK GOOGLETEST)
#
#   # Use custom repository and tag
#   configure_testing(FRAMEWORK GOOGLETEST GOOGLETEST_GIT_REPOSITORY https://github.com/myorg/googletest.git GOOGLETEST_GIT_TAG v1.13.0)
# =============================================================================
function(configure_testing)
  # Parse arguments
  set(options "")
  set(oneValueArgs FRAMEWORK ENABLE_TESTING GOOGLETEST_GIT_REPOSITORY GOOGLETEST_GIT_TAG CATCH2_GIT_REPOSITORY CATCH2_GIT_TAG)
  set(multiValueArgs "")
  cmake_parse_arguments(TEST_CONFIG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Set default framework
  if(NOT TEST_CONFIG_FRAMEWORK)
    set(TEST_CONFIG_FRAMEWORK "GOOGLETEST")
  endif()

  # Enable testing
  if(NOT DEFINED TEST_CONFIG_ENABLE_TESTING)
    set(TEST_CONFIG_ENABLE_TESTING ON)
  endif()

  if(TEST_CONFIG_ENABLE_TESTING)
    enable_testing()
    include(CTest)
  endif()

  # Configure framework
  if(TEST_CONFIG_FRAMEWORK STREQUAL "GOOGLETEST")
    _configure_googletest("${TEST_CONFIG_GOOGLETEST_GIT_REPOSITORY}" "${TEST_CONFIG_GOOGLETEST_GIT_TAG}")
  elseif(TEST_CONFIG_FRAMEWORK STREQUAL "CATCH2")
    _configure_catch2("${TEST_CONFIG_CATCH2_GIT_REPOSITORY}" "${TEST_CONFIG_CATCH2_GIT_TAG}")
  elseif(TEST_CONFIG_FRAMEWORK STREQUAL "BOOST_TEST")
    _configure_boost_test()
  elseif(TEST_CONFIG_FRAMEWORK STREQUAL "NONE")
    message(STATUS "TestingConfig: No testing framework configured")
  else()
    message(WARNING "TestingConfig: Unknown framework '${TEST_CONFIG_FRAMEWORK}', defaulting to GOOGLETEST")
    _configure_googletest("${TEST_CONFIG_GOOGLETEST_GIT_REPOSITORY}" "${TEST_CONFIG_GOOGLETEST_GIT_TAG}")
  endif()

  # Export framework choice
  set(TESTING_FRAMEWORK "${TEST_CONFIG_FRAMEWORK}" PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _configure_googletest
# =============================================================================
function(_configure_googletest)
  # Try to find GTest
  find_package(GTest QUIET)

  if(NOT GTest_FOUND)
    # Use FetchContent to get GoogleTest
    include(FetchContent)
    FetchContent_Declare(
      googletest
      GIT_REPOSITORY https://github.com/google/googletest.git
      GIT_TAG v1.14.0
      GIT_SHALLOW TRUE
    )
    FetchContent_MakeAvailable(googletest)
    message(STATUS "TestingConfig: GoogleTest fetched via FetchContent")
  else()
    message(STATUS "TestingConfig: GoogleTest found via find_package")
  endif()

  set(TESTING_FRAMEWORK_GOOGLETEST TRUE PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _configure_catch2
# =============================================================================
function(_configure_catch2 git_repo git_tag)
  # Set defaults
  if(NOT git_repo)
    set(git_repo "https://github.com/catchorg/Catch2.git")
  endif()
  if(NOT git_tag)
    set(git_tag "v3.5.0")
  endif()

  # Try to find Catch2
  find_package(Catch2 QUIET)

  if(NOT Catch2_FOUND)
    # Use FetchContent to get Catch2
    include(FetchContent)
    FetchContent_Declare(
      catch2
      GIT_REPOSITORY ${git_repo}
      GIT_TAG ${git_tag}
      GIT_SHALLOW TRUE
    )
    FetchContent_MakeAvailable(catch2)
    message(STATUS "TestingConfig: Catch2 fetched via FetchContent from ${git_repo} (${git_tag})")
  else()
    message(STATUS "TestingConfig: Catch2 found via find_package")
  endif()

  set(TESTING_FRAMEWORK_CATCH2 TRUE PARENT_SCOPE)
endfunction()

# =============================================================================
# Internal function: _configure_boost_test
# =============================================================================
function(_configure_boost_test)
  # Try to find Boost.Test
  find_package(Boost QUIET COMPONENTS unit_test_framework)

  if(NOT Boost_FOUND)
    message(WARNING "TestingConfig: Boost.Test not found. Please install Boost or set Boost_ROOT")
  else()
    message(STATUS "TestingConfig: Boost.Test found")
  endif()

  set(TESTING_FRAMEWORK_BOOST_TEST TRUE PARENT_SCOPE)
endfunction()

# =============================================================================
# Function: add_test_executable
#
# Creates a test executable target with the specified testing framework.
#
# Parameters:
#   <target>          - Target name (required)
#   SOURCES <...>     - Source files for the test executable
#   FRAMEWORK <fw>    - Testing framework (GOOGLETEST|CATCH2|BOOST_TEST|NONE)
#                       Default: Use framework from configure_testing()
#   LINK_LIBRARIES <...> - Additional libraries to link
#
# Usage:
#   add_test_executable(MyTests SOURCES test_main.cpp test_foo.cpp)
#   add_test_executable(MyTests SOURCES test_main.cpp FRAMEWORK CATCH2)
# =============================================================================
function(add_test_executable target)
  # Parse arguments
  set(options "")
  set(oneValueArgs FRAMEWORK)
  set(multiValueArgs SOURCES LINK_LIBRARIES)
  cmake_parse_arguments(TEST_EXE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT TEST_EXE_SOURCES)
    message(FATAL_ERROR "TestingConfig: add_test_executable requires SOURCES parameter")
  endif()

  # Determine framework
  if(TEST_EXE_FRAMEWORK)
    set(test_framework "${TEST_EXE_FRAMEWORK}")
  elseif(TESTING_FRAMEWORK)
    set(test_framework "${TESTING_FRAMEWORK}")
  else()
    set(test_framework "GOOGLETEST")
    message(STATUS "TestingConfig: No framework specified, defaulting to GOOGLETEST")
  endif()

  # Create executable
  add_executable(${target} ${TEST_EXE_SOURCES})

  # Link testing framework
  if(test_framework STREQUAL "GOOGLETEST")
    if(TARGET gtest_main)
      target_link_libraries(${target} PRIVATE gtest_main gtest)
    elseif(TARGET GTest::gtest_main)
      target_link_libraries(${target} PRIVATE GTest::gtest_main GTest::gtest)
    else()
      message(FATAL_ERROR "TestingConfig: GoogleTest not available. Call configure_testing(FRAMEWORK GOOGLETEST) first")
    endif()
  elseif(test_framework STREQUAL "CATCH2")
    if(TARGET Catch2::Catch2)
      target_link_libraries(${target} PRIVATE Catch2::Catch2)
    elseif(TARGET Catch2::Catch2WithMain)
      target_link_libraries(${target} PRIVATE Catch2::Catch2WithMain)
    else()
      message(FATAL_ERROR "TestingConfig: Catch2 not available. Call configure_testing(FRAMEWORK CATCH2) first")
    endif()
  elseif(test_framework STREQUAL "BOOST_TEST")
    if(TARGET Boost::unit_test_framework)
      target_link_libraries(${target} PRIVATE Boost::unit_test_framework)
    else()
      message(FATAL_ERROR "TestingConfig: Boost.Test not available. Install Boost or call configure_testing(FRAMEWORK BOOST_TEST)")
    endif()
  endif()

  # Link additional libraries
  if(TEST_EXE_LINK_LIBRARIES)
    target_link_libraries(${target} PRIVATE ${TEST_EXE_LINK_LIBRARIES})
  endif()

  message(STATUS "TestingConfig: Test executable '${target}' created with framework '${test_framework}'")
endfunction()

# =============================================================================
# Function: discover_tests
#
# Discovers and registers tests from a test executable.
#
# Parameters:
#   <target>          - Test executable target name (required)
#   FRAMEWORK <fw>     - Testing framework (GOOGLETEST|CATCH2|BOOST_TEST)
#                       Default: Use framework from configure_testing()
#   LABELS <...>       - Test labels
#   TIMEOUT <seconds>  - Test timeout in seconds
#
# Usage:
#   discover_tests(MyTests)
#   discover_tests(MyTests FRAMEWORK CATCH2 LABELS unit TIMEOUT 30)
# =============================================================================
function(discover_tests target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "TestingConfig: Target '${target}' does not exist")
  endif()

  # Parse arguments
  set(options "")
  set(oneValueArgs FRAMEWORK TIMEOUT)
  set(multiValueArgs LABELS)
  cmake_parse_arguments(TEST_DISCOVER "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Determine framework
  if(TEST_DISCOVER_FRAMEWORK)
    set(test_framework "${TEST_DISCOVER_FRAMEWORK}")
  elseif(TESTING_FRAMEWORK)
    set(test_framework "${TESTING_FRAMEWORK}")
  else()
    set(test_framework "GOOGLETEST")
  endif()

  # Discover tests based on framework
  if(test_framework STREQUAL "GOOGLETEST")
    include(GoogleTest)
    gtest_discover_tests(${target})
  elseif(test_framework STREQUAL "CATCH2")
    include(Catch)
    catch_discover_tests(${target})
  elseif(test_framework STREQUAL "BOOST_TEST")
    # Boost.Test doesn't have automatic discovery, add manual test
    add_test(NAME ${target} COMMAND ${target})
  else()
    # Generic test registration
    add_test(NAME ${target} COMMAND ${target})
  endif()

  # Set test properties
  if(TEST_DISCOVER_TIMEOUT)
    set_tests_properties(${target} PROPERTIES TIMEOUT ${TEST_DISCOVER_TIMEOUT})
  endif()

  if(TEST_DISCOVER_LABELS)
    set_tests_properties(${target} PROPERTIES LABELS "${TEST_DISCOVER_LABELS}")
  endif()

  message(STATUS "TestingConfig: Tests discovered for '${target}' using framework '${test_framework}'")
endfunction()
