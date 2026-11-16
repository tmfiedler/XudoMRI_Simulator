cmake_minimum_required(VERSION 3.24)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/NutateVersion.cmake")
nutate_read_version("${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION" NUTATE_VERSION)

project(NutateNoise VERSION ${NUTATE_VERSION} LANGUAGES CXX)

include(CTest)
add_subdirectory(../common "${CMAKE_BINARY_DIR}/common")

set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(NUTATE_NOISE_SOURCES
  src/CmdInterp.cpp
  src/E1MinsIn.cpp
  src/Execution.cpp
  src/Functions.cpp
  src/GeomIn.cpp
  src/main.cpp
  src/Nucleus.cpp
  src/SeqnIn.cpp
  src/TissIn.cpp
  src/TissueFile.cpp
  src/Vect3D.cpp
  src/Voxel.cpp
)

add_executable(NutateNoise ${NUTATE_NOISE_SOURCES})
target_link_libraries(NutateNoise PRIVATE NutateNucleus NutateModelInputs)
target_include_directories(NutateNoise PRIVATE include)
target_compile_features(NutateNoise PRIVATE cxx_std_17)
target_compile_definitions(NutateNoise PRIVATE NUTATE_VERSION="${NUTATE_VERSION}")

if(MSVC)
  target_compile_options(NutateNoise PRIVATE /W4 /EHsc)
else()
  target_compile_options(NutateNoise PRIVATE -Wall -Wextra)
endif()

set_target_properties(NutateNoise PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
)

if(BUILD_TESTING)
  add_executable(EssentialTests ../tests/EssentialTests.cpp)
  target_include_directories(EssentialTests PRIVATE ../common)
  target_compile_features(EssentialTests PRIVATE cxx_std_17)
  add_test(NAME Essentials COMMAND EssentialTests)
  add_executable(NutateNoiseMathTests
    tests/NoiseMathTests.cpp
    src/Functions.cpp
  )
  target_include_directories(NutateNoiseMathTests PRIVATE include)
  target_compile_features(NutateNoiseMathTests PRIVATE cxx_std_17)
  if(MSVC)
    target_compile_options(NutateNoiseMathTests PRIVATE /W4 /EHsc)
  else()
    target_compile_options(NutateNoiseMathTests PRIVATE -Wall -Wextra)
  endif()
  set_target_properties(NutateNoiseMathTests PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
  )
  add_test(NAME NoiseMath COMMAND NutateNoiseMathTests)
endif()
