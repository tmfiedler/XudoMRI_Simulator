cmake_minimum_required(VERSION 3.24)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/NutateVersion.cmake")
nutate_read_version("${CMAKE_CURRENT_SOURCE_DIR}/../../VERSION" NUTATE_VERSION)

project(NutateSignal VERSION ${NUTATE_VERSION} LANGUAGES CXX)

option(NUTATE_BUILD_GPU "Build NutateSignal_GPU with CUDA" ON)
option(NUTATE_USE_OPENMP "Enable OpenMP in the CPU engine" ON)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_subdirectory(../common "${CMAKE_BINARY_DIR}/common")

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(NUTATE_COMMON_SOURCES
  src/B1MinsIn.cpp
  src/B1PlusIn.cpp
  src/CmdInterp.cpp
  src/DelB0In.cpp
  src/DelGradIn.cpp
  src/Execution.cpp
  src/Functions.cpp
  src/GeomIn.cpp
  src/Nucleus.cpp
  src/SeqnIn.cpp
  src/TissIn.cpp
  src/TissueFile.cpp
  src/Vect3D.cpp
  src/Voxel.cpp
)

set(NUTATE_ENTRY_SOURCES
  src/main.cpp
  src/SimulationRunner.cpp
  src/CudaBackend.cpp
)

add_library(NutateSignalCommon STATIC ${NUTATE_COMMON_SOURCES})
target_include_directories(NutateSignalCommon PUBLIC include)
target_link_libraries(NutateSignalCommon PUBLIC NutateNucleus NutateModelInputs)

add_executable(NutateSignal_CPU ${NUTATE_ENTRY_SOURCES})
target_link_libraries(NutateSignal_CPU PRIVATE NutateSignalCommon)
target_compile_definitions(NutateSignal_CPU PRIVATE
  NUTATE_SIGNAL_CPU_BINARY
  NUTATE_VERSION="${NUTATE_VERSION}"
)

if(NUTATE_USE_OPENMP)
  find_package(OpenMP REQUIRED)
  target_link_libraries(NutateSignal_CPU PRIVATE OpenMP::OpenMP_CXX)
  target_compile_definitions(NutateSignal_CPU PRIVATE USE_OpenMP)
endif()

if(NUTATE_BUILD_GPU)
  enable_language(CUDA)
  if(NOT CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES "75;80;86;89" CACHE STRING "CUDA architectures" FORCE)
  endif()

  # Toolkit-provided CCCL 3.x requires C++17. Host sources remain C++14.
  set(CMAKE_CUDA_STANDARD 17)
  set(CMAKE_CUDA_STANDARD_REQUIRED ON)
  set(CMAKE_CUDA_EXTENSIONS OFF)

  add_executable(NutateSignal_GPU
    ${NUTATE_ENTRY_SOURCES}
    src/CudaBackend.cu
  )
  target_link_libraries(NutateSignal_GPU PRIVATE NutateSignalCommon)
  target_compile_definitions(NutateSignal_GPU PRIVATE
    NUTATE_HAS_CUDA_BACKEND
    NUTATE_SIGNAL_GPU_BINARY
    NUTATE_VERSION="${NUTATE_VERSION}"
  )
  set_target_properties(NutateSignal_GPU PROPERTIES
    CUDA_RUNTIME_LIBRARY Shared
    CUDA_SEPARABLE_COMPILATION ON
  )

endif()

set(NUTATE_EXECUTABLE_TARGETS NutateSignal_CPU)
if(NUTATE_BUILD_GPU)
  list(APPEND NUTATE_EXECUTABLE_TARGETS NutateSignal_GPU)
endif()

foreach(target IN LISTS NUTATE_EXECUTABLE_TARGETS)
  target_include_directories(${target} PRIVATE include)
  if(MSVC)
    target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/W4 /EHsc>)
    # CCCL requires MSVC's conforming preprocessor for CUDA host compilation.
    target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=/Zc:preprocessor>)
  else()
    target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra>)
  endif()
  set_target_properties(${target} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}/bin"
  )
endforeach()
