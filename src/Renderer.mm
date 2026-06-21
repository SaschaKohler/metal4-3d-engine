#include "Renderer.hpp"
#include "../shared/BindingIndices.h"
#include "../shared/Material.h"
#include "Math.hpp"
#include "Uniforms.hpp"

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h>

#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <string>

static constexpr std::size_t kGridSize = 10;
static constexpr std::size_t kInstanceCount = kGridSize * kGridSize;

static std::size_t alignUp(std::size_t value, std::size_t alignment) {
  return (value + alignment - 1) & ~(alignment - 1);
}
// ---------------------------------------------------------------------------
Renderer::Renderer(MTL::Device *device) : m_device(device->retain()) {
  m_commandQueue = m_device->newCommandQueue();
  buildPipeline();
  buildDepthStencilState();
  buildUniformBuffer();
  buildMaterialBuffer();
  buildScene();
}

Renderer::~Renderer() {
  delete m_mesh;
  m_uniformBuffer->release();
  m_materialBuffer->release();
  m_depthStencilState->release();
  m_pipelineState->release();
  m_library->release();
  m_commandQueue->release();
  m_device->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildPipeline() {
  NS::Error *error = nullptr;

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
void Renderer::buildUniformBuffer() {
  m_uniformStride = alignUp(sizeof(Uniforms), 256);

  m_uniformBuffer = m_device->newBuffer(m_uniformStride * m_maxDraws,
                                        MTL::ResourceStorageModeShared);
}

// ---------------------------------------------------------------------------
void Renderer::buildMaterialBuffer() {
  Material materials[kInstanceCount];

  for (std::size_t i = 0; i < kInstanceCount; ++i) {
    float t = static_cast<float>(i) / static_cast<float>(kInstanceCount - 1);
    float row =
        static_cast<float>(i / kGridSize) / static_cast<float>(kGridSize - 1);
    float col =
        static_cast<float>(i % kGridSize) / static_cast<float>(kGridSize - 1);

    materials[i].baseColor = {0.20f + 0.75f * col, 0.25f + 0.55f * row,
                              0.95f - 0.70f * col};
    materials[i].roughness = 0.10f + 0.85f * row;
    materials[i].metallic = t;
    materials[i]._padding = {0.0f, 0.0f, 0.0f};
  }

  m_materialBuffer = m_device->newBuffer(materials, sizeof(materials),
                                         MTL::ResourceStorageModeShared);
}
// ---------------------------------------------------------------------------
void Renderer::buildScene() {
  m_mesh = Mesh::loadGLB(m_device, "assets/cube.glb");
  if (!m_mesh) {
    printf("[Renderer] WARNING: mesh load failed — scene will be empty.\n");
  }

  m_camera.radius = 8.0f;
  m_camera.pitch = 0.45f;
  m_camera.yaw = 0.35f;

  m_sceneRoot = std::make_shared<Node>("root");

  float spacing = 0.55f;
  float center = static_cast<float>(kGridSize - 1) * 0.5f;

  for (std::size_t z = 0; z < kGridSize; ++z) {
    for (std::size_t x = 0; x < kGridSize; ++x) {
      std::size_t index = z * kGridSize + x;
      auto cube = std::make_shared<Node>("cube");
      cube->mesh = m_mesh;
      cube->translation = {(static_cast<float>(x) - center) * spacing, 0.0f,
                           (static_cast<float>(z) - center) * spacing};
      cube->rotationEuler = {0.0f, 0.0f, 0.0f};
      cube->uniformScale = 0.25f;
      cube->materialIndex = static_cast<std::uint32_t>(index);
      m_sceneRoot->addChild(cube);
    }
  }
}

// ---------------------------------------------------------------------------
void Renderer::onMouseDrag(float dx, float dy, bool rightButton) {
  if (rightButton)
    m_camera.pan(dx, dy);
  else
    m_camera.orbit(-dx, dy);
}

void Renderer::onScroll(float delta) { m_camera.scroll(delta); }

// ---------------------------------------------------------------------------
// drawNode — recursive: update uniforms + draw for every node with a mesh
// ---------------------------------------------------------------------------
static void drawNode(const Node &node, MTL::RenderCommandEncoder *enc,
                     MTL::Buffer *uniformBuffer, std::size_t uniformStride,
                     std::size_t &drawIndex, MTL::Buffer *materialBuffer,
                     const simd::float4x4 &view, const simd::float4x4 &proj) {
  if (node.mesh && node.mesh->isValid()) {
    Uniforms u;
    u.modelMatrix = node.worldMatrix;
    u.viewMatrix = view;
    u.projectionMatrix = proj;
    u.normalMatrix = math::normalMatrix(node.worldMatrix);
    u.materialIndex = node.materialIndex;
    u._padding = {0.0f, 0.0f, 0.0f};

    assert(drawIndex < kInstanceCount);

    std::size_t uniformOffset = drawIndex * uniformStride;
    auto *dst =
        static_cast<std::uint8_t *>(uniformBuffer->contents()) + uniformOffset;
    std::memcpy(dst, &u, sizeof(Uniforms));

    enc->setVertexBuffer(uniformBuffer, uniformOffset, BufferIndexUniforms);
    enc->setFragmentBuffer(materialBuffer, 0, BufferIndexMaterial);
    drawIndex++;

    node.mesh->draw(enc);
  }

  for (const auto &child : node.children())
    drawNode(*child, enc, uniformBuffer, uniformStride, drawIndex,
             materialBuffer, view, proj);
}

// ---------------------------------------------------------------------------
void Renderer::draw(CA::MetalDrawable *drawable, MTL::Texture *depthTexture,
                    float viewportWidth, float viewportHeight) {
  m_time += 1.0f / 60.0f;

  // Draw scene graph recursively
  const auto &cubes = m_sceneRoot->children();

  for (std::size_t i = 0; i < cubes.size(); ++i) {
    auto &cube = *cubes[i];

    float phase = static_cast<float>(i) * 0.15f;
    cube.rotationEuler.y = m_time * 0.8f + phase;
    cube.translation.y = std::sin(m_time * 2.0f + phase) * 0.25f;
    cube.rotationEuler.x = std::sin(m_time + phase) * 0.35f;
  }
  // Update scene graph world matrices top-down
  m_sceneRoot->updateWorldMatrix();

  // Camera matrices
  simd::float4x4 view =
      math::lookAt(m_camera.eye(), m_camera.target, simd::float3{0, 1, 0});
  float aspect = viewportWidth / viewportHeight;
  simd::float4x4 proj = math::perspectiveFov(60.0f * (3.14159265f / 180.0f),
                                             aspect, 0.01f, 1000.0f);

  // ── Render pass ─────────────────────────────────────────────────────────
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
  enc->setViewport(
      MTL::Viewport{0.0, 0.0, viewportWidth, viewportHeight, 0.0, 1.0});
  std::size_t drawIndex = 0;
  drawNode(*m_sceneRoot, enc, m_uniformBuffer, m_uniformStride, drawIndex,
           m_materialBuffer, view, proj);

  enc->endEncoding();
  cmdBuf->presentDrawable(drawable);
  cmdBuf->commit();
}
