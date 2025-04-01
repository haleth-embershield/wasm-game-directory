# wasm-game-directory

A static site to host multiple WASM games built with Zig, with a simple build and deployment pipeline.

## Core Design
- Single container with Zig and Nginx
- Bash scripts for initial implementation, with Go/Zig versions planned for comparison
- Static HTML/CSS/JS with no server-side interactivity
- Each game is a separate Zig project targeting WASM freestanding

## Current Build Dependencies
- Zig (for building games)
- Bun (for games that need JavaScript bundling)
- Nginx (for serving static files)

TODO:
- Build Bash script to pull, build, and deploy Zig WASM games
- Implement game grid homepage with thumbnails
- Create minimal templates for game pages and info pages

LATER:
- Reimplement build system in Go/Zig for performance comparison
- Use templates to provide consistent navigation and styling
- Implement tag-based filtering on the homepage
- Add game previews on hover using minimal JavaScript

LATERER:
- Consider HTMX for enhanced client-side features without full frameworks
- Automate thumbnail/preview generation

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