#import "MetalViewDelegate.h"
#include <AppKit/AppKit.h>
#include "Renderer.hpp"
#import <MetalKit/MetalKit.h>
#include <memory>

@implementation MetalViewDelegate {
  std::unique_ptr<Renderer> _renderer;
  MTL::Texture *_depthTexture;
  MTLPixelFormat _depthFormat;
}

- (instancetype)initWithDevice:(MTL::Device *)device {
  self = [super init];
  if (self) {
    _renderer = std::make_unique<Renderer>(device);
    _depthTexture = nullptr;
    _depthFormat = MTLPixelFormatDepth32Float;
  }
  return self;
}

- (void)dealloc {
  if (_depthTexture) {
    _depthTexture->release();
  }
}

// Called whenever the view size changes — rebuild depth texture
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
  if (_depthTexture) {
    _depthTexture->release();
    _depthTexture = nullptr;
  }

  id<MTLDevice> mtlDevice = view.device;

  auto *desc = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:_depthFormat
                                   width:(NSUInteger)size.width
                                  height:(NSUInteger)size.height
                               mipmapped:NO];
  desc.usage = MTLTextureUsageRenderTarget;
  desc.storageMode = MTLStorageModePrivate;

  id<MTLTexture> tex = [mtlDevice newTextureWithDescriptor:desc];
  _depthTexture = (__bridge_retained MTL::Texture *)tex;
}

// Called every frame
- (void)drawInMTKView:(MTKView *)view {
  CA::MetalDrawable *drawable =
      (__bridge CA::MetalDrawable *)view.currentDrawable;

  if (!drawable || !_depthTexture) {
    return;
  }

  CGSize sz = view.drawableSize;
  _renderer->draw(drawable, _depthTexture, (float)sz.width, (float)sz.height);
}

// ── Mouse input ────────────────────────────────────────────────────────────

- (void)mouseDragged:(NSEvent *)event {
  _renderer->onMouseDrag((float)event.deltaX, (float)event.deltaY, false);
}

- (void)rightMouseDragged:(NSEvent *)event {
  _renderer->onMouseDrag((float)event.deltaX, (float)event.deltaY, true);
}

- (void)scrollWheel:(NSEvent *)event {
  // trackpad momentum scroll gives deltaY, mouse wheel gives scrollingDeltaY
  float delta = (float)(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY
                                                        : event.deltaY * 3.0f);
  _renderer->onScroll(delta);
}

// -- Keyboard Input -------------------------------------------------
- (void)keyDown:(NSEvent *)event {
  if (event.keyCode == 18)
    _renderer->setScaleFactor(0.5f);
  else if (event.keyCode == 19)
    _renderer->setScaleFactor(0.67f);
  else if (event.keyCode == 20)
    _renderer->setScaleFactor(0.75f);
  else if (event.keyCode == 21)
    _renderer->setScaleFactor(1.0f);
}

@end
