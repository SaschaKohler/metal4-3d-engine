#pragma once

#include <simd/simd.h>
#include <cmath>

// ---------------------------------------------------------------------------
// Math.hpp — simd-based 3D math helpers (C++, no Objective-C)
//
// All functions operate on simd::float4x4 (column-major, matches Metal/GLSL
// convention).  Metal's clip space: x ∈ [-1,1], y ∈ [-1,1], z ∈ [0,1].
// ---------------------------------------------------------------------------

namespace math {

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
inline simd::float4x4 identity() {
    return matrix_identity_float4x4;
}

// ---------------------------------------------------------------------------
// Translation
// ---------------------------------------------------------------------------
inline simd::float4x4 translation(float tx, float ty, float tz) {
    simd::float4x4 m = matrix_identity_float4x4;
    m.columns[3] = simd::float4{ tx, ty, tz, 1.0f };
    return m;
}

// ---------------------------------------------------------------------------
// Scale (uniform)
// ---------------------------------------------------------------------------
inline simd::float4x4 scale(float s) {
    simd::float4x4 m = matrix_identity_float4x4;
    m.columns[0].x = s;
    m.columns[1].y = s;
    m.columns[2].z = s;
    return m;
}

// ---------------------------------------------------------------------------
// Rotation around an arbitrary axis (normalised)
// ---------------------------------------------------------------------------
inline simd::float4x4 rotation(float angleRadians, simd::float3 axis) {
    axis = simd::normalize(axis);
    float c = std::cos(angleRadians);
    float s = std::sin(angleRadians);
    float t = 1.0f - c;
    float x = axis.x, y = axis.y, z = axis.z;

    return simd::float4x4{
        simd::float4{ t*x*x + c,   t*x*y + s*z, t*x*z - s*y, 0 },
        simd::float4{ t*x*y - s*z, t*y*y + c,   t*y*z + s*x, 0 },
        simd::float4{ t*x*z + s*y, t*y*z - s*x, t*z*z + c,   0 },
        simd::float4{ 0,           0,            0,           1 }
    };
}

// ---------------------------------------------------------------------------
// View matrix — right-handed look-at (camera at `eye` looking toward `center`)
// ---------------------------------------------------------------------------
inline simd::float4x4 lookAt(simd::float3 eye,
                              simd::float3 center,
                              simd::float3 up) {
    simd::float3 f = simd::normalize(center - eye);   // forward
    simd::float3 r = simd::normalize(simd::cross(f, up)); // right
    simd::float3 u = simd::cross(r, f);               // true up

    // Column-major: columns are [r, u, -f, t]
    simd::float4x4 m;
    m.columns[0] = simd::float4{  r.x,  u.x, -f.x, 0 };
    m.columns[1] = simd::float4{  r.y,  u.y, -f.y, 0 };
    m.columns[2] = simd::float4{  r.z,  u.z, -f.z, 0 };
    m.columns[3] = simd::float4{ -simd::dot(r, eye),
                                 -simd::dot(u, eye),
                                  simd::dot(f, eye),
                                  1 };
    return m;
}

// ---------------------------------------------------------------------------
// Perspective projection — Metal clip space (z ∈ [0,1], reversed-Z friendly)
// fovY in radians, aspect = width/height
// ---------------------------------------------------------------------------
inline simd::float4x4 perspectiveFov(float fovY,
                                     float aspect,
                                     float nearZ,
                                     float farZ) {
    float ys = 1.0f / std::tan(fovY * 0.5f);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);          // maps [near,far] → [1,0] (reversed)

    simd::float4x4 m{};
    m.columns[0] = simd::float4{ xs,  0,  0,  0 };
    m.columns[1] = simd::float4{  0, ys,  0,  0 };
    m.columns[2] = simd::float4{  0,  0, zs, -1 };
    m.columns[3] = simd::float4{  0,  0, nearZ * zs, 0 };
    return m;
}

} // namespace math
