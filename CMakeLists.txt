cmake_minimum_required(VERSION 3.20)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "Minimum macOS version")
project(ReaBattery VERSION 0.1.0 LANGUAGES OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "ReaBattery requires macOS on Apple Silicon")
endif()

set(SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/reaper-sdk/sdk" CACHE PATH "REAPER SDK headers")
set(WDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/WDL/WDL" CACHE PATH "Cockos WDL directory")
if(NOT EXISTS "${SDK_DIR}/reaper_plugin.h" OR NOT EXISTS "${WDL_DIR}/swell/swell-modstub.mm")
    message(FATAL_ERROR "See README.md for the Cockos SDK dependencies")
endif()

add_library(reaper_reabattery MODULE src/reabattery.mm "${WDL_DIR}/swell/swell-modstub.mm")
target_include_directories(reaper_reabattery SYSTEM PRIVATE "${SDK_DIR}" "${WDL_DIR}")
target_compile_definitions(reaper_reabattery PRIVATE SWELL_PROVIDED_BY_APP)
set_source_files_properties(src/reabattery.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc;-Wall;-Wextra")
target_link_libraries(reaper_reabattery PRIVATE "-framework Cocoa" "-framework IOKit")
set_target_properties(reaper_reabattery PROPERTIES
    OBJCXX_STANDARD 17
    OBJCXX_STANDARD_REQUIRED YES
    OBJCXX_EXTENSIONS NO
    OBJCXX_VISIBILITY_PRESET hidden
    PREFIX ""
    SUFFIX ".dylib"
)
install(TARGETS reaper_reabattery LIBRARY DESTINATION UserPlugins)
