cmake_minimum_required(VERSION 3.25)
project(zig_vstgui_adapter LANGUAGES C CXX)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(VSTGUI_STANDALONE OFF CACHE BOOL "" FORCE)
set(VSTGUI_STANDALONE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(VSTGUI_TOOLS OFF CACHE BOOL "" FORCE)
set(VSTGUI_DISABLE_UNITTESTS ON CACHE BOOL "" FORCE)
set(VSTGUI_UISCRIPTING OFF CACHE BOOL "" FORCE)
set(VSTGUI_ENABLE_OPENGL_SUPPORT OFF CACHE BOOL "" FORCE)
set(VSTGUI_ENABLE_XMLPARSER OFF CACHE BOOL "" FORCE)
if(UNIX AND NOT APPLE)
    set(VSTGUI_ENABLE_WAYLAND_SUPPORT ON CACHE BOOL "" FORCE)
endif()

set(VSTGUI_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk/vstgui4")
add_subdirectory("${VSTGUI_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/vstgui")
set_target_properties(vstgui PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Release/libs"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/Release/libs"
)

set(ZIG_VSTGUI_ADAPTER_SOURCES
    zig_vstgui_adapter.cpp
    zig_vstgui_accessibility.cpp
    zig_vstgui_accessibility_bridge.cpp
    zig_vstgui_action_menu.cpp
    zig_vstgui_assets.cpp
    zig_vstgui_component.cpp
    zig_vstgui_controls.cpp
    zig_vstgui_drawing.cpp
    zig_vstgui_editor.cpp
    zig_vstgui_fonts.cpp
    zig_vstgui_graphs.cpp
    zig_vstgui_layout.cpp
    zig_vstgui_meters.cpp
    zig_vstgui_platform.cpp
    zig_vstgui_piano.cpp
    zig_vstgui_preset_browser.cpp
    zig_vstgui_theme.cpp
    zig_vstgui_xy_pad.cpp
)
if(APPLE)
    list(APPEND ZIG_VSTGUI_ADAPTER_SOURCES zig_vstgui_accessibility_macos.mm)
elseif(WIN32)
    list(APPEND ZIG_VSTGUI_ADAPTER_SOURCES zig_vstgui_accessibility_windows.cpp)
endif()

add_library(zig_vstgui_adapter STATIC ${ZIG_VSTGUI_ADAPTER_SOURCES})
if(APPLE)
    set_source_files_properties(zig_vstgui_accessibility_macos.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
endif()
target_compile_features(zig_vstgui_adapter PRIVATE cxx_std_17)
target_compile_definitions(zig_vstgui_adapter PRIVATE VSTGUI_ENABLE_XML_PARSER=0)
target_include_directories(zig_vstgui_adapter PRIVATE
    "${VSTGUI_SOURCE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk"
)
target_link_libraries(zig_vstgui_adapter PRIVATE vstgui)
if(WIN32)
    target_link_libraries(zig_vstgui_adapter PRIVATE comctl32 oleaut32 uiautomationcore)
endif()
set_target_properties(zig_vstgui_adapter PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Release/libs"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/Release/libs"
)

add_executable(zig_vstgui_adapter_tests zig_vstgui_adapter_tests.cpp)
target_compile_features(zig_vstgui_adapter_tests PRIVATE cxx_std_17)
target_compile_definitions(zig_vstgui_adapter_tests PRIVATE VSTGUI_ENABLE_XML_PARSER=0)
target_include_directories(zig_vstgui_adapter_tests PRIVATE
    "${VSTGUI_SOURCE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk"
)
target_link_libraries(zig_vstgui_adapter_tests PRIVATE zig_vstgui_adapter)

add_custom_target(zig_vstgui_adapter_tests_run
    COMMAND $<TARGET_FILE:zig_vstgui_adapter_tests>
    DEPENDS zig_vstgui_adapter_tests
)

if(APPLE)
    add_executable(zig_vstgui_accessibility_macos_tests zig_vstgui_accessibility_macos_tests.mm)
    target_compile_features(zig_vstgui_accessibility_macos_tests PRIVATE cxx_std_17)
    target_compile_options(zig_vstgui_accessibility_macos_tests PRIVATE -fobjc-arc)
    target_compile_definitions(zig_vstgui_accessibility_macos_tests PRIVATE VSTGUI_ENABLE_XML_PARSER=0)
    target_include_directories(zig_vstgui_accessibility_macos_tests PRIVATE
        "${VSTGUI_SOURCE_DIR}"
        "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk"
    )
    target_link_libraries(zig_vstgui_accessibility_macos_tests PRIVATE zig_vstgui_adapter "-framework AppKit")
    add_custom_target(zig_vstgui_accessibility_tests_run
        COMMAND $<TARGET_FILE:zig_vstgui_accessibility_macos_tests>
        DEPENDS zig_vstgui_accessibility_macos_tests
    )
else()
    add_custom_target(zig_vstgui_accessibility_tests_run)
endif()

add_executable(zig_vstgui_visual_tests zig_vstgui_visual_tests.cpp)
target_compile_features(zig_vstgui_visual_tests PRIVATE cxx_std_17)
target_compile_definitions(zig_vstgui_visual_tests PRIVATE VSTGUI_ENABLE_XML_PARSER=0)
target_include_directories(zig_vstgui_visual_tests PRIVATE
    "${VSTGUI_SOURCE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk"
)
target_link_libraries(zig_vstgui_visual_tests PRIVATE zig_vstgui_adapter)

add_custom_target(zig_vstgui_visual_tests_run
    COMMAND $<TARGET_FILE:zig_vstgui_visual_tests>
        "${CMAKE_CURRENT_LIST_DIR}/testdata/visual"
        "${CMAKE_BINARY_DIR}/visual-regression"
    DEPENDS zig_vstgui_visual_tests
)

add_custom_target(zig_vstgui_visual_tests_update
    COMMAND $<TARGET_FILE:zig_vstgui_visual_tests>
        "${CMAKE_CURRENT_LIST_DIR}/testdata/visual"
        "${CMAKE_BINARY_DIR}/visual-regression"
        --update
    DEPENDS zig_vstgui_visual_tests
)
