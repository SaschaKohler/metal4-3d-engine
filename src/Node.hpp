#pragma once

#include <simd/simd.h>
#include <vector>
#include <memory>
#include <cstdint>
#include "Math.hpp"
#include "Mesh.hpp"

// ---------------------------------------------------------------------------
// Node — one element of the scene graph.
//
// World matrix = parent->worldMatrix * localMatrix
// A Node optionally references a Mesh (leaf nodes) or acts as a group node.
// ---------------------------------------------------------------------------
class Node {
public:
  explicit Node(const char *name = "node") : m_name(name) {}

  const char *name() const { return m_name; }

  // ── Transform (local space) ─────────────────────────────────────────────
  simd::float3 translation{0, 0, 0};
  simd::float3 rotationEuler{0, 0, 0};
  float uniformScale{1.0f};

  // ── Optional mesh reference (non-owning) ────────────────────────────────
  Mesh *mesh{nullptr};
  uint32_t materialIndex{0};

  // ── Hierarchy ───────────────────────────────────────────────────────────
  void addChild(std::shared_ptr<Node> child) {
    child->m_parent = this;
    m_children.push_back(std::move(child));
  }

  const std::vector<std::shared_ptr<Node>> &children() const {
    return m_children;
  }

  // ── Matrix update ───────────────────────────────────────────────────────
  // Call once per frame top-down (parent before children).
  void updateWorldMatrix(
      const simd::float4x4 &parentWorld = matrix_identity_float4x4) {
    simd::float4x4 local =
        math::translation(translation.x, translation.y, translation.z) *
        math::rotation(rotationEuler.z, {0, 0, 1}) *
        math::rotation(rotationEuler.y, {0, 1, 0}) *
        math::rotation(rotationEuler.x, {1, 0, 0}) * math::scale(uniformScale);

    worldMatrix = parentWorld * local;

    for (auto &child : m_children)
      child->updateWorldMatrix(worldMatrix);
  }

  simd::float4x4 worldMatrix{matrix_identity_float4x4};

private:
  const char *m_name{"node"};
  Node *m_parent{nullptr};
  std::vector<std::shared_ptr<Node>> m_children;
};
