// MetalImpl.mm
// Generates the metal-cpp implementation exactly once in the translation unit.
// Include this file in the build but NEVER include it from headers.

#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION

#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
