#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static NSMutableSet<NSString *> *patchedWindowClasses;
static char patchedWindowKey;

@interface CortexNativeFullscreenController : NSObject
- (void)toggleFullscreen:(id)sender;
@end

static CortexNativeFullscreenController *fullscreenController;

static BOOL isCortexWindow(NSWindow *window)
{
    if (window == nil || [window isKindOfClass:[NSPanel class]])
        return NO;

    return [NSStringFromClass(window.class) rangeOfString:@"JUCEWindow"].location
           != NSNotFound;
}

static NSWindow *findCortexWindow(void)
{
    NSWindow *window = NSApplication.sharedApplication.mainWindow;

    if (!isCortexWindow(window))
        window = NSApplication.sharedApplication.keyWindow;

    if (!isCortexWindow(window)) {
        for (NSWindow *candidate in NSApplication.sharedApplication.windows) {
            if (isCortexWindow(candidate)) {
                window = candidate;
                break;
            }
        }
    }

    return isCortexWindow(window) ? window : nil;
}

static BOOL isNativeFullscreen(NSWindow *window)
{
    return (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

static NSSize passthroughResize(id self, SEL command, NSWindow *window,
                                NSSize proposedSize)
{
    (void) self;
    (void) command;
    (void) window;
    return proposedSize;
}

static NSSize passthroughFullscreenSize(id self, SEL command, NSWindow *window,
                                        NSSize proposedSize)
{
    (void) self;
    (void) command;
    (void) window;
    return proposedSize;
}

static NSRect passthroughConstrainedFrame(id self, SEL command, NSRect frame,
                                          NSScreen *screen)
{
    (void) self;
    (void) command;
    (void) screen;
    return frame;
}

static void replaceMethodIfPresent(Class windowClass, SEL selector,
                                   IMP replacement)
{
    Method method = class_getInstanceMethod(windowClass, selector);

    if (method == NULL)
        return;

    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(windowClass, selector, replacement, types))
        method_setImplementation(method, replacement);
}

static NSWindowCollectionBehavior fullscreenBehavior(NSWindow *window)
{
    NSWindowCollectionBehavior incompatible =
        NSWindowCollectionBehaviorFullScreenAuxiliary
        | NSWindowCollectionBehaviorFullScreenNone
        | NSWindowCollectionBehaviorFullScreenDisallowsTiling;

    return (window.collectionBehavior & ~incompatible)
           | NSWindowCollectionBehaviorFullScreenPrimary
           | NSWindowCollectionBehaviorFullScreenAllowsTiling;
}

static void invokeNativeFullscreenToggle(NSWindow *window)
{
    if (!isCortexWindow(window))
        return;

    window.collectionBehavior = fullscreenBehavior(window);
    window.minFullScreenContentSize = NSMakeSize(320.0, 240.0);
    window.maxFullScreenContentSize = NSMakeSize(100000.0, 100000.0);

    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        [window toggleFullScreen:nil];
    });
}

@implementation CortexNativeFullscreenController
- (void)toggleFullscreen:(id)sender
{
    (void) sender;
    invokeNativeFullscreenToggle(findCortexWindow());
}
@end

static void configureWindow(NSWindow *window)
{
    if (!isCortexWindow(window))
        return;
    if (objc_getAssociatedObject(window, &patchedWindowKey) != nil)
        return;

    Class windowClass = window.class;
    NSString *className = NSStringFromClass(windowClass);

    if (![patchedWindowClasses containsObject:className]) {
        replaceMethodIfPresent(windowClass, @selector(windowWillResize:toSize:),
                               (IMP) passthroughResize);
        replaceMethodIfPresent(
            windowClass, @selector(window:willUseFullScreenContentSize:),
            (IMP) passthroughFullscreenSize);
        replaceMethodIfPresent(windowClass,
                               @selector(constrainFrameRect:toScreen:),
                               (IMP) passthroughConstrainedFrame);
        [patchedWindowClasses addObject:className];
    }

    window.styleMask |= NSWindowStyleMaskTitled
                        | NSWindowStyleMaskClosable
                        | NSWindowStyleMaskMiniaturizable
                        | NSWindowStyleMaskResizable;
    window.collectionBehavior = fullscreenBehavior(window);
    window.minSize = NSMakeSize(320.0, 240.0);
    window.maxSize = NSMakeSize(100000.0, 100000.0);
    window.contentMinSize = NSMakeSize(320.0, 240.0);
    window.contentMaxSize = NSMakeSize(100000.0, 100000.0);
    window.contentAspectRatio = NSZeroSize;
    window.resizeIncrements = NSMakeSize(1.0, 1.0);
    window.minFullScreenContentSize = NSMakeSize(320.0, 240.0);
    window.maxFullScreenContentSize = NSMakeSize(100000.0, 100000.0);

    NSButton *zoomButton = [window standardWindowButton:NSWindowZoomButton];
    zoomButton.enabled = YES;
    zoomButton.hidden = NO;
    zoomButton.target = fullscreenController;
    zoomButton.action = @selector(toggleFullscreen:);

    objc_setAssociatedObject(window, &patchedWindowKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void configureAllWindows(void)
{
    for (NSWindow *window in NSApplication.sharedApplication.windows)
        configureWindow(window);
}

__attribute__((constructor))
static void installCortexNativeFullscreenPatch(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        patchedWindowClasses = [NSMutableSet set];
        fullscreenController = [CortexNativeFullscreenController new];

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:NSWindowDidBecomeMainNotification
                           object:nil
                            queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *note) {
            configureWindow((NSWindow *) note.object);
        }];
        [center addObserverForName:NSWindowDidBecomeKeyNotification
                           object:nil
                            queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *note) {
            configureWindow((NSWindow *) note.object);
        }];
        [center addObserverForName:NSWindowDidExitFullScreenNotification
                           object:nil
                            queue:NSOperationQueue.mainQueue
                       usingBlock:^(NSNotification *note) {
            NSWindow *window = (NSWindow *) note.object;
            if (isCortexWindow(window)) {
                objc_setAssociatedObject(window, &patchedWindowKey, nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                configureWindow(window);
            }
        }];

        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                             handler:^NSEvent *(NSEvent *event) {
            NSEventModifierFlags modifiers =
                event.modifierFlags
                & NSEventModifierFlagDeviceIndependentFlagsMask;
            NSEventModifierFlags required =
                NSEventModifierFlagCommand | NSEventModifierFlagControl;

            if ((modifiers & required) == required
                && [event.charactersIgnoringModifiers.lowercaseString
                    isEqualToString:@"f"]) {
                invokeNativeFullscreenToggle(findCortexWindow());
                return nil;
            }

            if ([event.charactersIgnoringModifiers isEqualToString:@"\e"]
                && isNativeFullscreen(findCortexWindow()))
                return nil;

            return event;
        }];

        configureAllWindows();
    });
}
