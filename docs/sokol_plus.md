# THINGS TO DO: Moving to WebGPU with Zig

This plan outlines steps to transition to WebGPU using Zig for a 3D tower defense game (with generative audio and heavy particle effects) and an in-browser MP4 decoder as a learning experiment. Start with Sokol for simplicity, then weave in raw WebGPU for compute shaders and command buffers if performance demands it.

---

## Phase 1: Set Up Sokol + WebGPU Basics
Goal: Get comfortable with WebGPU via Sokol, build a foundation for both projects, and minimize HTML reliance.

### General Setup
- [ ] Install Zig (latest version, e.g., 0.12.x as of March 2025)
- [ ] Clone `sokol-zig` (https://github.com/floooh/sokol-zig) for Zig bindings to Sokol
- [ ] Set up a minimal project structure:
  ```
  my_project/
  ├── src/
  │   └── main.zig
  ├── build.zig
  └── index.html
  ```
- [ ] Configure `build.zig` for WASM + WebGPU:
  - Target: `wasm32-emscripten`
  - Flags: `-s USE_WEBGPU=1` (via Emscripten linker)
  - Optimize: `-Drelease-small` for small binaries
- [ ] Create minimal `index.html`:
  ```html
  <canvas id="canvas"></canvas>
  <script src="game.js"></script>
  ```

### 3D Tower Defense Game
1. Build a basic Sokol + WebGPU prototype:
   - Import sokol_gfx.h and sokol_app.h via sokol-zig
   - Render a spinning 3D cube (test WebGPU rendering)
   - Use sapp_mouse_x()/sapp_mouse_y() for basic input (e.g., camera orbit)

2. Add a simple tower defense scene:
   - Load a 3D tower model (e.g., OBJ via custom parser or pre-baked arrays)
   - Render terrain as a textured quad
   - Implement a basic perspective camera (manual matrix math or sokol_math.h)

3. Integrate generative audio:
   - Import sokol_audio.h
   - Generate a sine wave in Zig (e.g., sin(time * freq)), push to saudio_push()
   - Test in-browser playback

4. Add initial particle effects:
   - Create a particle system (e.g., 1,000 particles) with vertex buffers
   - Use instancing (WebGPU supports it) to render particles as billboards
   - Update positions on CPU, upload to buffer each frame

### MP4 Decoder Experiment
1. Build a basic video playback prototype:
   - Use WebCodecs (VideoDecoder) in JS to decode an MP4 file
   - Pass frames to Zig/WASM via Emscripten's ccall
   - Render frames with Sokol (sg_image for texture, sg_draw for quad)

2. Test minimal setup:
   - Load a short MP4 (e.g., 10s clip)
   - Display on a <canvas> with Sokol's WebGPU backend

## Phase 2: Test and Benchmark Sokol Performance
Goal: Evaluate Sokol's WebGPU performance for your game and decoder, identify limits.

### 3D Tower Defense Game
1. Stress-test particle effects:
   - Scale to 5,000-10,000 particles (e.g., explosions, projectiles)
   - Measure FPS in Chrome DevTools (aim for 60 FPS on mid-tier hardware)

2. Benchmark draw calls:
   - Add 50-100 towers and enemies
   - Check if immediate-mode rendering (no command buffers) holds up

3. Optimize if needed:
   - Batch particle draws into fewer calls (e.g., one per system)
   - Use texture atlases for particle variety

### MP4 Decoder
1. Test playback performance:
   - Decode and render a 720p MP4 at 30 FPS
   - Measure latency from decode to display

2. Experiment with WebGPU basics:
   - Use raw webgpu.h to resize frames (simple compute shader)
   - Pass output texture to Sokol for rendering

## Phase 3: Integrate Raw WebGPU (If Needed)
Goal: Add compute shaders and command buffers for performance boosts, leveraging lessons from the MP4 decoder.

### General Setup
1. Add raw WebGPU bindings:
   - Import webgpu.h (from Dawn: https://dawn.googlesource.com/dawn) into Zig
   - Or use wgpu-native (https://github.com/gfx-rs/wgpu-native) if C API is preferred
   - Link with -lwebgpu or equivalent in build.zig

2. Learn WebGPU basics:
   - Study GPUComputePipeline for compute shaders
   - Study GPUCommandEncoder for command buffers

### 3D Tower Defense Game
1. Add compute shaders for particles:
   - Write a WGSL compute shader to update particle positions/velocities
   - Store results in a GPUBuffer
   - Render with Sokol (share buffer via sg_wgpu_buffer()) or raw WebGPU

2. Replace Sokol rendering (if necessary):
   - Use GPUCommandEncoder to record draw commands (e.g., towers, particles)
   - Submit with GPUQueue.submit()
   - Share Sokol's WebGPU device/context for compatibility

3. Test hybrid setup:
   - Sokol for UI/audio, raw WebGPU for 3D/particles
   - Verify FPS improves with compute and command buffers

### MP4 Decoder
1. Enhance with WebGPU compute:
   - Write a compute shader for YUV-to-RGB conversion
   - Output to a GPUTexture, render with Sokol

2. Experiment further:
   - Try GPU-accelerated decoding (e.g., motion compensation) as a stretch goal
   - Compare perf vs. WebCodecs CPU decoding

## Phase 4: Refine and Expand
Goal: Polish both projects, apply WebGPU knowledge across the board.

### 3D Tower Defense Game
1. Finalize features:
   - Add enemy waves, tower upgrades, UI buttons (textured quads + input)
   - Refine generative audio (e.g., pitch shifts for events)

2. Optimize WASM size:
   - Strip unused code (-flto, -Drelease-small)
   - Aim for <100 KB binary

### MP4 Decoder
1. Polish playback:
   - Add play/pause controls (WASM-driven)
   - Test with longer/higher-res MP4s

2. Document WebGPU lessons:
   - Note compute shader tricks for game reuse

## Milestones
- Week 1-2: Sokol + WebGPU prototype running (cube for game, MP4 frame for decoder)
- Week 3-4: Basic game (towers, particles, audio) and decoder (720p playback)
- Month 2: Benchmark Sokol, decide on raw WebGPU needs
- Month 3+: Integrate compute/command buffers if required, polish both projects

## Resources
- Sokol Docs: https://github.com/floooh/sokol
- Sokol-Zig: https://github.com/floooh/sokol-zig
- WebGPU Spec: https://www.w3.org/TR/webgpu/
- WebGPU C API: https://dawn.googlesource.com/dawn
- WebCodecs: https://developer.mozilla.org/en-US/docs/Web/API/WebCodecs_API

---

### Notes
- **Priority**: Start with the game prototype—it's your main project. Use the MP4 decoder as a parallel sandbox to deepen WebGPU skills.
- **Flexibility**: If Sokol's limits hit early (e.g., particle perf), jump to raw WebGPU sooner. The plan adapts to your findings.
- **Next Steps**: Pick one task (e.g., "Render a spinning cube") and go! I can provide Zig code snippets if you hit a snag.

This gives you a clear roadmap to dive into WebGPU with Sokol, scale up as needed, and learn through both projects. Let me know if you want to tweak it further!