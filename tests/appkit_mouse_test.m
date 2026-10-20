#import <Cocoa/Cocoa.h>
#include <math.h>
#include <stdio.h>

#include "appkit_mouse.h"

@interface RetinaWindow : NSWindow
@end
@implementation RetinaWindow
- (CGFloat)backingScaleFactor { return 2.0; }
@end

static int failures = 0;

static void expectPoint(const char* label, const char* name, NSPoint got, double wantX, double wantY) {
    if (fabs(got.x - wantX) > 0.01 || fabs(got.y - wantY) > 0.01) {
        printf("FAIL %s / %s: got (%.2f, %.2f), want (%.2f, %.2f)\n", label, name, got.x, got.y, wantX, wantY);
        failures++;
    } else {
        printf("ok   %s / %s\n", label, name);
    }
}

static void runCase(const char* label, Class windowClass) {
    const double W = 640, H = 360;
    NSWindow* window = [[windowClass alloc] initWithContentRect:NSMakeRect(100, 100, W, H)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
    NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    [window setContentView:view];

    double s = [window backingScaleFactor];

    expectPoint(label, "top-left",     appkitWindowPointToViewPixels(view, NSMakePoint(0, H)), 0,     0);
    expectPoint(label, "bottom-left",  appkitWindowPointToViewPixels(view, NSMakePoint(0, 0)), 0,     H * s);
    expectPoint(label, "top-right",    appkitWindowPointToViewPixels(view, NSMakePoint(W, H)), W * s, 0);
    expectPoint(label, "bottom-right", appkitWindowPointToViewPixels(view, NSMakePoint(W, 0)), W * s, H * s);
    expectPoint(label, "asymmetric",   appkitWindowPointToViewPixels(view, NSMakePoint(W / 4, H * 3 / 4)), W / 4 * s, H / 4 * s);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        runCase("host scale", [NSWindow class]);
        runCase("2x scale",   [RetinaWindow class]);
    }
    printf(failures == 0 ? "PASS\n" : "FAILED (%d)\n", failures);
    return failures == 0 ? 0 : 1;
}
