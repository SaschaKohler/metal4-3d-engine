cmake_minimum_required(VERSION 3.22)
project(metal4_3d_engine LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)

# ── clangd / LazyVim LSP support ─────────────────────────────────────────────
# Generates build/compile_commands.json consumed by clangd.
# Run once after cmake -B build:  ln -s build/compile_commands.json compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Sources ─────────────────────────────────────────────────────────────────
set(ENGINE_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/MetalViewDelegate.mm
    src/InputMTKView.mm
    src/Renderer.mm
    src/Mesh.mm
    src/MetalImpl.mm        # metal-cpp implementation (defined once)
)

add_executable(metal4engine MACOSX_BUNDLE ${ENGINE_SOURCES})

# ── metal-cpp headers ────────────────────────────────────────────────────────
# Clone https://github.com/apple/metal-cpp into vendor/metal-cpp
target_include_directories(metal4engine PRIVATE
    ${CMAKE_SOURCE_DIR}/vendor/metal-cpp
    ${CMAKE_SOURCE_DIR}/vendor/cgltf
    ${CMAKE_SOURCE_DIR}/src
)

# ── Apple frameworks ─────────────────────────────────────────────────────────
find_library(METAL_LIB       Metal)
find_library(FOUNDATION_LIB  Foundation)
find_library(QUARTZCORE_LIB  QuartzCore)
find_library(APPKIT_LIB      AppKit)
find_library(METALKIT_LIB    MetalKit)

target_link_libraries(metal4engine
    ${METAL_LIB}
    ${FOUNDATION_LIB}
    ${QUARTZCORE_LIB}
    ${APPKIT_LIB}
    ${METALKIT_LIB}
)

# ── macOS SDK (explicit isysroot so clangd sees it in compile_commands.json) ──
execute_process(
    COMMAND xcrun --sdk macosx --show-sdk-path
    OUTPUT_VARIABLE MACOS_SDK_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
message(STATUS "macOS SDK: ${MACOS_SDK_PATH}")

# ── Compiler flags ────────────────────────────────────────────────────────────
target_compile_options(metal4engine PRIVATE
    -Wall -Wextra
    -Wno-unused-parameter
    -fobjc-arc                  # ARC for Obj-C portions
    -isysroot ${MACOS_SDK_PATH}
)

# ── Metal shaders ─────────────────────────────────────────────────────────────
# Xcode / xcrun compiles .metal → .metallib automatically when included as
# resources. For CMake we invoke xcrun explicitly as a custom target.
set(SHADER_SOURCE ${CMAKE_SOURCE_DIR}/shaders/triangle.metal)
set(METALLIB_OUT  ${CMAKE_BINARY_DIR}/default.metallib)

add_custom_command(
    OUTPUT  ${METALLIB_OUT}
    COMMAND xcrun -sdk macosx metal -c ${SHADER_SOURCE} -o ${CMAKE_BINARY_DIR}/triangle.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_BINARY_DIR}/triangle.air -o ${METALLIB_OUT}
    DEPENDS ${SHADER_SOURCE}
    COMMENT "Compiling Metal shaders → default.metallib"
)

add_custom_target(shaders ALL DEPENDS ${METALLIB_OUT})
add_dependencies(metal4engine shaders)

# Copy metallib next to the app bundle so MTLDevice can find it
add_custom_command(TARGET metal4engine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${METALLIB_OUT}
        $<TARGET_FILE_DIR:metal4engine>/default.metallib
)

# Copy assets directory next to the executable
add_custom_command(TARGET metal4engine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/assets
        $<TARGET_FILE_DIR:metal4engine>/assets
)

# ── macOS bundle info ─────────────────────────────────────────────────────────
set_target_properties(metal4engine PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME        "Metal4Engine"
    MACOSX_BUNDLE_GUI_IDENTIFIER     "dev.saschakohler.metal4engine"
    MACOSX_BUNDLE_BUNDLE_VERSION     "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
)
