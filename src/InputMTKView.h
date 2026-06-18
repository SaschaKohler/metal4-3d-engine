#pragma once

#import <MetalKit/MetalKit.h>

// ---------------------------------------------------------------------------
// InputMTKView — MTKView subclass that accepts mouse/scroll events and
// forwards them to its delegate (expected to be a MetalViewDelegate).
// ---------------------------------------------------------------------------
@interface InputMTKView : MTKView
@end
