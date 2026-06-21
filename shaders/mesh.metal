#include <metal_stdlib>
#include "../shared/BindingIndices.h"
#include "../shared/Material.h"

using namespace metal;

// ---------------------------------------------------------------------------
// Uniforms — must match src/Uniforms.hpp exactly
// ---------------------------------------------------------------------------
struct Uniforms {
  float4x4 modelMatrix;
  float4x4 viewMatrix;
  float4x4 projectionMatrix;
  float3x3 normalMatrix; // transpose(inverse(modelMatrix)) — upper-left 3x3
  uint materialIndex;
  float3 _padding;
};

// ---------------------------------------------------------------------------
// Vertex input — matches the C++ `Vertex` struct (position + normal)
// ---------------------------------------------------------------------------
struct VertexIn {
  float3 position [[attribute(0)]];
  float3 normal [[attribute(1)]];
};

struct VertexOut {
  float4 position [[position]];
  float3 worldPos;
  float3 worldNorm;
  uint materialIndex [[flat]];
};

// ---------------------------------------------------------------------------
// Vertex shader
// ---------------------------------------------------------------------------
vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             const device VertexIn *vertices
                             [[buffer(BufferIndexVertices)]],
                             constant Uniforms &uniforms
                             [[buffer(BufferIndexUniforms)]]) {
  float4 worldPos =
      uniforms.modelMatrix * float4(vertices[vertexID].position, 1.0);
  float3 worldNorm = uniforms.normalMatrix * vertices[vertexID].normal;

  VertexOut out;
  out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
  out.worldPos = worldPos.xyz;
  out.worldNorm = worldNorm;
  out.materialIndex = uniforms.materialIndex;
  return out;
}

// ---------------------------------------------------------------------------
// Fragment shader — simple directional Phong diffuse + ambient
// ---------------------------------------------------------------------------
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant Material *materials
                              [[buffer(BufferIndexMaterial)]]) {
  constant Material &material = materials[in.materialIndex];

  float3 lightDir = normalize(float3(1.0, 2.0, 1.5));

  float3 viewDir = normalize(float3(0.0, 0.0, 1.0));
  float3 norm = normalize(in.worldNorm);

  float diffuse = saturate(dot(norm, lightDir));

  float3 halfDir = normalize(lightDir + viewDir);
  float specAngle = saturate(dot(norm, halfDir));

  float shininess = mix(96.0, 8.0, material.roughness);
  float specular = pow(specAngle, shininess);

  float ambient = 0.35;
  float diffuseWeight = 0.65;

  float3 baseColor = material.baseColor;
  float3 diffuseColor = baseColor * (ambient + diffuse * diffuseWeight);

  float3 specularColor = mix(float3(0.04), baseColor, material.metallic);
  float specularStrength = mix(0.25, 0.65, material.metallic);

  float3 color = diffuseColor + specularColor * specular * specularStrength;

  return float4(color, 1.0);
}
