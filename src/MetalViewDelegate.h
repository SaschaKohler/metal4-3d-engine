#pragma once

#import <MetalKit/MetalKit.h>
#include "Renderer.hpp"

// ---------------------------------------------------------------------------
// MetalViewDelegate
// Objective-C class that acts as the MTKViewDelegate.
// Owns the C++ Renderer and forwards draw / resize calls.
// ---------------------------------------------------------------------------
@interface MetalViewDelegate : NSObject <MTKViewDelegate>
- (instancetype)initWithDevice:(MTL::Device *)device;

// Mouse / scroll input — called by InputMTKView
- (void)mouseDragged:(NSEvent *)event;
- (void)rightMouseDragged:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
@end
