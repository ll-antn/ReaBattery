#pragma once

#define NOMINMAX
#include <reaper_plugin.h>

#include <charconv>
#include <chrono>
#include <cstring>
#include <limits>
#include <string>

// Compiled with the native indicator implementation selected by CMake.
namespace {

constexpr int indicatorWidthWithPercentage = 64;
constexpr int indicatorWidthWithoutPercentage = 34;
constexpr int indicatorHeight = 20;
constexpr char settingsSection[] = "ReaBattery";
constexpr char showPercentageKey[] = "ShowPercentage";
constexpr char fullscreenOnlyKey[] = "FullscreenOnly";
constexpr char showWhenPluggedInKey[] = "ShowWhenPluggedIn";
constexpr char positionKey[] = "Position";
constexpr int transportStatusControlId = 1010;
using Clock = std::chrono::steady_clock;

enum class IndicatorPosition { Right, Left, Center };
constexpr const char* positionValues[] = {"right", "left", "center"};

enum Option { PercentageOption, FullscreenOption, PluggedInOption,
              RightOption, LeftOption, CenterOption, OptionCount };

struct OptionAction {
    const char* identifier;
    const char* title;
    std::string description{};
    gaccel_register_t registration{};
};

OptionAction optionActions[OptionCount] = {
    {"ReaBatteryShowPercentage", "Show percentage"},
    {"ReaBatteryFullscreenOnly", "Show only in Fullscreen"},
    {"ReaBatteryShowWhenPluggedIn", "Show when plugged-in"},
    {"ReaBatteryPositionRight", "Right Corner"},
    {"ReaBatteryPositionLeft", "Left Corner"},
    {"ReaBatteryPositionCenter", "Center"}
};

bool showPercentage = true;
bool fullscreenOnly = false;
bool showWhenPluggedIn = true;
IndicatorPosition indicatorPosition = IndicatorPosition::Right;
void (*setExtState)(const char*, const char*, const char*, bool);
void detachIndicator();
void updateTransport();
bool createIndicator(REAPER_PLUGIN_HINSTANCE instance);
void destroyIndicator();
void redrawIndicator();
void tick();

int (*registerWithHost)(const char*, void*);
HWND (*getMainWindow)();
int (*getThemeColor)(const char*, int);
int (*getToggleCommandState)(int);

struct Battery {
    int percent = -1;
    bool pluggedIn = false;
};

bool supportsVersion(const char* version)
{
    if (!version)
        return false;
    const char* end = version + std::strlen(version);
    int major = 0;
    const auto majorResult = std::from_chars(version, end, major);
    if (majorResult.ec != std::errc{} || majorResult.ptr == end || *majorResult.ptr != '.')
        return false;
    const char* minorStart = majorResult.ptr + 1;
    int minor = 0;
    const auto minorResult = std::from_chars(minorStart, end, minor);
    if (minorResult.ec != std::errc{} || minor < 0)
        return false;
    // Interpret shortened display versions such as 7.5 as 7.50.
    if (minorResult.ptr - minorStart == 1)
        minor *= 10;
    return major > 7 || (major == 7 && minor > 50);
}

int optionIndexForCommand(int command)
{
    if (command > 0) {
        for (int i = 0; i < OptionCount; ++i) {
            if (optionActions[i].registration.accel.cmd == command)
                return i;
        }
    }
    return -1;
}

int optionToggleState(int command)
{
    switch (const int option = optionIndexForCommand(command)) {
    case PercentageOption:
        return showPercentage;
    case FullscreenOption:
        return fullscreenOnly;
    case PluggedInOption:
        return showWhenPluggedIn;
    case RightOption:
    case LeftOption:
    case CenterOption:
        return option - RightOption == static_cast<int>(indicatorPosition);
    default:
        return -1;
    }
}

void applyOption(int option)
{
    const char* key;
    const char* value;
    switch (option) {
    case PercentageOption:
        showPercentage = !showPercentage;
        key = showPercentageKey;
        value = showPercentage ? "1" : "0";
        break;
    case FullscreenOption:
        fullscreenOnly = !fullscreenOnly;
        key = fullscreenOnlyKey;
        value = fullscreenOnly ? "1" : "0";
        break;
    case PluggedInOption:
        showWhenPluggedIn = !showWhenPluggedIn;
        key = showWhenPluggedInKey;
        value = showWhenPluggedIn ? "1" : "0";
        break;
    case RightOption:
    case LeftOption:
    case CenterOption: {
        const auto position = static_cast<IndicatorPosition>(option - RightOption);
        if (position == indicatorPosition)
            return;
        indicatorPosition = position;
        key = positionKey;
        value = positionValues[option - RightOption];
        detachIndicator();
        break;
    }
    default:
        return;
    }
    setExtState(settingsSection, key, value, true);
    updateTransport();
    redrawIndicator();
}

bool handleOptionCommand(int command, int)
{
    const int option = optionIndexForCommand(command);
    if (option < 0)
        return false;
    applyOption(option);
    return true;
}

void appendMenuItem(HMENU menu, unsigned flags, UINT_PTR id, const char* title)
{
#ifdef _WIN32
    InsertMenuA(menu, static_cast<UINT>(-1), MF_BYPOSITION | flags, id, title);
#else
    InsertMenu(menu, -1, MF_BYPOSITION | flags, id, title);
#endif
}

HMENU createOptionsMenu(bool includeChecks)
{
    const HMENU options = CreatePopupMenu();
    const HMENU positions = CreatePopupMenu();
    if (!options || !positions) {
        if (options)
            DestroyMenu(options);
        if (positions)
            DestroyMenu(positions);
        return nullptr;
    }
    for (int i = 0; i < OptionCount; ++i) {
        const auto& action = optionActions[i];
        const int command = action.registration.accel.cmd;
        const bool checked = includeChecks && optionToggleState(command) == 1;
        appendMenuItem(i < RightOption ? options : positions,
                       MF_STRING | (checked ? MF_CHECKED : MF_UNCHECKED), command, action.title);
    }
    appendMenuItem(options, MF_POPUP, reinterpret_cast<UINT_PTR>(positions), "Position");
    return options;
}

void extensionsMenu(const char* name, void* handle, int flag)
{
    if (!handle)
        return;
    const auto menu = static_cast<HMENU>(handle);
    if (flag == 0 && name && std::strcmp(name, "Main extensions") == 0) {
        const HMENU options = createOptionsMenu(false);
        if (options)
            appendMenuItem(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(options), "ReaBattery");
    } else if (flag == 1) {
        // Submenus can be shown without the Main extensions menu ID.
        for (const auto& action : optionActions) {
            const int command = action.registration.accel.cmd;
            const int state = optionToggleState(command);
            if (state >= 0)
                CheckMenuItem(menu, command, MF_BYCOMMAND | (state ? MF_CHECKED : MF_UNCHECKED));
        }
    }
}

void unregisterMenuActions()
{
    registerWithHost("-hookcustommenu", reinterpret_cast<void*>(extensionsMenu));
    registerWithHost("-hookcommand", reinterpret_cast<void*>(handleOptionCommand));
    registerWithHost("-toggleaction", reinterpret_cast<void*>(optionToggleState));
    for (auto& action : optionActions) {
        if (action.registration.accel.cmd)
            registerWithHost("-gaccel", &action.registration);
        action.registration = {};
    }
}

bool registerMenuActions()
{
    for (auto& action : optionActions) {
        const int command = registerWithHost("command_id", const_cast<char*>(action.identifier));
        if (command <= 0 || command > std::numeric_limits<WORD>::max())
            return false;
        action.description = std::string("ReaBattery: ") + action.title;
        action.registration.accel.cmd = static_cast<WORD>(command);
        action.registration.desc = action.description.c_str();
        if (!registerWithHost("gaccel", &action.registration))
            return false;
    }
    return registerWithHost("hookcommand", reinterpret_cast<void*>(handleOptionCommand)) &&
           registerWithHost("toggleaction", reinterpret_cast<void*>(optionToggleState)) &&
           registerWithHost("hookcustommenu", reinterpret_cast<void*>(extensionsMenu));
}

bool reaperIsFullscreen()
{
    constexpr int toggleReaperFullscreenAction = 40346;
    return getToggleCommandState && getToggleCommandState(toggleReaperFullscreenAction) == 1;
}

} // namespace

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(
    REAPER_PLUGIN_HINSTANCE instance, reaper_plugin_info_t* host)
{
    if (!host) {
        if (registerWithHost) {
            registerWithHost("-timer", reinterpret_cast<void*>(tick));
            unregisterMenuActions();
        }
        destroyIndicator();
        registerWithHost = nullptr;
        return 0;
    }

    if (host->caller_version != REAPER_PLUGIN_VERSION || !host->GetFunc || !host->Register)
        return 0;
    auto getVersion = reinterpret_cast<const char* (*)()>(host->GetFunc("GetAppVersion"));
    if (!getVersion || !supportsVersion(getVersion()))
        return 0;
    getMainWindow = reinterpret_cast<decltype(getMainWindow)>(host->GetFunc("GetMainHwnd"));
    getThemeColor = reinterpret_cast<decltype(getThemeColor)>(host->GetFunc("GetThemeColor"));
    getToggleCommandState =
        reinterpret_cast<decltype(getToggleCommandState)>(host->GetFunc("GetToggleCommandState"));
    auto getExtState = reinterpret_cast<const char* (*)(const char*, const char*)>(host->GetFunc("GetExtState"));
    setExtState = reinterpret_cast<decltype(setExtState)>(host->GetFunc("SetExtState"));
    if (!getMainWindow || !getThemeColor || !getExtState || !setExtState)
        return 0;

    const char* savedPercentage = getExtState(settingsSection, showPercentageKey);
    showPercentage = !savedPercentage || std::strcmp(savedPercentage, "0") != 0;
    const char* savedFullscreenOnly = getExtState(settingsSection, fullscreenOnlyKey);
    fullscreenOnly = savedFullscreenOnly && std::strcmp(savedFullscreenOnly, "1") == 0;
    const char* savedShowWhenPluggedIn = getExtState(settingsSection, showWhenPluggedInKey);
    showWhenPluggedIn = !savedShowWhenPluggedIn || std::strcmp(savedShowWhenPluggedIn, "0") != 0;
    const char* savedPosition = getExtState(settingsSection, positionKey);
    indicatorPosition = IndicatorPosition::Right;
    if (savedPosition && std::strcmp(savedPosition, "left") == 0)
        indicatorPosition = IndicatorPosition::Left;
    if (savedPosition && std::strcmp(savedPosition, "center") == 0)
        indicatorPosition = IndicatorPosition::Center;
    if (!createIndicator(instance))
        return 0;
    if (!host->Register("timer", reinterpret_cast<void*>(tick))) {
        destroyIndicator();
        return 0;
    }
    registerWithHost = host->Register;
    if (!registerMenuActions()) {
        unregisterMenuActions();
        registerWithHost("-timer", reinterpret_cast<void*>(tick));
        registerWithHost = nullptr;
        destroyIndicator();
        return 0;
    }
    auto addExtensionsMainMenu = reinterpret_cast<bool (*)()>(host->GetFunc("AddExtensionsMainMenu"));
    if (addExtensionsMainMenu)
        addExtensionsMainMenu();
    host->Register("ext_name", const_cast<char*>("ReaBattery"));
    return 1;
}
