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

### Invertierung von deltaX im Orbit

In `Renderer::onMouseDrag` wird `dx` negiert bevor er an `camera.orbit()` weitergegeben wird:

```cpp
void Renderer::onMouseDrag(float dx, float dy, bool rightButton) {
    if (rightButton) m_camera.pan(dx, dy);
    else             m_camera.orbit(-dx, dy);  // ← negiertes dx
}
```

**Warum?** `NSEvent.deltaX` ist positiv wenn die Maus nach **rechts** bewegt wird. In `Camera::orbit()` erhöht ein positives `dx` den `yaw`-Winkel — was die Kamera entgegen dem Uhrzeigersinn dreht (die Welt dreht sich nach rechts). Das fühlt sich invertiert an: man zieht nach rechts, der Cube dreht sich nach rechts statt dass die Kamera nach rechts "fliegt".

Mit `-dx`: Maus nach rechts → negativer yaw-Zuwachs → Kamera dreht im Uhrzeigersinn → intuitives "ich drehe den Cube mit der Maus"-Gefühl.

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

In Milestone 3 erweitern wir den **C++ Engine Layer** um Mesh Loading (cgltf), Index Buffer, Scene Graph und Phong-Lighting.

---

# Milestone 3 — Mesh Loading, Index Buffer & Scene Graph

> Dieses Kapitel erklärt **jeden einzelnen Aspekt** des Milestone-3-Codes.
> Wir laden zum ersten Mal ein echtes 3D-Objekt aus einer `.glb`-Datei,
> bauen einen Scene Graph mit World-Matrix-Hierarchie, und rendern mit
> Phong-Beleuchtung statt Vertex-Farben.

---

## Inhaltsverzeichnis (Milestone 3)

29. [Die große Übersicht — Was ist neu?](#29-die-grosse-ubersicht-milestone-3)
30. [glTF 2.0 — Das moderne 3D-Format](#30-gltf-20)
31. [cgltf — Der header-only Loader](#31-cgltf)
32. [Index Buffer — Vertices teilen statt duplizieren](#32-index-buffer)
33. [Das neue Vertex-Layout: Position + Normal](#33-das-neue-vertex-layout)
34. [Mesh.hpp / Mesh.mm — Zeile für Zeile](#34-meshhpp--meshmm)
35. [Node.hpp — Der Scene Graph](#35-nodehpp--der-scene-graph)
36. [Phong Lighting im Shader](#36-phong-lighting-im-shader)
37. [Die Normal Matrix — Warum sie notwendig ist](#37-die-normal-matrix)
38. [Renderer — buildScene und drawNode](#38-renderer--buildscene-und-drawnode)
39. [CMakeLists.txt — Neue Einträge](#39-cmakeliststxt--neue-eintrage)
40. [Der aktualisierte Render-Loop](#40-der-aktualisierte-render-loop)
41. [Zusammenfassung: Was Milestone 3 aufgebaut hat](#41-zusammenfassung-milestone-3)

---

## 29. Die große Übersicht — Milestone 3

Milestone 2 zeichnete ein rotierendes Dreieck mit MVP-Kamera. Milestone 3 ersetzt das durch ein **echtes 3D-Mesh** aus einer Datei, verwaltet in einem **Scene Graph**:

```
Was sich verändert hat:

Milestone 2:  3 hardcodierte Vertices → Dreieck → Vertex-Farben
Milestone 3:  glTF-Datei laden → Vertices + Normals + Indices
                                  → Scene Graph Node-Hierarchie
                                  → Phong-Beleuchtung
```

**Neue Dateien:**

| Datei | Funktion |
|---|---|
| `src/Mesh.hpp` | Klassen-Interface: Vertex-Struct, Mesh-Klasse |
| `src/Mesh.mm` | Implementation: cgltf laden, Metal Buffer bauen |
| `src/Node.hpp` | Scene Graph Node: Transform + Children + worldMatrix |
| `assets/cube.glb` | Khronos offizielles Box-Sample-Asset |
| `vendor/cgltf` | header-only glTF 2.0 Loader (Git-Submodul) |

**Geänderte Dateien:**

| Datei | Was sich geändert hat |
|---|---|
| `shaders/triangle.metal` | VertexIn: float3 normal statt float4 color; Phong-Lighting im Fragment Shader; normalMatrix in Uniforms |
| `src/Uniforms.hpp` | +normalMatrix (simd::float3x3) |
| `src/Math.hpp` | +normalMatrix() Funktion |
| `src/Renderer.hpp` | buildScene() statt buildGeometry(); Mesh* + shared_ptr<Node> |
| `src/Renderer.mm` | Komplette Umstrukturierung auf Scene Graph + drawNode() |
| `CMakeLists.txt` | Mesh.mm in Sources; vendor/cgltf im Include-Pfad; Assets-Copy |

---

## 30. glTF 2.0

### Was ist glTF?

**glTF** (Graphics Language Transmission Format) ist der offene Standard für 3D-Assets — von Khronos entwickelt, dem gleichen Konsortium das OpenGL und Vulkan betreut. Es wird oft als "JPEG der 3D-Welt" bezeichnet.

Ein glTF-Asset beschreibt:
- **Meshes** — Vertices (Position, Normal, UV, Tangent), Indices
- **Materialien** — PBR-Parameter (Albedo, Metallic, Roughness, Normal Map)
- **Szenen-Hierarchien** — Parent-Child Node-Bäume mit Transforms
- **Animationen** — Keyframe-Animationen für Bones und Nodes
- **Skelett-Animation** (Skinning) — Mesh-Deformation durch Bones

### Zwei Dateiformate

| Format | Beschreibung |
|---|---|
| `.gltf` | JSON + separate `.bin`-Dateien für Binärdaten |
| `.glb` | Binary glTF — alles in einer Datei (JSON + Bin gepackt) |

Wir nutzen `.glb` — eine einzige Datei, kein Pfad-Management nötig.

### Warum glTF und nicht .obj?

| | OBJ | glTF 2.0 |
|---|---|---|
| Format | ASCII Text | Binary + JSON |
| Geschwindigkeit | Langsam (parsen) | Schnell (memcpy-fähig) |
| PBR-Materialien | Nicht standardisiert | Vollständig definiert |
| Animationen | Keine | Keyframe + Skelett |
| Tool-Support | Überall | Blender, Unity, Unreal, etc. |
| Khronos-Standard | Nein | Ja |

`.obj` ist für Hobby-Projekte praktisch, aber für professionelle Engines ist glTF die richtige Wahl.

### Unser Test-Asset: Khronos Box

```
assets/cube.glb  ←  Offizielles Khronos glTF-Sample-Asset "Box"
```

Das Khronos glTF-Sample-Repository (`KhronosGroup/glTF-Sample-Assets`) enthält dutzende validierte Test-Assets. `Box.glb` ist das einfachste — ein einziger Cube mit 24 Vertices und 36 Indices, Position + Normal.

---

## 31. cgltf

### Was ist cgltf?

`cgltf` ist eine **single-header C-Bibliothek** von Johannes Kuhlmann für glTF 2.0. "Single-header" bedeutet: die gesamte Implementation steckt in einer einzigen `.h`-Datei — kein Build-System-Aufwand, kein separates `.lib`-File.

Das Muster für single-header Libraries:

```cpp
// In GENAU EINER .mm-Datei (Mesh.mm):
#define CGLTF_IMPLEMENTATION   // Aktiviert die Implementation
#include "cgltf.h"

// In allen anderen Dateien: NUR einbinden, kein IMPLEMENTATION-Macro
#include "cgltf.h"
```

Würde man `CGLTF_IMPLEMENTATION` in zwei `.mm`-Dateien setzen: **Linker-Fehler** wegen doppelter Symbole — exakt wie bei den metal-cpp Macros in `MetalImpl.mm`.

### cgltf als Git-Submodul

```bash
git submodule add https://github.com/jkuhlmann/cgltf vendor/cgltf
```

cgltf liegt in `vendor/cgltf/cgltf.h`. In `CMakeLists.txt` fügen wir `vendor/cgltf` zum Include-Pfad hinzu — damit `#include "cgltf.h"` überall funktioniert.

### Die cgltf API

```c
cgltf_options options{};
cgltf_data*   data = nullptr;

// Schritt 1: JSON-Header parsen (kein Binärdata geladen)
cgltf_result result = cgltf_parse_file(&options, "cube.glb", &data);

// Schritt 2: Binäre Buffer-Daten laden (die eigentlichen Vertex-Daten)
cgltf_load_buffers(&options, data, "cube.glb");

// Schritt 3: Zugriff auf Mesh-Daten
cgltf_mesh*      mesh = &data->meshes[0];
cgltf_primitive* prim = &mesh->primitives[0];

// Attribute lesen
for (size_t i = 0; i < prim->attributes_count; ++i) {
    if (prim->attributes[i].type == cgltf_attribute_type_position)
        posAcc = prim->attributes[i].data;  // cgltf_accessor*
}

// Accessor: typsicherer Zugriff auf rohe Bytes
float tmp[3];
cgltf_accessor_read_float(posAcc, vertexIndex, tmp, 3);

// Index-Daten
size_t idx = cgltf_accessor_read_index(prim->indices, indexIndex);

// Schritt 4: Freigeben
cgltf_free(data);
```

Ein **Accessor** ist cgltfs typsicheres Fenster in die rohen Bytes des Binary Buffers. Er beschreibt: welcher Typ (`FLOAT`, `UNSIGNED_SHORT`...), wie viele Komponenten (`SCALAR`, `VEC2`, `VEC3`...), und den Byte-Offset in den Buffer.

---

## 32. Index Buffer

### Das Problem mit nicht-indizierten Meshes

Bis Milestone 2 hatten wir drei Vertices → ein Dreieck. Bei einem echten Mesh (z.B. ein Würfel) werden Vertices zwischen benachbarten Dreiecken **geteilt**:

```
Würfel-Fläche (2 Dreiecke, 4 Ecken):

  v0 ─── v1
  │  ╲   │
  │   ╲  │
  v3 ─── v2

Ohne Index Buffer (6 Vertices):
Triangle 0: v0, v1, v2
Triangle 1: v0, v2, v3
→ v0 und v2 sind doppelt gespeichert!

Mit Index Buffer (4 Vertices + 6 Indices):
Vertices: v0, v1, v2, v3
Indices:  0, 1, 2,  0, 2, 3
```

Bei einem typischen Mesh teilt jede Kante zwei Dreiecke. Ohne Index Buffer wäre jedes Vertex drei mal gespeichert (im Durchschnitt). Ein Index Buffer reduziert das auf einmal — **~60% Speicherersparnis**.

Zusätzlich: Die GPU hat einen **Post-Transform Cache** (auch "Vertex Cache" genannt). Wenn derselbe Vertex-Index kurz hintereinander verarbeitet wird, kommt das Ergebnis aus dem Cache — kein zweiter Vertex-Shader-Aufruf nötig.

### Metal Index Buffer API

```cpp
// Buffer erstellen
m_indexBuffer = device->newBuffer(
    indices.data(),                      // uint32_t Array
    indices.size() * sizeof(uint32_t),   // Byte-Größe
    MTL::ResourceStorageModeShared);

// Draw Call mit Index Buffer
enc->drawIndexedPrimitives(
    MTL::PrimitiveType::PrimitiveTypeTriangle,  // Primitiv-Typ
    m_indexCount,                               // Anzahl Indices
    MTL::IndexType::IndexTypeUInt32,            // Index-Typ (16 oder 32 Bit)
    m_indexBuffer,                              // Der Index Buffer
    0);                                         // Byte-Offset in den Buffer
```

Wir nutzen `uint32_t` (32-Bit Indices). Alternativ wäre `uint16_t` (16-Bit, max 65535 Vertices). Für den Khronos Box Mesh (24 Vertices) würde 16-Bit reichen, aber `uint32_t` ist der sichere Standard.

### Warum cgltf_accessor_read_index?

cgltf liest Indices aus dem glTF-Accessor. Der Index-Accessor kann verschiedene Formate haben (`UNSIGNED_BYTE`, `UNSIGNED_SHORT`, `UNSIGNED_INT`). `cgltf_accessor_read_index` abstrahiert das und gibt immer `size_t` zurück — wir casten dann auf `uint32_t`.

---

## 33. Das neue Vertex-Layout

### Warum Normal statt Color?

In Milestone 1+2 hatten wir:
```cpp
struct Vertex {
    simd::float3 position;   // 12 Bytes
    simd::float4 color;      // 16 Bytes  ← weg
};
```

Farben macht ein Lighting-Modell überflüssig: wir berechnen die Farbe aus Beleuchtung + Materialfarbe. Dafür brauchen wir die **Oberflächennormale** — den Vektor der senkrecht zur Fläche zeigt.

```cpp
struct Vertex {
    simd::float3 position;   // 12 Bytes
    simd::float3 normal;     // 12 Bytes  ← neu
};
// Gesamtgröße: 24 Bytes pro Vertex
```

### Was ist eine Normale?

Eine **Oberflächennormale** ist ein Einheitsvektor (Länge = 1) der senkrecht zur Oberfläche eines Dreiecks zeigt. Sie wird für Beleuchtungsberechnungen gebraucht:

```
     ↑ Normal (0, 1, 0)
     │
─────┼──────  Fläche (horizontal)

Je mehr die Normale zum Licht zeigt, desto heller die Fläche.
```

Bei einem Würfel hat jede Seite eine Normale die nach außen zeigt: oben `(0,1,0)`, rechts `(1,0,0)`, vorne `(0,0,1)`, etc.

### Warum nicht die Normale aus den Vertices berechnen?

Man könnte die Normale eines Dreiecks berechnen via `cross(v1-v0, v2-v0)`. Aber glTF-Meshes liefern **Vertex-Normalen** — pro Vertex definiert, nicht pro Dreieck. Das erlaubt **smooth shading**: an einer Kante zwischen zwei Dreiecken werden die Normalen interpoliert, die Oberfläche sieht weich aus statt facettiert.

---

## 34. Mesh.hpp / Mesh.mm

### Mesh.hpp — Das Interface

```cpp
class Mesh {
public:
    static Mesh* loadGLB(MTL::Device* device, const std::string& path);
    ~Mesh();
    void draw(MTL::RenderCommandEncoder* enc) const;
    bool isValid() const { return m_vertexBuffer && m_indexBuffer; }

private:
    MTL::Buffer* m_vertexBuffer { nullptr };
    MTL::Buffer* m_indexBuffer  { nullptr };
    uint32_t     m_indexCount   { 0 };
};
```

`loadGLB` ist eine **static factory method** — sie erstellt ein Mesh-Objekt und gibt einen rohen Pointer zurück (oder `nullptr` bei Fehler). Der Renderer ist Owner und löscht das Mesh im Destruktor via `delete m_mesh`.

### Mesh.mm — Pfad-Auflösung

```cpp
static std::string executableDir() {
    char buf[4096];
    uint32_t size = sizeof(buf);
    _NSGetExecutablePath(buf, &size);
    std::string path(buf);
    auto pos = path.rfind('/');
    return (pos != std::string::npos) ? path.substr(0, pos) : ".";
}
```

Wenn das Programm aus einem anderen Verzeichnis gestartet wird (z.B. `./build/metal4engine`), würde ein relativer Pfad wie `"assets/cube.glb"` falsch aufgelöst. Wir holen den absoluten Pfad zur Binary und bauen den Asset-Pfad relativ dazu.

`_NSGetExecutablePath` ist eine `<mach-o/dyld.h>`-Funktion — Apple-spezifisch. `rfind('/')` findet das letzte `/` im Pfad und schneidet den Dateinamen ab.

### Mesh.mm — Zwei-Schritt Pfad-Fallback

```cpp
cgltf_result result = cgltf_parse_file(&options, path.c_str(), &data);
if (result != cgltf_result_success) {
    std::string exePath = executableDir() + "/" + path;
    result = cgltf_parse_file(&options, exePath.c_str(), &data);
}
```

Wir versuchen zuerst den Pfad as-is (falls er absolut ist oder der CWD stimmt). Wenn das fehlschlägt, kombinieren wir executableDir + relativen Pfad. Das gleiche Muster für `cgltf_load_buffers`.

### Mesh.mm — Float-Zugriff auf simd-Vektoren

```cpp
float tmp[3];
cgltf_accessor_read_float(posAcc, i, tmp, 3);
vertices[i].position = simd::float3{ tmp[0], tmp[1], tmp[2] };
```

Man könnte erwarten: `cgltf_accessor_read_float(posAcc, i, &vertices[i].position.x, 3)`. Das geht **nicht** — `simd::float3` ist ein SIMD-Typ dessen Komponenten nicht adressierbar sind (sie liegen in SIMD-Registern). Deshalb lesen wir in ein temporäres C-Array und konstruieren dann den `simd::float3`.

### Mesh.mm — draw()

```cpp
void Mesh::draw(MTL::RenderCommandEncoder* enc) const {
    enc->setVertexBuffer(m_vertexBuffer, 0, 0);
    enc->drawIndexedPrimitives(
        MTL::PrimitiveType::PrimitiveTypeTriangle,
        m_indexCount,
        MTL::IndexType::IndexTypeUInt32,
        m_indexBuffer,
        0);
}
```

`draw()` macht genau zwei Dinge: Vertex Buffer binden (Slot 0) und indizierten Draw Call. Der Uniform Buffer (Slot 1) wird **außerhalb** von `draw()` gesetzt (in `drawNode()`) weil er von der Node-Transform abhängt, nicht vom Mesh.

---

## 35. Node.hpp — Der Scene Graph

### Konzept

Ein **Scene Graph** ist ein **Baum von Transformationen**. Jeder Node hat:
- Eine **lokale Transform** (Position, Rotation, Scale relativ zum Parent)
- Eine **World Matrix** (absolute Position/Rotation/Scale in der Welt)
- Optional eine **Mesh-Referenz** (Nodes ohne Mesh sind reine Gruppen-Nodes)
- Beliebig viele **Child-Nodes**

```
Root (worldMatrix = identity)
└── Cube (translation=(0,0,0), rotation=0.8t rad Y)
    worldMatrix = root.worldMatrix * local
```

In unserem Milestone-3-Beispiel ist der Tree flach: Root → ein Cube-Node. Die Struktur ist aber offen für beliebige Tiefe.

### Die World-Matrix-Formel

```
worldMatrix = parentWorldMatrix × localMatrix
```

`localMatrix` ist das Produkt aus Translation × Rotation × Scale des Nodes selbst.

**Reihenfolge**: Scale zuerst, dann Rotation, dann Translation (TRS-Konvention). Das ist die Reihenfolge in der glTF-Nodes gespeichert sind.

```cpp
void updateWorldMatrix(const simd::float4x4& parentWorld = matrix_identity_float4x4) {
    simd::float4x4 local =
        math::translation(translation.x, translation.y, translation.z)
        * math::rotation(rotationAngle, rotationAxis)
        * math::scale(uniformScale);

    worldMatrix = parentWorld * local;

    for (auto& child : m_children)
        child->updateWorldMatrix(worldMatrix);
}
```

Der Aufruf ist rekursiv — top-down vom Root. Jeder Node berechnet seine World Matrix aus der bereits berechneten Parent-World-Matrix. So muss man nur einmal von Root starten.

### Warum `std::shared_ptr` für Children?

```cpp
std::vector<std::shared_ptr<Node>> m_children;
```

`shared_ptr` ermöglicht es, dass mehrere Stellen eine Node halten können (z.B. eine Animation-Liste und der Scene Graph). Der Destruktor räumt automatisch auf wenn der letzte `shared_ptr` weg ist.

In unserem einfachen Milestone-3-Szenario wäre `unique_ptr` auch ausreichend, aber `shared_ptr` ist die robustere Wahl für spätere Erweiterungen.

### Nicht-owning Mesh-Pointer

```cpp
Mesh* mesh { nullptr };   // nicht-owning!
```

Der Node **referenziert** ein Mesh, er **besitzt** es nicht. Der Renderer besitzt das Mesh (`m_mesh`). Mehrere Nodes könnten dasselbe Mesh referenzieren (Instancing) — das ist der Hauptvorteil dieser Trennung.

---

## 36. Phong Lighting im Shader

In Milestone 2 gab der Fragment Shader einfach die interpolierte Vertex-Farbe aus. In Milestone 3 berechnen wir ein Beleuchtungsmodell.

### Das Phong-Modell

Das **Phong Beleuchtungsmodell** (1975, Bui Tuong Phong) ist das klassische Echtzeit-Beleuchtungsmodell — in modernen Engines oft durch PBR ersetzt, aber ideal zum Lernen:

```
I_total = I_ambient + I_diffuse + I_specular
```

Wir nutzen nur **Ambient + Diffuse** (kein Specular — für Milestone 3 ausreichend):

```metal
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float3 lightDir  = normalize(float3(1.0, 2.0, 1.5));  // fester Lichtvektor
    float3 norm      = normalize(in.worldNorm);            // normalisierte Normale
    float  diffuse   = saturate(dot(norm, lightDir));      // Lambert-Term
    float  ambient   = 0.15;
    float  intensity = ambient + diffuse * 0.85;

    float3 baseColor = float3(0.72, 0.55, 0.38);           // warm clay
    return float4(baseColor * intensity, 1.0);
}
```

### Lambert-Term

```metal
float diffuse = saturate(dot(norm, lightDir));
```

Das **Skalarprodukt** (dot product) zweier normalisierter Vektoren gibt den Kosinus des Winkels zwischen ihnen:
- Normale zeigt direkt zum Licht (`dot = 1.0`): maximale Helligkeit
- Normale senkrecht zum Licht (`dot = 0.0`): keine direkte Beleuchtung
- Normale weg vom Licht (`dot < 0.0`): `saturate()` klemmt auf 0

`saturate(x)` ist eine MSL Built-in Funktion: `clamp(x, 0.0, 1.0)`.

### Ambient Term

```metal
float ambient = 0.15;
float intensity = ambient + diffuse * 0.85;
```

**Ambient Light** simuliert indirektes Licht das von allen Seiten kommt. Ohne Ambient wären Flächen die vom Licht weg zeigen komplett schwarz — unrealistisch. 15% Ambient gibt der Szene eine minimale Grundhelligkeit.

### Warum worldNorm und nicht objectNorm?

Wenn wir das Modell rotieren, drehen sich auch seine Normalen. Ein Würfel der um 90° rotiert ist, hat jetzt eine andere Normalenorientierung im Welt-Raum — obwohl die Normalen in Object Space immer gleich bleiben.

```
Object Space Normal: (0, 1, 0) = zeigt nach oben
Nach Rotation um 90° Y: muss jetzt in World Space (1, 0, 0) sein (zeigt nach rechts)
```

Deshalb: Normalen in World Space transformieren (via Normal Matrix) → im Fragment Shader in World Space mit dem Lichtvektor (auch in World Space) vergleichen.

---

## 37. Die Normal Matrix

### Das Problem mit nicht-uniformem Scale

Wenn man Normalen mit der Model Matrix transformiert funktioniert das bei **Rotation** korrekt, aber **nicht bei nicht-uniformem Scale**. Beispiel:

```
Objekt in X-Richtung auf 2.0 skaliert:
  Model Matrix skaliert Position: (1, 0, 0) → (2, 0, 0)  ✓
  Model Matrix skaliert Normal:   (1, 0, 0) → (2, 0, 0)  → nach Normalisierung OK...
  Aber: schräge Normale (1, 1, 0) → (2, 1, 0) → falsche Richtung!
```

Die korrekte Lösung: Die **Normal Matrix** = `transpose(inverse(modelMatrix))`'s obere-linke 3×3.

### Herleitung

Sei `M` die Model Matrix. Eine Normale `n` ist orthogonal zu einer Tangente `t` auf der Oberfläche: `dot(n, t) = 0`.

Nach der Transformation gilt: `dot(N*n, M*t) = 0`, also `(N*n)^T * M*t = 0`, also `n^T * N^T * M * t = 0`. Das ist nur dann für alle `t` wahr wenn `N^T * M = I`, also `N = (M^-1)^T = transpose(inverse(M))`.

### Math.hpp — normalMatrix()

```cpp
inline simd::float3x3 normalMatrix(const simd::float4x4& m) {
    simd::float3x3 upper{
        simd::float3{ m.columns[0].x, m.columns[0].y, m.columns[0].z },
        simd::float3{ m.columns[1].x, m.columns[1].y, m.columns[1].z },
        simd::float3{ m.columns[2].x, m.columns[2].y, m.columns[2].z }
    };
    return simd::transpose(simd::inverse(upper));
}
```

Wir extrahieren die obere-linke 3×3 aus der 4×4 Model Matrix (die Translations-Spalte ist für Normalen irrelevant) und berechnen `transpose(inverse(...))`.

`simd::inverse()` und `simd::transpose()` sind direkte SIMD-Operationen — sehr schnell.

### Uniforms.hpp — das Update

```cpp
struct Uniforms {
    simd::float4x4 modelMatrix;
    simd::float4x4 viewMatrix;
    simd::float4x4 projectionMatrix;
    simd::float3x3 normalMatrix;     // transpose(inverse(modelMatrix)) obere-linke 3x3
};
```

`simd::float3x3` ist 36 Bytes (3 × 3 × 4). Das Struct ist nun **228 Bytes** gesamt. **Kein Padding-Problem** weil `float4x4` 16-Byte-aligned ist und `float3x3` nach drei `float4x4` folgt.

### Im Shader

```metal
struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
};

// Im Vertex Shader:
float3 worldNorm = uniforms.normalMatrix * vertices[vertexID].normal;
```

MSL `float3x3` und C++ `simd::float3x3` haben dasselbe Memory-Layout — `memcpy` funktioniert korrekt.

---

## 38. Renderer — buildScene und drawNode

### buildScene()

```cpp
void Renderer::buildScene() {
    m_mesh = Mesh::loadGLB(m_device, "assets/cube.glb");

    m_sceneRoot = std::make_shared<Node>("root");

    auto meshNode = std::make_shared<Node>("cube");
    meshNode->mesh          = m_mesh;
    meshNode->translation   = { 0.0f, 0.0f, 0.0f };
    meshNode->rotationAxis  = { 0.0f, 1.0f, 0.0f };
    meshNode->rotationAngle = 0.0f;
    meshNode->uniformScale  = 1.0f;

    m_sceneRoot->addChild(meshNode);
}
```

`buildScene()` ersetzt `buildGeometry()`. Die Trennung: der Renderer besitzt `m_mesh` (der Metal Buffer) und den Scene Graph (der die Transform-Hierarchie beschreibt). Der `meshNode` hält einen nicht-owning Pointer auf `m_mesh`.

### Animation im draw()

```cpp
void Renderer::draw(...) {
    m_time += 1.0f / 60.0f;

    // Cube-Node animieren
    if (!m_sceneRoot->children().empty()) {
        auto& cube = *m_sceneRoot->children()[0];
        cube.rotationAngle = m_time * 0.8f;
    }

    // World Matrices top-down aktualisieren
    m_sceneRoot->updateWorldMatrix();
```

Wir setzen nur `rotationAngle` des Cube-Nodes — `updateWorldMatrix()` berechnet dann automatisch die neue `worldMatrix`. Kein direktes Matrix-Manipulieren mehr.

### drawNode() — Rekursive Funktion

```cpp
static void drawNode(const Node& node,
                     MTL::RenderCommandEncoder* enc,
                     MTL::Buffer* uniformBuffer,
                     const simd::float4x4& view,
                     const simd::float4x4& proj) {
    if (node.mesh && node.mesh->isValid()) {
        Uniforms u;
        u.modelMatrix      = node.worldMatrix;
        u.viewMatrix       = view;
        u.projectionMatrix = proj;
        u.normalMatrix     = math::normalMatrix(node.worldMatrix);
        std::memcpy(uniformBuffer->contents(), &u, sizeof(Uniforms));

        enc->setVertexBuffer(uniformBuffer, 0, 1);
        node.mesh->draw(enc);
    }

    for (const auto& child : node.children())
        drawNode(*child, enc, uniformBuffer, view, proj);
}
```

Diese Funktion traversiert den Scene Graph rekursiv. Für jeden Node der ein valides Mesh hat:
1. Uniforms mit der Node's `worldMatrix` befüllen
2. Uniform Buffer binden
3. Mesh zeichnen

Dann für alle Kinder rekursiv. Die Reihenfolge (Pre-Order DFS) ist für unser Szenario egal — bei Transparenz würde man aber Back-to-Front sortieren.

**Wichtig**: In dieser einfachen Variante überschreibt jeder Node denselben `uniformBuffer`. Das funktioniert weil wir kein Multi-Threading und keine parallelen Draw Calls haben. Mit mehreren Meshes und Triple-Buffering würde man einen Ring-Buffer oder `MTL4ArgumentTable` verwenden (→ Milestone 4).

---

## 39. CMakeLists.txt — Neue Einträge

### Mesh.mm in ENGINE_SOURCES

```cmake
set(ENGINE_SOURCES
    src/main.mm
    src/AppDelegate.mm
    src/MetalViewDelegate.mm
    src/InputMTKView.mm
    src/Renderer.mm
    src/Mesh.mm          # ← neu
    src/MetalImpl.mm
)
```

`Mesh.mm` enthält `#define CGLTF_IMPLEMENTATION` und damit die gesamte cgltf-Implementation. Sie muss in die Source-Liste damit CMake sie kompiliert.

### cgltf Include-Pfad

```cmake
target_include_directories(metal4engine PRIVATE
    ${CMAKE_SOURCE_DIR}/vendor/metal-cpp
    ${CMAKE_SOURCE_DIR}/vendor/cgltf    # ← neu
    ${CMAKE_SOURCE_DIR}/src
)
```

So findet `#include "cgltf.h"` die Datei in `vendor/cgltf/cgltf.h`.

### Assets in das Build-Verzeichnis kopieren

```cmake
add_custom_command(TARGET metal4engine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/assets
        $<TARGET_FILE_DIR:metal4engine>/assets
)
```

`POST_BUILD` = wird nach dem Linken ausgeführt. `copy_directory` kopiert den gesamten `assets/`-Ordner neben die Binary. `$<TARGET_FILE_DIR:metal4engine>` ist ein CMake Generator-Expression — es expandiert zum Verzeichnis in dem die Binary liegt (z.B. `build/metal4engine.app/Contents/MacOS/`).

So liegt `cube.glb` nach dem Build immer neben der Binary und unser Pfad-Lookup funktioniert.

---

## 40. Der aktualisierte Render-Loop

```
draw() aufgerufen von MTKView (60fps)
    │
    ├─ m_time += 1/60
    │
    ├─ cube.rotationAngle = m_time * 0.8f     (Animation)
    ├─ sceneRoot.updateWorldMatrix()           (World Matrices berechnen)
    │
    ├─ View Matrix  = lookAt(camera.eye(), camera.target, up)
    ├─ Proj Matrix  = perspectiveFov(60°, aspect, 0.01, 1000)
    │
    ├─ CommandBuffer holen
    ├─ RenderPassDescriptor (clear color + clear depth)
    ├─ RenderCommandEncoder öffnen
    │    ├─ setRenderPipelineState
    │    ├─ setDepthStencilState
    │    ├─ setViewport
    │    └─ drawNode(sceneRoot, enc, uniformBuffer, view, proj)
    │         ├─ für jeden Node mit Mesh:
    │         │    ├─ Uniforms befüllen (worldMatrix, view, proj, normalMatrix)
    │         │    ├─ setVertexBuffer(uniformBuffer, 0, slot=1)
    │         │    └─ mesh.draw(enc)  → setVertexBuffer(vertices, slot=0)
    │         │                         drawIndexedPrimitives(...)
    │         └─ rekursiv für Children
    ├─ endEncoding
    ├─ presentDrawable
    └─ commit
```

**Was weggefallen ist** gegenüber Milestone 2:
- Kein `m_vertexBuffer` mehr im Renderer — der lebt jetzt in `Mesh`
- Kein manuelles `buildGeometry()` — ersetzt durch `buildScene()` + cgltf

**Was dazugekommen ist**:
- `drawNode()` — rekursive Scene-Graph-Traversierung
- `normalMatrix` in Uniforms — korrekte Normalentransformation
- `drawIndexedPrimitives` statt `drawPrimitives`

---

## 41. Zusammenfassung: Was Milestone 3 aufgebaut hat

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
│  ├─ Camera (orbit)                                       │
│  ├─ Math (lookAt, perspectiveFov, rotation, normalMatrix)│
│  ├─ Uniforms (M, V, P, normalMatrix)                     │
│  │                                                       │
│  ├─ Scene Graph:                                         │
│  │    Root Node                                          │
│  │    └── Cube Node (translation, rotation, scale)       │
│  │         worldMatrix = parentWorld × local             │
│  │                                                       │
│  └─ Mesh (cgltf loader)                                  │
│       ├─ MTL::Buffer (Vertex: position + normal)         │
│       └─ MTL::Buffer (Index: uint32_t)                   │
│            → drawIndexedPrimitives()                     │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│                     GPU / MSL Layer                      │
│  mesh.metal: vertex_main(vertices, uniforms)              │
│    → named bindings from shared/BindingIndices.h          │
│    → MVP * position                                      │
│    → normalMatrix * normal → worldNorm                   │
│  fragment_main(worldNorm)                                │
│    → Lambert diffuse + ambient → clay color              │
└─────────────────────────────────────────────────────────┘
```

**Kernerkenntnis von Milestone 3**: Der Renderer kennt keine Vertex-Daten mehr direkt. Er arbeitet mit dem Scene Graph (Transforms) und delegiert das Zeichnen an `Mesh::draw()`. Das ist die saubere Trennung zwischen **Szenen-Logik** (Node-Hierarchie) und **GPU-Ressourcen** (Buffer).

In Milestone 4 bereiten wir zuerst die Binding-Struktur für **Metal 4 Argument Tables** vor. Danach setzen wir `MTL4ArgumentTable` (Bindless Buffers) ein — um viele Meshes effizienter zu rendern ohne pro-Objekt-Bind-Calls.

---

# Milestone 4 — PBR Deferred Lighting

## Was wird gebaut?

**Physically Based Rendering** — Materialien die sich physikalisch korrekt verhalten, und ein **Deferred Renderer** der viele Lichtquellen effizient handhabt.

Bevor wir PBR und Deferred Rendering bauen, räumen wir zuerst die CPU/GPU-Binding-Struktur auf. Das ist kein Umweg: `MTL4ArgumentTable` funktioniert nur sauber, wenn klar ist, welcher Binding-Slot welche Bedeutung hat.

## Erster Milestone-4-Schritt — Shared Binding Indices

Bisher standen die Buffer-Slots als rohe Zahlen direkt im CPU- und GPU-Code:

```cpp
enc->setVertexBuffer(m_vertexBuffer, 0, 0); // Vertex Buffer auf Slot 0
enc->setVertexBuffer(uniformBuffer, 0, 1);  // Uniform Buffer auf Slot 1
```

Und im Shader:

```metal
const device VertexIn* vertices [[buffer(0)]],
constant Uniforms& uniforms     [[buffer(1)]]
```

Das funktioniert, ist aber fragil. Wenn CPU und GPU unterschiedliche Slot-Nummern verwenden, kompiliert das Programm oft trotzdem — aber der Shader liest dann falsche Daten. Solche Bugs sind schwer zu erkennen, weil sie wie kaputte Matrizen, kaputte Vertices oder komplett schwarzes Rendering aussehen können.

Deshalb gibt es jetzt einen gemeinsamen Header:

```cpp
#pragma once

enum BufferIndex {
  BufferIndexVertices = 0,
  BufferIndexUniforms = 1,
};
```

Die Datei liegt in `shared/BindingIndices.h`, nicht in `src/`, weil sie von beiden Welten gelesen wird:

| Nutzer | Include |
|---|---|
| CPU / Objective-C++ | `#include "../shared/BindingIndices.h"` |
| GPU / Metal Shader | `#include "../shared/BindingIndices.h"` |

Damit wird aus einem numerischen Slot ein semantischer Vertrag:

| Name | Wert | Bedeutung |
|---|---:|---|
| `BufferIndexVertices` | 0 | Vertex Buffer mit `VertexIn` Daten |
| `BufferIndexUniforms` | 1 | Uniform Buffer mit Model/View/Projection/Normal-Matrix |

CPU-Seite:

```cpp
enc->setVertexBuffer(m_vertexBuffer, 0, BufferIndexVertices);
enc->setVertexBuffer(uniformBuffer, 0, BufferIndexUniforms);
```

GPU-Seite:

```metal
const device VertexIn* vertices [[buffer(BufferIndexVertices)]],
constant Uniforms& uniforms     [[buffer(BufferIndexUniforms)]]
```

### Warum ist das Vorbereitung für `MTL4ArgumentTable`?

`MTL4ArgumentTable` verschiebt Bindings von vielen einzelnen Encoder-Aufrufen in eine Tabelle. Statt pro Draw Call einzelne Ressourcen zu setzen, beschreibt man Ressourcen zentral über Binding-Indizes. Genau deshalb müssen diese Indizes vorher eindeutig benannt und zwischen CPU und GPU geteilt sein.

Der aktuelle Schritt ist also noch kein Bindless Rendering, aber er macht die Architektur bindless-fähig.

### Shader-Datei umbenannt: `triangle.metal` → `mesh.metal`

Die Shader-Datei heisst jetzt `shaders/mesh.metal`, weil sie nicht mehr nur ein Demo-Dreieck rendert. Sie verarbeitet echte Mesh-Vertices aus glTF:

- Position
- Normalen
- Uniform-Matrizen
- Phong-Beleuchtung als aktueller Platzhalter vor PBR

Der Name `mesh.metal` beschreibt die aktuelle Verantwortung besser und lässt Raum für spätere Dateien wie `gbuffer.metal`, `pbr.metal` oder `lighting.metal`.

### CMake-Abhängigkeit für Shared Shader Header

Der Metal-Build hängt nicht nur von `mesh.metal` ab, sondern auch vom Shared Header:

```cmake
set(SHARED_SHADER_HEADERS ${CMAKE_SOURCE_DIR}/shared/BindingIndices.h)

add_custom_command(
    OUTPUT  ${METALLIB_OUT}
    COMMAND xcrun -sdk macosx metal -c ${SHADER_SOURCE} -o ${CMAKE_BINARY_DIR}/mesh.air
    COMMAND xcrun -sdk macosx metallib ${CMAKE_BINARY_DIR}/mesh.air -o ${METALLIB_OUT}
    DEPENDS ${SHADER_SOURCE} ${SHARED_SHADER_HEADERS}
)
```

Ohne diese Dependency würde CMake bei einer Änderung an `shared/BindingIndices.h` eventuell nicht erkennen, dass `default.metallib` neu gebaut werden muss.

## Material-Array und 100 Cube-Instanzen

Der nächste Milestone-4-Schritt erweitert das Rendering von einem einzelnen Mesh/Material zu vielen Objektinstanzen mit unterschiedlichen Materialdaten.

Aktuell laden wir `assets/cube.glb` einmal in einen einzigen `Mesh`:

```cpp
m_mesh = Mesh::loadGLB(m_device, "assets/cube.glb");
```

Danach erzeugen wir 100 `Node`-Instanzen in einem 10×10 Grid. Alle Nodes zeigen auf denselben Mesh-Speicher:

```text
cube node 0 ─┐
cube node 1 ─┤
cube node 2 ─┤
...          ├─> ein gemeinsames Mesh mit Vertex- und Index-Buffer
cube node 99 ┘
```

Das ist bereits eine wichtige Engine-Idee: **Instancing auf CPU-Seite**. Wir duplizieren nicht die Vertexdaten, sondern nur die Transform- und Materialauswahl pro Objekt.

Jede Node bekommt einen eigenen Materialindex:

```cpp
cube->materialIndex = static_cast<std::uint32_t>(index);
```

Der Material-Buffer enthält jetzt nicht mehr ein einzelnes Material, sondern ein Array:

```cpp
Material materials[kInstanceCount];
```

Für jedes Objekt wird ein anderer Eintrag gefüllt:

```cpp
materials[i].baseColor = ...;
materials[i].roughness = ...;
materials[i].metallic = ...;
```

Auf der GPU-Seite liest der Fragment Shader dann nicht mehr:

```metal
constant Material& material
```

sondern:

```metal
constant Material* materials [[buffer(BufferIndexMaterial)]]
```

Der konkrete Materialeintrag wird über den weitergereichten Index gewählt:

```metal
constant Material& material = materials[in.materialIndex];
```

### Datenfluss pro Cube

```text
Node.materialIndex
    ↓
Uniforms.materialIndex
    ↓
vertex_main: out.materialIndex = uniforms.materialIndex
    ↓
VertexOut.materialIndex [[flat]]
    ↓
fragment_main: materials[in.materialIndex]
```

`[[flat]]` ist wichtig, weil `materialIndex` eine ID ist. IDs dürfen nicht zwischen Vertices interpoliert werden. Ohne `[[flat]]` könnte die Rasterizer-Stufe versuchen, zwischen Materialindex 0, 1, 2 usw. zu interpolieren. Für Farben ist Interpolation sinnvoll, für Indizes nicht.

## Warum der Uniform Buffer jetzt Slots braucht

Vorher hatten wir nur ein Objekt. Deshalb reichte ein einzelner Uniform-Block:

```text
m_uniformBuffer
└─ Uniforms für ein Objekt
```

Bei mehreren Draw Calls ist das falsch. Der Grund ist wichtig:

```cpp
enc->setVertexBuffer(uniformBuffer, offset, BufferIndexUniforms);
```

Dieser Call kopiert nicht den Inhalt des Buffers. Er bindet nur:

```text
Buffer-Adresse + Offset + Binding-Slot
```

Die GPU führt die Commands später aus. Wenn die CPU vor mehreren Draw Calls immer denselben Speicherbereich überschreibt, sehen mehrere Draw Calls am Ende dieselben letzten Uniform-Daten.

Falsches Modell:

```text
Draw 0: UniformBuffer = Cube 0
Draw 1: UniformBuffer = Cube 1
Draw 2: UniformBuffer = Cube 2
...
GPU liest später: alle Draws sehen eventuell Cube 99
```

Richtiges Modell:

```text
m_uniformBuffer
├─ Slot 0  → Uniforms für Cube 0
├─ Slot 1  → Uniforms für Cube 1
├─ Slot 2  → Uniforms für Cube 2
│
└─ Slot 99 → Uniforms für Cube 99
```

Dafür berechnen wir einen Stride:

```cpp
m_uniformStride = alignUp(sizeof(Uniforms), 256);
```

`sizeof(Uniforms)` ist die tatsächliche Größe der Struct. `m_uniformStride` ist der Abstand zwischen zwei Uniform-Blöcken im Buffer.

### Warum 256 Byte Alignment?

Metal verlangt für Buffer-Offsets, die als Constant/Uniform-Daten genutzt werden, eine bestimmte Ausrichtung. Typisch ist 256 Byte. Deshalb darf der zweite Uniform-Block nicht einfach direkt nach dem ersten Struct beginnen, wenn die Struct-Größe nicht passend ausgerichtet ist.

Beispiel:

```text
sizeof(Uniforms) = 224 Bytes
m_uniformStride  = 256 Bytes
```

Dann liegen die Blöcke so:

```text
Offset 0   → Cube 0
Offset 256 → Cube 1
Offset 512 → Cube 2
...
```

Der Speicher zwischen `224` und `255` ist Padding. Er wird nicht genutzt, sorgt aber dafür, dass der nächste Block korrekt aligned ist.

### Was macht `drawIndex`?

`drawIndex` ist der aktuelle Slot-Zähler für den Frame.

Am Anfang jedes Frames:

```cpp
std::size_t drawIndex = 0;
```

Bei jedem Node mit Mesh:

```cpp
std::size_t uniformOffset = drawIndex * uniformStride;
```

Dann wird genau in diesen Slot geschrieben:

```cpp
auto* dst = static_cast<std::uint8_t*>(uniformBuffer->contents()) + uniformOffset;
std::memcpy(dst, &u, sizeof(Uniforms));
```

Danach wird der Draw Call mit diesem Offset gebunden:

```cpp
enc->setVertexBuffer(uniformBuffer, uniformOffset, BufferIndexUniforms);
```

Dann wird erhöht:

```cpp
drawIndex++;
```

### Bestimmt `drawIndex`, wie viele Objekte gezeichnet werden können?

Nicht direkt. `drawIndex` ist nur der aktuelle Zähler. Die maximale Anzahl wird durch die Größe des Uniform Buffers bestimmt:

```cpp
m_uniformBuffer = m_device->newBuffer(
    m_uniformStride * m_maxDraws,
    MTL::ResourceStorageModeShared);
```

Hier bedeutet:

```text
m_maxDraws = maximale Anzahl von Draw-Uniform-Slots
```

Wenn `m_maxDraws = 100`, dann gibt es Speicher für 100 Uniform-Blöcke:

```text
Slot 0 ... Slot 99
```

`drawIndex` darf dann nur Werte von `0` bis `99` verwenden.

Darum prüfen wir:

```cpp
assert(drawIndex < kInstanceCount);
```

Für unser aktuelles Beispiel ist:

```cpp
kGridSize = 10;
kInstanceCount = kGridSize * kGridSize; // 100
```

Das heißt:

```text
100 Cubes
100 Materials
100 Uniform-Slots
100 Draw Calls
```

Wenn später mehr Objekte gezeichnet werden sollen, müssen wir mindestens eine dieser Grenzen erhöhen:

- `m_maxDraws`
- Uniform-Buffer-Größe
- Material-Buffer-Größe
- Scene-Graph-Node-Anzahl

### Ist das schon echtes GPU Instancing?

Nein. Aktuell sind es 100 normale Draw Calls:

```text
100 Nodes → 100 drawIndexedPrimitives Calls
```

Aber die Architektur ist ein wichtiger Zwischenschritt:

- Meshdaten werden geteilt
- Materialien liegen in einem Buffer-Array
- pro Objekt gibt es einen Materialindex
- Uniformdaten liegen in einem großen per-frame Buffer
- jeder Draw bekommt nur einen anderen Offset

Später können wir daraus echtes GPU Instancing oder bindless Rendering mit `MTL4ArgumentTable` entwickeln.

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
M1  ✅── Basis (Metal 1-3 APIs, Architektur aufbauen)
M2  ✅── simd Matrizen, Uniform Buffer, Orbit-Kamera, MVP
M3  ✅── cgltf glTF-Loader, Index Buffer, Scene Graph, Phong Lighting
M4  ────  MTL4ArgumentTable (Bindless Buffers), PBR BRDF, GBuffer
M5  ────  MTL4CommandEncoder (Unified Encoder), Deferred Lighting
M6  ────  MetalFX Temporal Upscaling + Frame Interpolation
M7  ────  Acceleration Structures, Inline Ray Tracing, RT Denoiser
M8  ────  MSL Tensors, Neural Accelerators, Neural Material Synthesis
          ↑
          Hier sind alle Metal 4-Features aktiv
```

Jeder Milestone baut auf dem vorherigen auf. Kein Schritt kann übersprungen werden ohne das Fundament zu verlieren.
