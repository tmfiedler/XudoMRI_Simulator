# Shared host-only configuration support. No YAML types enter CUDA kernels.
file(GLOB yaml_sources CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/yaml-cpp/src/*.cpp")
add_library(NutateYaml STATIC ${yaml_sources})
target_include_directories(NutateYaml PUBLIC ../third_party/yaml-cpp/include PRIVATE ../third_party/yaml-cpp/src)
target_compile_definitions(NutateYaml PUBLIC YAML_CPP_STATIC_DEFINE PRIVATE YAML_CPP_NO_CONTRIB)
target_compile_features(NutateYaml PUBLIC cxx_std_11)

add_library(NutateNucleus STATIC NucleusDefinitions.cpp TissueProperties.cpp)
target_include_directories(NutateNucleus PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(NutateNucleus PUBLIC cxx_std_14)
target_link_libraries(NutateNucleus PUBLIC NutateYaml)
