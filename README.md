# metal4-3d-engine

An indie 3D engine built step-by-step on **Metal 4** using **metal-cpp**.

## Milestone Status

| # | Milestone | Status |
|---|-----------|--------|
| 1 | Metal backbone — triangle on screen | ✅ Done |
| 2 | Render loop & camera | ✅ Done |
| 3 | Mesh loading & scene graph | ✅ Done |
| 4 | PBR lighting (Cook-Torrance BRDF, Light Buffer) | ✅ Done |
| 5 | MetalFX upscaling | 🔜 |
| 6 | Ray traced shadows / AO | 🔜 |
| 7 | Neural rendering (ML-in-shader) | 🔜 |

---

## Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 16+ (for Metal 4 SDK headers)
- CMake ≥ 3.22
- `metal-cpp` headers from Apple

## Setup

### 1. Clone metal-cpp

```bash
cd vendor
git clone https://github.com/apple/metal-cpp.git
```

### 2. Configure & build

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(sysctl -n hw.logicalcpu)
```

### 2b. LazyVim / clangd LSP (einmalig)

```bash
ln -s build/compile_commands.json compile_commands.json
```

`clangd` findet die Datei automatisch im Projekt-Root — volle Autocomplete, Go-to-Definition und Fehleranzeige für `.mm`, `.hpp`, `.cpp` und `.metal`.

### 3. Run

```bash
./build/metal4engine.app/Contents/MacOS/metal4engine
```

You should see a **1280×720 window** with a colored triangle (red top, green left, blue right) on a near-black background.

---

## Project Structure

```
metal4-3d-engine/
├── CMakeLists.txt
├── shaders/
│   └── triangle.metal        # Vertex + fragment shaders (MSL)
├── src/
│   ├── main.mm               # Entry point — NSApplication bootstrap
│   ├── AppDelegate.mm/.hpp   # Window + MTKView creation
│   ├── MetalViewDelegate.mm/.hpp  # MTKViewDelegate → C++ bridge
│   ├── Renderer.mm/.hpp      # Core renderer: device, queue, pipeline
│   └── MetalImpl.mm          # metal-cpp private implementation (once only)
└── vendor/
    └── metal-cpp/            # Apple's header-only C++ Metal wrapper
```

---

## Learning Guide

- **`GUIDE.md`** — vollständiges Lehrbuch zu allen Milestones (Deutsch). Erklärt jede Entscheidung mit Physik- und Technik-Hintergrund.
- **`GUIDE.html`** — gleicher Inhalt als navigierbare HTML-Seite (öffnen mit Browser).
- Referenzprojekt: `ModernRenderingWithMetal/` — Apple's offiziales Metal Sample als Vergleich.

---

## Architecture Notes

- **`MetalImpl.mm`** — defines `NS/CA/MTL_PRIVATE_IMPLEMENTATION` once. Never include from a header.
- **`Renderer`** — pure C++ class. No Objective-C. Owns all Metal objects with manual retain/release (no ARC for C++ objects).
- **`MetalViewDelegate`** — thin Objective-C wrapper. Owns the `Renderer` via `std::unique_ptr` and rebuilds the depth texture on resize.
- Shaders are compiled by CMake via `xcrun metal` → `.air` → `default.metallib`, then copied next to the executable.
