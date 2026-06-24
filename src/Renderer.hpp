#pragma once

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <memory>
#include <cstddef>
#include <vector>
#include "../shared/Material.h"
#include "Camera.hpp"
#include "Mesh.hpp"
#include "Metal/MTLTexture.hpp"
#include "Node.hpp"

// ---------------------------------------------------------------------------
// Renderer
// Owns the Metal device, command queue, pipeline state, uniform buffer,
// depth stencil state, orbit camera, loaded mesh, and the scene root node.
// ---------------------------------------------------------------------------
class Renderer {
public:
  explicit Renderer(MTL::Device *device);
  ~Renderer();

  void draw(CA::MetalDrawable *drawable, MTL::Texture *depthTexture,
            float viewportWidth, float viewportHeight);

  // Mouse / scroll input — forwarded from MetalViewDelegate
  void onMouseDrag(float dx, float dy, bool rightButton);
  void onScroll(float delta);
  void setScaleFactor(float scale);

private:
  void buildPipeline();
  void rebuildRenderTextures(float width, float height);
  void buildUniformBuffer();
  void buildMaterialBuffer();
  void buildLightBuffer();
  void buildDepthStencilState();
  void buildScene();

  MTL::Device *m_device{nullptr};
  MTL::CommandQueue *m_commandQueue{nullptr};
  MTL::RenderPipelineState *m_pipelineState{nullptr};
  MTL::DepthStencilState *m_depthStencilState{nullptr};
  MTL::Texture *m_renderTexture{nullptr};
  MTL::Texture *m_outputTexture{nullptr};
  MTL::Buffer *m_uniformBuffer{nullptr};
  MTL::Buffer *m_materialBuffer{nullptr};
  MTL::Buffer *m_lightBuffer{nullptr};
  MTL::Library *m_library{nullptr};

  Mesh *m_mesh{nullptr}; // owned
  Mesh *m_lightMesh{nullptr};
  std::vector<std::shared_ptr<Node>> m_lightNodes;
  std::shared_ptr<Node> m_sceneRoot;
  std::size_t m_uniformStride{0};
  std::size_t m_maxDraws{100};

  Camera m_camera;
  float m_time{0.0f};
  float m_scaleFactor{0.75f};
  void *m_upscaler{nullptr};
};
