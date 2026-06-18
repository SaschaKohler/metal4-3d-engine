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
Renderer::Renderer(MTL::Device* device) : m_device(device->retain()) {
    m_commandQueue = m_device->newCommandQueue();
    buildPipeline();
    buildDepthStencilState();
    buildUniformBuffer();
    buildScene();
}

Renderer::~Renderer() {
    delete m_mesh;
    m_uniformBuffer->release();
    m_depthStencilState->release();
    m_pipelineState->release();
    m_library->release();
    m_commandQueue->release();
    m_device->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildPipeline() {
    NS::Error* error = nullptr;

    char exePath[4096];
    uint32_t size = sizeof(exePath);
    _NSGetExecutablePath(exePath, &size);
    std::string libPathStr = std::string(dirname(exePath)) + "/default.metallib";

    NS::String* libPath = NS::String::string(
        libPathStr.c_str(), NS::StringEncoding::UTF8StringEncoding);

    m_library = m_device->newLibrary(libPath, &error);
    if (!m_library) {
        printf("[Renderer] Failed to load default.metallib: %s\n",
               error->localizedDescription()->utf8String());
        assert(false);
    }

    MTL::Function* vertFn = m_library->newFunction(
        NS::String::string("vertex_main", NS::StringEncoding::UTF8StringEncoding));
    MTL::Function* fragFn = m_library->newFunction(
        NS::String::string("fragment_main", NS::StringEncoding::UTF8StringEncoding));

    assert(vertFn && fragFn);

    auto* desc = MTL::RenderPipelineDescriptor::alloc()->init();
    desc->setVertexFunction(vertFn);
    desc->setFragmentFunction(fragFn);
    desc->colorAttachments()->object(0)->setPixelFormat(
        MTL::PixelFormat::PixelFormatBGRA8Unorm_sRGB);
    desc->setDepthAttachmentPixelFormat(MTL::PixelFormat::PixelFormatDepth32Float);

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
    auto* desc = MTL::DepthStencilDescriptor::alloc()->init();
    desc->setDepthCompareFunction(MTL::CompareFunctionLess);
    desc->setDepthWriteEnabled(true);
    m_depthStencilState = m_device->newDepthStencilState(desc);
    desc->release();
}

// ---------------------------------------------------------------------------
void Renderer::buildUniformBuffer() {
    m_uniformBuffer = m_device->newBuffer(sizeof(Uniforms),
                                          MTL::ResourceStorageModeShared);
}

// ---------------------------------------------------------------------------
void Renderer::buildScene() {
    // Load Khronos Box.glb — path relative to the executable
    m_mesh = Mesh::loadGLB(m_device, "assets/cube.glb");
    if (!m_mesh) {
        printf("[Renderer] WARNING: mesh load failed — scene will be empty.\n");
    }

    // Build a minimal scene: root → meshNode
    m_sceneRoot = std::make_shared<Node>("root");

    auto meshNode = std::make_shared<Node>("cube");
    meshNode->mesh           = m_mesh;
    meshNode->translation    = { 0.0f, 0.0f, 0.0f };
    meshNode->rotationAxis   = { 0.0f, 1.0f, 0.0f };
    meshNode->rotationAngle  = 0.0f;
    meshNode->uniformScale   = 1.0f;

    m_sceneRoot->addChild(meshNode);
}

// ---------------------------------------------------------------------------
void Renderer::onMouseDrag(float dx, float dy, bool rightButton) {
    if (rightButton) m_camera.pan(dx, dy);
    else             m_camera.orbit(dx, dy);
}

void Renderer::onScroll(float delta) { m_camera.scroll(delta); }

// ---------------------------------------------------------------------------
// drawNode — recursive: update uniforms + draw for every node with a mesh
// ---------------------------------------------------------------------------
static void drawNode(const Node& node,
                     MTL::RenderCommandEncoder* enc,
                     MTL::Buffer* uniformBuffer,
                     const simd::float4x4& view,
                     const simd::float4x4& proj) {
    if (node.mesh && node.mesh->isValid()) {
        Uniforms u;
        u.modelMatrix      = node.worldMatrix;
        u.viewMatrix       = view;
        u.projectionMatrix = proj;
        u.normalMatrix     = math::normalMatrix(node.worldMatrix);
        std::memcpy(uniformBuffer->contents(), &u, sizeof(Uniforms));

        enc->setVertexBuffer(uniformBuffer, 0, 1);
        node.mesh->draw(enc);
    }

    for (const auto& child : node.children())
        drawNode(*child, enc, uniformBuffer, view, proj);
}

// ---------------------------------------------------------------------------
void Renderer::draw(CA::MetalDrawable* drawable, MTL::Texture* depthTexture,
                    float viewportWidth, float viewportHeight) {
    m_time += 1.0f / 60.0f;

    // Animate the cube node (child 0 of root)
    if (!m_sceneRoot->children().empty()) {
        auto& cube = *m_sceneRoot->children()[0];
        cube.rotationAngle = m_time * 0.8f;
    }

    // Update scene graph world matrices top-down
    m_sceneRoot->updateWorldMatrix();

    // Camera matrices
    simd::float4x4 view = math::lookAt(
        m_camera.eye(), m_camera.target, simd::float3{0, 1, 0});
    float aspect = viewportWidth / viewportHeight;
    simd::float4x4 proj = math::perspectiveFov(
        60.0f * (3.14159265f / 180.0f), aspect, 0.01f, 1000.0f);

    // ── Render pass ─────────────────────────────────────────────────────────
    auto* cmdBuf   = m_commandQueue->commandBuffer();
    auto* passDesc = MTL::RenderPassDescriptor::alloc()->init();

    auto* colorAttach = passDesc->colorAttachments()->object(0);
    colorAttach->setTexture(drawable->texture());
    colorAttach->setLoadAction(MTL::LoadActionClear);
    colorAttach->setStoreAction(MTL::StoreActionStore);
    colorAttach->setClearColor(MTL::ClearColor(0.08, 0.08, 0.10, 1.0));

    auto* depthAttach = passDesc->depthAttachment();
    depthAttach->setTexture(depthTexture);
    depthAttach->setLoadAction(MTL::LoadActionClear);
    depthAttach->setStoreAction(MTL::StoreActionDontCare);
    depthAttach->setClearDepth(1.0);

    auto* enc = cmdBuf->renderCommandEncoder(passDesc);
    passDesc->release();

    enc->setRenderPipelineState(m_pipelineState);
    enc->setDepthStencilState(m_depthStencilState);
    enc->setViewport(MTL::Viewport{0.0, 0.0, viewportWidth, viewportHeight, 0.0, 1.0});

    // Draw scene graph recursively
    drawNode(*m_sceneRoot, enc, m_uniformBuffer, view, proj);

    enc->endEncoding();
    cmdBuf->presentDrawable(drawable);
    cmdBuf->commit();
}
