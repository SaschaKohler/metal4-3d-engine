#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

#include "../shared/BindingIndices.h"
#include "Mesh.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <mach-o/dyld.h>
#include <vector>

// ---------------------------------------------------------------------------
// Helper: resolve the absolute path to an asset bundled next to the executable
// ---------------------------------------------------------------------------
static std::string executableDir() {
  char buf[4096];
  uint32_t size = sizeof(buf);
  _NSGetExecutablePath(buf, &size);
  std::string path(buf);
  auto pos = path.rfind('/');
  return (pos != std::string::npos) ? path.substr(0, pos) : ".";
}

// ---------------------------------------------------------------------------
Mesh *Mesh::loadGLB(MTL::Device *device, const std::string &path) {
  cgltf_options options{};
  cgltf_data *data = nullptr;

  // Resolve to absolute path: try as-is, then relative to executable
  std::string resolvedPath = path;
  cgltf_result result = cgltf_parse_file(&options, resolvedPath.c_str(), &data);
  if (result != cgltf_result_success) {
    resolvedPath = executableDir() + "/" + path;
    printf("[Mesh] Retrying with: %s\n", resolvedPath.c_str());
    result = cgltf_parse_file(&options, resolvedPath.c_str(), &data);
  }

  if (result != cgltf_result_success) {
    printf("[Mesh] Failed to parse glTF: %s\n", resolvedPath.c_str());
    return nullptr;
  }

  // Use the same resolved path for buffer loading
  result = cgltf_load_buffers(&options, data, resolvedPath.c_str());
  if (result != cgltf_result_success) {
    printf("[Mesh] Failed to load glTF buffers: %s\n", resolvedPath.c_str());
    cgltf_free(data);
    return nullptr;
  }

  // ── Find first primitive with POSITION ──────────────────────────────────
  cgltf_primitive *prim = nullptr;
  for (size_t mi = 0; mi < data->meshes_count && !prim; ++mi) {
    for (size_t pi = 0; pi < data->meshes[mi].primitives_count && !prim; ++pi) {
      prim = &data->meshes[mi].primitives[pi];
    }
  }

  if (!prim) {
    printf("[Mesh] No primitives found in %s\n", path.c_str());
    cgltf_free(data);
    return nullptr;
  }

  // ── Read POSITION and NORMAL accessors ──────────────────────────────────
  cgltf_accessor *posAcc = nullptr;
  cgltf_accessor *normAcc = nullptr;

  for (size_t ai = 0; ai < prim->attributes_count; ++ai) {
    auto &attr = prim->attributes[ai];
    if (attr.type == cgltf_attribute_type_position)
      posAcc = attr.data;
    if (attr.type == cgltf_attribute_type_normal)
      normAcc = attr.data;
  }

  if (!posAcc) {
    printf("[Mesh] No POSITION attribute in %s\n", path.c_str());
    cgltf_free(data);
    return nullptr;
  }

  size_t vertexCount = posAcc->count;

  // Build interleaved vertex array
  std::vector<Vertex> vertices(vertexCount);
  for (size_t i = 0; i < vertexCount; ++i) {
    float tmp[3];
    cgltf_accessor_read_float(posAcc, i, tmp, 3);
    vertices[i].position = simd::float3{tmp[0], tmp[1], tmp[2]};
    if (normAcc) {
      cgltf_accessor_read_float(normAcc, i, tmp, 3);
      vertices[i].normal = simd::float3{tmp[0], tmp[1], tmp[2]};
    } else {
      vertices[i].normal = simd::float3{0, 1, 0};
    }
  }

  // ── Read index accessor ─────────────────────────────────────────────────
  std::vector<uint32_t> indices;
  if (prim->indices) {
    size_t idxCount = prim->indices->count;
    indices.resize(idxCount);
    for (size_t i = 0; i < idxCount; ++i)
      indices[i] =
          static_cast<uint32_t>(cgltf_accessor_read_index(prim->indices, i));
  } else {
    // Non-indexed: generate sequential indices
    indices.resize(vertexCount);
    for (size_t i = 0; i < vertexCount; ++i)
      indices[i] = static_cast<uint32_t>(i);
  }

  cgltf_free(data);

  // ── Upload to Metal buffers ─────────────────────────────────────────────
  Mesh *mesh = new Mesh();

  mesh->m_vertexBuffer =
      device->newBuffer(vertices.data(), vertices.size() * sizeof(Vertex),
                        MTL::ResourceStorageModeShared);

  mesh->m_indexBuffer =
      device->newBuffer(indices.data(), indices.size() * sizeof(uint32_t),
                        MTL::ResourceStorageModeShared);

  mesh->m_indexCount = static_cast<uint32_t>(indices.size());

  printf("[Mesh] Loaded %s — %zu vertices, %zu indices\n", path.c_str(),
         vertexCount, indices.size());

  return mesh;
}

// ---------------------------------------------------------------------------
Mesh::~Mesh() {
  if (m_indexBuffer)
    m_indexBuffer->release();
  if (m_vertexBuffer)
    m_vertexBuffer->release();
}

// ---------------------------------------------------------------------------
void Mesh::draw(MTL::RenderCommandEncoder *enc) const {
  enc->setVertexBuffer(m_vertexBuffer, 0, BufferIndexVertices);
  enc->drawIndexedPrimitives(MTL::PrimitiveType::PrimitiveTypeTriangle,
                             m_indexCount, MTL::IndexType::IndexTypeUInt32,
                             m_indexBuffer, 0);
}
