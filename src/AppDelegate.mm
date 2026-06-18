#import "AppDelegate.h"
#import "MetalViewDelegate.h"
#import "InputMTKView.h"

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@implementation AppDelegate {
    NSWindow*          _window;
    InputMTKView*      _mtkView;
    MetalViewDelegate* _viewDelegate;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    // ── Window ──────────────────────────────────────────────────────────────
    NSRect frame = NSMakeRect(0, 0, 1280, 720);
    _window = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:(NSWindowStyleMaskTitled |
                   NSWindowStyleMaskClosable |
                   NSWindowStyleMaskResizable |
                   NSWindowStyleMaskMiniaturizable)
        backing:NSBackingStoreBuffered
        defer:NO];
    _window.title = @"Metal4Engine — Milestone 3";

    // ── MTKView ──────────────────────────────────────────────────────────────
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _mtkView = [[InputMTKView alloc] initWithFrame:frame device:device];
    _mtkView.colorPixelFormat        = MTLPixelFormatBGRA8Unorm_sRGB;
    _mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _mtkView.preferredFramesPerSecond = 60;
    _mtkView.clearColor = MTLClearColorMake(0.08, 0.08, 0.10, 1.0);

    // ── Delegate (bridges to C++ Renderer) ───────────────────────────────────
    _viewDelegate = [[MetalViewDelegate alloc]
        initWithDevice:(__bridge MTL::Device*)device];
    _mtkView.delegate = _viewDelegate;

    // Trigger initial size event
    [_viewDelegate mtkView:_mtkView drawableSizeWillChange:_mtkView.drawableSize];

    // ── Show window ───────────────────────────────────────────────────────────
    _window.contentView = _mtkView;
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_mtkView];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    return YES;
}

@end
