#pragma once

#include <simd/simd.h>

// ---------------------------------------------------------------------------
// Uniforms.hpp — GPU-side constant data for each draw call.
//
// Must be kept in sync with the `Uniforms` struct in the Metal shader.
// Alignment: simd::float4x4 is 64-byte aligned — Metal buffer offset must
// be a multiple of 256 bytes (MTLDevice.minimumConstantBufferOffsetAlignment).
// For simplicity we use one buffer per frame (single draw call, no offsets).
// ---------------------------------------------------------------------------
struct Uniforms {
    simd::float4x4 modelMatrix;
    simd::float4x4 viewMatrix;
    simd::float4x4 projectionMatrix;
};
