#import <Cocoa/Cocoa.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/ps/IOPowerSources.h>

#define NOMINMAX
#include <reaper_plugin.h>

#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {

constexpr CGFloat indicatorWidthWithPercentage = 64;
constexpr CGFloat indicatorWidthWithoutPercentage = 34;
constexpr CGFloat indicatorHeight = 20;
constexpr char settingsSection[] = "ReaBattery";
constexpr char showPercentageKey[] = "ShowPercentage";
constexpr char fullscreenOnlyKey[] = "FullscreenOnly";
constexpr char showWhenPluggedInKey[] = "ShowWhenPluggedIn";
constexpr char positionKey[] = "Position";
constexpr int transportStatusControlId = 1010;
using Clock = std::chrono::steady_clock;

enum class IndicatorPosition { Right, Left, Center };
constexpr const char* positionValues[] = {"right", "left", "center"};

bool showPercentage = true;
bool fullscreenOnly = false;
bool showWhenPluggedIn = true;
IndicatorPosition indicatorPosition = IndicatorPosition::Right;
void (*setExtState)(const char*, const char*, const char*, bool);
void detachIndicator();
void updateTransport();

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

bool matches(CFTypeRef value, CFStringRef expected)
{
    return value && CFEqual(value, expected);
}

int capacity(CFDictionaryRef source, CFStringRef key)
{
    const auto value = (CFNumberRef)CFDictionaryGetValue(source, key);
    int result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID() &&
        CFNumberGetValue(value, kCFNumberIntType, &result))
        return result;
    return -1;
}

Battery readBattery()
{
    CFTypeRef snapshot = IOPSCopyPowerSourcesInfo();
    if (!snapshot)
        return {};

    Battery battery;
    CFArrayRef sources = IOPSCopyPowerSourcesList(snapshot);
    if (sources) {
        const CFIndex count = CFArrayGetCount(sources);
        for (CFIndex i = 0; i < count; ++i) {
            CFDictionaryRef source = IOPSGetPowerSourceDescription(
                snapshot, CFArrayGetValueAtIndex(sources, i));
            if (!source ||
                !matches(CFDictionaryGetValue(source, CFSTR(kIOPSTypeKey)), CFSTR(kIOPSInternalBatteryType)) ||
                CFDictionaryGetValue(source, CFSTR(kIOPSIsPresentKey)) == kCFBooleanFalse)
                continue;

            const int current = capacity(source, CFSTR(kIOPSCurrentCapacityKey));
            const int maximum = capacity(source, CFSTR(kIOPSMaxCapacityKey));
            if (current < 0 || maximum <= 0)
                continue;

            battery.percent = std::lround(100.0 * std::min(current, maximum) / maximum);
            CFTypeRef power = CFDictionaryGetValue(source, CFSTR(kIOPSPowerSourceStateKey));
            if (!power)
                power = IOPSGetProvidingPowerSourceType(snapshot);
            battery.pluggedIn = matches(power, CFSTR(kIOPSACPowerValue));
            break;
        }
        CFRelease(sources);
    }
    CFRelease(snapshot);
    return battery;
}

NSColor* batteryColor(Battery battery)
{
    if (battery.pluggedIn)
        return [NSColor colorWithSRGBRed:0.35 green:0.68 blue:1 alpha:1];
    if (battery.percent >= 50)
        return [NSColor colorWithSRGBRed:0.42 green:0.86 blue:0.51 alpha:1];
    if (battery.percent >= 20)
        return [NSColor colorWithSRGBRed:1 green:0.81 blue:0.31 alpha:1];
    return [NSColor colorWithSRGBRed:1 green:0.40 blue:0.42 alpha:1];
}

} // namespace

@interface ReaBatteryIndicator : NSView
- (void)showBattery:(Battery)battery;
- (void)refreshBackgroundFromTransport:(NSView*)view leftEdge:(BOOL)leftEdge fallbackColor:(int)color;
@end

@implementation ReaBatteryIndicator {
    Battery _battery;
    NSString* _percentText;
    NSBitmapImageRep* _transportEdge;
    int _fallbackColor;
}

- (NSRect)badgeRect
{
    const CGFloat y = std::floor(NSMidY(self.bounds) - indicatorHeight / 2);
    return NSMakeRect(3, y, NSWidth(self.bounds) - 7, indicatorHeight);
}

- (NSView*)hitTest:(NSPoint)point
{
    if (!NSPointInRect([self convertPoint:point fromView:self.superview], [self badgeRect]))
        return nil;
    return [super hitTest:point];
}

- (NSMenu*)menuForEvent:(NSEvent*)event
{
    NSMenu* menu = [[NSMenu alloc] init];
    NSMenuItem* item = [menu addItemWithTitle:@"Show Percentage"
                                      action:@selector(togglePercentage:)
                               keyEquivalent:@""];
    item.target = self;
    item.state = showPercentage ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* fullscreenItem = [menu addItemWithTitle:@"Show Only in Fullscreen"
                                                action:@selector(toggleFullscreenOnly:)
                                         keyEquivalent:@""];
    fullscreenItem.target = self;
    fullscreenItem.state = fullscreenOnly ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* pluggedInItem = [menu addItemWithTitle:@"Show when plugged-in"
                                              action:@selector(toggleShowWhenPluggedIn:)
                                       keyEquivalent:@""];
    pluggedInItem.target = self;
    pluggedInItem.state = showWhenPluggedIn ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* positionItem = [menu addItemWithTitle:@"Position" action:nil keyEquivalent:@""];
    NSMenu* positions = [[NSMenu alloc] initWithTitle:@"Position"];
    NSArray<NSString*>* names = @[@"Right Corner", @"Left Corner", @"Center"];
    for (NSUInteger i = 0; i < names.count; ++i) {
        NSMenuItem* choice = [positions addItemWithTitle:names[i]
                                                 action:@selector(changeIndicatorPosition:)
                                          keyEquivalent:@""];
        choice.target = self;
        choice.tag = i;
        choice.state = i == static_cast<NSUInteger>(indicatorPosition)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    positionItem.submenu = positions;
    return menu;
}

- (void)changeIndicatorPosition:(NSMenuItem*)sender
{
    const NSInteger index = sender.tag;
    if (index < 0 || index > static_cast<NSInteger>(IndicatorPosition::Center))
        return;
    const auto position = static_cast<IndicatorPosition>(index);
    if (position == indicatorPosition)
        return;
    indicatorPosition = position;
    setExtState(settingsSection, positionKey, positionValues[index], true);
    detachIndicator();
    updateTransport();
}

- (void)togglePercentage:(NSMenuItem*)sender
{
    showPercentage = !showPercentage;
    sender.state = showPercentage ? NSControlStateValueOn : NSControlStateValueOff;
    setExtState(settingsSection, showPercentageKey, showPercentage ? "1" : "0", true);
    updateTransport();
    self.needsDisplay = YES;
}

- (void)toggleFullscreenOnly:(NSMenuItem*)sender
{
    fullscreenOnly = !fullscreenOnly;
    sender.state = fullscreenOnly ? NSControlStateValueOn : NSControlStateValueOff;
    setExtState(settingsSection, fullscreenOnlyKey, fullscreenOnly ? "1" : "0", true);
    updateTransport();
}

- (void)toggleShowWhenPluggedIn:(NSMenuItem*)sender
{
    showWhenPluggedIn = !showWhenPluggedIn;
    sender.state = showWhenPluggedIn ? NSControlStateValueOn : NSControlStateValueOff;
    setExtState(settingsSection, showWhenPluggedInKey, showWhenPluggedIn ? "1" : "0", true);
    updateTransport();
}

- (void)showBattery:(Battery)battery
{
    if (_battery.percent == battery.percent && _battery.pluggedIn == battery.pluggedIn)
        return;
    _battery = battery;
    _percentText = [NSString stringWithFormat:@"%d%%", battery.percent];
    self.accessibilityElement = YES;
    self.accessibilityRole = NSAccessibilityStaticTextRole;
    self.accessibilityLabel = @"Battery";
    self.accessibilityValue = battery.pluggedIn
        ? [_percentText stringByAppendingString:@", plugged in"]
        : _percentText;
    self.needsDisplay = YES;
}

- (void)refreshBackgroundFromTransport:(NSView*)view leftEdge:(BOOL)leftEdge fallbackColor:(int)color
{
    // Extend the painted edge so WALTER fills and vertical gradients continue
    // across the space reserved for the indicator.
    _transportEdge = nil;
    if (view) {
        const NSRect bounds = view.bounds;
        const CGFloat pixel = [view convertSizeFromBacking:NSMakeSize(1, 1)].width;
        const CGFloat x = leftEdge ? NSMinX(bounds) + 1 : NSMaxX(bounds) - 1 - pixel;
        const NSRect edge = NSMakeRect(x, NSMinY(bounds), pixel, NSHeight(bounds));
        _transportEdge = [view bitmapImageRepForCachingDisplayInRect:edge];
        if (_transportEdge)
            [view cacheDisplayInRect:edge toBitmapImageRep:_transportEdge];
    }
    _fallbackColor = color;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (_transportEdge) {
        [_transportEdge drawInRect:self.bounds fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver fraction:1
                    respectFlipped:YES hints:nil];
    } else if (_fallbackColor >= 0) {
        [[NSColor colorWithSRGBRed:(_fallbackColor & 0xff) / 255.0
                            green:((_fallbackColor >> 8) & 0xff) / 255.0
                             blue:((_fallbackColor >> 16) & 0xff) / 255.0 alpha:1] setFill];
        NSRectFill(dirtyRect);
    }

    const NSRect badge = [self badgeRect];
    const CGFloat y = NSMinY(badge);

    const bool drawPercentage = showPercentage && NSWidth(self.bounds) >= indicatorWidthWithPercentage;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    if (!drawPercentage) {
        const CGFloat centerX = NSMidX(badge);
        const CGFloat centerY = NSMidY(badge);
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, centerX, centerY);
        CGContextScaleCTM(context, 1.3, 1.3);
        CGContextTranslateCTM(context, -centerX, -centerY);
    }

    NSColor* color = batteryColor(_battery);
    [color set];
    NSBezierPath* outline = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(8.5, y + 5.5, 15, 9)
                                                          xRadius:2 yRadius:2];
    outline.lineWidth = 1;
    [outline stroke];
    NSRectFill(NSMakeRect(24, y + 8, 1.5, 4));
    const CGFloat fillWidth = 12 * _battery.percent / 100.0;
    NSRectFill(NSMakeRect(10, y + 7, fillWidth, 6));

    if (!drawPercentage) {
        CGContextRestoreGState(context);
        return;
    }

    NSDictionary* attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: color
    };
    const NSSize size = [_percentText sizeWithAttributes:attributes];
    [_percentText drawAtPoint:NSMakePoint(55 - size.width, y + (indicatorHeight - size.height) / 2)
               withAttributes:attributes];
}

@end

namespace {

int (*registerWithHost)(const char*, void*);
HWND (*getMainWindow)();
int (*getThemeColor)(const char*, int);
int (*getToggleCommandState)(int);

ReaBatteryIndicator* indicator;
__weak NSView* transport;
NSRect previousVisibleBar;

struct FrameReservation {
    __weak NSView* view;
    __weak NSView* parent;
    NSRect original;
    NSRect adjusted;

    bool isAppliedTo(NSView* candidate) const
    {
        return parent && candidate && candidate == view && candidate.superview == parent &&
               NSEqualRects(candidate.frame, adjusted);
    }

    NSRect originalFrame(NSView* candidate) const
    {
        return isAppliedTo(candidate) ? original : candidate.frame;
    }

    void restore()
    {
        NSView* previous = view;
        if (isAppliedTo(previous))
            previous.frame = original;
        view = nil;
        parent = nil;
    }

    bool apply(NSView* target, NSRect fullFrame, NSRect newFrame)
    {
        view = target;
        parent = target.superview;
        original = fullFrame;
        adjusted = newFrame;
        if (NSEqualRects(target.frame, newFrame))
            return false;
        target.frame = newFrame;
        return true;
    }
} reservation;

Clock::time_point nextLayout{};
Clock::time_point nextBatteryRead{};
Clock::time_point nextBackgroundRead{};
Battery battery;

NSView* findDockedTransport(NSView* mainView)
{
    // The main-window Transport dialog has no title when docked at startup.
    for (NSView* view in mainView.subviews) {
        if (view.hidden || view.frame.size.height < indicatorHeight)
            continue;
        const HWND status = GetDlgItem((__bridge HWND)view, transportStatusControlId);
        char className[64]{};
        if (status && GetClassName(status, className, sizeof(className)) &&
            std::strcmp(className, "REAPERstatusdisp") == 0)
            return view;
    }
    return nil;
}

void detachIndicator()
{
    reservation.restore();
    [indicator removeFromSuperview];
    transport = nil;
    previousVisibleBar = NSZeroRect;
    nextBackgroundRead = {};
}

bool isFullscreen(NSWindow* window)
{
    constexpr int toggleReaperFullscreenAction = 40346;
    return (window.styleMask & NSWindowStyleMaskFullScreen) != 0 ||
           (getToggleCommandState && getToggleCommandState(toggleReaperFullscreenAction) == 1);
}

NSView* findCenterAnchor(NSView* bar, NSView* mainView, CGFloat width)
{
    // When Center falls back to a corner, wait for REAPER to lay out a fresh
    // Transport frame before retrying the time display.
    if (indicatorPosition != IndicatorPosition::Center || reservation.isAppliedTo(bar))
        return nil;
    id status = (__bridge id)GetDlgItem((__bridge HWND)bar, transportStatusControlId);
    if (![status isKindOfClass:[NSView class]])
        return nil;
    NSView* display = status;
    const NSRect displayFrame = reservation.originalFrame(display);
    const NSRect visible = NSIntersectionRect(bar.bounds, [bar convertRect:mainView.bounds fromView:mainView]);
    if (display.superview != bar || display.hidden || NSHeight(displayFrame) < indicatorHeight ||
        NSWidth(displayFrame) < 200 + width || !NSContainsRect(visible, displayFrame))
        return nil;
    return display;
}

void updateTransport()
{
    id mainWindow = (__bridge id)getMainWindow();
    NSView* mainView = [mainWindow isKindOfClass:[NSWindow class]]
        ? ((NSWindow*)mainWindow).contentView : mainWindow;
    NSView* current = battery.percent >= 0 && [mainView isKindOfClass:[NSView class]] &&
        (showWhenPluggedIn || !battery.pluggedIn) &&
        (!fullscreenOnly || isFullscreen(mainView.window))
        ? findDockedTransport(mainView) : nil;
    if (!current) {
        detachIndicator();
        return;
    }
    if (current != transport)
        detachIndicator();

    const NSRect barFrame = reservation.originalFrame(current);
    const NSRect visible = NSIntersectionRect(barFrame, mainView.bounds);
    if (NSWidth(visible) <= indicatorWidthWithoutPercentage || NSHeight(visible) < indicatorHeight) {
        detachIndicator();
        return;
    }

    const CGFloat width = showPercentage && NSWidth(visible) > indicatorWidthWithPercentage
        ? indicatorWidthWithPercentage : indicatorWidthWithoutPercentage;
    if (indicatorPosition == IndicatorPosition::Center && !NSEqualRects(visible, previousVisibleBar) &&
        reservation.isAppliedTo(current))
        reservation.restore();
    previousVisibleBar = visible;

    NSView* centerAnchor = findCenterAnchor(current, mainView, width);
    NSView* anchor = centerAnchor ?: current;
    NSView* parent = centerAnchor ? current : mainView;
    if (reservation.view && reservation.view != anchor)
        reservation.restore();

    const bool leftEdge = indicatorPosition == IndicatorPosition::Left;
    const NSRect original = centerAnchor ? reservation.originalFrame(centerAnchor) : barFrame;
    const NSRect area = centerAnchor ? original : visible;
    const CGFloat x = leftEdge ? NSMinX(area) : NSMaxX(area) - width;
    const NSRect position = NSMakeRect(x, NSMinY(area), width, NSHeight(area));

    // Reserve the slot from the time display in Center mode or from the
    // Transport itself at a corner, allowing REAPER to reflow the controls.
    NSRect remaining = original;
    if (leftEdge) {
        remaining.origin.x = NSMaxX(position);
        remaining.size.width = NSMaxX(original) - NSMinX(remaining);
    } else {
        remaining.size.width = NSMinX(position) - NSMinX(original);
    }
    const bool layoutChanged = reservation.apply(anchor, original, remaining);
    transport = current;

    [indicator showBattery:battery];
    const bool parentChanged = indicator.superview != parent;
    if (parentChanged)
        [indicator removeFromSuperview];
    if (!NSEqualRects(indicator.frame, position))
        indicator.frame = position;
    if (parentChanged)
        [parent addSubview:indicator positioned:NSWindowAbove relativeTo:anchor];

    const auto now = Clock::now();
    if (centerAnchor) {
        if (parentChanged)
            [indicator refreshBackgroundFromTransport:nil leftEdge:NO fallbackColor:-1];
    } else if (parentChanged || layoutChanged || now >= nextBackgroundRead) {
        [indicator refreshBackgroundFromTransport:current
                                         leftEdge:leftEdge
                                    fallbackColor:getThemeColor("col_trans_bg", 0)];
        nextBackgroundRead = now + std::chrono::seconds(1);
    }
}

void tick()
{
    const auto now = Clock::now();
    if (now < nextLayout)
        return;
    nextLayout = now + std::chrono::milliseconds(250);

    @autoreleasepool {
        if (now >= nextBatteryRead) {
            battery = readBattery();
            nextBatteryRead = now + std::chrono::seconds(2);
        }
        updateTransport();
    }
}

} // namespace

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(
    REAPER_PLUGIN_HINSTANCE, reaper_plugin_info_t* host)
{
    if (!host) {
        if (registerWithHost)
            registerWithHost("-timer", reinterpret_cast<void*>(tick));
        detachIndicator();
        indicator = nil;
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
    indicator = [[ReaBatteryIndicator alloc] initWithFrame:NSZeroRect];
    if (!host->Register("timer", reinterpret_cast<void*>(tick))) {
        indicator = nil;
        return 0;
    }
    nextLayout = {};
    nextBatteryRead = {};
    registerWithHost = host->Register;
    host->Register("ext_name", const_cast<char*>("ReaBattery"));
    return 1;
}
