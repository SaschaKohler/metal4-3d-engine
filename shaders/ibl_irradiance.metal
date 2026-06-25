#include <metal_stdlib>
#include "../shared/BindingIndices.h"
using namespace metal;

kernel void computeIrradiance(texturecube<float, access::sample> envMap
                              [[texture(TextureIndexEnvironment)]],
                              texturecube<float, access::write> irradianceMap
                              [[texture(TextureIndexIrradiance)]],
                              sampler envSampler
                              [[sampler(SamplerIndexDefault)]],
                              uint3 gid [[thread_position_in_grid]]) {
  uint face = gid.z;
  uint2 outputSize = irradianceMap.get_width();

  if (gid.x >= outputSize.x || gid.y >= outputSize.y)
    return;

  float2 uv = (float2(gid.xy) + 0.5) / float2(outputSize);
  float2 st = uv * 2.0 - 1.0;

  float3 N;
  switch (face) {
  case 0:
    N = float3(1.0, st.y, -st.x);
    break; // +X
  case 1:
    N = float3(-1.0, st.y, st.x);
    break; // -X
  case 2:
    N = float3(st.x, 1.0, -st.y);
    break; // +Y
  case 3:
    N = float3(st.x, -1.0, st.y);
    break; // -Y
  case 4:
    N = float3(st.x, st.y, 1.0);
    break; // +Z
  case 5:
    N = float3(-st.x, st.y, -1.0);
    break; // -Z
  }
  N = normalize(N);

  // Lokales Koordinatensystem aufbauen
  float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(0.0, 1.0, 0.0);
  float3 tangent = normalize(cross(up, N));
  float3 bitangent = cross(N, tangent);

  // Integration über die obere Hemisphäre
  const float dPhi = 2.0 * M_PI_F / 64.0;
  const float dTheta = 0.5 * M_PI_F / 32.0;

  float3 irradiance = float3(0.0);
  float totalWeight = 0.0;

  for (float phi = 0.0; phi < 2.0 * M_PI_F; phi += dPhi) {
    for (float theta = 0.0; theta < 0.5 * M_PI_F; theta += dTheta) {
      float3 localDir;
      localDir.x = sin(theta) * cos(phi);
      localDir.y = sin(theta) * sin(phi);
      localDir.z = cos(theta);

      float3 worldDir =
          tangent * localDir.x + bitangent * localDir.y + N * localDir.z;

      float NdotL = max(dot(N, worldDir), 0.0);
      float sampleWeight = NdotL * sin(theta);

      irradiance += envMap.sample(envSampler, worldDir).rgb * sampleWeight;
      totalWeight += sampleWeight;
    }
  }

  irradiance /= max(totalWeight, 1e-5);

  irradianceMap.write(float4(irradiance, 1.0), gid.xy, face);
}
