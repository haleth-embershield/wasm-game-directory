# wasm-game-directory

A static site to host multiple WASM games built with Zig, with a simple build and deployment pipeline.

## Core Design
- Single container with Zig and Nginx
- Bash scripts for initial implementation, with Go/Zig versions planned for comparison
- Static HTML/CSS/JS with no server-side interactivity
- Each game is a separate Zig project targeting WASM freestanding

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