#pragma once

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include "Camera.hpp"

// ---------------------------------------------------------------------------
// Renderer
// Owns the Metal device, command queue, pipeline state, vertex buffer,
// uniform buffer, depth stencil state, and the orbit camera.
// ---------------------------------------------------------------------------
class Renderer {
public:
    explicit Renderer(MTL::Device* device);
    ~Renderer();

    void draw(CA::MetalDrawable* drawable, MTL::Texture* depthTexture,
              float viewportWidth, float viewportHeight);

    // Mouse / scroll input — forwarded from MetalViewDelegate
    void onMouseDrag(float dx, float dy, bool rightButton);
    void onScroll(float delta);

private:
    void buildPipeline();
    void buildGeometry();
    void buildUniformBuffer();
    void buildDepthStencilState();

    MTL::Device*              m_device             { nullptr };
    MTL::CommandQueue*        m_commandQueue       { nullptr };
    MTL::RenderPipelineState* m_pipelineState      { nullptr };
    MTL::DepthStencilState*   m_depthStencilState  { nullptr };
    MTL::Buffer*              m_vertexBuffer       { nullptr };
    MTL::Buffer*              m_uniformBuffer      { nullptr };
    MTL::Library*             m_library            { nullptr };

    Camera m_camera;

    float m_time { 0.0f };   // seconds elapsed — used to spin the model
};
