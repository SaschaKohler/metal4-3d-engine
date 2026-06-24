#pragma once

#ifndef __METAL_VERSION__
#include <simd/simd.h>
#endif

#define LIGHT_TYPE_DIRECTIONAL 0
#define LIGHT_TYPE_POINT 1

struct Light {
  simd_float3 positionOrDirection;
  float intensity;
  simd_float3 color;
  int type;
  float radius;
  simd_float3 _pad;
};
