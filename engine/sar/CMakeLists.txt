cmake_minimum_required(VERSION 3.24)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/NutateVersion.cmake")
nutate_read_version("${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION" NUTATE_VERSION)

project(NutateSARLegacy VERSION ${NUTATE_VERSION} LANGUAGES CXX)

# This is a reproducibility harness for the historical source. It is not an
# integration with the active engines and does not establish SAR validity.
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(OpenMP REQUIRED)

set(NUTATE_SAR_LEGACY_SOURCES
  src/B1MinsIn.cpp
  src/B1PlusIn.cpp
  src/CmdInterp.cpp
  src/E1PlusIn.cpp
  src/Execution.cpp
  src/GeomIn.cpp
  src/SeqnIn.cpp
  src/TissIn.cpp
  src/Vect3D.cpp
  src/Voxel.cpp
  src/main.cpp
)

add_executable(NutateSAR ${NUTATE_SAR_LEGACY_SOURCES})
target_include_directories(NutateSAR PRIVATE include)
target_compile_definitions(NutateSAR PRIVATE NUTATE_VERSION="${NUTATE_VERSION}")
target_link_libraries(NutateSAR PRIVATE OpenMP::OpenMP_CXX)

if(MSVC)
  target_compile_options(NutateSAR PRIVATE /W4 /EHsc)
else()
  target_compile_options(NutateSAR PRIVATE -Wall -Wextra)
endif()

set_target_properties(NutateSAR PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
)
