cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "llama_flutter_android")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(PLUGIN_NAME "llama_flutter_android_plugin")

find_package(Threads REQUIRED)

# All of this plugin's shared libraries end up flat in the app bundle's
# lib/ directory alongside libllama/libggml*. Flutter's plugin packaging
# copies the as-built .so directly (there's no separate `cmake --install`
# step), so the $ORIGIN rpath must be baked in at BUILD time, not deferred
# to an install step that never runs.
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)
set(CMAKE_INSTALL_RPATH "$ORIGIN")
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

# ---- llama.cpp (CPU-only for the Linux v1 build) ----
set(GGML_VULKAN OFF CACHE BOOL "")
set(GGML_OPENMP OFF CACHE BOOL "")
set(GGML_STATIC OFF CACHE BOOL "")
set(BUILD_SHARED_LIBS ON CACHE BOOL "")
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "")
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "")
add_subdirectory(llama.cpp)

list(APPEND PLUGIN_SOURCES
  "llama_flutter_android_plugin.cc"
  "llama_message_codec.cc"
  "llama_engine.cc"
  "chat_templates.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/ggml/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE llama)
target_link_libraries(${PLUGIN_NAME} PRIVATE Threads::Threads)

# Bundled with the app so the runtime can find libllama/libggml* at launch.
set(llama_flutter_android_bundled_libraries
  $<TARGET_FILE:llama>
  $<TARGET_FILE:ggml>
  $<TARGET_FILE:ggml-base>
  $<TARGET_FILE:ggml-cpu>
  PARENT_SCOPE
)
