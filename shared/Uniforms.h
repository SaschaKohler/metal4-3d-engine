#pragma once

#ifdef __METAL_VERSION__
#define F4X4 metal::float4x4
#define F3    metal::float3
#else
#include <simd/simd.h>
#define F4X4 simd_float4x4
#define F3    simd_float3
#endif

struct Uniforms {
  F4X4 modelMatrix;
  F4X4 viewMatrix;
  F4X4 projectionMatrix;
  F4X4 normalMatrix;
  uint materialIndex;
  F3   _pad0;
  F3   cameraPosition;
  float _pad1;
  uint lightCount;
  F3   _pad2;
};

#undef F4X4
#undef F3
