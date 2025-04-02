# wasm-game-directory fr

A static site to host multiple WASM games built with Zig, with a simple build and deployment pipeline.

## Core Design
- Single container with Zig and Nginx
- Bash scripts for initial implementation, with Go/Zig versions planned for comparison
- Static HTML/CSS/JS with no server-side interactivity
- Each game is a separate Zig project targeting WASM freestanding
- Automatic thumbnail generation using Bun + Puppeteer

## Current Build Dependencies
- Zig (for building games)
- Bun (for games that need JavaScript bundling and thumbnail generation)
- Nginx (for serving static files)
- Chromium (headless browser for thumbnail capture)

## Features
- Build system to pull, build, and deploy Zig WASM games
- Game grid homepage with generated thumbnails
- Minimal templates for game pages and info pages
- Automated thumbnail generation from game screenshots

## How Thumbnail Generation Works
The system automatically generates thumbnails for each game by:
1. Loading each game in a headless Chromium browser via Puppeteer
2. Taking a screenshot of the first frame/screen
3. Resizing to a standard thumbnail size (200x150px by default)
4. Including these thumbnails in the game directory homepage

## Container Size Concerns
The current Docker container has grown significantly in size due to the inclusion of:
- Thumbnail generation dependencies (Chromium, Mesa, etc.)
- Multiple build systems (Zig, Bun, Emscripten)
- Various development tools

Possible solutions to consider:
1. **Split into multiple containers**:
   - Main container for game serving (Nginx + minimal dependencies)
   - Build container for game compilation (Zig, Emscripten)
   - Utility container for thumbnail generation (Puppeteer, Chromium)

2. **Feature flags during build**:
   - Allow building container with/without thumbnail generation
   - Provide option to exclude certain build tools if not needed

3. **External thumbnail generation**:
   - Move thumbnail generation to CI/CD pipeline
   - Pre-generate thumbnails before deployment

This will be addressed in upcoming optimizations to improve deployment efficiency.

TODO:
- the hashes dont seem to save between build (volumes created but not seen?) so we need to test the hash creation so we are not rebuilding every time
- Implement tag-based filtering on the homepage
- Add game previews on hover using minimal JavaScript
- Develop a solution to inject consistent header/footer elements into game HTML files without replacing them

LATER:
- Reimplement build system in Go/Zig for performance comparison
- Use templates to provide consistent navigation and styling
- Reimplement thumbnail generator in Zig using native tools

LATERER:
- Consider HTMX for enhanced client-side features without full frameworks

## Future Dependency Management Options
Consider one of these approaches for future development:

1. **Game-specific Dependencies in games.json**:
   - Add `dependencies` field to games.json entries
   - Container includes all possible dependencies
   - Each game specifies which ones it needs

2. **Self-contained Game Repos**:
   - Each repo handles its own dependencies during build
   - Downloaded/installed in temporary build directory
   - Cleaner container, but potentially slower builds

3. **Standardized Template**:
   - Require all games to follow a strict template
   - No external build dependencies allowed
   - Most efficient but least flexible option

For now, the container includes common dependencies (Zig and Bun) that games might need.