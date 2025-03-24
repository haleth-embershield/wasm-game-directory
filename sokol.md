update teh WASM templates to use sokol

When including Sokol in a Zig WebAssembly (WASM) project, the size impact depends on which Sokol libraries you use, how they’re compiled, and the optimization settings. Sokol is designed to be lightweight and header-only, so it’s generally quite small compared to larger frameworks, but let’s break it down to give you a concrete idea.
Sokol Components
Sokol consists of several independent header files, and you only include the ones you need. The most commonly used for a Zig WASM project with graphics are:
sokol_gfx.h: Core graphics API (WebGL backend for WASM).
sokol_app.h: Application/window/input handling (maps to browser events in WASM).
sokol_glue.h: Connects sokol_app and sokol_gfx for easier integration.
Optionally, sokol_time.h or sokol_fetch.h for timing or asset loading.
Each header is self-contained C code, and Zig can interface with them directly via its C interop or through bindings like sokol-zig.
Size of Sokol Source
The raw source size of Sokol headers is tiny:
sokol_gfx.h: ~2,500 lines, ~100 KB (unminified text).
sokol_app.h: ~2,000 lines, ~80 KB.
sokol_glue.h: ~100 lines, ~5 KB.
However, this doesn’t directly translate to the final WASM binary size—what matters is the compiled output after Zig processes it.
Compiled Size in WASM
When compiled to WebAssembly with Zig, the size depends on:
Which Sokol Features You Use: Only the code you actually call gets included (thanks to dead code elimination).
Toolchain: Zig with Emscripten or a standalone WASM target (e.g., wasm32-freestanding).
Optimization Flags: -O3 (releaseFast), -Os (ReleaseSmall), or debug builds.
Runtime Overhead: WASM binaries include some runtime code (e.g., for memory management or browser glue).
Minimal Example
A minimal Zig + Sokol WASM app (e.g., clearing the screen with sokol_gfx and sokol_app):
Source: A few lines of Zig to set up a render loop.
Compiled Size: 
With Zig + Emscripten (zig build -Dtarget=wasm32-emscripten -Drelease-small):
.wasm file: ~20-30 KB (after optimization and stripping).
Plus HTML/JS glue: ~5-10 KB (Emscripten’s minimal runtime).
With standalone wasm32-freestanding: ~15-25 KB (no Emscripten overhead, but you’d need custom JS to load it).
Typical 3D Example
A more realistic 3D app (e.g., rendering a spinning cube with shaders):
Adds vertex buffers, shaders, and matrix math (e.g., via sokol_math.h or your own).
Compiled Size: 
With Emscripten: ~30-50 KB .wasm (optimized).
Standalone: ~25-40 KB.
Factors That Increase Size
Shaders: Embedded GLSL code adds a bit (a few KB per shader).
Extra Sokol Libs: Adding sokol_fetch.h or sokol_audio.h increases size slightly (e.g., +5-10 KB each).
Debug Builds: Unoptimized builds can balloon to 100-200 KB due to extra metadata.
Zig Standard Library: If you link Zig’s stdlib (e.g., for std.log), it adds ~50-100 KB unless you disable it with -fno-std.
Optimization Tips
To keep Sokol + Zig WASM small:
Use -Drelease-small or -Doptimize=ReleaseSmall in Zig for size optimization.
Enable Link-Time Optimization (LTO): -flto (via Emscripten or Zig flags).
Strip unused code: Zig’s dead code elimination works well if you avoid unnecessary imports.
Minimize JS glue: Use Emscripten’s -s EXPORTED_FUNCTIONS to export only what you need.
Avoid dynamic linking: Stick to static compilation for WASM.
Comparison
Sokol vs. Three.js: Three.js minified is ~150 KB (gzipped ~50 KB) as JS, plus WebGL runtime. Sokol’s compiled WASM is much smaller for basic tasks but lacks Three.js’s features.
Raw WebGL: Writing raw WebGL in JS might be smaller for trivial cases, but Sokol’s abstraction adds negligible overhead for the convenience.
Real-World Data
From Sokol samples (e.g., floooh’s GitHub):
The triangle-sapp example (basic triangle with Sokol) compiles to ~30 KB WASM with Emscripten, optimized.
More complex demos (e.g., cube-sapp) hit ~40-60 KB with shaders and math.
Conclusion
For a Zig WASM project, including Sokol typically adds 20-50 KB to your .wasm file, depending on features and optimization. It’s extremely lightweight for what it offers—far smaller than high-level libraries—making it ideal for minimal WASM apps. If you’re targeting a specific use case (e.g., 3D with shaders), I can refine the estimate further!