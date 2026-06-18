#include "Renderer.hpp"
#include "Math.hpp"
#include "Uniforms.hpp"

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h>

#include <cassert>
#include <cstdio>
#include <cstring>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <string>

// ---------------------------------------------------------------------------
// Interleaved vertex: position (float3) + color (float4)
// ---------------------------------------------------------------------------
struct Vertex {
  simd::float3 position;
  simd::float4 color;
};

// ---------------------------------------------------------------------------
Renderer::Renderer(MTL::Device *device) : m_device(device->retain()) {
  m_commandQueue = m_device->newCommandQueue();
  buildPipeline();
  buildDepthStencilState();
  buildGeometry();
  buildUniformBuffer();
}

Renderer::~Renderer() {
  m_uniformBuffer->release();
  m_vertexBuffer->release();
  m_depthStencilState->release();
  m_pipelineState->release();
  m_library->release();
  m_commandQueue->release();
  m_device->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildPipeline() {
  NS::Error *error = nullptr;

  // Resolve default.metallib relative to the executable
  char exePath[4096];
  uint32_t size = sizeof(exePath);
  _NSGetExecutablePath(exePath, &size);
  std::string libPathStr = std::string(dirname(exePath)) + "/default.metallib";

  NS::String *libPath = NS::String::string(
      libPathStr.c_str(), NS::StringEncoding::UTF8StringEncoding);

  m_library = m_device->newLibrary(libPath, &error);
  if (!m_library) {
    printf("[Renderer] Failed to load default.metallib: %s\n",
           error->localizedDescription()->utf8String());
    assert(false);
  }

  MTL::Function *vertFn = m_library->newFunction(NS::String::string(
      "vertex_main", NS::StringEncoding::UTF8StringEncoding));
  MTL::Function *fragFn = m_library->newFunction(NS::String::string(
      "fragment_main", NS::StringEncoding::UTF8StringEncoding));

  assert(vertFn && fragFn);

  auto *desc = MTL::RenderPipelineDescriptor::alloc()->init();
  desc->setVertexFunction(vertFn);
  desc->setFragmentFunction(fragFn);
  desc->colorAttachments()->object(0)->setPixelFormat(
      MTL::PixelFormat::PixelFormatBGRA8Unorm_sRGB);
  desc->setDepthAttachmentPixelFormat(
      MTL::PixelFormat::PixelFormatDepth32Float);

  m_pipelineState = m_device->newRenderPipelineState(desc, &error);
  if (!m_pipelineState) {
    printf("[Renderer] Pipeline compile error: %s\n",
           error->localizedDescription()->utf8String());
    assert(false);
  }

  vertFn->release();
  fragFn->release();
  desc->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildDepthStencilState() {
  auto *desc = MTL::DepthStencilDescriptor::alloc()->init();
  desc->setDepthCompareFunction(MTL::CompareFunctionLess);
  desc->setDepthWriteEnabled(true);
  m_depthStencilState = m_device->newDepthStencilState(desc);
  desc->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildGeometry() {
  // Coloured triangle in local model space (centred at origin, unit-ish size)
  const Vertex vertices[] = {
      {{0.0f, 0.5f, 0.0f}, {1.0f, 0.2f, 0.2f, 1.0f}},   // top   – red
      {{-0.5f, -0.5f, 0.0f}, {0.2f, 1.0f, 0.2f, 1.0f}}, // left  – green
      {{0.5f, -0.5f, 0.0f}, {0.2f, 0.2f, 1.0f, 1.0f}},  // right – blue
  };

  m_vertexBuffer = m_device->newBuffer(vertices, sizeof(vertices),
                                       MTL::ResourceStorageModeShared);
}

// ---------------------------------------------------------------------------
void Renderer::buildUniformBuffer() {
  // One Uniforms struct per frame — allocate with Shared so we can memcpy each
  // frame.
  m_uniformBuffer =
      m_device->newBuffer(sizeof(Uniforms), MTL::ResourceStorageModeShared);
}

// ---------------------------------------------------------------------------
void Renderer::onMouseDrag(float dx, float dy, bool rightButton) {
  if (rightButton) {
    m_camera.pan(dx, dy);
  } else {
    m_camera.orbit(dx, dy);
  }
}

void Renderer::onScroll(float delta) { m_camera.scroll(delta); }

// ---------------------------------------------------------------------------
void Renderer::draw(CA::MetalDrawable *drawable, MTL::Texture *depthTexture,
                    float viewportWidth, float viewportHeight) {
  // Advance time (assuming ~60 fps; real delta-time would need a clock)
  m_time += 1.0f / 60.0f;

  // ── Build MVP matrices ──────────────────────────────────────────────────
  // Model: slow rotation around Y axis
  simd::float4x4 model = math::rotation(m_time * 0.8f, {0, 1, 0});
  model = model * math::rotation(m_time * 1.2f, {1, 0, 0});
  // View: orbit camera
  simd::float4x4 view =
      math::lookAt(m_camera.eye(), m_camera.target, simd::float3{0, 1, 0});

  // Projection: 60° FoV, window aspect ratio
  float aspect = viewportWidth / viewportHeight;
  simd::float4x4 proj =
      math::perspectiveFov(60.0f * (3.14159265f / 180.0f), // 60° in radians
                           aspect, 0.01f, 1000.0f);

  // Write uniforms into the shared buffer
  Uniforms uniforms;
  uniforms.modelMatrix = model;
  uniforms.viewMatrix = view;
  uniforms.projectionMatrix = proj;
  std::memcpy(m_uniformBuffer->contents(), &uniforms, sizeof(Uniforms));

  // ── Render pass setup ───────────────────────────────────────────────────
  auto *cmdBuf = m_commandQueue->commandBuffer();

  auto *passDesc = MTL::RenderPassDescriptor::alloc()->init();

  auto *colorAttach = passDesc->colorAttachments()->object(0);
  colorAttach->setTexture(drawable->texture());
  colorAttach->setLoadAction(MTL::LoadActionClear);
  colorAttach->setStoreAction(MTL::StoreActionStore);
  colorAttach->setClearColor(MTL::ClearColor(0.08, 0.08, 0.10, 1.0));

  auto *depthAttach = passDesc->depthAttachment();
  depthAttach->setTexture(depthTexture);
  depthAttach->setLoadAction(MTL::LoadActionClear);
  depthAttach->setStoreAction(MTL::StoreActionDontCare);
  depthAttach->setClearDepth(1.0);

  auto *enc = cmdBuf->renderCommandEncoder(passDesc);
  passDesc->release();

  enc->setRenderPipelineState(m_pipelineState);
  enc->setDepthStencilState(m_depthStencilState);

  MTL::Viewport vp{0.0, 0.0, viewportWidth, viewportHeight, 0.0, 1.0};
  enc->setViewport(vp);

  // buffer(0) = vertices, buffer(1) = uniforms
  enc->setVertexBuffer(m_vertexBuffer, 0, 0);
  enc->setVertexBuffer(m_uniformBuffer, 0, 1);

  enc->drawPrimitives(MTL::PrimitiveType::PrimitiveTypeTriangle,
                      NS::UInteger(0), NS::UInteger(3));

  enc->endEncoding();
  cmdBuf->presentDrawable(drawable);
  cmdBuf->commit();
}
