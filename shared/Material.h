#pragma once

#include <simd/simd.h>

struct Material {
  simd_float3 baseColor;
  float roughness;
  float metallic;
  simd_float3 _padding;
};
