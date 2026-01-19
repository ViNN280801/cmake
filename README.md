# Universal CMake Utilities

A collection of universal, reusable CMake functions and modules designed to simplify cross-platform C/C++ project configuration. This repository provides production-ready CMake utilities that work seamlessly across Windows, Linux, and macOS with support for MSVC, GCC, Clang, and Intel ICC compilers.

## Goals and Objectives

This repository aims to:

- **Eliminate boilerplate code**: Provide ready-to-use functions for common CMake tasks
- **Ensure cross-platform compatibility**: Support all major platforms and compilers out of the box
- **Promote best practices**: Implement industry-standard configurations for warnings, optimizations, testing, and deployment
- **Simplify project setup**: Enable developers to configure complex build systems with minimal effort
- **Maintain consistency**: Standardize build configurations across multiple projects

## Repository Structure

```console
cmake/
├── 3rdparty/          # Third-party library integration
├── analysis/          # Static analysis and code quality
├── core/              # Core compiler and linker configuration
├── cpp_specific/      # C++-specific features (modules, etc.)
├── dependencies/      # Dependency management
├── deployment/        # Installation, packaging, and deployment
├── optimizations/     # Performance optimizations
├── testing/           # Testing frameworks and tools
└── utils/             # Utility functions and helpers
```

## Modules Overview

### Core Configuration (`core/`)

#### `CompilerFlags.cmake`

Universal compiler flags configuration for all C/C++ compilers.

**Functions:**

- `configure_compiler_flags(<target> [STANDARD <c++_standard>] [WARNINGS <level>] ...)`

**Features:**

- C++ standard selection (C++11 through C++26)
- Configurable warning levels (OFF, LOW, MEDIUM, HIGH, PEDANTIC)
- Compiler-specific flags (MSVC, GCC, Clang, Intel)
- Cross-platform UTF-8 support

#### `LinkerFlags.cmake`

Universal linker flags configuration with LTO support.

**Functions:**

- `configure_linker_flags(<target> [LTO <ON|OFF>] [EXTRA_FLAGS <flags...>] ...)`

**Features:**

- Link-Time Optimization (LTO) configuration
- Compiler-specific linker flags
- Cross-platform symbol visibility

#### `VersionConfig.cmake`

Project version management and configuration.

**Functions:**

- `configure_version([VERSION <version>] [MAJOR <n>] [MINOR <n>] ...)`

**Features:**

- Semantic versioning support
- Automatic version generation from Git tags
- Version header generation

#### `WindowsVersionConfig.cmake`

Windows-specific version configuration and API targeting.

**Functions:**

- `configure_windows_version([TARGET_VERSION <version>] [WIN32_WINNT <value>] ...)`

**Features:**

- Windows API version targeting
- `WIN32_WINNT` and `NTDDI_VERSION` configuration
- Windows SDK version detection

### C++-Specific Features (`cpp_specific/`)

#### `CppModulesConfig.cmake`

C++20 modules support configuration.

**Functions:**

- `configure_modules(<target> [ENABLE <ON|OFF>] [MODULE_DIR <directory>] ...)`
- `add_module(<target> <module_name> [SOURCES <sources...>] [INTERFACE])`

**Features:**

- C++20 modules support for MSVC, GCC, and Clang
- Header units configuration
- Automatic dependency scanning
- Module interface and implementation management

### Optimizations (`optimizations/`)

#### `HardwareOptimization.cmake`

Hardware-specific optimization configuration.

**Functions:**

- `configure_hardware_optimization(<target> [OPTIMIZATIONS <opt1> <opt2> ...] ...)`

**Features:**

- SIMD instruction sets (SSE, AVX, AVX2, AVX-512)
- CPU architecture targeting (march, mtune)
- Floating-point optimization modes (FAST, STRICT, PRECISE)
- Automatic optimization detection and application
- Compiler-specific optimization flags

#### `PGOConfig.cmake`

Profile-Guided Optimization (PGO) configuration.

**Functions:**

- `configure_pgo(<target> [ENABLE <ON|OFF>] [INSTRUMENT <ON|OFF>] ...)`

**Features:**

- PGO instrumentation and optimization
- Profile data collection
- Compiler-specific PGO flags (MSVC `/GL`, GCC `-fprofile-use`)

#### `PrecompiledHeadersConfig.cmake`

Precompiled headers (PCH) configuration.

**Functions:**

- `configure_precompiled_headers(<target> [HEADER <header>] [REUSE_FROM <target>] ...)`

**Features:**

- Precompiled header generation
- PCH reuse across targets
- Compiler-specific PCH support

#### `UnityBuildConfig.cmake`

Unity builds configuration for faster compilation.

**Functions:**

- `configure_unity_build(<target> [ENABLE <ON|OFF>] [BATCH_SIZE <n>] ...)`

**Features:**

- Source file batching
- Configurable batch sizes
- Compiler-specific unity build flags

### Testing (`testing/`)

#### `TestingConfig.cmake`

Testing framework configuration and integration.

**Functions:**

- `configure_testing([FRAMEWORK <framework>] [ENABLE_TESTING <ON|OFF>])`
- `add_test_executable(<target> [SOURCES <sources...>] [FRAMEWORK <framework>])`
- `discover_tests(<target> [FRAMEWORK <framework>])`

**Features:**

- Google Test integration
- Catch2 support
- Boost.Test support
- Automatic test discovery
- CTest integration

#### `SanitizersConfig.cmake`

Sanitizer configuration for runtime error detection.

**Functions:**

- `configure_sanitizers(<target> [ASAN <ON|OFF>] [MSAN <ON|OFF>] ...)`

**Features:**

- AddressSanitizer (ASan)
- MemorySanitizer (MSan)
- ThreadSanitizer (TSan)
- UndefinedBehaviorSanitizer (UBSan)
- LeakSanitizer (LSan)

#### `CoverageConfig.cmake`

Code coverage configuration.

**Functions:**

- `configure_coverage(<target> [ENABLE <ON|OFF>] [FORMAT <format>] ...)`

**Features:**

- GCC/Clang coverage flags (`--coverage`, `-fprofile-arcs`)
- MSVC coverage support
- Coverage report generation

### Analysis (`analysis/`)

#### `StaticAnalysisConfig.cmake`

Static analysis tool configuration.

**Functions:**

- `configure_static_analysis(<target> [CLANG_TIDY <ON|OFF>] [CPPCHECK <ON|OFF>] ...)`

**Features:**

- clang-tidy integration
- cppcheck integration
- Configurable check options
- Analysis report generation

### Dependencies (`dependencies/`)

#### `DependenciesConfig.cmake`

Universal dependency management.

**Functions:**

- `add_dependency(<name> [METHOD <FETCH|FIND|SYSTEM>] [GIT_REPOSITORY <url>] ...)`

**Features:**

- FetchContent integration
- `find_package` wrapper
- System package detection
- Component-based dependencies
- Version management

### Deployment (`deployment/`)

#### `InstallConfig.cmake`

Installation rules configuration.

**Functions:**

- `configure_install_rules(<target> [EXECUTABLE_DEST <dir>] [LIBRARY_DEST <dir>] ...)`

**Features:**

- Executable installation
- Library installation (shared/static)
- Header installation
- Documentation installation
- CMake package configuration

#### `PackageConfig.cmake`

CPack packaging configuration.

**Functions:**

- `configure_packaging([GENERATORS <generators...>] [COMPONENTS <components...>] ...)`

**Features:**

- Multiple package generators (NSIS, DEB, RPM, ZIP, TGZ, etc.)
- Component-based packaging
- Cross-platform package creation
- Installer customization

#### `BuildInfoPrinter.cmake`

Build information printing utility.

**Functions:**

- `print_build_info()`

**Features:**

- Compiler information
- Build configuration summary
- Platform detection
- Feature flags status

### Third-Party Integration (`3rdparty/`)

#### `BoostConfig.cmake`

Universal Boost C++ Libraries integration for CMake projects.

**Functions:**

- `add_boost_dependency([METHOD <FETCH|FIND|SYSTEM>] [VERSION <version>] [COMPONENTS <components...>] ...)`
- `link_boost_to_target(<target> [COMPONENTS <components...>] [INTERFACE_TARGET <target_name>])`

**Features:**

- Multiple integration methods (FetchContent, find_package, system packages)
- Configurable Boost version and components
- Automatic component linking
- Cross-platform support
- Flexible build options (shared/static libraries, testing)

**Usage:**

```cmake
include(cmake/3rdparty/BoostConfig)
add_boost_dependency(
    METHOD FETCH
    VERSION "1.84.0"
    COMPONENTS system filesystem thread chrono
    BUILD_SHARED_LIBS ON
)
link_boost_to_target(MyTarget COMPONENTS system filesystem)
```

#### `QtDeployment.cmake`

Qt framework deployment for Windows.

**Functions:**

- `find_windeployqt([CUSTOM_PATH <path>])`
- `deploy_qt_dependencies(<target> [QML_DIR <dir>] [RELEASE_ONLY <ON|OFF>] ...)`

**Features:**

- Qt DLL deployment
- Qt plugin deployment
- Windows-specific Qt deployment
- `windeployqt` integration

### Utilities (`utils/`)

#### `WarningSuppression.cmake`

Warning suppression configuration.

**Functions:**

- `suppress_warnings(<target> [KEEP <warning1> <warning2> ...])`

**Features:**

- Suppress all warnings or all except specified
- MSVC warning code support (numeric codes)
- GCC/Clang warning name support
- Intel ICC warning code support
- Dynamic warning code generation

#### `CompileCommandsConfig.cmake`

`compile_commands.json` generation for language servers.

**Functions:**

- `configure_compile_commands([ENABLE <ON|OFF>] [OUTPUT_DIR <dir>] ...)`

**Features:**

- Automatic `compile_commands.json` generation
- Cross-platform symlink/copy support
- Language server integration (clangd, etc.)

#### `GenerateBuildInfo.cmake`

Build information generation.

**Functions:**

- `generate_build_info([OUTPUT_FILE <file>] [INCLUDE_GIT_INFO <ON|OFF>] ...)`

**Features:**

- Build timestamp generation
- Git information integration
- Version information embedding
- Build configuration details

#### `GenerateBuildInfoScript.cmake`

Build information script generation.

**Functions:**

- `generate_build_info_script([OUTPUT_FILE <file>] ...)`

**Features:**

- Build script generation
- Cross-platform script support
- Build metadata extraction

#### `RecursiveSourceCollection.cmake`

Universal recursive source file collection for C/C++ projects.

**Functions:**

- `collect_sources_recursive(<dir> <result_var> [EXCLUDE_DIRS <dirs...>] [EXCLUDE_PATTERNS <patterns...>] [INCLUDE_EXAMPLES <ON|OFF>] [INCLUDE_TESTS <ON|OFF>] [EXTENSIONS <exts...>])`
- `collect_sources_recursive_multiple(<result_var> DIRS <dirs...> [EXCLUDE_DIRS <dirs...>] ...)`

**Features:**

- Recursive file discovery without hardcoding file names
- Configurable exclusion patterns (directories, file patterns)
- Optional inclusion of examples and tests
- Support for multiple file extensions (cpp, hpp, c, h, etc.)
- Flexible filtering options

**Usage:**

```cmake
include(cmake/utils/RecursiveSourceCollection)

# Collect sources from a single directory
collect_sources_recursive("${CMAKE_SOURCE_DIR}/src/api" API_SOURCES
    EXCLUDE_DIRS "3rdparty" "tests"
    INCLUDE_EXAMPLES OFF
    INCLUDE_TESTS OFF
    EXTENSIONS "cpp" "hpp"
)

# Collect sources from multiple directories
collect_sources_recursive_multiple(ALL_SOURCES
    DIRS
        "${CMAKE_SOURCE_DIR}/src/api"
        "${CMAKE_SOURCE_DIR}/src/core"
    EXCLUDE_DIRS "3rdparty" "tests" "test"
    INCLUDE_EXAMPLES ${BUILD_EXAMPLES}
    INCLUDE_TESTS OFF
    EXTENSIONS "cpp" "hpp"
)
```

#### `LibraryVersioning.cmake`

Universal library versioning and vendor metadata for shared libraries.

**Functions:**

- `apply_library_versioning(<TARGET_NAME> [LIBRARY_DESCRIPTION <desc>] [PROJECT_VERSION <version>] [VENDOR_NAME <name>] [VENDOR_EMAIL <email>] [VENDOR_COMPANY <company>] [COPYRIGHT_YEAR <year>] ...)`

**Features:**

- Automatic version embedding in shared libraries (.dll, .so)
- Windows version resource file generation
- Linux library versioning (SOVERSION, VERSION)
- Vendor metadata embedding (company, author, contact)
- Copyright information
- Cross-platform support

**Usage:**

```cmake
include(cmake/utils/LibraryVersioning)

apply_library_versioning(
    TARGET_NAME MyLibrary
    LIBRARY_DESCRIPTION "My Awesome Library"
    PROJECT_VERSION "1.2.3"
    VENDOR_NAME "John Doe"
    VENDOR_EMAIL "john@example.com"
    VENDOR_COMPANY "My Company Ltd."
    COPYRIGHT_YEAR "2025"
)
```

## Usage Example

```cmake
cmake_minimum_required(VERSION 3.16)
project(MyProject VERSION 1.0.0)

# Include CMake utilities
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")

# Core configuration
include(core/CompilerFlags)
include(core/LinkerFlags)
include(core/VersionConfig)

# Configure compiler flags
configure_compiler_flags(MyApp STANDARD 20 WARNINGS HIGH)

# Configure linker with LTO
configure_linker_flags(MyApp LTO ON)

# Hardware optimizations
include(optimizations/HardwareOptimization)
configure_hardware_optimization(MyApp OPTIMIZATIONS AVX2 FAST_MATH)

# Testing
include(testing/TestingConfig)
configure_testing(FRAMEWORK GOOGLETEST)
add_test_executable(MyTests SOURCES test_main.cpp)

# Static analysis
include(analysis/StaticAnalysisConfig)
configure_static_analysis(MyApp CLANG_TIDY ON)

# Installation
include(deployment/InstallConfig)
configure_install_rules(MyApp INCLUDE_DIRS include/)

# Compile commands for language servers
include(utils/CompileCommandsConfig)
configure_compile_commands(ENABLE ON)
```

## Requirements

- **CMake**: 3.16 or higher
- **Compilers**: MSVC 2019+, GCC 7+, Clang 10+, or Intel ICC 19+
- **Platforms**: Windows (10+), Linux, macOS (10.14+)

## License

--freeware--

## Contributing

Contributions are welcome! Please ensure that:

- All functions are cross-platform compatible
- Documentation is updated
- Code follows CMake best practices
- Tests are added for new features

## Support

For issues, questions, or contributions, please open an issue or submit a pull request.
