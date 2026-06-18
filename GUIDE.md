# Metal4Engine — Das Lehrbuch zu Milestone 1

> Dieses Dokument erklärt **jeden einzelnen Aspekt** des Milestone-1-Codes,
> von der untersten Hardware-Schicht bis zur letzten Zeile Shader-Code.
> Ziel: Du sollst nicht nur wissen *was* der Code tut, sondern *warum* jede
> Entscheidung so getroffen wurde.

---

## Inhaltsverzeichnis

1. [Die große Übersicht — Was passiert beim Starten?](#1-die-grosse-übersicht)
2. [Die Hardware-Seite — Was ist eine GPU?](#2-die-hardware-seite)
3. [Metal 4 — Warum dieses API?](#3-metal-4)
4. [metal-cpp — C++ spricht mit Metal](#4-metal-cpp)
5. [Der Speicher auf der GPU](#5-der-speicher-auf-der-gpu)
6. [Projektstruktur und Sprachenwahl](#6-projektstruktur-und-sprachenwahl)
7. [CMakeLists.txt — Zeile für Zeile](#7-cmakelists)
8. [main.mm — Der Einstiegspunkt](#8-mainmm)
9. [AppDelegate — Das Fenster](#9-appdelegate)
10. [MetalViewDelegate — Die Render-Brücke](#10-metalviewdelegate)
11. [Renderer — Das Herzstück](#11-renderer)
12. [triangle.metal — Der Shader](#12-trianglemetal)
13. [Die Render-Pipeline — Das große Bild](#13-die-render-pipeline)
14. [Koordinatensysteme und NDC](#14-koordinatensysteme-und-ndc)
15. [Memory Management in metal-cpp](#15-memory-management)
16. [clangd und .clangd — Der LSP erklärt](#16-clangd)

---

## 1. Die große Übersicht

Wenn du `./metal4engine` startest, passiert folgendes in exakt dieser Reihenfolge:

```
main()
  └─ NSApplication starten
       └─ AppDelegate: Fenster + MTKView erstellen
            └─ MTLDevice holen (= Zugriff auf GPU)
                 └─ MetalViewDelegate erstellen (hält den C++ Renderer)
                      └─ Renderer erstellen:
                           ├─ CommandQueue erstellen
                           ├─ Shader laden (default.metallib)
                           ├─ RenderPipelineState kompilieren
                           └─ Vertex Buffer befüllen
                                └─ MTKView startet den Render-Loop (60fps)
                                     └─ Jeden Frame:
                                          ├─ CommandBuffer holen
                                          ├─ RenderPassDescriptor konfigurieren
                                          ├─ RenderCommandEncoder öffnen
                                          ├─ Pipeline + Buffer binden
                                          ├─ drawPrimitives()
                                          ├─ Encoder schliessen
                                          ├─ presentDrawable()
                                          └─ commit()
```

Alles dreht sich um diesen Loop. Jede Sekunde läuft er 60 Mal.

---

## 2. Die Hardware-Seite

### Was ist eine GPU überhaupt?

Eine **CPU** (dein M-Chip Efficiency/Performance Core) hat wenige, aber sehr mächtige Kerne — optimiert für sequentielle Logik, Verzweigungen, Caches.

Eine **GPU** hat **tausende winzige Kerne** — optimiert dafür, die *gleiche Operation parallel* auf riesige Datenmengen anzuwenden. Ein Apple M4 Pro hat z.B. 20 GPU-Kerne, jeder mit hunderten von "Shader-Threads".

### Warum braucht man ein API wie Metal?

Die GPU versteht nur Maschinencode — ähnlich wie die CPU. Aber der Weg dorthin ist anders:

- GPU-Programme heissen **Shader** und werden in einer eigenen Sprache geschrieben (bei Metal: **MSL** — Metal Shading Language).
- Shader werden zur Laufzeit kompiliert (oder vorcompiliert in `.metallib`-Dateien).
- Die CPU schickt der GPU **Command Buffers** — eine Liste von Befehlen, die die GPU abarbeitet.
- Die GPU ist **asynchron** — sie arbeitet parallel zur CPU.

Metal ist das Apple-API das diese Kommunikation ermöglicht.

### Die Apple Unified Memory Architecture

Apple Silicon (M1–M5) hat eine **Besonderheit**: CPU und GPU teilen sich denselben physischen RAM. Es gibt keinen separaten "VRAM". Das ist warum `MTL::ResourceStorageModeShared` bei uns funktioniert — der Vertex Buffer liegt im RAM und ist für beide direkt zugänglich, ohne Kopie.

```
┌─────────────────────────────────┐
│         Unified Memory          │
│  ┌──────────┐  ┌──────────────┐ │
│  │   CPU    │  │     GPU      │ │
│  │ (Swift,  │  │ (Shader,     │ │
│  │  C++)    │  │  Rasterizer) │ │
│  └──────────┘  └──────────────┘ │
│       ↕ direkter RAM-Zugriff ↕  │
└─────────────────────────────────┘
```

Auf diskreten GPUs (NVIDIA, AMD) müsste man Daten explizit von CPU-RAM in GPU-VRAM kopieren. Auf Apple Silicon entfällt das.

---

## 3. Metal 4

### Geschichte

- **Metal 1** (2014): Ersatz für OpenGL/OpenCL auf Apple-Plattformen. Niedrigerer Overhead.
- **Metal 2** (2017): Argument Buffers, VR-Support, Machine Learning.
- **Metal 3** (2022): MetalFX Upscaling, Mesh Shaders, Offline Compilation.
- **Metal 4** (2025/WWDC): **Unified Command Encoder**, native Tensor-Typen in MSL, MetalFX Frame Interpolation, verbessertes Ray Tracing.

### Nutzt Milestone 1 bereits Metal 4?

**Nein — und das ist Absicht.**

Milestone 1 verwendet ausschliesslich **Metal 1-3 APIs** die seit 2014 existieren:

| Code in Milestone 1 | Metal-Version |
|---|---|
| `MTL::Device`, `MTL::CommandQueue` | Metal 1 (2014) |
| `MTL::RenderPipelineState` | Metal 1 (2014) |
| `MTL::RenderCommandEncoder` | Metal 1 (2014) |
| `MTKView`, `CAMetalDrawable` | Metal 1 (2014) |
| `MTL::Buffer`, `StorageModeShared` | Metal 1 (2014) |
| `metal-cpp` Wrapper | Metal 2+ (2019) |

Das ist kein Fehler — es ist die richtige Reihenfolge. Metal 4-Features wie `MTL4ArgumentTable` oder `MTL4CommandEncoder` bauen auf diesen Grundlagen auf. Wer sie überspringt, versteht Metal 4 nicht wirklich.

**Woran man Milestone 1 als Metal-4-Projekt erkennt:**
- Es kompiliert mit dem **Metal 4 SDK** (`MacOSX26.5.sdk`)
- Die **Architektur** ist für Metal 4 vorbereitet (isolierter C++ Renderer, klare Layer-Trennung)
- Die Shader laufen auf **Metal 4-fähiger Hardware** (M4/A19 GPU)

### Was ist neu in Metal 4 — und wann kommt es?

| Feature | Ab wann relevant |
|---|---|
| `MTL4ArgumentTable` (Bindless Buffers) | Milestone 3 |
| `MTL4CommandEncoder` (Unified Encoder) | Milestone 4 |
| MetalFX Neural Upscaling | Milestone 5 |
| Ray Tracing Denoiser | Milestone 6 |
| Native Tensor-Typen in MSL | Milestone 7 |
| Placement Sparse Resources | Milestone 3+ |

### Metal vs. Vulkan vs. OpenGL

| | Metal | Vulkan | OpenGL |
|---|---|---|---|
| Overhead | Sehr niedrig | Sehr niedrig | Hoch |
| Plattformen | Apple only | Cross-platform | Cross-platform |
| Lernkurve | Mittel | Steil | Flach |
| Shader-Sprache | MSL (C++-ähnlich) | GLSL/HLSL → SPIRV | GLSL |
| Moderne Features | Metal 4: Tensors, AI | VK 1.3: Ray Tracing | Veraltet |

Wir wählen Metal weil: Apple Silicon, keine Abstraktionsschicht, direkter Zugriff auf Neural Engine via Tensors (Milestone 7).

---

## 4. metal-cpp

### Was ist metal-cpp?

`metal-cpp` ist eine **header-only C++ Wrapper Library**, offiziell von Apple entwickelt. Sie mapped die Objective-C Metal-Klassen 1:1 auf C++ Namespaces.

Ohne metal-cpp müsste man schreiben:
```objc
id<MTLDevice> device = MTLCreateSystemDefaultDevice();
id<MTLCommandQueue> queue = [device newCommandQueue];
```

Mit metal-cpp schreibt man:
```cpp
MTL::Device* device = MTL::CreateSystemDefaultDevice();
MTL::CommandQueue* queue = device->newCommandQueue();
```

Gleiche Operationen, gleiche Performance — nur C++-Syntax.

### Wie funktioniert es intern?

metal-cpp generiert **keine** neuen Objekte. Es ist reines Casting:

```cpp
// Vereinfacht aus dem metal-cpp Quellcode:
namespace MTL {
    class Device : public NS::Object {
    public:
        CommandQueue* newCommandQueue() {
            return Object::sendMessage<CommandQueue*>(this, _MTL_PRIVATE_SEL(newCommandQueue));
        }
    };
}
```

`sendMessage` ist Objective-C Message Dispatch — `metal-cpp` ruft intern `objc_msgSend` auf. Das bedeutet **null Overhead** gegenüber direktem Objective-C.

### Die drei Implementierungs-Macros

In `MetalImpl.mm`:
```cpp
#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
```

Diese Macros sind **kritisch**. metal-cpp ist header-only, aber die privaten Selector-Strings (z.B. `@selector(newCommandQueue)`) müssen genau **einmal** in einer Translation Unit definiert werden. Diese Macros aktivieren diese Definitionen.

**Würde man sie in zwei `.mm`-Dateien setzen**: Linker-Fehler wegen doppelter Symbole.
**Würde man sie vergessen**: Linker-Fehler wegen fehlender Symbole.

Deshalb existiert `MetalImpl.mm` als dedizierte Datei — sie tut nichts außer diese drei Macros zu aktivieren und die Header einzubinden.

---

## 5. Der Speicher auf der GPU

### ResourceStorageModes

Metal kennt drei Speichermodi:

```
MTL::ResourceStorageModeShared   → CPU + GPU können lesen/schreiben
                                   (Apple Silicon: kein Overhead)
                                   (Intel Mac: Kopie nötig)

MTL::ResourceStorageModePrivate  → Nur GPU kann zugreifen
                                   (schnellster GPU-Zugriff)
                                   (CPU kann nicht lesen)

MTL::ResourceStorageModeManaged  → Explizite Synchronisation
                                   (nur auf Intel Macs relevant)
```

Unser **Vertex Buffer** nutzt `Shared` — weil wir die Daten von der CPU befüllen und die GPU sie lesen soll, ohne Kopie.

Unser **Depth Texture** nutzt `Private` — weil nur die GPU sie beim Rendern liest/schreibt. Die CPU braucht keinen Zugriff.

### Was ist ein Buffer?

Ein `MTL::Buffer` ist ein roher Speicherbereich auf der GPU-zugänglichen Seite des RAM. Kein Typ, keine Interpretation — nur Bytes. Die GPU weiss erst durch den Shader, wie sie die Bytes interpretieren soll.

```
Buffer-Inhalt (3 Vertices × 28 Bytes):
Byte 0-11:   float3 position  (3 × 4 Bytes) = {0.0, 0.5, 0.0}
Byte 12-27:  float4 color     (4 × 4 Bytes) = {1.0, 0.2, 0.2, 1.0}
Byte 28-39:  float3 position  = {-0.5, -0.5, 0.0}
...
```

Der Shader liest exakt dieses Layout — deshalb muss die C++-`Vertex`-Struct **identisch** zum MSL-`VertexIn`-Struct sein.

---

## 6. Projektstruktur und Sprachenwahl

```
src/
├── main.mm                  ← Objective-C++ (braucht NSApplication)
├── AppDelegate.h            ← Objective-C Header (@interface)
├── AppDelegate.mm           ← Objective-C++ Implementation
├── MetalViewDelegate.h      ← Objective-C Header (@interface)
├── MetalViewDelegate.mm     ← Objective-C++ (ObjC + C++ gemischt)
├── Renderer.hpp             ← Reines C++ Header
├── Renderer.mm              ← Reines C++ (kompiliert als OBJCXX wegen .mm)
└── MetalImpl.mm             ← Nur die metal-cpp Implementierungs-Macros
```

### Warum `.mm` und nicht `.cpp`?

`.mm` = **Objective-C++** — der Compiler akzeptiert sowohl Objective-C-Syntax (`@interface`, `[ ]` Message-Sends) als auch C++-Syntax. Selbst `Renderer.mm` — das kein Objective-C enthält — wird als `.mm` kompiliert, weil es `metal-cpp` Header einbindet die intern Objective-C-Selektoren nutzen.

### Warum `.h` für ObjC und `.hpp` für C++?

`clangd` (der LSP) bestimmt die Sprache eines Headers anhand der Extension:
- `.hpp` → C++ Header → kein Objective-C erlaubt
- `.h` → ambig → via `.clangd` als `objective-c++-header` behandelt

`@interface`, `@end`, `#import` in einem `.hpp` führt zu `clangd`-Fehlern.

---

## 7. CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.22)
project(metal4_3d_engine LANGUAGES CXX OBJCXX)
```

`OBJCXX` ist entscheidend — ohne diese Language-Deklaration weiss CMake nicht, dass `.mm`-Dateien mit dem Objective-C++ Compiler gebaut werden sollen.

```cmake
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
```

Generiert `build/compile_commands.json` — eine JSON-Datei die für jede Source-Datei den exakten Compiler-Aufruf listet. `clangd` liest diese Datei um zu wissen: welche Include-Pfade, welche Flags, welcher Standard.

```cmake
execute_process(
    COMMAND xcrun --sdk macosx --show-sdk-path
    OUTPUT_VARIABLE MACOS_SDK_PATH
    ...
)
```

`xcrun` ist Apples Tool um den korrekten SDK-Pfad zu finden. Dieser Pfad ändert sich mit jeder Xcode-Version (bei uns: `MacOSX26.5.sdk`). Durch `xcrun` ist der Build-Script immer korrekt, egal welche Xcode-Version installiert ist.

```cmake
add_custom_command(
    COMMAND xcrun -sdk macosx metal -c triangle.metal -o triangle.air
    COMMAND xcrun -sdk macosx metallib triangle.air -o default.metallib
    ...
)
```

Metal-Shader werden in **zwei Schritten** kompiliert:
1. `.metal` → `.air` (Apple Intermediate Representation — ähnlich wie LLVM IR)
2. `.air` → `.metallib` (fertige Bibliothek, kann mehrere Shader enthalten)

Xcode macht das automatisch. In CMake müssen wir `xcrun metal` und `xcrun metallib` explizit aufrufen.

---

## 8. main.mm

```objc
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        AppDelegate*   del = [[AppDelegate alloc] init];
        app.delegate = del;
        [app run];
    }
    return 0;
}
```

### `@autoreleasepool`

Ein Objective-C Speichermanagement-Konstrukt. Objekte die mit `autorelease` markiert werden, leben bis das `autoreleasepool` verlassen wird. Ohne diesen Block könnten Objekte die während des App-Starts erstellt werden zu früh freigegeben werden.

### `[NSApplication sharedApplication]`

Erstellt den Singleton der macOS-Applikation. Danach existiert genau eine `NSApplication`-Instanz — sie verwaltet den Event Loop, Menüleiste, und App-Lifecycle.

### `[app run]`

Startet den **Event Loop** — eine Endlosschleife die:
- macOS-Events empfängt (Maus, Tastatur, Fenster-Events)
- Sie an den `delegate` weiterleitet
- Den MTKView-Render-Loop antreibt

`[app run]` kehrt erst zurück wenn die App beendet wird.

---

## 9. AppDelegate

```objc
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
```

Diese Methode wird von `NSApplication` aufgerufen sobald die App vollständig gestartet ist — alle Frameworks geladen, Event Loop läuft. Hier erstellen wir alles was ein Fenster und Metal braucht.

```objc
NSRect frame = NSMakeRect(0, 0, 1280, 720);
_window = [[NSWindow alloc] initWithContentRect:frame
    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | ...)
    backing:NSBackingStoreBuffered
    defer:NO];
```

`NSMakeRect(x, y, width, height)` — Koordinaten in **Punkten** (nicht Pixeln). Auf Retina-Displays ist 1 Punkt = 2 Pixel. Der Ursprung (0,0) ist auf macOS **unten links** (anders als auf iOS wo er oben links ist).

`NSBackingStoreBuffered` — Double Buffering: Die App zeichnet in einen Hintergrundpuffer, macOS tauscht ihn zum richtigen Zeitpunkt aus (kein Flimmern).

`defer:NO` — Fenster sofort erstellen (nicht lazy).

```objc
id<MTLDevice> device = MTLCreateSystemDefaultDevice();
```

Das ist der wichtigste Aufruf der ganzen App. `MTLCreateSystemDefaultDevice()` gibt uns ein Handle auf die **beste verfügbare GPU**. Auf einem MacBook Pro M4 ist das die integrierte Apple GPU.

`id<MTLDevice>` ist Objective-C Syntax: `id` = generischer Objekt-Pointer, `<MTLDevice>` = muss das `MTLDevice`-Protokoll implementieren. Das ist Apples Objective-C API — wir werden es sofort in metal-cpp's `MTL::Device*` konvertieren.

```objc
_mtkView = [[MTKView alloc] initWithFrame:frame device:device];
_mtkView.colorPixelFormat        = MTLPixelFormatBGRA8Unorm_sRGB;
_mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
_mtkView.preferredFramesPerSecond = 60;
```

`MTKView` ist MetalKit's Fenster-View — sie verwaltet automatisch:
- Den **CAMetalLayer** (Core Animation Layer der mit Metal kommuniziert)
- Den **Drawable** (das aktuelle Render-Ziel)
- Den **Render-Loop** (ruft unseren Delegate 60x/Sekunde auf)

**Pixel-Formate:**
- `BGRA8Unorm_sRGB`: Blau-Grün-Rot-Alpha, 8 Bit pro Kanal, unsigned normalized (0–255 → 0.0–1.0), sRGB Farbraum
- `Depth32Float`: 32-Bit Floating-Point Tiefenwerte (0.0 = nah, 1.0 = fern)

Warum **BGRA** und nicht RGBA? Apple's GPUs sind historisch auf BGRA optimiert — die Reihenfolge der Kanäle im Speicher passt besser zum internen Display-Treiber.

```objc
_viewDelegate = [[MetalViewDelegate alloc]
    initWithDevice:(__bridge MTL::Device*)device];
```

`(__bridge MTL::Device*)device` — das ist ein **ARC Bridge Cast**. Wir konvertieren den Objective-C `id<MTLDevice>` Pointer in einen C++ `MTL::Device*` Pointer. `__bridge` bedeutet: kein Ownership-Transfer — ARC verwaltet das Objekt weiterhin auf der ObjC-Seite.

---

## 10. MetalViewDelegate

### Die Brücke zwischen ObjC und C++

```objc
@implementation MetalViewDelegate {
    std::unique_ptr<Renderer> _renderer;
    MTL::Texture*             _depthTexture;
    MTLPixelFormat            _depthFormat;
}
```

Objective-C++ erlaubt C++-Typen als Instance-Variablen. `std::unique_ptr<Renderer>` ist hier entscheidend — wenn `MetalViewDelegate` von ARC freigegeben wird, ruft ARC den `dealloc` auf, der `unique_ptr` destruktor gibt den `Renderer` frei, der `Renderer`-Destruktor gibt alle Metal-Objekte frei. **Automatische Cleanup-Kette** ohne manuellen Code.

### drawableSizeWillChange — Warum eine eigene Depth-Texture?

```objc
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
```

MTKView verwaltet den **Color Buffer** automatisch (der Drawable). Den **Depth Buffer** müssen wir selbst verwalten — weil Metal kein automatisches Depth-Attachment hat. Wenn sich die Fenstergröße ändert, muss die Depth-Texture die gleiche Größe haben wie der Color Buffer, sonst crasht der Render Pass.

```objc
id<MTLTexture> tex = [mtlDevice newTextureWithDescriptor:desc];
_depthTexture = (__bridge_retained MTL::Texture*)tex;
```

`__bridge_retained` — hier **übertragen** wir die Ownership von ARC zu unserem manuellen C++ Memory Management. ARC gibt das Objekt nicht frei, wir sind selbst dafür verantwortlich es mit `->release()` freizugeben. Das passiert in `dealloc` und in `mtkView:drawableSizeWillChange:`.

### drawInMTKView — Der Frame

```objc
- (void)drawInMTKView:(MTKView*)view {
    CA::MetalDrawable* drawable =
        (__bridge CA::MetalDrawable*)view.currentDrawable;
```

`view.currentDrawable` gibt uns das **aktuelle Render-Target** — die Textur die am Ende des Frames auf dem Bildschirm erscheint. MetalKit verwaltet intern einen **Drawable Pool** (typisch 3 Drawables) und gibt uns immer das nächste verfügbare.

---

## 11. Renderer

### Der Konstruktor

```cpp
Renderer::Renderer(MTL::Device* device)
    : m_device(device->retain())
```

`device->retain()` — metal-cpp folgt Cocoa Memory Management: wer ein Objekt hält, muss `retain()` aufrufen um den Reference Count zu erhöhen. Sonst könnte der Aufrufer das Device freigeben während wir noch damit arbeiten. Im Destruktor rufen wir `m_device->release()` auf.

### buildPipeline — Die 5 Schritte

#### Schritt 1: Library laden

```cpp
_NSGetExecutablePath(exePath, &size);
std::string libPathStr = std::string(dirname(exePath)) + "/default.metallib";
```

`_NSGetExecutablePath` ist eine macOS-Funktion die den absoluten Pfad zur laufenden Binary zurückgibt. `dirname()` schneidet den Dateinamen ab und gibt nur das Verzeichnis zurück. So finden wir `default.metallib` immer korrekt — unabhängig davon aus welchem Verzeichnis das Programm gestartet wird.

```cpp
m_library = m_device->newLibrary(libPath, &error);
```

Eine `MTL::Library` ist ein Container für kompilierte Shader-Funktionen. Sie entspricht der `.metallib`-Datei auf der Festplatte.

#### Schritt 2: Shader-Funktionen holen

```cpp
MTL::Function* vertFn = m_library->newFunction(
    NS::String::string("vertex_main", ...));
```

Wir holen die Shader-Funktionen **by name** aus der Library. Der Name muss exakt mit der `vertex`-Funktion im `.metal`-File übereinstimmen.

#### Schritt 3: RenderPipelineDescriptor

```cpp
auto* desc = MTL::RenderPipelineDescriptor::alloc()->init();
desc->setVertexFunction(vertFn);
desc->setFragmentFunction(fragFn);
desc->colorAttachments()->object(0)->setPixelFormat(
    MTL::PixelFormat::PixelFormatBGRA8Unorm_sRGB);
desc->setDepthAttachmentPixelFormat(MTL::PixelFormat::PixelFormatDepth32Float);
```

Der `RenderPipelineDescriptor` beschreibt die **gesamte Render-Pipeline**:
- Welcher Vertex Shader?
- Welcher Fragment Shader?
- In welches Pixel-Format wird gerendert?
- Welches Depth-Format wird verwendet?

**Die Pixel-Formate hier müssen exakt mit denen des RenderPasses übereinstimmen.** Wenn der Descriptor `BGRA8Unorm_sRGB` sagt aber der RenderPass `RGBA8Unorm` — Crash.

#### Schritt 4: Pipeline kompilieren

```cpp
m_pipelineState = m_device->newRenderPipelineState(desc, &error);
```

Das ist eine **teure Operation** — der GPU-Treiber kompiliert hier die Shader und optimiert die gesamte Pipeline für diese spezifische Konfiguration. Deshalb macht man das **einmal beim Start**, nicht jeden Frame.

`RenderPipelineState` ist immutable (unveränderlich) — einmal kompiliert, kann man nichts mehr ändern. Will man z.B. einen anderen Shader nutzen, braucht man einen neuen `RenderPipelineState`.

#### Schritt 5: Cleanup

```cpp
vertFn->release();
fragFn->release();
desc->release();
```

`vertFn` und `fragFn` werden vom `RenderPipelineState` intern gehalten (retain). Wir können unsere lokalen Referenzen danach freigeben. Der `desc` wird nach dem Kompilieren nicht mehr gebraucht.

### buildTriangleBuffer

```cpp
const Vertex vertices[] = {
    { {  0.0f,  0.5f, 0.0f }, { 1.0f, 0.2f, 0.2f, 1.0f } },  // top   – rot
    { { -0.5f, -0.5f, 0.0f }, { 0.2f, 1.0f, 0.2f, 1.0f } },  // links – grün
    { {  0.5f, -0.5f, 0.0f }, { 0.2f, 0.2f, 1.0f, 1.0f } },  // rechts – blau
};

m_vertexBuffer = m_device->newBuffer(
    vertices, sizeof(vertices), MTL::ResourceStorageModeShared);
```

Die Koordinaten sind in **NDC** (Normalized Device Coordinates) — dazu mehr in Kapitel 14.

`newBuffer(data, size, mode)` kopiert die CPU-Daten in den geteilten Speicher. Mit `StorageModeShared` auf Apple Silicon ist das eine direkte Speicheroperation — keine GPU-Kopie nötig.

### draw — Ein Frame

```cpp
auto* cmdBuf = m_commandQueue->commandBuffer();
```

Ein `CommandBuffer` ist wie ein leeres **Skript** das wir mit GPU-Befehlen füllen. Erst wenn wir `commit()` aufrufen, wird das Skript an die GPU geschickt.

```cpp
auto* passDesc = MTL::RenderPassDescriptor::alloc()->init();
auto* colorAttach = passDesc->colorAttachments()->object(0);
colorAttach->setTexture(drawable->texture());
colorAttach->setLoadAction(MTL::LoadActionClear);
colorAttach->setStoreAction(MTL::StoreActionStore);
colorAttach->setClearColor(MTL::ClearColor(0.08, 0.08, 0.10, 1.0));
```

Der `RenderPassDescriptor` definiert **was** gerendert wird und wie:

- `setTexture(drawable->texture())` — wir rendern in den aktuellen Drawable (den Bildschirm-Puffer)
- `LoadActionClear` — **vor dem Rendern**: Textur mit der ClearColor füllen (0.08, 0.08, 0.10 = sehr dunkles Grau-Blau)
- `StoreActionStore` — **nach dem Rendern**: Ergebnis in der Textur speichern (damit es am Bildschirm erscheint)

**LoadAction-Optionen:**
```
LoadActionClear  → Textur mit ClearColor füllen (teuer aber sauber)
LoadActionLoad   → Vorherigen Inhalt behalten (für Multi-Pass Rendering)
LoadActionDontCare → Inhalt undefiniert (schnellste Option wenn man alles überschreibt)
```

**StoreAction-Optionen:**
```
StoreActionStore     → Inhalt speichern (nötig für Color Buffer)
StoreActionDontCare  → Inhalt wegwerfen (optimal für Depth Buffer — nach dem Frame nicht mehr gebraucht)
```

```cpp
auto* enc = cmdBuf->renderCommandEncoder(passDesc);
```

Der `RenderCommandEncoder` ist das Interface um Render-Befehle aufzuzeichnen. Er öffnet den Render Pass — ab jetzt läuft alles innerhalb dieses Passes.

```cpp
enc->setRenderPipelineState(m_pipelineState);
MTL::Viewport vp { 0.0, 0.0, viewportWidth, viewportHeight, 0.0, 1.0 };
enc->setViewport(vp);
enc->setVertexBuffer(m_vertexBuffer, 0, 0);
```

- `setRenderPipelineState` — welche Shader und Pipeline-Konfiguration
- `setViewport` — wo auf dem Bildschirm gerendert wird (x, y, width, height, znear, zfar)
- `setVertexBuffer(buffer, offset, index)` — buffer 0 im Shader bekommt unsere Vertex-Daten

```cpp
enc->drawPrimitives(MTL::PrimitiveTypeTriangle, 0, 3);
```

Der eigentliche Zeichenbefehl: Zeichne `3` Vertices als `Triangle`, beginnend bei Vertex `0`. Die GPU nimmt die drei Vertices aus dem Buffer, schickt jeden durch den Vertex Shader, rasterisiert das Dreieck, und schickt jeden Fragment (Pixel) durch den Fragment Shader.

```cpp
enc->endEncoding();
cmdBuf->presentDrawable(drawable);
cmdBuf->commit();
```

- `endEncoding()` — Render Pass abschliessen
- `presentDrawable(drawable)` — der GPU sagen: sobald dieser CommandBuffer fertig ist, zeige diesen Drawable auf dem Bildschirm
- `commit()` — CommandBuffer an die GPU schicken (asynchron — kehrt sofort zurück)

---

## 12. triangle.metal

### Metal Shading Language (MSL)

MSL ist C++14-basiert mit GPU-spezifischen Erweiterungen. Alles was man in C++ kennt (Structs, Funktionen, Templates) funktioniert auch in MSL.

```metal
#include <metal_stdlib>
using namespace metal;
```

`metal_stdlib` ist die MSL Standardbibliothek — enthält mathematische Funktionen (`sin`, `cos`, `sqrt`), Vektor-Typen (`float2`, `float3`, `float4`), Texture-Sampling-Funktionen, etc.

### Attribute-Syntax `[[ ]]`

MSL nutzt `[[attribut]]` um GPU-spezifische Semantiken zu annotieren. Das ist das Herzstück das C++ von MSL unterscheidet.

```metal
struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};
```

`[[attribute(0)]]` bedeutet: dieses Feld kommt aus dem Vertex Buffer an Slot 0, an der Position die durch das Vertex-Layout definiert ist.

**Wichtig**: Wir nutzen in unserem Shader `vertex_id` und lesen direkt aus dem Buffer — wir nutzen `[[attribute]]` hier nur zur Dokumentation der Struct. Der eigentliche Zugriff passiert über `vertices[vertexID]`.

```metal
struct VertexOut {
    float4 position [[position]];
    float4 color;
};
```

`[[position]]` ist ein **built-in Attribut** — dieses Feld ist die clip-space Position die die GPU für Rasterisierung nutzt. **Jeder Vertex Shader muss genau ein `[[position]]` Feld zurückgeben.**

### Der Vertex Shader

```metal
vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             const device VertexIn* vertices [[buffer(0)]])
```

Das Schlüsselwort `vertex` markiert die Funktion als Vertex Shader. Die Parameter:

- `uint vertexID [[vertex_id]]` — die GPU übergibt automatisch die aktuelle Vertex-ID (0, 1, 2 für unsere drei Vertices)
- `const device VertexIn* vertices [[buffer(0)]]` — Pointer auf unseren Vertex Buffer (Slot 0)

`device` ist ein MSL **Adressraum-Qualifier**:
```
device    → GPU device memory (unser Vertex Buffer)
constant  → Read-only constant buffer (gut für Uniforms/Matrizen)
threadgroup → Geteilter Speicher innerhalb einer Thread-Gruppe
thread    → Lokaler Speicher des aktuellen Threads
```

```metal
VertexOut out;
out.position = float4(vertices[vertexID].position, 1.0);
out.color    = vertices[vertexID].color;
return out;
```

`float4(float3, 1.0)` — wir erweitern den `float3` Positions-Vektor auf `float4` indem wir `w=1.0` hinzufügen. Das `w`-Komponente ist für **homogene Koordinaten** — bei `w=1.0` bleibt der Punkt unverändert. Bei `w≠1.0` wird perspektivisch dividiert (wichtig für Milestone 2 — Perspective Camera).

### Der Fragment Shader

```metal
fragment float4 fragment_main(VertexOut in [[stage_in]])
{
    return in.color;
}
```

`[[stage_in]]` bedeutet: dieser Parameter kommt von der vorherigen Stage (dem Vertex Shader). Die GPU **interpoliert** automatisch die Vertex-Outputs über das Dreieck — daher die weichen Farbverläufe die wir sehen. Ein Fragment (Pixel) in der Mitte des Dreiecks bekommt die gewichtete Durchschnittsfarbe der drei Vertices.

Das ist **Barycentric Interpolation** — und sie passiert kostenlos durch die Rasterizer-Hardware.

---

## 13. Die Render-Pipeline

Die vollständige GPU-Pipeline von Vertex bis Pixel:

```
CPU schickt: drawPrimitives(Triangle, 0, 3)
                    │
                    ▼
         ┌─────────────────────┐
         │   Input Assembler   │  Liest Vertices aus dem Buffer
         └─────────┬───────────┘
                   │ 3 Vertices
                   ▼
         ┌─────────────────────┐
         │   Vertex Shader     │  vertex_main() × 3 (parallel)
         │   (programmierbar)  │  → clip-space Positionen + Farben
         └─────────┬───────────┘
                   │ Primitives (Dreiecke)
                   ▼
         ┌─────────────────────┐
         │   Rasterizer        │  Bestimmt welche Pixel das Dreieck bedeckt
         │   (fest-verdrahtet) │  Interpoliert Vertex-Outputs (Farbe!)
         └─────────┬───────────┘
                   │ Fragments (Pixel-Kandidaten)
                   ▼
         ┌─────────────────────┐
         │   Fragment Shader   │  fragment_main() × N Pixel (massiv parallel)
         │   (programmierbar)  │  → finale Farbe pro Pixel
         └─────────┬───────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │   Depth Test        │  Verwirft verdeckte Fragments
         │   (fest-verdrahtet) │  (unser Dreieck hat keinen Konkurrenten)
         └─────────┬───────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │   Output Merger     │  Schreibt Farbe in den Framebuffer
         └─────────────────────┘
                   │
                   ▼
              Bildschirm
```

---

## 14. Koordinatensysteme und NDC

### Normalized Device Coordinates (NDC)

Unsere Triangle-Vertices sind in NDC:
```
( 0.0,  0.5)  ← oben mitte
(-0.5, -0.5)  ← unten links
( 0.5, -0.5)  ← unten rechts
```

NDC ist ein normalisiertes Koordinatensystem:
- X: -1.0 (links) bis +1.0 (rechts)
- Y: -1.0 (unten) bis +1.0 (oben) — **Achtung: bei Metal Y nach oben!**
- Z: 0.0 (nah) bis +1.0 (fern) — **Metal nutzt [0,1], OpenGL nutzt [-1,1]!**

Nach dem Vertex Shader transformiert der Rasterizer NDC in **Screen Space** (Pixel-Koordinaten). Das passiert automatisch — wir müssen nur die korrekten NDC-Koordinaten liefern.

### Warum `float4` für Positionen?

```metal
out.position = float4(vertices[vertexID].position, 1.0);
//                    ┌──────────────────────────┐  ──
//                              xyz                  w
```

Homogene Koordinaten (4D) erlauben **Matrixmultiplikation für Perspektive**:
- Nach dem Vertex Shader macht die GPU **perspective division**: `(x/w, y/w, z/w)`
- Bei `w=1.0`: keine Veränderung (orthographisch)
- Bei `w=z_camera`: perspektivische Verkleinerung weiter entfernter Objekte

Für Milestone 1 (kein Camera-Transform) setzen wir `w=1.0`. In Milestone 2 wird eine Projektionsmatrix `w` auf den Camera-Space-Z-Wert setzen.

---

## 15. Memory Management in metal-cpp

metal-cpp folgt den **Cocoa Memory Management Rules** manuell (da C++ kein ARC hat):

| Regel | Bedeutung |
|---|---|
| `new*` Methoden | Geben Objekt mit retain count 1 zurück — du bist Owner |
| `->retain()` | Erhöht retain count — du willst Miteigentümer sein |
| `->release()` | Verringert retain count — wenn 0, wird Objekt freigegeben |
| `->autorelease()` | Gibt Ownership an den Autorelease Pool — wird später freigegeben |

**Faustregel**: Jedes `new*`, `copy*`, `create*` muss irgendwann mit `release()` bezahlt werden.

```cpp
// Im Konstruktor:
m_device = device->retain();          // +1 (wir sind Miteigentümer)
m_commandQueue = m_device->newCommandQueue();  // +1 (wir sind Owner)

// Im Destruktor:
m_commandQueue->release();  // -1 → 0 → freigegeben
m_device->release();        // -1 (Haupteigentümer gibt noch frei)
```

**Häufige Fehler:**
- `release()` vergessen → Memory Leak
- Doppeltes `release()` → Crash (Use-after-free)
- `retain()` vergessen → Dangling Pointer (Objekt wird von anderem Owner freigegeben)

---

## 16. clangd und .clangd

### Was ist clangd?

`clangd` ist ein **Language Server** — ein Prozess der im Hintergrund läuft und dem Editor (LazyVim) Informationen über den Code liefert:
- Autocomplete
- Go-to-Definition
- Fehleranzeige (Diagnostics)
- Rename-Refactoring

Es basiert auf LLVM/Clang — dem gleichen Compiler der auch den Code baut.

### compile_commands.json

```json
{
  "directory": "/Users/.../metal4-3d-engine",
  "command": "/usr/bin/c++ -std=c++20 -fobjc-arc -isysroot /path/to/SDK ... -c src/Renderer.mm",
  "file": "src/Renderer.mm"
}
```

Diese Datei listet für jede Source-Datei den exakten Compile-Befehl. `clangd` führt intern die gleiche Analyse durch wie der Compiler — deshalb muss es die gleichen Flags kennen. Ohne `-isysroot` findet `clangd` die Apple Framework-Header nicht.

### .clangd Config

```yaml
If: { PathMatch: ".*\\.mm$" }
CompileFlags:
  Add:
    - -x
    - objective-c++
```

Da `.mm`-Dateien in `compile_commands.json` manchmal ohne explizites `-x objective-c++` erscheinen, erzwingen wir es via `.clangd`. So weiss `clangd` dass `@interface`, `@implementation` etc. valide Syntax sind.

---

## Zusammenfassung: Was Milestone 1 aufgebaut hat

```
┌─────────────────────────────────────────────────────────┐
│                    macOS App Layer                       │
│  main.mm → NSApplication → AppDelegate → NSWindow       │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                  MetalKit Bridge Layer                   │
│  MTKView (Drawable Pool, Render Loop) → MetalViewDelegate│
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                   C++ Engine Layer                       │
│  Renderer (Device, CommandQueue, PipelineState, Buffer)  │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                     GPU / MSL Layer                      │
│  vertex_main() → Rasterizer → fragment_main() → Screen  │
└─────────────────────────────────────────────────────────┘
```

Jede Schicht ist klar getrennt. In Milestone 2 erweitern wir nur den **C++ Engine Layer** (Renderer) um Uniform Buffers und Matrizen — die anderen Schichten bleiben unverändert. Das ist gutes Engine-Design.

---

# Milestone 2 — Render Loop & Camera

> Dieses Kapitel erklärt **jeden einzelnen Aspekt** des Milestone-2-Codes.
> Ziel: Du sollst verstehen warum MVP-Matrizen funktionieren, wie ein Uniform
> Buffer aufgebaut ist, und wie Mouse-Input sauber durch die ObjC/C++-Grenze
> geleitet wird.

---

## Inhaltsverzeichnis (Milestone 2)

17. [Die große Übersicht — Was ist neu?](#17-die-grosse-ubersicht-milestone-2)
18. [Das Transformations-Triptychon: MVP](#18-das-transformations-triptychon-mvp)
19. [Homogene Koordinaten und Perspective Division](#19-homogene-koordinaten)
20. [simd — Apples Vektor-Mathematik](#20-simd)
21. [Math.hpp — Zeile für Zeile](#21-mathhpp)
22. [Uniforms.hpp — Der Daten-Vertrag](#22-uniformshpp)
23. [Camera.hpp — Die Orbit-Kamera](#23-camerahpp)
24. [triangle.metal — MVP im Shader](#24-trianglemetal-milestone-2)
25. [Renderer — Uniform Buffer & Depth Stencil State](#25-renderer-milestone-2)
26. [InputMTKView — Mouse-Events durch die ObjC/C++-Grenze](#26-inputmtkview)
27. [Der aktualisierte Render-Loop](#27-der-aktualisierte-render-loop)
28. [Zusammenfassung: Was Milestone 2 aufgebaut hat](#28-zusammenfassung-milestone-2)

---

## 17. Die große Übersicht — Milestone 2

Milestone 1 zeichnete ein Dreieck direkt in NDC — keine Transformation, kein 3D-Raum, keine Kamera. Milestone 2 ergänzt die **drei fehlenden Schichten**:

```
Milestone 1:  Vertex (NDC) ──────────────────────────────► Bildschirm

Milestone 2:  Vertex (Model Space)
                    │
                    ▼  × Model Matrix  (Renderer, jeden Frame)
              World Space
                    │
                    ▼  × View Matrix   (Camera.hpp → Renderer)
              Camera Space
                    │
                    ▼  × Projection Matrix  (Math::perspectiveFov)
              Clip Space  ──────────────────────────────► Bildschirm
```

**Was sich verändert hat:**

| Datei | Milestone 1 | Milestone 2 |
|---|---|---|
| `triangle.metal` | Vertex direkt als NDC ausgeben | MVP-Transform via `Uniforms` |
| `Renderer` | Nur Vertex Buffer | + Uniform Buffer, Depth Stencil State, Camera, Zeit |
| `MetalViewDelegate` | Nur draw/resize | + mouseDragged, rightMouseDragged, scrollWheel |
| Neue Dateien | — | `Math.hpp`, `Uniforms.hpp`, `Camera.hpp`, `InputMTKView` |

---

## 18. Das Transformations-Triptychon: MVP

Jeder Vertex durchläuft drei Koordinatensystem-Transformationen bevor er auf dem Bildschirm landet. Das ist keine Konvention — es ist die einzig logische Struktur wenn man **mehrere Objekte** in einer **Welt** mit einer **beweglichen Kamera** haben will.

```
Object Space  →[Model]→  World Space  →[View]→  Camera Space  →[Projection]→  Clip Space
```

### Model Matrix — Wo steht das Objekt?

Die **Model Matrix** transformiert Vertices aus dem lokalen Koordinatensystem des Objekts (Object Space) in die gemeinsame Welt (World Space).

Ein Vertex bei `(0, 0.5, 0)` in Object Space ist der Spitzpunkt unseres Dreiecks. Wenn das Objekt 2 Einheiten nach rechts bewegt und um 45° gedreht wird, wandert dieser Punkt in World Space zu einer anderen Position.

```cpp
// Unser Renderer dreht das Dreieck langsam:
simd::float4x4 model = math::rotation(m_time * 0.8f, {0, 1, 0});
```

Die Model Matrix ist das Produkt aus Translation × Rotation × Scale. In unserem Fall: nur Rotation (das Dreieck bleibt beim Ursprung).

### View Matrix — Wohin schaut die Kamera?

Die **View Matrix** transformiert World Space in Camera Space — das Koordinatensystem bei dem die Kamera im Ursprung sitzt und entlang der -Z-Achse schaut.

**Wichtige Einsicht**: Die View Matrix bewegt nicht die Kamera. Sie bewegt die gesamte Welt in die entgegengesetzte Richtung. Wenn die Kamera 3 Einheiten zurückgeht, ist das identisch dazu, die gesamte Welt 3 Einheiten nach vorne zu schieben.

```cpp
simd::float4x4 view = math::lookAt(
    m_camera.eye(),      // Kamera-Position in World Space
    m_camera.target,     // Wohin sie schaut
    {0, 1, 0}            // "Oben" = positive Y-Achse
);
```

### Projection Matrix — Perspektive

Die **Projection Matrix** erzeugt Perspektive: weiter entfernte Objekte erscheinen kleiner. Sie transformiert Camera Space in Clip Space.

```cpp
simd::float4x4 proj = math::perspectiveFov(
    60.0f * (M_PI / 180.0f),  // 60° vertikales Sichtfeld
    viewportWidth / viewportHeight,
    0.01f,                     // near plane
    1000.0f                    // far plane
);
```

`near` und `far` definieren das **View Frustum** — den pyramidenförmigen Bereich den die Kamera sieht. Alles ausserhalb wird geClipt (verworfen). `near` muss > 0 sein — eine Kameraebene bei z=0 würde eine Division durch Null verursachen.

### Warum Column-major?

`simd::float4x4` (und MSL `float4x4`) sind **column-major**: die Spalten werden hintereinander im Speicher abgelegt.

```
Matrix:          Speicher (column-major):
┌ a b c d ┐      [a, e, i, m,   ← Spalte 0
│ e f g h │       b, f, j, n,   ← Spalte 1
│ i j k l │       c, g, k, o,   ← Spalte 2
└ m n o p ┘       d, h, l, p]   ← Spalte 3
```

Das bedeutet: Matrix-Vektor-Multiplikation ist `M * v` (Matrix links, Vektor rechts). Die Reihenfolge der MVP-Verkettung ist deshalb:

```metal
clipPos = projectionMatrix * viewMatrix * modelMatrix * float4(position, 1.0);
```

Wir teilen das im Shader auf drei Schritte auf für Klarheit — das Ergebnis ist identisch.

---

## 19. Homogene Koordinaten

Warum ist eine 3D-Position ein `float4` und nicht ein `float3`?

Das vierte Element `w` ermöglicht **perspektivische Division** — der Trick der Perspektive erzeugt:

```
Nach dem Vertex Shader: GPU führt durch:  x/w, y/w, z/w
```

Bei `w = 1.0` (Milestone 1): keine Veränderung — orthographisches Bild.

Bei `w = z_camera` (Milestone 2, Projection Matrix): Vertices weiter hinten haben ein grösseres `w`, ihr `x/w` und `y/w` werden kleiner — sie erscheinen kleiner auf dem Bildschirm. Das ist Perspektive.

```
Kamera-Space Z=1 (nah):  w=1  → x/w = x    (gross)
Kamera-Space Z=5 (fern): w=5  → x/w = x/5  (klein)
```

Die Projektionsmatrix setzt `w = -z_camera` (oder `z_camera` je nach Konvention). Die GPU macht den Rest automatisch — das nennt sich **Perspective Division** und passiert in Hardware zwischen Vertex Shader und Rasterizer.

---

## 20. simd

`simd` ist Apples C++ Header-Bibliothek für SIMD-Vektoren und -Matrizen. Sie ist nicht `std::`, sie ist nicht Eigen, sie ist nicht GLM — sie ist direkt in den Apple Clang Compiler integriert.

### Typen

```cpp
simd::float2   // 2D-Vektor (x, y)
simd::float3   // 3D-Vektor (x, y, z)
simd::float4   // 4D-Vektor (x, y, z, w)
simd::float4x4 // 4×4 Matrix (column-major)
```

### Operatoren

```cpp
simd::float3 a = {1, 0, 0};
simd::float3 b = {0, 1, 0};

simd::float3 c = a + b;              // Komponentenweise Addition
float d = simd::dot(a, b);           // Skalarprodukt
simd::float3 e = simd::cross(a, b);  // Kreuzprodukt
simd::float3 f = simd::normalize(a); // Normalisieren (Länge = 1)
```

### Matrix × Vektor

```cpp
simd::float4x4 M = math::rotation(0.5f, {0, 1, 0});
simd::float4   v = {1, 0, 0, 1};
simd::float4   result = M * v;  // Matrix × Vektor (C++ Operator-Overloading)
```

### Warum nicht GLM?

GLM ist gut, aber `simd` ist:
- **Nativ**: Kein externes Vendor-Verzeichnis nötig
- **Identisch zu MSL**: `simd::float4x4` und MSL `float4x4` haben dasselbe Memory-Layout — wir können den C++-Struct direkt in den GPU-Buffer `memcpy`-en
- **Optimiert**: Compiliert auf Apple Silicon zu NEON SIMD-Instruktionen

---

## 21. Math.hpp

`Math.hpp` ist eine reine C++ Header-Datei — kein Objective-C, kein `.mm`. Alle Funktionen sind `inline` im `math` Namespace.

### `identity()`

```cpp
inline simd::float4x4 identity() {
    return matrix_identity_float4x4;
}
```

`matrix_identity_float4x4` ist ein macOS-System-Konstante aus `<simd/simd.h>` — die 4×4 Einheitsmatrix. Eine Multiplikation mit der Einheitsmatrix verändert nichts — das ist der neutrale Ausgangspunkt.

### `rotation(float angle, simd::float3 axis)`

```cpp
float c = std::cos(angleRadians);
float s = std::sin(angleRadians);
float t = 1.0f - c;
float x = axis.x, y = axis.y, z = axis.z;

return simd::float4x4{
    simd::float4{ t*x*x + c,   t*x*y + s*z, t*x*z - s*y, 0 },
    simd::float4{ t*x*y - s*z, t*y*y + c,   t*y*z + s*x, 0 },
    ...
};
```

Das ist die **Rodrigues Rotation Formula** — die allgemeine Rotationsmatrix um eine beliebige Achse. Das Besondere: `simd::float4x4{col0, col1, col2, col3}` initialisiert die Matrix **spaltenweise** (column-major). Jeder `simd::float4` Argument ist eine Spalte, nicht eine Zeile.

Warum `axis = simd::normalize(axis)` am Anfang? Die Formel funktioniert nur für Einheitsvektoren (Länge = 1). Wenn jemand `{0, 2, 0}` übergibt, würde die Rotation falsch sein.

### `lookAt(eye, center, up)`

```cpp
simd::float3 f = simd::normalize(center - eye);   // forward
simd::float3 r = simd::normalize(simd::cross(f, up)); // right
simd::float3 u = simd::cross(r, f);               // true up
```

`lookAt` konstruiert die View Matrix aus drei Vektoren:

1. **forward** (`f`): Richtung vom Auge zum Ziel
2. **right** (`r`): Senkrecht zu forward und world-up (via Kreuzprodukt)
3. **true up** (`u`): Senkrecht zu forward und right (via zweitem Kreuzprodukt)

Diese drei Vektoren bilden ein Orthonormal-Basis (alle senkrecht zueinander, alle Länge 1). Das ist das Kamera-Koordinatensystem.

```cpp
m.columns[0] = simd::float4{  r.x,  u.x, -f.x, 0 };
m.columns[1] = simd::float4{  r.y,  u.y, -f.y, 0 };
m.columns[2] = simd::float4{  r.z,  u.z, -f.z, 0 };
m.columns[3] = simd::float4{ -dot(r,eye), -dot(u,eye), dot(f,eye), 1 };
```

Warum `-f`? Weil Kamera-Space die Kamera entlang der **negativen** Z-Achse schaut (OpenGL/Metal Konvention). Forward zeigt nach vorne (positiv), aber in Camera Space ist "vorne" -Z.

Die letzte Spalte (Translation) verwendet Skalarprodukte um die Kameraposition zu "invertieren" — wir verschieben die Welt in die entgegengesetzte Richtung der Kamera.

### `perspectiveFov(fovY, aspect, nearZ, farZ)`

```cpp
float ys = 1.0f / std::tan(fovY * 0.5f);
float xs = ys / aspect;
float zs = farZ / (nearZ - farZ);

m.columns[0] = { xs, 0,  0,  0 };
m.columns[1] = {  0, ys, 0,  0 };
m.columns[2] = {  0, 0,  zs, -1 };
m.columns[3] = {  0, 0,  nearZ * zs, 0 };
```

`ys` = `1/tan(fov/2)` — der "Zoom-Faktor" für die Y-Achse. Bei 60° FoV: `tan(30°) ≈ 0.577`, also `ys ≈ 1.73`. Weiter weg erscheinende Punkte werden stärker gestaucht.

`xs = ys / aspect` — die X-Achse wird durch den Aspect Ratio geteilt damit das Bild nicht verzerrt aussieht (Kreise bleiben Kreise).

`zs` und `nearZ * zs` — diese beiden Terme mappen den Z-Bereich `[nearZ, farZ]` auf `[1, 0]` (**reversed depth**). Reversed-Z ist **präziser** für grosse Tiefenbereiche weil Floating-Point Zahlen näher am Nullpunkt dichter liegen. Metal empfiehlt reversed-Z.

`columns[2].w = -1` — das ist der Trick der `w` auf `-z_camera` setzt. Die GPU teilt danach durch `w`, was die Perspektive erzeugt.

---

## 22. Uniforms.hpp

```cpp
struct Uniforms {
    simd::float4x4 modelMatrix;
    simd::float4x4 viewMatrix;
    simd::float4x4 projectionMatrix;
};
```

Diese Datei ist ein **Daten-Vertrag** zwischen C++ und MSL. Dieselbe Struct-Definition existiert in `Uniforms.hpp` (C++) und in `triangle.metal` (MSL). Beide müssen **byte-for-byte identisch** sein — gleiche Reihenfolge, gleiche Typen, gleiche Grösse.

`simd::float4x4` (C++) und `float4x4` (MSL) sind beide:
- 4 Spalten × 4 Zeilen × 4 Bytes = **64 Bytes**
- Column-major Layout
- 16-Byte-aligned

Die gesamte `Uniforms`-Struct ist **192 Bytes** (3 × 64). Kein Padding nötig — `float4x4` ist natürlicherweise 16-byte-aligned.

---

## 23. Camera.hpp

Die `Camera`-Klasse modelliert eine **Orbit-Kamera**: eine Kamera die um einen festen Punkt (`target`) kreist. Die Position wird durch drei Kugelkoordinaten beschrieben:

```
         up (Y)
          │
          │   / eye
          │  /   ← radius
          │ /  ↗ pitch (elevation)
          │/___________
    target        ─────── yaw (azimuth, um Y rotiert)
```

### Sphärische Koordinaten → kartesische Koordinaten

```cpp
simd::float3 eye() const {
    float cosP = std::cos(pitch);
    return target + simd::float3{
        radius * cosP * std::sin(yaw),   // x
        radius * std::sin(pitch),        // y
        radius * cosP * std::cos(yaw)    // z
    };
}
```

`yaw` dreht die Kamera horizontal (um die Y-Achse). `pitch` hebt sie an oder senkt sie ab. `radius` bestimmt die Entfernung zum Ziel.

Das ist Standard-Kugelkoordinaten-Umrechnung: `x = r·cos(φ)·sin(θ)`, `y = r·sin(φ)`, `z = r·cos(φ)·cos(θ)`.

### Pitch-Clamp

```cpp
constexpr float kMaxPitch = 1.55f; // ~89°
pitch = std::clamp(pitch, -kMaxPitch, kMaxPitch);
```

Ohne Clamp würde die Kamera beim Überschreiten von 90° "flippen" — die Up-Achse würde sich umkehren und die View Matrix würde seltsam werden. Wir halten uns kurz vor den Polen.

### Pan

```cpp
void pan(float dx, float dy) {
    simd::float3 fwd   = simd::normalize(target - eye());
    simd::float3 right = simd::normalize(simd::cross(fwd, {0,1,0}));
    simd::float3 up    = simd::cross(right, fwd);

    target -= right * (dx * panSensitivity * radius);
    target += up    * (dy * panSensitivity * radius);
}
```

Pan bewegt das **Ziel** (nicht die Kamera direkt). Die Kamera folgt weil sie immer auf `target` schaut. Die Bewegungsrichtungen sind `right` und `up` aus dem Kamera-Koordinatensystem — so fühlt sich Pan intuitiv an unabhängig davon wohin die Kamera schaut.

`* radius` skaliert die Pan-Geschwindigkeit mit der Entfernung — wenn man weit weg ist, ist es sinnvoll schneller zu pannen.

### Scroll / Dolly

```cpp
void scroll(float delta) {
    radius -= delta * scrollSensitivity;
    radius = std::max(radius, 0.1f);
}
```

Scroll verändert nur den Radius. `std::max(radius, 0.1f)` verhindert dass die Kamera durch das Ziel durchschiesst oder hinter es gerät.

---

## 24. triangle.metal — Milestone 2

### Der neue Uniforms-Struct im Shader

```metal
struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};
```

Dieser Block muss **identisch** zu `Uniforms.hpp` sein. Der Compiler prüft das nicht — wenn die Reihenfolge falsch ist, werden die falschen Matrizen angewendet (kein Crash, aber falsches Bild).

### Der neue Vertex Shader

```metal
vertex VertexOut vertex_main(uint                   vertexID  [[vertex_id]],
                             const device VertexIn* vertices  [[buffer(0)]],
                             constant     Uniforms& uniforms  [[buffer(1)]]) {
```

Der dritte Parameter `constant Uniforms& uniforms [[buffer(1)]]` ist der Uniform Buffer:

- `constant` — Adressraum: Read-only, für alle Threads gleich. Die GPU kann diesen Speicher in schnellen On-Chip-Caches halten weil er sich während des Draw Calls nicht ändert.
- `Uniforms&` — Referenz (nicht Pointer) — bequemer zu lesen, gleiche Performance
- `[[buffer(1)]]` — Binding-Slot 1 (Vertex Buffer ist auf Slot 0)

```metal
float4 worldPos = uniforms.modelMatrix      * float4(vertices[vertexID].position, 1.0);
float4 viewPos  = uniforms.viewMatrix       * worldPos;
float4 clipPos  = uniforms.projectionMatrix * viewPos;
```

Drei aufeinanderfolgende Matrix-Multiplikationen. Warum aufteilen und nicht `proj * view * model * v`? Bessere Lesbarkeit. Der Shader-Compiler optimiert das zu denselben Instruktionen.

---

## 25. Renderer — Milestone 2

### buildDepthStencilState

```cpp
void Renderer::buildDepthStencilState() {
    auto* desc = MTL::DepthStencilDescriptor::alloc()->init();
    desc->setDepthCompareFunction(MTL::CompareFunctionLess);
    desc->setDepthWriteEnabled(true);
    m_depthStencilState = m_device->newDepthStencilState(desc);
    desc->release();
}
```

In Milestone 1 haben wir eine Depth Texture erstellt aber den **Depth Test** nie aktiviert — wir hatten vergessen den `DepthStencilState` zu setzen. In Milestone 2 holen wir das nach.

`CompareFunctionLess`: Ein Fragment besteht den Depth Test wenn sein Z-Wert **kleiner** ist als der gespeicherte Wert. Da wir reversed-Z nutzen (near=1, far=0), bedeutet "kleiner" = "näher an der Kamera".

**Wichtig**: `DepthStencilState` muss beim Encoding explizit gesetzt werden:
```cpp
enc->setDepthStencilState(m_depthStencilState);
```

Ohne diesen Aufruf — selbst wenn ein Depth Attachment vorhanden ist — führt Metal keinen Depth Test durch.

### buildUniformBuffer

```cpp
void Renderer::buildUniformBuffer() {
    m_uniformBuffer = m_device->newBuffer(sizeof(Uniforms),
                                          MTL::ResourceStorageModeShared);
}
```

Ein einzelner `Shared`-Buffer der jeden Frame überschrieben wird. Mit `Shared` auf Apple Silicon ist das direkter RAM-Zugriff — kein Staging Buffer, kein Memcpy über PCIe nötig.

**In der Praxis** (mehr als 2 Frames in Flight): Man würde `kMaxFramesInFlight` (typisch 3) Uniform Buffer allocieren und pro Frame einen anderen nutzen um GPU/CPU-Races zu vermeiden. Für Milestone 2 mit einem einzigen Draw Call pro Frame ist ein einzelner Buffer ausreichend.

### Uniform Buffer befüllen (jeden Frame)

```cpp
Uniforms uniforms;
uniforms.modelMatrix      = model;
uniforms.viewMatrix       = view;
uniforms.projectionMatrix = proj;
std::memcpy(m_uniformBuffer->contents(), &uniforms, sizeof(Uniforms));
```

`m_uniformBuffer->contents()` gibt einen `void*` auf den CPU-zugänglichen Speicher des Buffers. `std::memcpy` kopiert die 192 Bytes direkt — kein Overhead.

### Buffer binden (im Encoder)

```cpp
enc->setVertexBuffer(m_vertexBuffer,  0, 0);  // slot 0 = Vertices
enc->setVertexBuffer(m_uniformBuffer, 0, 1);  // slot 1 = Uniforms
```

`setVertexBuffer(buffer, offset, index)`:
- `buffer` — der MTL::Buffer
- `offset` — Byte-Offset in den Buffer (0 = Anfang)
- `index` — der Buffer-Slot im Shader (`[[buffer(0)]]`, `[[buffer(1)]]` etc.)

---

## 26. InputMTKView

### Das Problem

`MetalViewDelegate` ist ein `NSObject` — kein `NSResponder`. Mouse-Events werden in macOS über die **Responder Chain** weitergeleitet: `NSWindow` → `NSView` → `NSView`-Subklassen. Ein `NSObject` das als `MTKViewDelegate` registriert ist, empfängt diese Events **nicht**.

### Die Lösung

`InputMTKView` ist eine dünne Subklasse von `MTKView` die:

1. `acceptsFirstResponder` überschreibt → View meldet sich für Events an
2. Die drei Mouse-Methoden überschreibt und an den Delegate weiterleitet

```objc
@implementation InputMTKView

- (BOOL)acceptsFirstResponder { return YES; }

- (void)mouseDragged:(NSEvent*)event {
    [(MetalViewDelegate*)self.delegate mouseDragged:event];
}
```

`AppDelegate` macht sie zum First Responder:
```objc
[_window makeFirstResponder:_mtkView];
```

### NSEvent deltaX / deltaY

```objc
- (void)mouseDragged:(NSEvent*)event {
    _renderer->onMouseDrag((float)event.deltaX, (float)event.deltaY, false);
}
```

`deltaX`/`deltaY` sind die **Differenz** seit dem letzten Event in Punkten — nicht absolute Koordinaten. Das ist genau was wir für Orbit/Pan brauchen.

### Trackpad vs. Mausrad

```objc
- (void)scrollWheel:(NSEvent*)event {
    float delta = (float)(event.hasPreciseScrollingDeltas
                          ? event.scrollingDeltaY
                          : event.deltaY * 3.0f);
    _renderer->onScroll(delta);
}
```

`hasPreciseScrollingDeltas` ist `YES` für Trackpads — sie liefern feiner aufgelöste `scrollingDeltaY` Werte. Mäuse liefern ganzzahlige `deltaY` Werte, die wir mit `3.0` skalieren damit es ähnlich flüssig anfühlt.

---

## 27. Der aktualisierte Render-Loop

Jeder Frame in Milestone 2:

```
draw() aufgerufen von MTKView (60fps)
    │
    ├─ m_time += 1/60  (einfacher Zeitfortschritt)
    │
    ├─ Model Matrix = rotation(m_time * 0.8, Y)
    ├─ View Matrix  = lookAt(camera.eye(), camera.target, up)
    ├─ Proj Matrix  = perspectiveFov(60°, aspect, 0.01, 1000)
    │
    ├─ memcpy(uniformBuffer, Uniforms{M,V,P}, 192 Bytes)
    │
    ├─ CommandBuffer holen
    ├─ RenderPassDescriptor (clear color + clear depth)
    ├─ RenderCommandEncoder öffnen
    │    ├─ setRenderPipelineState
    │    ├─ setDepthStencilState      ← NEU in Milestone 2
    │    ├─ setViewport
    │    ├─ setVertexBuffer(vertices, slot=0)
    │    ├─ setVertexBuffer(uniforms, slot=1)  ← NEU
    │    └─ drawPrimitives(Triangle, 0, 3)
    ├─ endEncoding
    ├─ presentDrawable
    └─ commit
```

Mouse-Events laufen **ausserhalb** des Render-Loops — sie kommen vom NSEvent-System und aktualisieren nur den `Camera`-State. Beim nächsten Frame-Draw liest der Renderer den aktuellen Kamera-State und berechnet die View Matrix neu.

---

## 28. Zusammenfassung: Was Milestone 2 aufgebaut hat

```
┌─────────────────────────────────────────────────────────┐
│                    macOS App Layer                       │
│  main.mm → NSApplication → AppDelegate → NSWindow       │
│                            ↓ makeFirstResponder          │
│                      InputMTKView  ← Mouse/Scroll Events │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                  MetalKit Bridge Layer                   │
│  InputMTKView → MetalViewDelegate                        │
│                 (draw + resize + mouse-forward)          │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                   C++ Engine Layer                       │
│  Renderer                                                │
│  ├─ Camera (orbit: yaw, pitch, radius, target)           │
│  ├─ Math (lookAt, perspectiveFov, rotation)              │
│  ├─ Uniforms (modelMatrix, viewMatrix, projMatrix)        │
│  ├─ MTL::Buffer (vertices + uniforms)                    │
│  ├─ MTL::DepthStencilState                               │
│  └─ MTL::RenderPipelineState                             │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                     GPU / MSL Layer                      │
│  vertex_main(vertices[[0]], uniforms[[1]])                │
│    → Model * View * Proj * position                      │
│    → Rasterizer → fragment_main() → Screen               │
└─────────────────────────────────────────────────────────┘
```

In Milestone 3 erweitern wir den **C++ Engine Layer** um Mesh Loading (cgltf) und einen Scene Graph — und setzen zum ersten Mal **Metal 4 APIs** ein (`MTL4ArgumentTable`).

---

# Milestone 3 — Mesh Loading & Scene Graph

## Was wird gebaut?

Echte 3D-Objekte aus `.obj` oder `.gltf`-Dateien laden und in einer **Scene Graph**-Hierarchie verwalten.

## glTF — Das moderne 3D-Format

glTF 2.0 ist der "JPEG der 3D-Welt" — ein offenes Format das unterstützt:
- Meshes (Vertices, Normals, UVs, Tangents)
- Materialien (PBR-Parameter)
- Szenen-Hierarchien (Parent-Child Transforms)
- Animationen
- Skelett-Animation (Skinning)

Wir nutzen **`cgltf`** — eine header-only C-Bibliothek:

```cpp
#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

cgltf_data* data = nullptr;
cgltf_parse_file(&options, "model.gltf", &data);
cgltf_load_buffers(&options, data, "model.gltf");
// data->meshes[0].primitives[0].attributes → Vertices
```

## Index Buffer

Bis jetzt: 3 Vertices, 1 Dreieck. Ein echter Mesh hat tausende Vertices — viele davon **geteilt** zwischen Dreiecken. Index Buffer vermeiden Duplikate:

```
Ohne Index Buffer (6 Vertices für 2 Dreiecke):
v0 v1 v2 v0 v2 v3   ← v0 und v2 doppelt

Mit Index Buffer (4 Vertices + 6 Indices):
Vertices: v0 v1 v2 v3
Indices:  0  1  2  0  2  3   ← Referenzieren Vertices by Index
```

Speicherersparnis bei einem typischen Mesh: ~40-60%.

```cpp
m_indexBuffer = m_device->newBuffer(indices, indexCount * sizeof(uint32_t), ...);
enc->drawIndexedPrimitives(MTL::PrimitiveTypeTriangle, indexCount,
                           MTL::IndexTypeUInt32, m_indexBuffer, 0);
```

## Scene Graph

Ein **Scene Graph** ist ein Baum von Nodes. Jeder Node hat:
- Eine lokale Transform (Position, Rotation, Scale)
- Optional eine Mesh-Referenz
- Beliebig viele Child-Nodes

```
Root
├── DirectionalLight
├── Suzanne (Monkey Mesh)
│   ├── LeftEye
│   └── RightEye
└── Floor
```

Die **World Matrix** eines Nodes = eigene Local Matrix × Parent World Matrix. So bewegen sich Kinder automatisch mit dem Elternteil.

## MTL4ArgumentTable — Erster Einsatz

Mit vielen Meshes und Materialien lohnt sich jetzt der Metal 4 Weg:

```cpp
// Alle Buffer in einer Table bündeln
MTL4ArgumentTable* table = device->newArgumentTable(descriptor);
table->setBuffer(vertexBuffer,  0, 0);
table->setBuffer(uniformBuffer, 0, 1);
table->setTexture(albedoTex,       0);

// Ein einziger Bind-Call statt vieler einzelner
encoder->setVertexArgumentTable(table, 0);
```

**Bindless Rendering**: Der Shader kann über einen Index in ein Array von Texturen/Buffern zugreifen — ohne dass die CPU für jedes Objekt einen separaten Bind-Call macht. Fundamental für performantes Rendern vieler Objekte.

---

# Milestone 4 — PBR Deferred Lighting

## Was wird gebaut?

**Physically Based Rendering** — Materialien die sich physikalisch korrekt verhalten, und ein **Deferred Renderer** der viele Lichtquellen effizient handhabt.

## Physically Based Rendering (PBR)

PBR-Materialien werden durch wenige intuitive Parameter beschrieben:

| Parameter | Bedeutung | Bereich |
|---|---|---|
| **Albedo** | Grundfarbe (ohne Beleuchtung) | 0.0 – 1.0 (RGB) |
| **Metallic** | Wie metallisch ist die Oberfläche? | 0 = Plastik, 1 = Metall |
| **Roughness** | Wie rau ist die Oberfläche? | 0 = Spiegel, 1 = Matt |
| **Normal Map** | Detaillierte Oberflächenstruktur | Tangent-Space Vektoren |
| **AO** | Ambient Occlusion — Selbstverschattung | 0.0 – 1.0 |

Das zugrundeliegende Beleuchtungsmodell ist die **Cook-Torrance BRDF** (Bidirectional Reflectance Distribution Function):

```
L_out = (albedo/π + D*F*G / (4*NdotL*NdotV)) * L_in * NdotL
         ────────────────────────────────────────────────────
         Diffuse                Specular
```

- `D` — Normal Distribution Function (GGX): Wie viele Mikrofacetten zeigen in Richtung Halfway-Vektor?
- `F` — Fresnel (Schlick): Mehr Reflexion bei flachem Winkel
- `G` — Geometry (Smith): Selbstverschattung der Mikrofacetten

## Deferred Rendering

### Das Problem mit Forward Rendering

Bei Forward Rendering (Milestone 1-3) berechnet man für jedes Fragment sofort die finale Farbe. Mit N Objekten und M Lichtern = O(N×M) Berechnungen. Mit 100 Objekten und 50 Lichtern = 5000 Shader-Aufrufe pro Pixel.

### Die Lösung: GBuffer

Deferred Rendering teilt das Rendering in zwei Passes:

**Pass 1 — Geometry Pass**: Zeichne alle Objekte, aber speichere statt der finalen Farbe die Material-Daten in Texturen (den **GBuffer**):

```
GBuffer Texturen:
┌─────────────────┐  ┌─────────────────┐
│   Albedo (RGBA) │  │  Normal (RGB)   │
└─────────────────┘  └─────────────────┘
┌─────────────────┐  ┌─────────────────┐
│  Depth (Float)  │  │ Metallic/Rough  │
└─────────────────┘  └─────────────────┘
```

**Pass 2 — Lighting Pass**: Zeichne ein Screen-Quad, sample den GBuffer, berechne Beleuchtung nur für sichtbare Pixel:

```metal
fragment float4 lighting_pass(
    texture2d<float> albedoTex   [[texture(0)]],
    texture2d<float> normalTex   [[texture(1)]],
    texture2d<float> depthTex    [[texture(2)]],
    // ... alle Lichter als Buffer
) {
    // Reconstruct world position from depth
    // Sample material data from GBuffer
    // Apply Cook-Torrance BRDF for each light
}
```

**Vorteil**: O(N + M) statt O(N×M). 100 Objekte + 50 Lichter = 150 Operationen statt 5000.

## MTL4CommandEncoder — Unified Encoder

Ab Milestone 4 wechseln wir auf den Metal 4 Unified Encoder:

```cpp
// Metal 1-3: Separate Encoder für jeden Pass
auto* geoEncoder   = cmdBuf->renderCommandEncoder(geoPassDesc);
// ... encode geometry ...
geoEncoder->endEncoding();

auto* lightEncoder = cmdBuf->renderCommandEncoder(lightPassDesc);
// ... encode lighting ...
lightEncoder->endEncoding();

// Metal 4: Ein Encoder für alles
auto* encoder = cmdBuf->renderCommandEncoder(desc);  // MTL4CommandEncoder
encoder->beginPass(geoPassDesc);
// ... geometry ...
encoder->endPass();
encoder->beginPass(lightPassDesc);
// ... lighting ...
encoder->endPass();
encoder->endEncoding();
```

**Vorteil**: Weniger CPU-Overhead, bessere GPU-Scheduling-Möglichkeiten.

---

# Milestone 5 — MetalFX Upscaling

## Was wird gebaut?

Statt in nativer Auflösung zu rendern, rendern wir in **50-70% der Auflösung** und lassen MetalFX die fehlenden Details rekonstruieren. Das ergibt ~2-4× mehr GPU-Budget für Graphik-Features.

## Temporal Upscaling

MetalFX Temporal Upscaling nutzt **mehrere aufeinanderfolgende Frames** um Details zu rekonstruieren:

```
Frame N-2:  640×360  ──┐
Frame N-1:  640×360  ──┤→ MetalFX → 1280×720  (mit Motion Vectors)
Frame N:    640×360  ──┘             ↑ temporal accumulation
```

**Motion Vectors**: Für jeden Pixel, in welche Richtung hat er sich seit dem letzten Frame bewegt? Der G-Buffer aus Milestone 4 liefert die Tiefeninformation um Motion Vectors zu berechnen.

```cpp
MTLFXTemporalScalerDescriptor* desc = [[MTLFXTemporalScalerDescriptor alloc] init];
desc.inputWidth    = renderWidth;   // 640
desc.inputHeight   = renderHeight;  // 360
desc.outputWidth   = displayWidth;  // 1280
desc.outputHeight  = displayHeight; // 720
desc.colorTextureFormat     = MTLPixelFormatRGBA16Float;
desc.motionTextureFormat    = MTLPixelFormatRG16Float;
desc.depthTextureFormat     = MTLPixelFormatDepth32Float;

id<MTLFXTemporalScaler> scaler = [desc newTemporalScalerWithDevice:device];
```

## Frame Interpolation (Metal 4 neu)

Noch einen Schritt weiter: MetalFX kann zwischen zwei gerenderten Frames einen **synthetischen Frame interpolieren**:

```
Gerendert:    Frame 0        Frame 2        Frame 4
Interpoliert:       Frame 1        Frame 3
Angezeigt:    F0   F1   F2   F3   F4   ...  → 120fps aus 60fps Render
```

**Nutzen**: Auf einem 120Hz Display flüssigeres Bild bei halber GPU-Last.

## Neural Upscaling (M5 Pro/Max)

Auf M5 Pro und M5 Max nutzt MetalFX die **Neural Accelerators** — spezialisierte ML-Hardware — für noch schärfere Rekonstruktion als traditionelles Temporal Upscaling.

---

# Milestone 6 — Ray Traced Shadows & AO

## Was wird gebaut?

**Kontaktschatten** und **Ambient Occlusion** via Ray Tracing — exaktere Beleuchtung als rasterisierungsbasierte Approximationen.

## Acceleration Structures

Ray Tracing braucht eine räumliche Datenstruktur um schnell zu bestimmen welche Geometrie ein Strahl trifft. Metal nutzt ein **BVH** (Bounding Volume Hierarchy):

```
TLAS (Top-Level Acceleration Structure)
├── BLAS (Bottom-Level) ← Suzanne Mesh
├── BLAS               ← Floor Mesh
└── BLAS               ← Wall Mesh
```

- **BLAS**: Enthält die tatsächliche Dreiecksgeometrie eines Meshes
- **TLAS**: Referenziert BLASes mit ihrer World-Transform

```cpp
// BLAS bauen (einmalig pro Mesh, teuer)
MTLAccelerationStructureTriangleGeometryDescriptor* geoDesc = ...;
geoDesc.vertexBuffer = m_vertexBuffer;
MTLPrimitiveAccelerationStructureDescriptor* blasDesc = ...;
blasDesc.geometryDescriptors = @[geoDesc];
id<MTLAccelerationStructure> blas = [device newAccelerationStructureWithDescriptor:blasDesc];

// TLAS bauen (jeden Frame wenn sich Objekte bewegen)
MTLInstanceAccelerationStructureDescriptor* tlasDesc = ...;
tlasDesc.instancedAccelerationStructures = @[blas, blas2, ...];
id<MTLAccelerationStructure> tlas = [device newAccelerationStructureWithDescriptor:tlasDesc];
```

Metal 4 bietet neue **Build-Flags** für Speed/Memory Trade-off:
```cpp
MTLAccelerationStructureBuildFlagPreferFastBuild   // Schneller Build, mehr RAM
MTLAccelerationStructureBuildFlagPreferFastTrace   // Langsamerer Build, schnelleres Tracing
```

## Inline Ray Tracing im Fragment Shader

```metal
// Im Fragment Shader (Lighting Pass):
ray r;
r.origin    = worldPosition + normal * 0.001; // Bias gegen Self-Intersection
r.direction = normalize(lightPosition - worldPosition);
r.min_distance = 0.001;
r.max_distance = length(lightPosition - worldPosition);

intersector<triangle_data> intersect;
intersect.assume_geometry_type(geometry_type::triangle);
intersection_result<triangle_data> result = intersect(r, tlas);

float shadow = (result.type == intersection_type::none) ? 1.0 : 0.0;
```

## Ray Tracing Denoiser (Metal 4 neu)

Ray Traced Shadows mit wenigen Samples (z.B. 1 Sample/Pixel) sind **verrauscht**. Metal 4's integrierter Denoiser nutzt temporale Information um das Rauschen zu reduzieren — ähnlich wie MetalFX, aber für Schattentexturen.

---

# Milestone 7 — Neural Rendering

## Was wird gebaut?

**Machine Learning direkt im Shader** — ein kleines neuronales Netz das Material-Eigenschaften synthetisiert oder als AI-Denoiser arbeitet.

## Tensoren in MSL (Metal 4 neu)

Metal 4 führt native Tensor-Typen in MSL ein:

```metal
// Ein Tensor ist ein N-dimensionales Array auf der GPU
tensor<float, shape<128, 64>> weights;  // 128×64 Gewichtsmatrix
tensor<float, shape<1, 64>>   input;    // Input-Vektor

// Matrix-Multiplikation direkt in MSL
tensor<float, shape<1, 128>> output = metal::multiply(input, weights);
```

## Neural Accelerators (M5 Pro/Max)

Die neuen **Neural Accelerators** auf M5 Pro und M5 Max sind spezialisierte ML-Recheneinheiten die Metal Performance Primitives (MPP) nutzen — 10-100× schneller als General-Purpose GPU-Shader für Matrix-Operationen.

```cpp
// Metal Performance Primitives für quantisierte Inferenz
MPSGraph* graph = [[MPSGraph alloc] init];
MPSGraphTensor* inputTensor  = [graph placeholderWithShape:@[@1, @64] ...];
MPSGraphTensor* weightTensor = [graph constantWithData:weightsData shape:@[@64, @128] ...];
MPSGraphTensor* output       = [graph matMulWithPrimaryTensor:inputTensor
                                             secondaryTensor:weightTensor name:nil];
```

## Anwendungsfall: Neural Material Synthesis

Statt gesampelter Texturen (Albedo, Normal, Roughness) kann ein kleines neuronales Netz Material-Eigenschaften aus einem kompakten latenten Code synthetisieren:

```
Latenter Code (8 Floats) → [Neural Network] → Albedo + Normal + Roughness + AO
```

**Vorteil**: Dramatisch reduzierter Textur-Speicher, unbegrenzte Detailstufe, prozedurale Variation.

---

# Roadmap: Wo Metal 4 Features eingesetzt werden

```
M1  ──── Basis (Metal 1-3 APIs, Architektur aufbauen)
M2  ──── simd Matrizen, Uniform Buffer, Kamera
M3  ──── MTL4ArgumentTable (Bindless), cgltf, Scene Graph
M4  ──── MTL4CommandEncoder (Unified), GBuffer, PBR BRDF
M5  ──── MetalFX Temporal Upscaling + Frame Interpolation
M6  ──── Acceleration Structures, Inline Ray Tracing, Denoiser
M7  ──── MSL Tensors, Neural Accelerators, Neural Material Synthesis
         ↑
         Hier sind alle Metal 4-Features aktiv
```

Jeder Milestone baut auf dem vorherigen auf. Kein Schritt kann übersprungen werden ohne das Fundament zu verlieren.
