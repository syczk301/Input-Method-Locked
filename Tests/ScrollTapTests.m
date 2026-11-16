#import "../Sources/ScrollEngine/ScrollTap.m"
#include <assert.h>

// Exercise the same mouse dispatch path as the live tap without posting events.
@interface ObservedScrollTap : ScrollTap
@property BOOL permitted;
@property NSUInteger conversions;
@end
@implementation ObservedScrollTap
- (BOOL)canPostScrollEvents { return self.permitted; }
- (CGEventRef)pixelEventForWheel:(CGEventRef)event pixels:(int32_t)pixels
                        sender:(uint64_t)sender proxy:(CGEventTapProxy)proxy {
    self.conversions++;
    return NULL; // Also exercise safe fallback after a failed allocation.
}
@end

int main(void) {
    @autoreleasepool {
        ObservedScrollTap *tap = [ObservedScrollTap new];
        for (int smooth = 0; smooth <= 1; smooth++) {
            for (int permission = 0; permission <= 1; permission++) {
                for (int reverse = 0; reverse <= 1; reverse++) {
                    for (int lines = -12; lines <= 12; lines++) {
                        if (!lines) continue;
                        CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, lines);
                        assert(event);
                        // Deliberately unequal representations: do not regenerate one from another.
                        double fixed = lines * 1.25;
                        int64_t points = lines * 23;
                        CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1, fixed);
                        CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1, points);
                        CGEventSetTimestamp(event, 123456789);
                        tap.smoothMouseScrolling = smooth;
                        tap.permitted = permission;
                        tap.conversions = 0;
                        CGEventRef result = [tap adjustMouseWheel:event reverse:reverse hidEvent:NULL sender:1 proxy:NULL];
                        assert(result == event);
                        assert(tap.conversions == (smooth && permission ? 1 : 0));
                        int sign = reverse ? -1 : 1;
                        assert(CGEventGetIntegerValueField(result, kCGScrollWheelEventDeltaAxis1) == sign * lines);
                        assert(CGEventGetIntegerValueField(result, kCGScrollWheelEventPointDeltaAxis1) == sign * points);
                        assert(CGEventGetDoubleValueField(result, kCGScrollWheelEventFixedPtDeltaAxis1) == sign * fixed);
                        assert(CGEventGetTimestamp(result) == 123456789);
                        assert(!CGEventGetIntegerValueField(result, kCGScrollWheelEventIsContinuous));
                        NSEvent *native = [NSEvent eventWithCGEvent:result];
                        assert(!native.hasPreciseScrollingDeltas);
                        CFRelease(event);
                    }
                }
            }
        }
        puts("PASS: 192 native wheel cases; disabled/unavailable smoothing bypasses conversion, direction and all deltas preserved");
    }
}
