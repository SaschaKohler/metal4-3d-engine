#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Uniforms — must match src/Uniforms.hpp exactly
// ---------------------------------------------------------------------------
struct Uniforms {
  float4x4 modelMatrix;
  float4x4 viewMatrix;
  float4x4 projectionMatrix;
};

// ---------------------------------------------------------------------------
// Vertex input — matches the C++ `Vertex` struct (position + color)
// ---------------------------------------------------------------------------
struct VertexIn {
  float3 position [[attribute(0)]];
  float4 color    [[attribute(1)]];
};

struct VertexOut {
  float4 position [[position]];
  float4 color;
};

// ---------------------------------------------------------------------------
// Vertex shader — applies MVP transform via uniform buffer at buffer(1)
// ---------------------------------------------------------------------------
vertex VertexOut vertex_main(uint                    vertexID  [[vertex_id]],
                             const device VertexIn  *vertices  [[buffer(0)]],
                             constant     Uniforms  &uniforms  [[buffer(1)]]) {
  float4 worldPos = uniforms.modelMatrix      * float4(vertices[vertexID].position, 1.0);
  float4 viewPos  = uniforms.viewMatrix       * worldPos;
  float4 clipPos  = uniforms.projectionMatrix * viewPos;

  VertexOut out;
  out.position = clipPos;
  out.color    = vertices[vertexID].color;
  return out;
}

// ---------------------------------------------------------------------------
// Fragment shader
// ---------------------------------------------------------------------------
fragment float4 fragment_main(VertexOut in [[stage_in]]) { return in.color; }
