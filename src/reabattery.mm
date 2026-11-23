#import <Cocoa/Cocoa.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/ps/IOPowerSources.h>

#include "reabattery_host.hpp"

#include <algorithm>
#include <cmath>

namespace {

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
- (void)togglePercentage:(NSMenuItem*)sender;
- (void)toggleFullscreenOnly:(NSMenuItem*)sender;
- (void)toggleShowWhenPluggedIn:(NSMenuItem*)sender;
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
    NSMenuItem* item = [menu addItemWithTitle:@(optionActions[PercentageOption].title)
                                      action:@selector(togglePercentage:)
                               keyEquivalent:@""];
    item.target = self;
    item.state = showPercentage ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* fullscreenItem = [menu addItemWithTitle:@(optionActions[FullscreenOption].title)
                                                action:@selector(toggleFullscreenOnly:)
                                         keyEquivalent:@""];
    fullscreenItem.target = self;
    fullscreenItem.state = fullscreenOnly ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* pluggedInItem = [menu addItemWithTitle:@(optionActions[PluggedInOption].title)
                                              action:@selector(toggleShowWhenPluggedIn:)
                                       keyEquivalent:@""];
    pluggedInItem.target = self;
    pluggedInItem.state = showWhenPluggedIn ? NSControlStateValueOn : NSControlStateValueOff;
    NSMenuItem* positionItem = [menu addItemWithTitle:@"Position" action:nil keyEquivalent:@""];
    NSMenu* positions = [[NSMenu alloc] initWithTitle:@"Position"];
    for (int i = RightOption; i < OptionCount; ++i) {
        const int position = i - RightOption;
        NSMenuItem* choice = [positions addItemWithTitle:@(optionActions[i].title)
                                                 action:@selector(changeIndicatorPosition:)
                                          keyEquivalent:@""];
        choice.target = self;
        choice.tag = position;
        choice.state = position == static_cast<int>(indicatorPosition)
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
    applyOption(RightOption + static_cast<int>(index));
}

- (void)togglePercentage:(NSMenuItem*)sender
{
    applyOption(PercentageOption);
    sender.state = showPercentage ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleFullscreenOnly:(NSMenuItem*)sender
{
    applyOption(FullscreenOption);
    sender.state = fullscreenOnly ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)toggleShowWhenPluggedIn:(NSMenuItem*)sender
{
    applyOption(PluggedInOption);
    sender.state = showWhenPluggedIn ? NSControlStateValueOn : NSControlStateValueOff;
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
    return (window.styleMask & NSWindowStyleMaskFullScreen) != 0 || reaperIsFullscreen();
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

bool createIndicator(REAPER_PLUGIN_HINSTANCE)
{
    nextLayout = {};
    nextBatteryRead = {};
    indicator = [[ReaBatteryIndicator alloc] initWithFrame:NSZeroRect];
    return indicator != nil;
}

void destroyIndicator()
{
    detachIndicator();
    indicator = nil;
}

void redrawIndicator()
{
    indicator.needsDisplay = YES;
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
