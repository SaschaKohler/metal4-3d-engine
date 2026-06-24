
#include "Metal/MTLCommandBuffer.hpp"
#include "Metal/MTLComputeCommandEncoder.hpp"
#include "Metal/MTLLibrary.hpp"
#include "Metal/MTLSampler.hpp"
#include "Metal/MTLTypes.hpp"
#include "stb_image.h"

#include "Renderer.hpp"
#include "../shared/BindingIndices.h"
#include "../shared/Material.h"
#include "../shared/Light.h"
#include "Camera.hpp"
#include "Foundation/NSTypes.hpp"
#include "Math.hpp"
#include "Metal/MTLPixelFormat.hpp"
#include "Metal/MTLResource.hpp"
#include "Metal/MTLTexture.hpp"
#include "Uniforms.hpp"

#include <CoreFoundation/CFBase.h>
#include <MetalFX/MetalFX.h>
#include <Metal/Metal.hpp>

#include <QuartzCore/QuartzCore.hpp>
#include <simd/geometry.h>
#include <simd/simd.h>

#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <string>

static constexpr std::size_t kGridSize = 3;
static constexpr std::size_t kInstanceCount = kGridSize * kGridSize;
static constexpr std::size_t kLightCount = 3;
static_assert(sizeof(Uniforms) % 16 == 0, "Uniforms must be 16-byte aligned");
// If build fails here, check: sizeof(Uniforms) = ?

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
  buildLightBuffer();
  buildScene();
  buildEnvironmentMap();
}

Renderer::~Renderer() {
  delete m_mesh;
  m_lightBuffer->release();
  m_uniformBuffer->release();
  m_materialBuffer->release();
  m_depthStencilState->release();
  m_pipelineState->release();
  m_library->release();
  m_commandQueue->release();
  if (m_renderTexture) {
    m_renderTexture->release();
  }
  if (m_outputTexture) {
    m_outputTexture->release();
  }
  if (m_upscaler) {
    CFRelease(m_upscaler);
  }
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
      MTL::PixelFormat::PixelFormatBGRA8Unorm);
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
void Renderer::rebuildRenderTextures(float width, float height) {
  if (m_renderTexture) {
    m_renderTexture->release();
    m_renderTexture = nullptr;
  }
  if (m_outputTexture) {
    m_outputTexture->release();
    m_outputTexture = nullptr;
  }

  auto *desc = MTL::TextureDescriptor::alloc()->init();
  desc->setTextureType(MTL::TextureType2D);
  desc->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
  desc->setWidth((NS::UInteger)(width * m_scaleFactor));
  desc->setHeight((NS::UInteger)(height * m_scaleFactor));
  desc->setUsage(MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
  desc->setStorageMode(MTL::StorageModePrivate);

  m_renderTexture = m_device->newTexture(desc);

  desc->setWidth((NS::UInteger)width);
  desc->setHeight((NS::UInteger)height);
  desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);

  m_outputTexture = m_device->newTexture(desc);

  desc->release();

  if (m_upscaler) {
    CFRelease(m_upscaler);
    m_upscaler = nullptr;
  }

  MTLFXSpatialScalerDescriptor *scalerDesc =
      [[MTLFXSpatialScalerDescriptor alloc] init];
  scalerDesc.inputWidth = (NSUInteger)(width * m_scaleFactor);
  scalerDesc.inputHeight = (NSUInteger)(height * m_scaleFactor);
  scalerDesc.outputWidth = (NSUInteger)width;
  scalerDesc.outputHeight = (NSUInteger)height;
  scalerDesc.colorTextureFormat = MTLPixelFormatBGRA8Unorm;
  scalerDesc.outputTextureFormat = MTLPixelFormatBGRA8Unorm;
  scalerDesc.colorProcessingMode =
      MTLFXSpatialScalerColorProcessingModePerceptual;

  id<MTLFXSpatialScaler> scaler =
      [scalerDesc newSpatialScalerWithDevice:(__bridge id<MTLDevice>)m_device];
  m_upscaler = (void *)CFBridgingRetain(scaler);
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
MTL::Texture *Renderer::loadEquirectangularTexture(const std::string &path) {
  int width, height, channels;
  float *data = stbi_loadf(path.c_str(), &width, &height, &channels, 4);
  if (!data) {
    printf("[Renderer] Could not load EnvironmentMap for Equirectangular "
           "Texture.");
    return nullptr;
  }

  MTL::TextureDescriptor *desc = MTL::TextureDescriptor::alloc()->init();
  desc->setTextureType(MTL::TextureType2D);
  desc->setWidth(width);
  desc->setHeight(height);
  desc->setPixelFormat(MTL::PixelFormatRGBA32Float);
  desc->setMipmapLevelCount(1);
  desc->setUsage(MTL::TextureUsageShaderRead);

  MTL::Texture *texture = m_device->newTexture(desc);
  texture->replaceRegion(MTL::Region(0, 0, 0, width, height, 1), 0, data,
                         width * 4 * sizeof(float));

  stbi_image_free(data);
  desc->release();

  return texture;
}

// ---------------------------------------------------------------------------
void Renderer::buildEnvironmentMap() {
  MTL::Texture *equirectTexture =
      loadEquirectangularTexture("assets/hdri/kloppenheim_03_4k.hdr");
  if (!equirectTexture) {
    return;
  }
  const uint faceSize = 1024;

  MTL::TextureDescriptor *cubeDesc = MTL::TextureDescriptor::alloc()->init();
  cubeDesc->setTextureType(MTL::TextureTypeCube);
  cubeDesc->setWidth(faceSize);
  cubeDesc->setHeight(faceSize);
  cubeDesc->setPixelFormat(MTL::PixelFormatRGBA32Float);
  cubeDesc->setMipmapLevelCount(1);
  cubeDesc->setUsage(MTL::TextureUsageShaderWrite |
                     MTL::TextureUsageShaderRead);

  m_environmentCubemap = m_device->newTexture(cubeDesc);

  // Pipeline holen
  NS::Error *error = nullptr;
  MTL::Function *kernel = m_library->newFunction(NS::String::string(
      "equirectToCubemap", NS::StringEncoding::UTF8StringEncoding));
  m_equirectToCubePipeline = m_device->newComputePipelineState(kernel, &error);

  // Command Encoder
  MTL::CommandBuffer *cmdBuffer = m_commandQueue->commandBuffer();
  MTL::ComputeCommandEncoder *encoder = cmdBuffer->computeCommandEncoder();

  encoder->setComputePipelineState(m_equirectToCubePipeline);
  encoder->setTexture(equirectTexture, 0);
  encoder->setTexture(m_environmentCubemap, 1);

  MTL::SamplerDescriptor *samplerDesc = MTL::SamplerDescriptor::alloc()->init();
  samplerDesc->setMinFilter(MTL::SamplerMinMagFilterLinear);
  samplerDesc->setMagFilter(MTL::SamplerMinMagFilterLinear);
  samplerDesc->setSAddressMode(MTL::SamplerAddressModeRepeat);
  samplerDesc->setTAddressMode(MTL::SamplerAddressModeClampToEdge);
  MTL::SamplerState *sampler = m_device->newSamplerState(samplerDesc);

  encoder->setSamplerState(sampler, 0);

  MTL::Size threadsPerGroup = MTL::Size::Make(8, 8, 1);
  MTL::Size threadgroups =
      MTL::Size::Make((faceSize + 7) / 8, (faceSize + 7) / 8, 6);

  encoder->dispatchThreadgroups(threadgroups, threadsPerGroup);

  encoder->endEncoding();
  cmdBuffer->commit();
  cmdBuffer->waitUntilCompleted();

  // Cleanup
  sampler->release();
  samplerDesc->release();
  equirectTexture->release();
  cubeDesc->release();
  kernel->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildUniformBuffer() {
  m_uniformStride = alignUp(sizeof(Uniforms), 256);

  m_uniformBuffer = m_device->newBuffer(m_uniformStride * m_maxDraws,
                                        MTL::ResourceStorageModeShared);
}

// ---------------------------------------------------------------------------
void Renderer::buildMaterialBuffer() {
  static constexpr std::size_t kLightCount = 3;
  Material materials[kInstanceCount + kLightCount];

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

  simd_float3 lightColors[3] = {
      {1.0f, 0.4f, 0.1f}, // Licht 1: warm
      {0.2f, 0.4f, 1.0f}, // Licht 2: kalt
      {1.0f, 1.0f, 0.8f}, // Licht 3: neutral
  };

  for (std::size_t i = 0; i < kLightCount; ++i) {
    materials[kInstanceCount + i].baseColor = lightColors[i];
    materials[kInstanceCount + i].roughness = 0.0f;
    materials[kInstanceCount + i].metallic = 0.0f;
    materials[kInstanceCount + i].emissive = 1;
    materials[kInstanceCount + i]._padding = {0.0f, 0.0f, 0.0f};
  }

  m_materialBuffer = m_device->newBuffer(materials, sizeof(materials),
                                         MTL::ResourceStorageModeShared);
}
// ---------------------------------------------------------------------------
void Renderer::buildLightBuffer() {
  Light lights[4];

  // Licht 0: Directional (Sonne)
  lights[0].positionOrDirection =
      simd::normalize(simd::float3{1.0f, 2.0f, 1.5f});
  lights[0].color = {1.0f, 0.95f, 0.85f};
  lights[0].intensity = 3.0f;
  lights[0].type = LIGHT_TYPE_DIRECTIONAL;
  lights[0].radius = 0.0f;
  lights[0]._pad = {0.0f, 0.0f, 0.0f};

  // Licht 1: Point Light (warm, links)
  lights[1].positionOrDirection = {-2.0f, 1.5f, 1.0f};
  lights[1].color = {1.0f, 0.4f, 0.1f};
  lights[1].intensity = 8.0f;
  lights[1].type = LIGHT_TYPE_POINT;
  lights[1].radius = 6.0f;
  lights[1]._pad = {0.0f, 0.0f, 0.0f};

  // Licht 2: Point Light (kalt, rechts)
  lights[2].positionOrDirection = {2.0f, 1.0f, -1.0f};
  lights[2].color = {0.2f, 0.4f, 1.0f};
  lights[2].intensity = 9.0f;
  lights[2].type = LIGHT_TYPE_POINT;
  lights[2].radius = 5.0f;
  lights[2]._pad = {0.0f, 0.0f, 0.0f};

  // Licht 3: Point Light (animiert — wird in draw() überschrieben)
  lights[3].positionOrDirection = {0.0f, 2.0f, 0.0f};
  lights[3].color = {1.0f, 1.0f, 0.8f};
  lights[3].intensity = 10.0f;
  lights[3].type = LIGHT_TYPE_POINT;
  lights[3].radius = 8.0f;
  lights[3]._pad = {0.0f, 0.0f, 0.0f};

  m_lightBuffer = m_device->newBuffer(lights, sizeof(lights),
                                      MTL::ResourceStorageModeShared);
}
// ---------------------------------------------------------------------------
void Renderer::buildScene() {
  m_mesh = Mesh::loadGLB(m_device, "assets/suzanne.glb");
  if (!m_mesh) {
    printf("[Renderer] WARNING: mesh load failed — scene will be empty.\n");
  }

  m_lightMesh = Mesh::loadGLB(m_device, "assets/sphere.glb");
  if (!m_lightMesh) {
    printf("[Renderer] WARNING: m_lightMesh load failed.\n");
  }

  m_camera.radius = 8.0f;
  m_camera.pitch = 0.45f;
  m_camera.yaw = 0.35f;

  m_sceneRoot = std::make_shared<Node>("root");

  float spacing = 1.0f;
  float center = static_cast<float>(kGridSize - 1) * 0.5f;

  for (std::size_t z = 0; z < kGridSize; ++z) {
    for (std::size_t x = 0; x < kGridSize; ++x) {
      std::size_t index = z * kGridSize + x;
      auto cube = std::make_shared<Node>("cube");
      cube->mesh = m_mesh;
      cube->translation = {(static_cast<float>(x) - center) * spacing, 0.0f,
                           (static_cast<float>(z) - center) * spacing};
      cube->rotationEuler = {-1.5f, 0.0f, 0.0f};
      cube->uniformScale = 0.25f;
      cube->materialIndex = static_cast<std::uint32_t>(index);
      m_sceneRoot->addChild(cube);
    }
  }

  for (int i = 0; i < 3; ++i) {
    auto node = std::make_shared<Node>("lightCube");
    node->mesh = m_lightMesh;
    node->uniformScale = 0.05f;
    node->materialIndex = kInstanceCount + i;
    m_lightNodes.push_back(node);
    m_sceneRoot->addChild(node);
  }
}

// ---------------------------------------------------------------------------
void Renderer::setScaleFactor(float scale) {
  printf("[Renderer] scaleFactor -> %.2f\n", scale);
  m_scaleFactor = scale;

  if (m_renderTexture) {
    m_renderTexture->release();
    m_renderTexture = nullptr;
  }
  if (m_outputTexture) {
    m_outputTexture->release();
    m_outputTexture = nullptr;
  }
  if (m_upscaler) {
    CFRelease(m_upscaler);
    m_upscaler = nullptr;
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
                     MTL::Buffer *lightBuffer, const simd::float4x4 &view,
                     const simd::float4x4 &proj,
                     const simd::float3 &cameraEye) {
  if (node.mesh && node.mesh->isValid()) {
    simd::float3x3 n3 = math::normalMatrix(node.worldMatrix);
    Uniforms u{};
    u.modelMatrix = node.worldMatrix;
    u.viewMatrix = view;
    u.projectionMatrix = proj;
    u.normalMatrix = simd_matrix(
        simd::float4{n3.columns[0].x, n3.columns[0].y, n3.columns[0].z, 0.0f},
        simd::float4{n3.columns[1].x, n3.columns[1].y, n3.columns[1].z, 0.0f},
        simd::float4{n3.columns[2].x, n3.columns[2].y, n3.columns[2].z, 0.0f},
        simd::float4{0.0f, 0.0f, 0.0f, 1.0f});
    u.materialIndex = node.materialIndex;
    u._pad0 = {0.0f, 0.0f, 0.0f};
    u.cameraPosition = cameraEye;
    u.lightCount = 4;
    u._pad2 = {0.0f, 0.0f, 0.0f};

    assert(drawIndex < kInstanceCount + kLightCount);

    std::size_t uniformOffset = drawIndex * uniformStride;
    auto *dst =
        static_cast<std::uint8_t *>(uniformBuffer->contents()) + uniformOffset;
    std::memcpy(dst, &u, sizeof(Uniforms));

    enc->setVertexBuffer(uniformBuffer, uniformOffset, BufferIndexUniforms);
    enc->setFragmentBuffer(materialBuffer, 0, BufferIndexMaterial);
    enc->setFragmentBuffer(lightBuffer, 0, BufferIndexLights);
    enc->setFragmentBuffer(uniformBuffer, uniformOffset, BufferIndexUniforms);
    drawIndex++;

    node.mesh->draw(enc);
  }

  for (const auto &child : node.children())
    drawNode(*child, enc, uniformBuffer, uniformStride, drawIndex,
             materialBuffer, lightBuffer, view, proj, cameraEye);
}

// ---------------------------------------------------------------------------
void Renderer::draw(CA::MetalDrawable *drawable, MTL::Texture *depthTexture,
                    float viewportWidth, float viewportHeight) {
  m_time += 1.0f / 60.0f;

  Light *lights = static_cast<Light *>(m_lightBuffer->contents());
  lights[3].positionOrDirection = simd::normalize(simd::float3{
      std::cos(m_time * 0.8f) * 5.0f, 3.0f, std::sin(m_time * 0.8f)});

  for (int i = 0; i < 3; ++i) {
    auto pos = lights[i + 1].positionOrDirection;
    m_lightNodes[i]->translation = {pos.x, pos.y, pos.z};
  }
  uint32_t rw = m_renderTexture ? (uint32_t)m_renderTexture->width() : 0;
  uint32_t rh = m_renderTexture ? (uint32_t)m_renderTexture->height() : 0;

  if (rw != (uint32_t)(viewportWidth * m_scaleFactor) ||
      rh != (uint32_t)(viewportHeight * m_scaleFactor)) {
    rebuildRenderTextures(viewportWidth, viewportHeight);
  }
  // Draw scene graph recursively
  /* const auto &cubes = m_sceneRoot->children(); */

  /* for (std::size_t i = 0; i < cubes.size(); ++i) { */
  /*   auto &cube = *cubes[i]; */
  /**/
  /*   float phase = static_cast<float>(i) * 0.15f; */
  /*   cube.rotationEuler.y = m_time * 0.8f + phase; */
  /*   cube.translation.y = std::sin(m_time * 2.0f + phase) * 0.25f; */
  /*   cube.rotationEuler.x = std::sin(m_time + phase) * 0.35f; */
  /* } */
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
  colorAttach->setTexture(m_renderTexture);
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

  //
  //
  // test
  /* MTL::SamplerDescriptor *samplerDesc =
   * MTL::SamplerDescriptor::alloc()->init(); */
  /* samplerDesc->setMinFilter(MTL::SamplerMinMagFilterLinear); */
  /* samplerDesc->setMagFilter(MTL::SamplerMinMagFilterLinear); */
  /* samplerDesc->setMipFilter(MTL::SamplerMipFilterLinear); */
  /* samplerDesc->setSAddressMode(MTL::SamplerAddressModeClampToEdge); */
  /* samplerDesc->setTAddressMode(MTL::SamplerAddressModeClampToEdge); */
  /* samplerDesc->setRAddressMode(MTL::SamplerAddressModeClampToEdge); */
  /* MTL::SamplerState *envSampler = m_device->newSamplerState(samplerDesc); */
  /**/
  /* enc->setFragmentSamplerState(envSampler, 0); */
  /* enc->setFragmentTexture(m_environmentCubemap, 0); */
  // test
  //

  drawNode(*m_sceneRoot, enc, m_uniformBuffer, m_uniformStride, drawIndex,
           m_materialBuffer, m_lightBuffer, view, proj, m_camera.eye());

  enc->endEncoding();
  // ... nach enc->endEncoding() ...
  /* samplerDesc->release(); */
  /* envSampler->release(); */
  //
  //
  id<MTLFXSpatialScaler> scaler = (__bridge id<MTLFXSpatialScaler>)m_upscaler;
  scaler.colorTexture = (__bridge id<MTLTexture>)m_renderTexture;
  scaler.outputTexture = (__bridge id<MTLTexture>)m_outputTexture;
  [scaler encodeToCommandBuffer:(__bridge id<MTLCommandBuffer>)cmdBuf];

  id<MTLBlitCommandEncoder> blit =
      [(__bridge id<MTLCommandBuffer>)cmdBuf blitCommandEncoder];
  [blit copyFromTexture:(__bridge id<MTLTexture>)m_outputTexture
              toTexture:(__bridge id<MTLTexture>)drawable->texture()];
  [blit endEncoding];

  cmdBuf->presentDrawable(drawable);
  cmdBuf->commit();
}
