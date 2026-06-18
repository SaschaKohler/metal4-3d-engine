#pragma once

#include <simd/simd.h>
#include <cmath>
#include <algorithm>

// ---------------------------------------------------------------------------
// Camera.hpp — Orbit camera (spherical coordinates around a target).
//
// Interaction model:
//   - Left-drag  → orbit (yaw + pitch)
//   - Right-drag → pan (translate target in view-space XY)
//   - Scroll     → dolly (zoom by changing radius)
//
// All angles in radians.  No Objective-C — pure C++ header.
// ---------------------------------------------------------------------------
class Camera {
public:
    // Orbit parameters
    float yaw    { 0.3f };                // radians around world-Y
    float pitch  { 0.3f };               // radians above horizon
    float radius { 3.0f };               // distance from target
    simd::float3 target { 0, 0, 0 };     // look-at point

    // Sensitivity
    float orbitSensitivity { 0.01f };
    float panSensitivity   { 0.005f };
    float scrollSensitivity{ 0.1f };

    // ---------------------------------------------------------------------------
    // Eye position in world space derived from spherical coords
    // ---------------------------------------------------------------------------
    simd::float3 eye() const {
        float cosP = std::cos(pitch);
        return target + simd::float3{
            radius * cosP * std::sin(yaw),
            radius * std::sin(pitch),
            radius * cosP * std::cos(yaw)
        };
    }

    // ---------------------------------------------------------------------------
    // Input handlers
    // ---------------------------------------------------------------------------
    void orbit(float dx, float dy) {
        yaw   += dx * orbitSensitivity;
        pitch += dy * orbitSensitivity;
        // Clamp pitch so camera doesn't flip at the poles
        constexpr float kMaxPitch = 1.55f; // ~89°
        pitch = std::clamp(pitch, -kMaxPitch, kMaxPitch);
    }

    void pan(float dx, float dy) {
        // Move target along camera's local right and up axes
        simd::float3 e   = eye();
        simd::float3 fwd = simd::normalize(target - e);
        simd::float3 worldUp { 0, 1, 0 };
        simd::float3 right = simd::normalize(simd::cross(fwd, worldUp));
        simd::float3 up    = simd::cross(right, fwd);

        target -= right * (dx * panSensitivity * radius);
        target += up    * (dy * panSensitivity * radius);
    }

    void scroll(float delta) {
        radius -= delta * scrollSensitivity;
        radius = std::max(radius, 0.1f);   // prevent going behind target
    }
};
