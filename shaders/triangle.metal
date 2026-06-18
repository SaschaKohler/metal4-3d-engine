#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Uniforms — must match src/Uniforms.hpp exactly
// ---------------------------------------------------------------------------
struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;   // transpose(inverse(modelMatrix)) — upper-left 3x3
};

// ---------------------------------------------------------------------------
// Vertex input — matches the C++ `Vertex` struct (position + normal)
// ---------------------------------------------------------------------------
struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position  [[position]];
    float3 worldPos;
    float3 worldNorm;
};

// ---------------------------------------------------------------------------
// Vertex shader
// ---------------------------------------------------------------------------
vertex VertexOut vertex_main(uint                   vertexID [[vertex_id]],
                             const device VertexIn* vertices [[buffer(0)]],
                             constant     Uniforms& uniforms [[buffer(1)]]) {
    float4 worldPos  = uniforms.modelMatrix * float4(vertices[vertexID].position, 1.0);
    float3 worldNorm = uniforms.normalMatrix * vertices[vertexID].normal;

    VertexOut out;
    out.position  = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPos  = worldPos.xyz;
    out.worldNorm = worldNorm;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment shader — simple directional Phong diffuse + ambient
// ---------------------------------------------------------------------------
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float3 lightDir  = normalize(float3(1.0, 2.0, 1.5));
    float3 norm      = normalize(in.worldNorm);
    float  diffuse   = saturate(dot(norm, lightDir));
    float  ambient   = 0.15;
    float  intensity = ambient + diffuse * 0.85;

    float3 baseColor = float3(0.72, 0.55, 0.38);   // warm clay
    return float4(baseColor * intensity, 1.0);
}
