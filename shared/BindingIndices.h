#pragma once

enum BufferIndex {
  BufferIndexVertices = 0,
  BufferIndexUniforms = 1,
  BufferIndexMaterial = 2,
  BufferIndexLights = 3,
};

enum TextureIndex {
  TextureIndexEquirectInput = 0,
  TextureIndexEnvironment = 1,
  TextureIndexIrradiance = 2,
  TextureIndexPrefiltered = 3,
  TextureIndexBRDFLUT = 4,
  TextureIndexBaseColor = 5,
  TextureIndexNormal = 6,
};

enum SamplerIndex {
  SamplerIndexDefault = 0,
};
