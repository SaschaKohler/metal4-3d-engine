#pragma once

#include <Metal/Metal.hpp>
#include <simd/simd.h>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Vertex — interleaved position + normal (matches MSL VertexIn)
// ---------------------------------------------------------------------------
struct Vertex {
    simd::float3 position;
    simd::float3 normal;
};

// ---------------------------------------------------------------------------
// Mesh — owns Metal vertex + index buffers loaded from a glTF primitive.
// ---------------------------------------------------------------------------
class Mesh {
public:
    static Mesh* loadGLB(MTL::Device* device, const std::string& path);
    ~Mesh();

    void draw(MTL::RenderCommandEncoder* enc) const;

    uint32_t indexCount()  const { return m_indexCount; }
    bool     isValid()     const { return m_vertexBuffer && m_indexBuffer; }

private:
    Mesh() = default;

    MTL::Buffer* m_vertexBuffer { nullptr };
    MTL::Buffer* m_indexBuffer  { nullptr };
    uint32_t     m_indexCount   { 0 };
};
