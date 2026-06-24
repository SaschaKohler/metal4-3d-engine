#pragma once

#ifndef __METAL_VERSION__
#include <simd/simd.h>
#endif

struct Material {
  simd_float3 baseColor;
  float roughness;
  float metallic;
  int emissive;
  simd_float3 _padding;
};
