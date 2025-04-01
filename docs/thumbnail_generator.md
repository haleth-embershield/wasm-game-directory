# Thumbnail Generation TODO

This document outlines the steps to automatically generate thumbnails for WebAssembly games built with Zig. The initial solution uses Node.js (or Bun) for simplicity, with a stretch goal to transition to a native Zig implementation later.

---

## Part 1: Simplest Node.js/Bun Setup

### What
Generate thumbnails of the first screen of each WebAssembly game by:
- Running the game’s `/dist/index.html` in a headless browser.
- Capturing a screenshot.
- Resizing it to a thumbnail (e.g., 200x150px).
- Integrating this into the Zig build process.

### Tools
- **Bun** (preferred for speed) or **Node.js**: Runtime for JavaScript.
- **Puppeteer**: Headless browser automation to load and screenshot the game.
- **Sharp**: Fast image resizing library.

### Setup Steps

#### 1. Install Bun (or Node.js)
- **Bun**: Install globally:
  ```bash
  curl -fsSL https://bun.sh/install | bash
  ```
- **Node.js** (alternative): Download from [nodejs.org](https://nodejs.org/) or use a package manager (`nvm`, `brew`, etc.).
- Verify: `bun --version` or `node --version`.

#### 2. Initialize Project
- In your project root (where `games/` lives):
  ```bash
  bun init -y  # or npm init -y for Node.js
  bun add puppeteer sharp  # or npm install puppeteer sharp
  ```

#### 3. Create Thumbnail Script
- File: `generate-thumbnails.js`
- Content:
  ```javascript
  const puppeteer = require('puppeteer');
  const fs = require('fs');
  const path = require('path');
  const sharp = require('sharp');

  async function generateThumbnail(gameDir, outputDir, width = 200, height = 150) {
      const browser = await puppeteer.launch({ headless: 'new' });
      const page = await browser.newPage();
      await page.setViewport({ width: 1280, height: 720 });

      const gamePath = path.join(gameDir, 'dist', 'index.html');
      await page.goto(`file://${path.resolve(gamePath)}`, { waitUntil: 'networkidle0' });
      await page.waitForTimeout(1000); // Adjust if games load slower

      const screenshotPath = path.join(outputDir, `${path.basename(gameDir)}.png`);
      await page.screenshot({ path: screenshotPath });

      await sharp(screenshotPath)
          .resize(width, height)
          .toFile(path.join(outputDir, `${path.basename(gameDir)}-thumb.png`));

      await browser.close();
  }

  async function main() {
      const gamesRoot = './games';
      const outputDir = './thumbnails';
      if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir);

      const gameDirs = fs.readdirSync(gamesRoot).filter(dir =>
          fs.existsSync(path.join(gamesRoot, dir, 'dist', 'index.html'))
      );

      for (const dir of gameDirs) {
          console.log(`Generating thumbnail for ${dir}`);
          await generateThumbnail(path.join(gamesRoot, dir), outputDir);
      }
  }

  main().catch(err => {
      console.error(err);
      process.exit(1);
  });
  ```
- Notes:
  - Adjust `gamesRoot` to match your directory structure.
  - Tweak `waitForTimeout` if your games need more/less time to render.

#### 4. Update Zig Build
- File: `build.zig` (root-level, assuming it builds all games)
- Content:
  ```zig
  const std = @import("std");

  pub fn build(b: *std.Build) void {
      const games = [_][]const u8{ "game1", "game2" }; // List your games
      var last_step: *std.Build.Step = b.default_step;

      for (games) |game| {
          const exe = b.addExecutable(.{
              .name = game,
              .root_source_file = .{ .path = b.fmt("games/{s}/src/main.zig", .{game}) },
              .target = .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
              .optimize = .ReleaseSmall,
          });
          const install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = b.fmt("games/{s}/dist", .{game}) } } });
          last_step.dependOn(&install.step);
          last_step = &install.step;
      }

      const thumbnail_step = b.addSystemCommand(&[_][]const u8{
          "bun", // or "node"
          "generate-thumbnails.js",
      });
      thumbnail_step.step.dependOn(last_step);
      b.default_step.dependOn(&thumbnail_step.step);
  }
  ```
- Notes:
  - Replace `"bun"` with `"node"` if using Node.js.
  - Ensure paths match your game sources and output (`dist`).

#### 5. Run It
- Build and generate thumbnails:
  ```bash
  zig build
  ```
- Check `./thumbnails/` for `game1-thumb.png`, `game2-thumb.png`, etc.

#### 6. Verify
- Open thumbnails to ensure they capture the first screen correctly.
- Adjust `waitForTimeout` or viewport size if needed.

---

## Part 2: Stretch Goal - Native Zig Solution

### What
Replace Node.js/Bun with a pure Zig solution to:
- Run WebAssembly games natively.
- Capture the first rendered frame.
- Resize it into a thumbnail.

### Challenges
- **WebAssembly Execution**: Zig lacks a built-in browser-like environment to run WASM and render to a canvas.
- **Rendering**: Need to access pixel data from the WASM game’s canvas or WebGL context.
- **Image Processing**: Requires a Zig library to manipulate and resize images.

### Steps to Explore

#### 1. WebAssembly Runtime
- Use **Wasmtime** or **Wasmer** (via Zig bindings) to execute the WASM module.
- TODO: Find or create Zig bindings for Wasmtime/Wasmer.
- Load the game’s `.wasm` file from `/dist`.

#### 2. Rendering Context
- Simulate a browser environment:
  - Integrate a lightweight WebGL library (e.g., `zgl`) or a headless browser engine (e.g., WebKit via `webkitgtk` bindings).
  - TODO: Research Zig-compatible WebGL or canvas libraries.
- Capture the first frame’s pixel data (e.g., from WebGL buffer).

#### 3. Image Processing
- Use **zigimg** (https://github.com/zigimg/zigimg):
  - Convert raw pixel data to an image format (e.g., PNG).
  - Resize to thumbnail dimensions.
- TODO: Integrate zigimg into the build process.

#### 4. Build Integration
- Modify `build.zig` to:
  - Run the WASM module.
  - Capture the frame.
  - Output thumbnails.
- TODO: Prototype a single-game thumbnail generator in Zig.

### Milestones
1. **Proof of Concept**: Run a WASM game in Zig using Wasmtime and log output.
2. **Rendering**: Get pixel data from a simple WASM canvas app.
3. **Thumbnail**: Resize and save the pixel data with zigimg.
4. **Automation**: Hook into the build process for all games.

### Notes
- This is a significant undertaking due to the lack of mature Zig libraries for browser-like WASM execution.
- Start with a minimal test case (e.g., a WASM app drawing a square) before scaling to full games.
- Consider contributing Zig bindings to open-source projects (e.g., Wasmtime) if none exist.

---

## Next Steps
- Implement the Bun/Node.js solution now for immediate results.
- Experiment with Zig + Wasmtime in parallel as a long-term goal.
- Document findings and iterate on the native solution as Zig ecosystem matures.
```

### Notes
- **Bun vs. Node.js**: Bun is faster and lighter, so it’s prioritized here. The setup is nearly identical for Node.js—just swap `bun` for `node`.
- **Zig Stretch Goal**: It’s ambitious and depends on external library support. I’ve kept it high-level since it’s a future task.
- **Structure**: The file assumes a `games/` folder with subdirectories (`game1/`, `game2/`) containing `src/` and `dist/`. Adjust paths as needed.