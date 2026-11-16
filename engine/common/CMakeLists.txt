# Shared host-only configuration support. No YAML types enter CUDA kernels.
file(GLOB yaml_sources CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/yaml-cpp/src/*.cpp")
add_library(NutateYaml STATIC ${yaml_sources})
target_include_directories(NutateYaml PUBLIC ../third_party/yaml-cpp/include PRIVATE ../third_party/yaml-cpp/src)
target_compile_definitions(NutateYaml PUBLIC YAML_CPP_STATIC_DEFINE PRIVATE YAML_CPP_NO_CONTRIB)
target_compile_features(NutateYaml PUBLIC cxx_std_11)

include(FetchContent)
# Build the gzip reader into the executables so deployment needs no extra DLL.
set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "Build zlib examples")
FetchContent_Declare(nutate_zlib
  GIT_REPOSITORY https://github.com/madler/zlib.git
  GIT_TAG v1.3.1
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(nutate_zlib)
add_library(NutateModelInputs STATIC ModelInputs.cpp)
target_include_directories(NutateModelInputs PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(NutateModelInputs PRIVATE "${nutate_zlib_SOURCE_DIR}" "${nutate_zlib_BINARY_DIR}")
target_compile_features(NutateModelInputs PUBLIC cxx_std_14)
target_link_libraries(NutateModelInputs PRIVATE zlibstatic)

add_library(NutateNucleus STATIC NucleusDefinitions.cpp TissueProperties.cpp)
target_include_directories(NutateNucleus PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(NutateNucleus PUBLIC cxx_std_14)
target_link_libraries(NutateNucleus PUBLIC NutateYaml)
