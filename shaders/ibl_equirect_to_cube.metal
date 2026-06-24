#include <metal_stdlib>
using namespace metal;

constant float2 invAtan = float2(0.1591, 0.3183); // 1 / (2π), 1 / π

kernel void equirectToCubemap(texture2d<float, access::sample> inputTexture
                              [[texture(0)]],
                              texturecube<float, access::write> outputTexture
                              [[texture(1)]],
                              sampler texSampler [[sampler(0)]],
                              uint3 gid [[thread_position_in_grid]]) {
  uint face = gid.z;
  uint2 outputSize = outputTexture.get_width();

  if (gid.x >= outputSize.x || gid.y >= outputSize.y)
    return;

  float2 uv = (float2(gid.xy) + 0.5) / float2(outputSize);
  float2 st = uv * 2.0 - 1.0; // [-1, 1]

  float3 dir;
  switch (face) {
  case 0:
    dir = float3(1.0, st.y, -st.x);
    break; // +X
  case 1:
    dir = float3(-1.0, st.y, st.x);
    break; // -X
  case 2:
    dir = float3(st.x, 1.0, -st.y);
    break; // +Y
  case 3:
    dir = float3(st.x, -1.0, st.y);
    break; // -Y
  case 4:
    dir = float3(st.x, st.y, 1.0);
    break; // +Z
  case 5:
    dir = float3(-st.x, st.y, -1.0);
    break; // -Z
  }
  dir = normalize(dir);

  float2 equiUV;
  equiUV.x = atan2(dir.z, dir.x) * invAtan.x + 0.5;
  equiUV.y = asin(dir.y) * invAtan.y + 0.5;

  float4 color = inputTexture.sample(texSampler, equiUV);
  outputTexture.write(color, gid.xy, face);
}
