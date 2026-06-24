#include <metal_stdlib>
#include "../shared/BindingIndices.h"
#include "../shared/Material.h"
#include "../shared/Uniforms.h"
#include "../shared/Light.h"

using namespace metal;

float D_GGX(float NdotH, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
  return a2 / (M_PI_F * d * d);
}

float G_Smith(float NdotV, float NdotL, float roughness) {
  float r = roughness + 1.0;
  float k = (r * r) / 8.0;
  float gv = NdotV / (NdotV * (1.0 - k) + k);
  float gl = NdotL / (NdotL * (1.0 - k) + k);
  return gv * gl;
}

float3 F_Schlick(float HdotV, float3 F0) {
  return F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);
}

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
  float3 worldNorm =
      float3x3(uniforms.normalMatrix[0].xyz, uniforms.normalMatrix[1].xyz,
               uniforms.normalMatrix[2].xyz) *
      vertices[vertexID].normal;

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
                              constant Uniforms &uniforms
                              [[buffer(BufferIndexUniforms)]],
                              constant Material *materials
                              [[buffer(BufferIndexMaterial)]],
                              constant Light *lights
                              [[buffer(BufferIndexLights)]]) {
  constant Material &material = materials[in.materialIndex];

  if (material.emissive == 1) {
    return float4(pow(material.baseColor, float3(1.0 / 2.2)), 1.0);
  }
  float3 N = normalize(in.worldNorm);
  float3 V = normalize(uniforms.cameraPosition - in.worldPos);

  float3 albedo = material.baseColor;
  float rough = max(material.roughness, 0.04);
  float metal = material.metallic;
  float3 F0 = mix(float3(0.04), albedo, metal);

  float NdotV = saturate(dot(N, V));
  float3 color = float3(0.0);

  for (uint i = 0; i < uniforms.lightCount; i++) {
    float3 L;
    float attenuation = 1.0;

    if (lights[i].type == 0) {
      // Directional
      L = normalize(lights[i].positionOrDirection);
    } else {
      // Point
      float3 delta = lights[i].positionOrDirection - in.worldPos;
      float dist = length(delta);
      L = normalize(delta);
      attenuation = 1.0 / max(dist * dist, 0.001);
      // Soft cutoff am radius
      float r = lights[i].radius;
      attenuation *= pow(saturate(1.0 - (dist / r)), 2.0);
    }

    float3 H = normalize(V + L);
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float HdotV = saturate(dot(H, V));

    float3 F = F_Schlick(HdotV, F0);
    float3 spec = (D_GGX(NdotH, rough) * G_Smith(NdotV, NdotL, rough) * F) /
                  max(4.0 * NdotV * NdotL, 0.001);
    float3 kd = (1.0 - F) * (1.0 - metal);

    color += (kd * albedo / M_PI_F + spec) * lights[i].color *
             lights[i].intensity * NdotL * attenuation;
  }

  // Reinhard tonemapping
  color = color / (color + 1.0);

  // Gamma correction: linear -> sRGB (gamma 2.2)
  color = pow(color, float3(1.0 / 2.2));

  return float4(color, 1.0);
}
