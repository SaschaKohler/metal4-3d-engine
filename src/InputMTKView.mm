#import "InputMTKView.h"
#import "MetalViewDelegate.h"

@implementation InputMTKView

// NSView subclasses must return YES from acceptsFirstResponder to receive
// keyboard and mouse events.
- (BOOL)acceptsFirstResponder {
  return YES;
}

// ── Orbit (left drag) ─────────────────────────────────────────────────────
- (void)mouseDragged:(NSEvent *)event {
  [(MetalViewDelegate *)self.delegate mouseDragged:event];
}

// ── Pan (right drag) ──────────────────────────────────────────────────────
- (void)rightMouseDragged:(NSEvent *)event {
  [(MetalViewDelegate *)self.delegate rightMouseDragged:event];
}

// ── Dolly (scroll / trackpad pinch) ──────────────────────────────────────
- (void)scrollWheel:(NSEvent *)event {
  [(MetalViewDelegate *)self.delegate scrollWheel:event];
}

// -- get the Key events
- (void)keyDown:(NSEvent *)event {
  [(MetalViewDelegate *)self.delegate keyDown:event];
}

@end
