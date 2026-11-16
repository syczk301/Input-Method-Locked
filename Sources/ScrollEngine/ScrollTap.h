#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, ScrollDirection) {
    ScrollDirectionNatural,
    ScrollDirectionClassic,
    ScrollDirectionSystem,
};

@interface ScrollTap : NSObject
@property (nonatomic) ScrollDirection trackpadDirection;
@property (nonatomic) ScrollDirection mouseDirection;
@property (nonatomic) BOOL smoothMouseScrolling;
@property (nonatomic, readonly) BOOL canPostScrollEvents;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (class, nonatomic, readonly) BOOL canIdentifyDevices;

- (BOOL)start;
- (void)stop;
- (void)refreshPostingPermission;
@end
