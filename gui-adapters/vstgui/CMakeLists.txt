cmake_minimum_required(VERSION 3.25)
project(zig_vstgui_adapter LANGUAGES C CXX)

option(ZIG_VSTGUI_ENABLE_SANITIZERS "Enable address and undefined-behavior sanitizers" OFF)
option(ZIG_VSTGUI_ENABLE_THREAD_SANITIZER "Enable the thread sanitizer" OFF)
option(ZIG_VSTGUI_RUN_VISUAL_TESTS "Run visual snapshot tests when building their validation target" ON)

if(ZIG_VSTGUI_ENABLE_SANITIZERS AND ZIG_VSTGUI_ENABLE_THREAD_SANITIZER)
    message(FATAL_ERROR "Address and thread sanitizers require separate builds")
endif()

if(ZIG_VSTGUI_ENABLE_SANITIZERS)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        message(FATAL_ERROR "ZIG_VSTGUI_ENABLE_SANITIZERS requires Clang or GCC")
    endif()
    add_compile_options(-fsanitize=address,undefined -fno-sanitize=enum -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()

if(ZIG_VSTGUI_ENABLE_THREAD_SANITIZER)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        message(FATAL_ERROR "ZIG_VSTGUI_ENABLE_THREAD_SANITIZER requires Clang or GCC")
    endif()
    add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
    add_link_options(-fsanitize=thread)
endif()

if(APPLE)
    enable_language(OBJCXX)
endif()

set(VSTGUI_STANDALONE OFF CACHE BOOL "" FORCE)
set(VSTGUI_STANDALONE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(VSTGUI_TOOLS OFF CACHE BOOL "" FORCE)
set(VSTGUI_DISABLE_UNITTESTS ON CACHE BOOL "" FORCE)
set(VSTGUI_UISCRIPTING OFF CACHE BOOL "" FORCE)
set(VSTGUI_ENABLE_DEPRECATED_METHODS ON CACHE BOOL "" FORCE)
set(VSTGUI_ENABLE_OPENGL_SUPPORT OFF CACHE BOOL "" FORCE)
set(VSTGUI_ENABLE_XMLPARSER OFF CACHE BOOL "" FORCE)
if(UNIX AND NOT APPLE)
    set(VSTGUI_ENABLE_WAYLAND_SUPPORT ON CACHE BOOL "" FORCE)
endif()

set(VSTGUI_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk/vstgui4")
add_subdirectory("${VSTGUI_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/vstgui")
set_target_properties(vstgui PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    OBJCXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Release/libs"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/Release/libs"
)
if(APPLE)
    target_compile_options(vstgui PRIVATE -Wno-error=deprecated-declarations)
endif()

set(ZIG_VSTGUI_ADAPTER_SOURCES
    zig_vstgui_adapter.cpp
    zig_vstgui_accessibility.cpp
    zig_vstgui_accessibility_bridge.cpp
    zig_vstgui_action_button.cpp
    zig_vstgui_text_progress.cpp
    zig_vstgui_viewport.cpp
    zig_vstgui_range_selection.cpp
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
    zig_vstgui_step_sequencer.cpp
    zig_vstgui_file_drop.cpp
    zig_vstgui_preset_browser.cpp
    zig_vstgui_theme.cpp
    zig_vstgui_xy_pad.cpp
)
if(APPLE)
    list(APPEND ZIG_VSTGUI_ADAPTER_SOURCES
        zig_vstgui_accessibility_macos.mm
        zig_vstgui_platform_macos.mm
    )
elseif(WIN32)
    list(APPEND ZIG_VSTGUI_ADAPTER_SOURCES
        zig_vstgui_accessibility_windows.cpp
    )
endif()

add_library(zig_vstgui_adapter STATIC ${ZIG_VSTGUI_ADAPTER_SOURCES})
if(APPLE)
    set_source_files_properties(
        zig_vstgui_accessibility_macos.mm
        zig_vstgui_platform_macos.mm
        PROPERTIES COMPILE_OPTIONS "-fobjc-arc"
    )
endif()
target_compile_features(zig_vstgui_adapter PRIVATE cxx_std_17)
target_compile_definitions(zig_vstgui_adapter PUBLIC
    VSTGUI_ENABLE_DEPRECATED_METHODS=1
    VSTGUI_ENABLE_XML_PARSER=0
    VSTGUI_OPENGL_SUPPORT=0
)
target_include_directories(zig_vstgui_adapter PRIVATE
    "${VSTGUI_SOURCE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/../../.vst3-sdk/vst3sdk"
)
target_link_libraries(zig_vstgui_adapter PRIVATE vstgui)
if(APPLE AND (ZIG_VSTGUI_ENABLE_SANITIZERS OR ZIG_VSTGUI_ENABLE_THREAD_SANITIZER))
    target_link_libraries(zig_vstgui_adapter PUBLIC "-framework OpenGL")
endif()
if(WIN32)
    target_link_libraries(zig_vstgui_adapter PRIVATE comctl32 oleaut32 uiautomationcore)
endif()
set_target_properties(zig_vstgui_adapter PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    OBJCXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Release/libs"
    ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/Release/libs"
)

if(UNIX AND NOT APPLE)
    execute_process(
        COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=libstdc++.so
        OUTPUT_VARIABLE ZIG_VSTGUI_CXX_RUNTIME
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE ZIG_VSTGUI_CXX_RUNTIME_RESULT
    )
    if(NOT ZIG_VSTGUI_CXX_RUNTIME_RESULT EQUAL 0 OR
       ZIG_VSTGUI_CXX_RUNTIME STREQUAL "libstdc++.so" OR
       NOT EXISTS "${ZIG_VSTGUI_CXX_RUNTIME}")
        message(FATAL_ERROR "Could not locate the C++ runtime used by ${CMAKE_CXX_COMPILER}")
    endif()
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/Release/libs")
    file(COPY_FILE
        "${ZIG_VSTGUI_CXX_RUNTIME}"
        "${CMAKE_BINARY_DIR}/Release/libs/libstdc++.so"
        ONLY_IF_DIFFERENT
    )
    execute_process(
        COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=libgcc_s.so.1
        OUTPUT_VARIABLE ZIG_VSTGUI_UNWIND_RUNTIME
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE ZIG_VSTGUI_UNWIND_RUNTIME_RESULT
    )
    if(NOT ZIG_VSTGUI_UNWIND_RUNTIME_RESULT EQUAL 0 OR
       ZIG_VSTGUI_UNWIND_RUNTIME STREQUAL "libgcc_s.so.1" OR
       NOT EXISTS "${ZIG_VSTGUI_UNWIND_RUNTIME}")
        message(FATAL_ERROR "Could not locate the unwind runtime used by ${CMAKE_CXX_COMPILER}")
    endif()
    file(COPY_FILE
        "${ZIG_VSTGUI_UNWIND_RUNTIME}"
        "${CMAKE_BINARY_DIR}/Release/libs/libgcc_s.so.1"
        ONLY_IF_DIFFERENT
    )
endif()

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

if(ZIG_VSTGUI_RUN_VISUAL_TESTS)
    add_custom_target(zig_vstgui_visual_tests_run
        COMMAND $<TARGET_FILE:zig_vstgui_visual_tests>
            "${CMAKE_CURRENT_LIST_DIR}/testdata/visual"
            "${CMAKE_BINARY_DIR}/visual-regression"
            ${ZIG_VSTGUI_VISUAL_TEST_ARGS}
        DEPENDS zig_vstgui_visual_tests
    )
else()
    add_custom_target(zig_vstgui_visual_tests_run
        DEPENDS zig_vstgui_visual_tests
    )
endif()

add_custom_target(zig_vstgui_visual_tests_update
    COMMAND $<TARGET_FILE:zig_vstgui_visual_tests>
        "${CMAKE_CURRENT_LIST_DIR}/testdata/visual"
        "${CMAKE_BINARY_DIR}/visual-regression"
        --update
    DEPENDS zig_vstgui_visual_tests
)
