#include "reabattery_host.hpp"

#include <algorithm>
#include <cwchar>
#include <iterator>
#include <windowsx.h>

namespace {

constexpr wchar_t indicatorClass[] = L"ReaBattery.Indicator";
constexpr wchar_t statusClass[] = L"REAPERstatusdisp";
constexpr int dpiAt100Percent = 96;

HINSTANCE module;
HWND indicator;
HWND transport;
RECT previousVisibleBar;
bool leftEdgeBackground;
Battery battery;
Clock::time_point nextLayout{};
Clock::time_point nextBatteryRead{};
Clock::time_point nextBackgroundRead{};

RECT windowFrame(HWND window, HWND parent)
{
    RECT frame{};
    if (GetWindowRect(window, &frame))
        MapWindowPoints(nullptr, parent, reinterpret_cast<POINT*>(&frame), 2);
    return frame;
}

void moveWindow(HWND window, const RECT& frame)
{
    SetWindowPos(window, nullptr, frame.left, frame.top,
                 frame.right - frame.left, frame.bottom - frame.top,
                 SWP_NOACTIVATE | SWP_NOZORDER);
}

struct FrameReservation {
    HWND window{};
    HWND parent{};
    RECT original{};
    RECT adjusted{};

    bool isAppliedTo(HWND candidate) const
    {
        if (!candidate || candidate != window || !parent || GetParent(candidate) != parent)
            return false;
        const RECT current = windowFrame(candidate, parent);
        return EqualRect(&current, &adjusted);
    }

    RECT originalFrame(HWND candidate) const
    {
        return isAppliedTo(candidate) ? original : windowFrame(candidate, GetParent(candidate));
    }

    void restore()
    {
        if (isAppliedTo(window))
            moveWindow(window, original);
        window = nullptr;
        parent = nullptr;
    }

    bool apply(HWND target, const RECT& fullFrame, const RECT& newFrame)
    {
        window = target;
        parent = GetParent(target);
        original = fullFrame;
        adjusted = newFrame;
        const RECT current = windowFrame(target, parent);
        if (EqualRect(&current, &newFrame))
            return false;
        moveWindow(target, newFrame);
        return true;
    }
} reservation;

Battery readBattery()
{
    SYSTEM_POWER_STATUS status{};
    if (!GetSystemPowerStatus(&status) || status.BatteryLifePercent > 100 ||
        (status.BatteryFlag != 255 && (status.BatteryFlag & 128)))
        return {};

    const bool pluggedIn = status.ACLineStatus == 1 ||
        (status.ACLineStatus == 255 && status.BatteryFlag != 255 && (status.BatteryFlag & 8));
    return {status.BatteryLifePercent, pluggedIn};
}

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

int scaleForWindow(HWND window, int pixels)
{
    const UINT dpi = GetDpiForWindow(window);
    return MulDiv(pixels, dpi ? dpi : dpiAt100Percent, dpiAt100Percent);
}

void paintIndicator(HWND window, HDC dc, const RECT& area)
{
    const int width = area.right;
    const int height = area.bottom;
    RECT bar{};
    bool painted = false;
    if (GetClientRect(transport, &bar) && bar.right > 2 && bar.bottom >= height) {
        const RECT slot = windowFrame(window, transport);
        const int sourceY = std::clamp<int>(slot.top, 0, bar.bottom - height);
        const bool useLeft = leftEdgeBackground || (GetParent(window) == transport && slot.right >= bar.right - 2);
        const int sourceX = useLeft ? 1 : bar.right - 2;
        if (HDC source = GetDC(transport)) {
            painted = StretchBlt(dc, 0, 0, width, height, source,
                                 sourceX, sourceY, 1, height, SRCCOPY) != 0;
            ReleaseDC(transport, source);
        }
    }
    if (!painted) {
        const int color = getThemeColor("col_trans_bg", 0);
        HBRUSH fill = CreateSolidBrush(color < 0 ? GetSysColor(COLOR_BTNFACE) : static_cast<COLORREF>(color));
        FillRect(dc, &area, fill);
        DeleteObject(fill);
    }

    const auto px = [window](int size) { return scaleForWindow(window, size); };
    const bool drawPercentage = showPercentage && width >= px(indicatorWidthWithPercentage);
    const COLORREF color = batteryColor();
    const int iconWidth = px(drawPercentage ? 16 : 21);
    const int iconHeight = px(drawPercentage ? 10 : 13);
    const int capWidth = px(2);
    const int x = drawPercentage ? px(8) : (width - iconWidth - capWidth) / 2;
    const int y = (height - iconHeight) / 2;

    HPEN pen = CreatePen(PS_SOLID, px(1), color);
    HGDIOBJ oldPen = SelectObject(dc, pen);
    HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    RoundRect(dc, x, y, x + iconWidth, y + iconHeight, px(4), px(4));
    SelectObject(dc, oldBrush);
    SelectObject(dc, oldPen);
    DeleteObject(pen);

    HBRUSH fill = CreateSolidBrush(color);
    const RECT cap{x + iconWidth, y + iconHeight / 3, x + iconWidth + capWidth, y + 2 * iconHeight / 3};
    FillRect(dc, &cap, fill);
    const int padding = px(2);
    const RECT charge{x + padding, y + padding,
        x + padding + MulDiv(iconWidth - 2 * padding, battery.percent, 100), y + iconHeight - padding};
    FillRect(dc, &charge, fill);
    DeleteObject(fill);

    if (drawPercentage) {
        wchar_t label[8]{};
        std::swprintf(label, std::size(label), L"%d%%", battery.percent);
        RECT textArea{x + iconWidth + capWidth + px(2), 0, width - px(8), height};
        HFONT font = CreateFontW(-px(12), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                                 OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, DEFAULT_QUALITY,
                                 DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        HGDIOBJ oldFont = font ? SelectObject(dc, font) : nullptr;
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, color);
        DrawTextW(dc, label, -1, &textArea, DT_SINGLELINE | DT_RIGHT | DT_VCENTER | DT_NOPREFIX);
        if (oldFont)
            SelectObject(dc, oldFont);
        if (font)
            DeleteObject(font);
    }
}

LRESULT CALLBACK indicatorProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    switch (message) {
    case WM_PAINT: {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(window, &paint);
        RECT area{};
        GetClientRect(window, &area);
        if (dc && !IsRectEmpty(&area)) {
            HDC buffer = CreateCompatibleDC(dc);
            HBITMAP bitmap = buffer ? CreateCompatibleBitmap(dc, area.right, area.bottom) : nullptr;
            if (bitmap) {
                HGDIOBJ previous = SelectObject(buffer, bitmap);
                paintIndicator(window, buffer, area);
                BitBlt(dc, 0, 0, area.right, area.bottom, buffer, 0, 0, SRCCOPY);
                SelectObject(buffer, previous);
                DeleteObject(bitmap);
            } else {
                paintIndicator(window, dc, area);
            }
            if (buffer)
                DeleteDC(buffer);
        }
        EndPaint(window, &paint);
        return 0;
    }
    case WM_ERASEBKGND:
        return 1;
    case WM_CONTEXTMENU: {
        if (HMENU menu = createOptionsMenu(true)) {
            POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
            if (point.x == -1 && point.y == -1) {
                point = {};
                ClientToScreen(window, &point);
            }
            const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                               point.x, point.y, 0, window, nullptr);
            DestroyMenu(menu);
            handleOptionCommand(command, 0);
        }
        return 0;
    }
    case WM_NCDESTROY:
        if (indicator == window)
            indicator = nullptr;
        break;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

HWND findDockedTransport(HWND mainWindow)
{
    for (HWND child = GetWindow(mainWindow, GW_CHILD); child; child = GetWindow(child, GW_HWNDNEXT)) {
        if (!IsWindowVisible(child))
            continue;
        wchar_t name[64]{};
        if (const HWND status = GetDlgItem(child, transportStatusControlId)) {
            if (GetClassNameW(status, name, static_cast<int>(std::size(name))) && _wcsicmp(name, statusClass) == 0)
                return child;
        }
    }
    return nullptr;
}

HWND findCenterAnchor(HWND bar, HWND mainWindow, int width)
{
    if (indicatorPosition != IndicatorPosition::Center || reservation.isAppliedTo(bar))
        return nullptr;
    const HWND status = GetDlgItem(bar, transportStatusControlId);
    if (!status || GetParent(status) != bar || !IsWindowVisible(status))
        return nullptr;

    RECT available{};
    GetClientRect(bar, &available);
    RECT mainArea{};
    GetClientRect(mainWindow, &mainArea);
    MapWindowPoints(mainWindow, bar, reinterpret_cast<POINT*>(&mainArea), 2);
    IntersectRect(&available, &available, &mainArea);
    const RECT frame = reservation.originalFrame(status);
    RECT visible{};
    IntersectRect(&visible, &frame, &available);
    return EqualRect(&visible, &frame) && frame.right - frame.left >= scaleForWindow(bar, 200) + width &&
        frame.bottom - frame.top >= scaleForWindow(bar, indicatorHeight) ? status : nullptr;
}

void detachIndicator()
{
    if (indicator)
        ShowWindow(indicator, SW_HIDE);
    reservation.restore();
    transport = nullptr;
    previousVisibleBar = {};
    nextBackgroundRead = {};
}

bool createIndicator(REAPER_PLUGIN_HINSTANCE instance)
{
    module = instance;
    nextLayout = {};
    nextBatteryRead = {};
    WNDCLASSW windowClass{};
    windowClass.lpfnWndProc = indicatorProc;
    windowClass.hInstance = module;
    windowClass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    windowClass.lpszClassName = indicatorClass;
    return RegisterClassW(&windowClass) != 0;
}

void destroyIndicator()
{
    detachIndicator();
    if (indicator)
        DestroyWindow(indicator);
    UnregisterClassW(indicatorClass, module);
    module = nullptr;
}

void redrawIndicator()
{
    if (indicator && IsWindowVisible(indicator))
        InvalidateRect(indicator, nullptr, FALSE);
}

void updateTransport()
{
    const HWND mainWindow = getMainWindow();
    const HWND bar = mainWindow && battery.percent >= 0 && (showWhenPluggedIn || !battery.pluggedIn) &&
        (!fullscreenOnly || reaperIsFullscreen()) ? findDockedTransport(mainWindow) : nullptr;
    if (!bar || bar != transport)
        detachIndicator();
    if (!bar)
        return;

    const RECT barFrame = reservation.originalFrame(bar);
    RECT mainArea{};
    GetClientRect(mainWindow, &mainArea);
    RECT visible{};
    IntersectRect(&visible, &barFrame, &mainArea);
    const int compactWidth = scaleForWindow(bar, indicatorWidthWithoutPercentage);
    const int fullWidth = scaleForWindow(bar, indicatorWidthWithPercentage);
    const int visibleWidth = visible.right - visible.left;
    if (visibleWidth <= compactWidth || visible.bottom - visible.top < scaleForWindow(bar, indicatorHeight)) {
        detachIndicator();
        return;
    }
    const int width = showPercentage && visibleWidth > fullWidth ? fullWidth : compactWidth;
    if (indicatorPosition == IndicatorPosition::Center && !EqualRect(&visible, &previousVisibleBar) &&
        reservation.isAppliedTo(bar))
        reservation.restore();
    previousVisibleBar = visible;

    const HWND center = findCenterAnchor(bar, mainWindow, width);
    const HWND anchor = center ? center : bar;
    const HWND parent = center ? bar : mainWindow;
    const RECT original = center ? reservation.originalFrame(center) : barFrame;
    const RECT area = center ? original : visible;
    leftEdgeBackground = indicatorPosition == IndicatorPosition::Left;
    const int x = leftEdgeBackground ? area.left : area.right - width;
    const RECT position{x, area.top, x + width, area.bottom};

    if (indicator && GetParent(indicator) != parent)
        DestroyWindow(indicator);
    if (!indicator) {
        indicator = CreateWindowExW(0, indicatorClass, L"ReaBattery", WS_CHILD | WS_CLIPSIBLINGS,
                                   0, 0, 0, 0, parent, nullptr, module, nullptr);
        if (!indicator) {
            detachIndicator();
            return;
        }
    }
    if (reservation.window && reservation.window != anchor)
        reservation.restore();
    RECT remaining = original;
    if (leftEdgeBackground)
        remaining.left = position.right;
    else
        remaining.right = position.left;
    const bool barChanged = reservation.apply(anchor, original, remaining);
    transport = bar;
    const RECT oldPosition = windowFrame(indicator, parent);
    if (!IsWindowVisible(indicator) || !EqualRect(&oldPosition, &position)) {
        SetWindowPos(indicator, HWND_TOP, position.left, position.top, width,
                     position.bottom - position.top, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
    const auto now = Clock::now();
    if (barChanged || now >= nextBackgroundRead) {
        redrawIndicator();
        nextBackgroundRead = now + std::chrono::seconds(1);
    }
}

void tick()
{
    const auto now = Clock::now();
    if (now < nextLayout)
        return;
    nextLayout = now + std::chrono::milliseconds(250);
    const bool powerChanged = now >= nextBatteryRead;
    if (powerChanged) {
        battery = readBattery();
        nextBatteryRead = now + std::chrono::seconds(2);
    }
    updateTransport();
    if (powerChanged && indicator && IsWindowVisible(indicator)) {
        wchar_t name[40]{};
        std::swprintf(name, std::size(name), L"Battery %d%%%ls", battery.percent,
                      battery.pluggedIn ? L", plugged in" : L"");
        SetWindowTextW(indicator, name);
        redrawIndicator();
    }
}

} // namespace
