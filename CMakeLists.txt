cmake_minimum_required(VERSION 3.20)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version")
project(ReaBattery VERSION 0.1 LANGUAGES CXX)

set(SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/reaper-sdk/sdk" CACHE PATH "REAPER SDK headers")
if(NOT EXISTS "${SDK_DIR}/reaper_plugin.h")
    message(FATAL_ERROR "See README.md for the Cockos SDK dependencies")
endif()

if(APPLE)
    enable_language(OBJCXX)
    set(WDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/WDL/WDL" CACHE PATH "Cockos WDL directory")
    if(NOT EXISTS "${WDL_DIR}/swell/swell-modstub.mm")
        message(FATAL_ERROR "See README.md for the Cockos WDL dependency")
    endif()
    add_library(reaper_reabattery MODULE src/reabattery.mm "${WDL_DIR}/swell/swell-modstub.mm")
    target_include_directories(reaper_reabattery SYSTEM PRIVATE "${WDL_DIR}")
    target_compile_definitions(reaper_reabattery PRIVATE SWELL_PROVIDED_BY_APP)
    set_source_files_properties(src/reabattery.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc;-Wall;-Wextra")
    target_link_libraries(reaper_reabattery PRIVATE "-framework Cocoa" "-framework IOKit")
    set_target_properties(reaper_reabattery PROPERTIES
        OBJCXX_STANDARD 17
        OBJCXX_STANDARD_REQUIRED YES
        OBJCXX_EXTENSIONS NO
        OBJCXX_VISIBILITY_PRESET hidden
        SUFFIX ".dylib"
    )
elseif(WIN32)
    if(NOT MSVC OR NOT CMAKE_CXX_COMPILER_ARCHITECTURE_ID STREQUAL "x64")
        message(FATAL_ERROR "Build ReaBattery with an MSVC-compatible x64 compiler. For Visual Studio, pass -A x64.")
    endif()
    add_library(reaper_reabattery MODULE src/reabattery_win.cpp)
    target_compile_definitions(reaper_reabattery PRIVATE _WIN32_WINNT=0x0A00)
    target_compile_options(reaper_reabattery PRIVATE /W4 /permissive-)
    target_link_libraries(reaper_reabattery PRIVATE user32 gdi32)
    set_target_properties(reaper_reabattery PROPERTIES
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
else()
    message(FATAL_ERROR "ReaBattery supports Apple Silicon macOS and Windows x64")
endif()

target_include_directories(reaper_reabattery SYSTEM PRIVATE "${SDK_DIR}")
set_target_properties(reaper_reabattery PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
    PREFIX ""
)
install(TARGETS reaper_reabattery
    LIBRARY DESTINATION UserPlugins
    RUNTIME DESTINATION UserPlugins
)
