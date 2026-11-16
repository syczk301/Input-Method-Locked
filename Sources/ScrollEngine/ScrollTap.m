#import "ScrollTap.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hid/IOHIDUsageTables.h>
#include <math.h>

// These exported symbols are outside the public macOS SDK API.
// Weak imports let the app detect their absence after a macOS update.
extern CFTypeRef CGEventCopyIOHIDEvent(CGEventRef event) CF_RETURNS_RETAINED __attribute__((weak_import));
extern uint64_t IOHIDEventGetSenderID(CFTypeRef event) __attribute__((weak_import));
extern double IOHIDEventGetFloatValue(CFTypeRef event, uint32_t field) __attribute__((weak_import));
extern void IOHIDEventSetFloatValue(CFTypeRef event, uint32_t field, double value) __attribute__((weak_import));

// IOHID scroll event type 6, with vertical (Y) at field offset 1.
static const uint32_t HIDScrollY = (6U << 16) | 1U;
static const int64_t PixelEventTag = 0x5343524F4C4C4452;
static const NSTimeInterval ScrollFrameInterval = 1.0 / 60.0;
static const NSTimeInterval MaximumWheelInterval = 0.075;

typedef NS_ENUM(NSInteger, ScrollDevice) {
    ScrollDeviceUnknown,
    ScrollDeviceTrackpad,
    ScrollDeviceMouse,
};

static ScrollDevice IdentifyDevice(uint64_t sender) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(sender));
    if (!service) {
        return ScrollDeviceUnknown;
    }

    NSString *acceleration = CFBridgingRelease(IORegistryEntryCreateCFProperty(
        service, CFSTR(kIOHIDScrollAccelerationTypeKey), kCFAllocatorDefault, 0));
    NSNumber *usagePage = CFBridgingRelease(IORegistryEntryCreateCFProperty(
        service, CFSTR(kIOHIDPrimaryUsagePageKey), kCFAllocatorDefault, 0));
    NSNumber *usage = CFBridgingRelease(IORegistryEntryCreateCFProperty(
        service, CFSTR(kIOHIDPrimaryUsageKey), kCFAllocatorDefault, 0));
    BOOL trackpadDriver = IOObjectConformsTo(service, "AppleMultitouchTrackpadHIDEventDriver");

    io_registry_entry_t parent = IO_OBJECT_NULL;
    if (!trackpadDriver && IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS) {
        trackpadDriver = IOObjectConformsTo(parent, "AppleMultitouchTrackpadHIDEventDriver");
        IOObjectRelease(parent);
    }
    IOObjectRelease(service);

    BOOL touchpadUsage = usagePage.integerValue == kHIDPage_Digitizer &&
                         usage.integerValue == kHIDUsage_Dig_TouchPad;
    if (trackpadDriver || touchpadUsage || [acceleration isEqual:@"HIDTrackpadScrollAcceleration"]) {
        return ScrollDeviceTrackpad;
    }

    // A local HID service that has emitted a scroll event is treated as a mouse
    // after checking the trackpad markers, including for continuous-scroll mice.
    return ScrollDeviceMouse;
}

static BOOL ShouldReverse(ScrollDirection direction, BOOL natural) {
    return direction != ScrollDirectionSystem && (direction == ScrollDirectionNatural) != natural;
}

static int32_t WheelPixels(CGEventRef event) {
    // Keep the displacement calculated by macOS, including wheel acceleration.
    int64_t points = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    if (!points) {
        // A wheel event can carry a line count without a point delta.
        points = 10 * CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
    }
    return (int32_t)MAX(INT32_MIN + 1, MIN(INT32_MAX, points));
}

static BOOL IsVerticalWheel(CGEventRef event) {
    const CGEventFlags modifiers = kCGEventFlagMaskShift | kCGEventFlagMaskControl |
                                   kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;
    return !(CGEventGetFlags(event) & modifiers) &&
           !CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous) &&
           !CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2) &&
           !CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2) &&
           !CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
}

// A lone or slow tick is delivered whole. During a burst, interpolate only
// within one frame and use the actual wheel cadence, without a deceleration tail.
static NSTimeInterval InterpolationDelay(CGEventTimestamp previous, CGEventTimestamp current) {
    if (!previous || current <= previous) {
        return 0;
    }
    NSTimeInterval interval = (current - previous) / 1e9;
    return interval <= MaximumWheelInterval ? MIN(interval / 2, ScrollFrameInterval) : 0;
}

static CGEventRef CreatePixelEvent(CGEventSourceRef source, int32_t pixels,
                                   CGPoint location, CGEventFlags flags) CF_RETURNS_RETAINED {
    CGEventRef event = CGEventCreateScrollWheelEvent(source, kCGScrollEventUnitPixel, 1, pixels);
    if (event) {
        CGEventSetLocation(event, location);
        CGEventSetFlags(event, flags);
        CGEventSetIntegerValueField(event, kCGEventSourceUserData, PixelEventTag);
    }
    return event;
}

static void ReverseVertical(CGEventRef event, CFTypeRef hidEvent) {
    int64_t lines = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
    double fixed = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
    int64_t points = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1, -lines);
    // Setting the line delta recalculates the other deltas. Restore their
    // original magnitudes so momentum and smooth scrolling retain their step size.
    CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1, -fixed);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1, -points);

    if (hidEvent && IOHIDEventGetFloatValue && IOHIDEventSetFloatValue) {
        double vertical = IOHIDEventGetFloatValue(hidEvent, HIDScrollY);
        IOHIDEventSetFloatValue(hidEvent, HIDScrollY, -vertical);
    }
}

@interface ScrollTap ()
- (void)resumeTap;
- (CGEventRef)adjustEvent:(CGEventRef)event proxy:(CGEventTapProxy)proxy;
- (void)cancelSmoothScroll;
@end

static CGEventRef HandleScroll(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    ScrollTap *tap = (__bridge ScrollTap *)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [tap resumeTap];
    } else if (type == kCGEventScrollWheel && event) {
        @autoreleasepool {
            return [tap adjustEvent:event proxy:proxy];
        }
    }
    return event;
}

@implementation ScrollTap {
    CFMachPortRef _port;
    CFRunLoopSourceRef _source;
    NSMutableDictionary<NSNumber *, NSNumber *> *_devices;
    CGEventSourceRef _smoothSource;
    NSTimer *_smoothTimer;
    int32_t _pendingPixels;
    CGPoint _scrollLocation;
    CGEventFlags _scrollFlags;
    uint64_t _scrollSender;
    int64_t _scrollWindow;
    CGEventTimestamp _lastWheelTimestamp;
    BOOL _lastWheelPositive;
}

@synthesize smoothMouseScrolling = _smoothMouseScrolling;
@synthesize mouseDirection = _mouseDirection;

+ (BOOL)canIdentifyDevices {
    return CGEventCopyIOHIDEvent && IOHIDEventGetSenderID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _trackpadDirection = ScrollDirectionNatural;
        _mouseDirection = ScrollDirectionClassic;
        _devices = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)isRunning {
    return _port && CFMachPortIsValid(_port) && CGEventTapIsEnabled(_port);
}

- (BOOL)start {
    if (self.running) {
        return YES;
    }
    [self stop];
    if (!ScrollTap.canIdentifyDevices || !AXIsProcessTrusted()) {
        return NO;
    }

    _port = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault,
                             CGEventMaskBit(kCGEventScrollWheel), HandleScroll, (__bridge void *)self);
    if (!_port) {
        return NO;
    }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _port, 0);
    if (!_source) {
        [self stop];
        return NO;
    }
    _smoothSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    [self resumeTap];
    return self.running;
}

- (void)stop {
    [self cancelSmoothScroll];
    if (_smoothSource) {
        CFRelease(_smoothSource);
        _smoothSource = NULL;
    }
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_port) {
        CFMachPortInvalidate(_port);
        CFRelease(_port);
        _port = NULL;
    }
    [_devices removeAllObjects];
}

- (void)dealloc {
    [self stop];
}

- (void)resumeTap {
    if (_port && CFMachPortIsValid(_port)) {
        CGEventTapEnable(_port, true);
    }
}

- (void)setSmoothMouseScrolling:(BOOL)enabled {
    _smoothMouseScrolling = enabled;
    if (!enabled) {
        [self cancelSmoothScroll];
    }
}

- (void)setMouseDirection:(ScrollDirection)direction {
    _mouseDirection = direction;
    [self cancelSmoothScroll];
}

- (void)refreshPostingPermission {
    _canPostScrollEvents = CGPreflightPostEventAccess();
    if (!_canPostScrollEvents) {
        [self cancelSmoothScroll];
    }
}

- (void)clearPendingFrame {
    [_smoothTimer invalidate];
    _smoothTimer = nil;
    _pendingPixels = 0;
}

- (void)cancelSmoothScroll {
    [self clearPendingFrame];
    _lastWheelTimestamp = 0;
}

- (void)postPendingFrameAt:(CGEventTapProxy)proxy {
    int32_t pixels = _pendingPixels;
    [self clearPendingFrame];
    if (!pixels) {
        return;
    }

    CGEventRef frame = CreatePixelEvent(_smoothSource, pixels, _scrollLocation, _scrollFlags);
    if (frame) {
        if (proxy) {
            CGEventTapPostEvent(proxy, frame);
        } else {
            CGEventPost(kCGSessionEventTap, frame);
        }
        CFRelease(frame);
    }
}

- (void)postScheduledFrame {
    CGEventRef pointer = CGEventCreate(NULL);
    if (pointer) {
        CGPoint location = CGEventGetLocation(pointer);
        CFRelease(pointer);
        if (hypot(location.x - _scrollLocation.x, location.y - _scrollLocation.y) > 32) {
            [self cancelSmoothScroll];
            return;
        }
    }
    [self postPendingFrameAt:NULL];
}

- (CGEventRef)pixelEventForWheel:(CGEventRef)event pixels:(int32_t)pixels
                         sender:(uint64_t)sender proxy:(CGEventTapProxy)proxy {
    CGPoint location = CGEventGetLocation(event);
    CGEventFlags flags = CGEventGetFlags(event);
    CGEventTimestamp timestamp = CGEventGetTimestamp(event);
    int64_t window = CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent);
    BOOL interpolate = self.smoothMouseScrolling && self.canPostScrollEvents && _smoothSource;
    BOOL sameTarget = _lastWheelTimestamp && sender == _scrollSender && window == _scrollWindow &&
                      flags == _scrollFlags &&
                      hypot(location.x - _scrollLocation.x, location.y - _scrollLocation.y) <= 32;
    NSTimeInterval delay = 0;
    if (interpolate && sameTarget) {
        [self postPendingFrameAt:proxy];
        if (_lastWheelPositive == (pixels > 0)) {
            delay = InterpolationDelay(_lastWheelTimestamp, timestamp);
        }
    } else {
        [self cancelSmoothScroll];
    }

    int32_t deferred = delay > 0 ? pixels / 2 : 0;
    CGEventRef immediate = CreatePixelEvent(_smoothSource, pixels - deferred, location, flags);
    if (!immediate) {
        [self cancelSmoothScroll];
        return NULL;
    }
    CGEventSetTimestamp(immediate, timestamp);
    if (interpolate) {
        _lastWheelTimestamp = timestamp;
        _lastWheelPositive = pixels > 0;
        _scrollSender = sender;
        _scrollWindow = window;
        _scrollLocation = location;
        _scrollFlags = flags;
    }
    if (deferred) {
        _pendingPixels = deferred;
        __weak ScrollTap *owner = self;
        _smoothTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
            [owner postScheduledFrame];
        }];
        [NSRunLoop.mainRunLoop addTimer:_smoothTimer forMode:NSRunLoopCommonModes];
    }
    return immediate;
}

// Ordinary wheel events are line-based. Replacing them with pixel events even
// when smoothing is off changes how the receiving app scales the displacement.
- (CGEventRef)adjustMouseWheel:(CGEventRef)event reverse:(BOOL)reverse hidEvent:(CFTypeRef)hidEvent
                       sender:(uint64_t)sender proxy:(CGEventTapProxy)proxy {
    if (self.smoothMouseScrolling && self.canPostScrollEvents && IsVerticalWheel(event)) {
        int32_t pixels = WheelPixels(event);
        if (reverse) pixels = -pixels;
        if (pixels) {
            CGEventRef replacement = [self pixelEventForWheel:event pixels:pixels sender:sender proxy:proxy];
            if (replacement) return replacement;
        }
    }
    [self cancelSmoothScroll];
    if (reverse) ReverseVertical(event, hidEvent);
    return event;
}

- (CGEventRef)adjustEvent:(CGEventRef)event proxy:(CGEventTapProxy)proxy {
    // Pixel events posted by the animation must reach apps without re-entering it.
    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == PixelEventTag) {
        return event;
    }
    CFTypeRef hidEvent = CGEventCopyIOHIDEvent(event);
    if (!hidEvent) {
        [self cancelSmoothScroll];
        return event;
    }

    uint64_t sender = IOHIDEventGetSenderID(hidEvent);
    if (sender) {
        NSNumber *key = @(sender);
        NSNumber *cachedDevice = _devices[key];
        ScrollDevice device = cachedDevice ? cachedDevice.integerValue : IdentifyDevice(sender);
        if (!cachedDevice) {
            // Bound the cache across reconnects. Registry IDs are unique within a boot.
            if (_devices.count >= 128) {
                [_devices removeAllObjects];
            }
            _devices[key] = @(device);
        }
        if (device != ScrollDeviceUnknown) {
            ScrollDirection direction = device == ScrollDeviceTrackpad ? self.trackpadDirection : self.mouseDirection;
            NSEvent *scroll = [NSEvent eventWithCGEvent:event];
            BOOL reverse = scroll && ShouldReverse(direction, scroll.isDirectionInvertedFromDevice);
            if (device == ScrollDeviceMouse) {
                CGEventRef result = [self adjustMouseWheel:event reverse:reverse hidEvent:hidEvent
                                                   sender:sender proxy:proxy];
                CFRelease(hidEvent);
                return result;
            }
            if (reverse) {
                ReverseVertical(event, hidEvent);
            }
        }
    }
    CFRelease(hidEvent);
    [self cancelSmoothScroll];
    return event;
}
@end
