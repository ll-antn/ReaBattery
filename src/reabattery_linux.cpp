#include "reabattery_host.hpp"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>

namespace {

namespace fs = std::filesystem;

std::string readAttribute(const fs::path& supply, const char* attribute)
{
    std::ifstream stream(supply / attribute);
    std::string value;
    std::getline(stream, value);
    return value;
}

long long readNumber(const fs::path& supply, const char* attribute)
{
    const auto value = readAttribute(supply, attribute);
    long long number = -1;
    const auto result = std::from_chars(value.data(), value.data() + value.size(), number);
    return result.ec == std::errc{} && result.ptr == value.data() + value.size() ? number : -1;
}

int batteryPercentage(const fs::path& supply)
{
    const auto capacity = readNumber(supply, "capacity");
    if (capacity >= 0 && capacity <= 100)
        return static_cast<int>(capacity);

    const char* const attributes[][2] = {{"energy_now", "energy_full"}, {"charge_now", "charge_full"}};
    for (const auto& pair : attributes) {
        const auto now = readNumber(supply, pair[0]);
        const auto full = readNumber(supply, pair[1]);
        if (now >= 0 && full > 0) {
            const double ratio = std::min(1.0, static_cast<double>(now) / full);
            return static_cast<int>(100 * ratio + 0.5);
        }
    }
    return -1;
}

Battery readBattery(const fs::path& root)
{
    int total = 0;
    int count = 0;
    bool adapterReported = false;
    bool adapterOnline = false;
    bool charging = false;
    std::error_code error;
    for (fs::directory_iterator entry(root, error), end; !error && entry != end; entry.increment(error)) {
        const auto& supply = entry->path();
        const auto type = readAttribute(supply, "type");
        if (readAttribute(supply, "scope") == "Device")
            continue;

        if (type == "Battery" && readNumber(supply, "present") != 0) {
            const int percent = batteryPercentage(supply);
            if (percent >= 0) {
                total += percent;
                ++count;
                charging |= readAttribute(supply, "status") == "Charging";
            }
        } else if (type == "Mains" || type == "Wireless" || type.rfind("USB", 0) == 0) {
            const auto online = readNumber(supply, "online");
            adapterReported |= online >= 0;
            adapterOnline |= online == 1;
        }
    }
    return count ? Battery{(total + count / 2) / count, adapterReported ? adapterOnline : charging} : Battery{};
}

HWND indicator;
HWND transport;
Battery battery;
Clock::time_point nextLayout;
Clock::time_point nextBatteryRead;

int scale(int pixels)
{
    const int scaling = SWELL_GetScaling256();
    return MulDiv(pixels, scaling > 0 ? scaling : 256, 256);
}

RECT windowFrame(HWND window, HWND parent)
{
    RECT frame{};
    if (GetWindowRect(window, &frame)) {
        POINT topLeft{frame.left, frame.top};
        POINT bottomRight{frame.right, frame.bottom};
        ScreenToClient(parent, &topLeft);
        ScreenToClient(parent, &bottomRight);
        frame = {topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
    }
    return frame;
}

bool sameFrame(const RECT& a, const RECT& b)
{
    return a.left == b.left && a.right == b.right && a.top == b.top && a.bottom == b.bottom;
}

void moveWindow(HWND window, const RECT& frame)
{
    SetWindowPos(window, nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top, SWP_NOACTIVATE | SWP_NOZORDER);
}

struct FrameReservation {
    HWND window{};
    HWND parent{};
    RECT original{};
    RECT adjusted{};

    bool isAppliedTo(HWND candidate) const
    {
        return candidate && candidate == window && IsWindow(candidate) &&
            GetParent(candidate) == parent && sameFrame(windowFrame(candidate, parent), adjusted);
    }

    RECT fullFrame(HWND candidate) const
    {
        return isAppliedTo(candidate) ? original : windowFrame(candidate, GetParent(candidate));
    }

    void restore()
    {
        if (isAppliedTo(window))
            moveWindow(window, original);
        window = nullptr;
    }

    bool apply(HWND target, const RECT& full, const RECT& remaining)
    {
        if (window != target)
            restore();
        window = target;
        parent = GetParent(target);
        original = full;
        adjusted = remaining;
        if (sameFrame(windowFrame(target, parent), adjusted))
            return false;
        moveWindow(target, adjusted);
        return true;
    }
} reservation;

COLORREF batteryColor()
{
    if (battery.pluggedIn)
        return RGB(89, 173, 255);
    if (battery.percent >= 50)
        return RGB(107, 219, 130);
    if (battery.percent >= 20)
        return RGB(255, 207, 79);
    return RGB(255, 102, 107);
}

void paintIndicator(HWND window, HDC dc)
{
    RECT area{};
    GetClientRect(window, &area);
    const int width = area.right;
    const int height = area.bottom;

    RECT bar{};
    if (transport && IsWindow(transport))
        GetClientRect(transport, &bar);
    const HDC source = bar.right > 2 && bar.bottom >= height ? GetDC(transport) : nullptr;
    if (source) {
        const auto slot = windowFrame(window, transport);
        const int y = std::clamp<int>(slot.top, 0, bar.bottom - height);
        const int x = indicatorPosition == IndicatorPosition::Left ? 1 : bar.right - 2;
        StretchBlt(dc, 0, 0, width, height, source, x, y, 1, height, SRCCOPY);
        ReleaseDC(transport, source);
    } else {
        const int themeColor = getThemeColor("col_trans_bg", 0);
        HBRUSH fill = CreateSolidBrush(themeColor < 0 ? GetSysColor(COLOR_BTNFACE) : themeColor);
        FillRect(dc, &area, fill);
        DeleteObject(fill);
    }

    const bool drawPercentage = showPercentage && width >= scale(indicatorWidthWithPercentage);
    const COLORREF color = batteryColor();
    const int iconWidth = scale(drawPercentage ? 16 : 21);
    const int iconHeight = scale(drawPercentage ? 10 : 13);
    const int capWidth = scale(2);
    const int x = drawPercentage ? scale(8) : (width - iconWidth - capWidth) / 2;
    const int y = (height - iconHeight) / 2;

    const HPEN pen = CreatePen(PS_SOLID, scale(1), color);
    const HGDIOBJ oldPen = SelectObject(dc, pen);
    const HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    RoundRect(dc, x, y, x + iconWidth, y + iconHeight, scale(4), scale(4));
    SelectObject(dc, oldBrush);
    SelectObject(dc, oldPen);
    DeleteObject(pen);

    const HBRUSH fill = CreateSolidBrush(color);
    const RECT cap{x + iconWidth, y + iconHeight / 3, x + iconWidth + capWidth, y + 2 * iconHeight / 3};
    FillRect(dc, &cap, fill);
    const int inset = scale(2);
    const RECT charge{x + inset, y + inset,
        x + inset + MulDiv(iconWidth - 2 * inset, battery.percent, 100), y + iconHeight - inset};
    FillRect(dc, &charge, fill);
    DeleteObject(fill);

    if (drawPercentage) {
        char label[8];
        std::snprintf(label, sizeof(label), "%d%%", battery.percent);
        RECT textArea{x + iconWidth + capWidth + scale(2), 0, width - scale(5), height};
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, color);
        DrawText(dc, label, -1, &textArea, DT_SINGLELINE | DT_RIGHT | DT_VCENTER | DT_NOPREFIX);
    }
}

LRESULT indicatorProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        if (const HDC dc = BeginPaint(window, &paint))
            paintIndicator(window, dc);
        EndPaint(window, &paint);
        return 0;
    }
    case WM_CONTEXTMENU: {
        if (const HMENU menu = createOptionsMenu(true)) {
            const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam), 0, window, nullptr);
            DestroyMenu(menu);
            handleOptionCommand(command, 0);
        }
        return 0;
    }
    case WM_DESTROY:
        if (indicator == window)
            indicator = nullptr;
        break;
    }
    return DefWindowProc(window, message, wparam, lparam);
}

HWND findDockedTransport(HWND mainWindow)
{
    for (HWND child = GetWindow(mainWindow, GW_CHILD); child; child = GetWindow(child, GW_HWNDNEXT)) {
        if (!IsWindowVisible(child))
            continue;
        char name[64]{};
        const HWND status = GetDlgItem(child, transportStatusControlId);
        if (status && GetClassName(status, name, sizeof(name)) && std::strcmp(name, "REAPERstatusdisp") == 0)
            return child;
    }
    return nullptr;
}

HWND centerAnchor(HWND bar, int width)
{
    const HWND status = GetDlgItem(bar, transportStatusControlId);
    if (!status || !IsWindowVisible(status))
        return nullptr;

    const RECT frame = reservation.fullFrame(status);
    RECT area{};
    RECT visible{};
    GetClientRect(bar, &area);
    return IntersectRect(&visible, &frame, &area) && sameFrame(visible, frame) &&
        frame.right - frame.left >= scale(200) + width &&
        frame.bottom - frame.top >= scale(indicatorHeight) ? status : nullptr;
}

void detachIndicator()
{
    if (indicator)
        ShowWindow(indicator, SW_HIDE);
    reservation.restore();
    transport = nullptr;
}

bool createIndicator(REAPER_PLUGIN_HINSTANCE)
{
    battery = {};
    nextLayout = {};
    nextBatteryRead = {};
    return true;
}

void destroyIndicator()
{
    detachIndicator();
    if (indicator)
        DestroyWindow(indicator);
}

void redrawIndicator()
{
    if (indicator && IsWindowVisible(indicator))
        InvalidateRect(indicator, nullptr, FALSE);
}

void updateTransport()
{
    const HWND mainWindow = getMainWindow();
    const bool shouldShow = battery.percent >= 0 && (showWhenPluggedIn || !battery.pluggedIn) &&
        (!fullscreenOnly || reaperIsFullscreen());
    const HWND bar = mainWindow && shouldShow ? findDockedTransport(mainWindow) : nullptr;
    if (bar != transport)
        detachIndicator();
    if (!bar)
        return;

    RECT mainArea{};
    RECT visible{};
    GetClientRect(mainWindow, &mainArea);
    const RECT fullBar = reservation.fullFrame(bar);
    const int compactWidth = scale(indicatorWidthWithoutPercentage);
    if (!IntersectRect(&visible, &fullBar, &mainArea) ||
        visible.right - visible.left <= compactWidth || visible.bottom - visible.top < scale(indicatorHeight)) {
        detachIndicator();
        return;
    }

    const int fullWidth = scale(indicatorWidthWithPercentage);
    const int width = showPercentage && visible.right - visible.left > fullWidth ? fullWidth : compactWidth;
    const HWND center = indicatorPosition == IndicatorPosition::Center ? centerAnchor(bar, width) : nullptr;
    const HWND anchor = center ? center : bar;
    const HWND parent = center ? bar : mainWindow;
    if (reservation.window != anchor)
        reservation.restore();
    const RECT original = center ? reservation.fullFrame(center) : fullBar;
    const RECT area = center ? original : visible;
    const bool left = indicatorPosition == IndicatorPosition::Left;
    const int x = left ? area.left : area.right - width;
    const RECT position{x, area.top, x + width, area.bottom};

    if (indicator && GetParent(indicator) != parent)
        DestroyWindow(indicator);
    if (!indicator)
        indicator = CreateDialog(nullptr, nullptr, parent, reinterpret_cast<DLGPROC>(indicatorProc));
    if (!indicator) {
        detachIndicator();
        return;
    }

    RECT remaining = original;
    if (left)
        remaining.left = position.right;
    else
        remaining.right = position.left;
    const bool changed = reservation.apply(anchor, original, remaining);
    transport = bar;
    if (!sameFrame(windowFrame(indicator, parent), position))
        moveWindow(indicator, position);
    if (!IsWindowVisible(indicator))
        ShowWindow(indicator, SW_SHOWNA);
    if (changed)
        redrawIndicator();
}

void tick()
{
    const auto now = Clock::now();
    if (now < nextLayout)
        return;
    nextLayout = now + std::chrono::milliseconds(250);
    const bool refreshBattery = now >= nextBatteryRead;
    if (refreshBattery) {
        battery = readBattery("/sys/class/power_supply");
        nextBatteryRead = now + std::chrono::seconds(2);
    }
    updateTransport();
    if (refreshBattery)
        redrawIndicator();
}

} // namespace
