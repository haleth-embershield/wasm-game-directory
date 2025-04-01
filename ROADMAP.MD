# Implementation Roadmap

## Implementation Strategy
1. Start with Bash implementation for simplicity
2. Later implement in Go for concurrency and performance comparison
3. Evaluate potential pure Zig implementation

## 1. Project Structure
- `/scripts/` - Bash scripts for building games
- `/web/` - Static web assets and templates
- `/nginx/` - Nginx configuration
- `/games/` - Output directory for built games
- `/hashes/` - Storage for build hashes

## 2. Data Management
- Use `games.json` as the single source of truth:
  ```json
  [
    {
      "name": "game-name",
      "repo_url": "https://github.com/user/repo.git",
      "description": "Short game description",
      "tags": ["puzzle", "action"],
      "thumbnail": "thumbnail.png",
      "build_command": "zig build deploy"
    }
  ]
  ```
- No database required - all data stored in static files
- Game state handled client-side by individual games if needed

## 3. Dependency Management
- Current approach: Include common dependencies (Zig, Bun) in the container
- Future options to explore:
  1. **Extended games.json**:
      ```json
      {
        "name": "game-name",
        "repo_url": "...",
        "dependencies": ["bun", "rust", "ffmpeg"]
      }
      ```
  2. **Self-contained repos**: Games manage their own dependencies
  3. **Standardized build template**: All games follow the same pattern

## 4. Bash Implementation (Phase 1)
- Create a Bash script to handle:
  - Parsing `games.json` with jq
  - Cloning/pulling game repositories
  - Building games with Zig targeting WASM
  - Basic templating for HTML pages
  - Tracking build hashes to detect changes
- Run via cron for periodic builds

## 5. Build Process
1. Read `games.json` for game metadata
2. For each game:
   - Clone repo to temp directory
   - Compare hash with previous build
   - If changed or new:
     - Run Zig build
     - Copy assets to `/games/{game-name}/`
     - Generate HTML pages from templates
     - Store new hash
   - Clean up temp files
3. Generate homepage with game grid

## 6. Go/Zig Implementation (Phase 2)
- Reimplement the build system in Go/Zig for comparison:
  - Concurrent builds with goroutines/threads
  - Better error handling
  - More sophisticated templating
  - Performance benchmarking against Bash version

## 7. Web Structure
- Static site with simple URL scheme:
  - `games.mydomain.com/` - Homepage with game grid
  - `games.mydomain.com/{game-name}/` - Game page
  - `games.mydomain.com/{game-name}/info/` - Game info page
- Minimal templates for consistent layout:
  - `base.html` - Base template with header/footer
  - `game.html` - Template for game pages
  - `info.html` - Template for game info pages
  - `home.html` - Template for homepage grid

## 8. Frontend Features (All Static)
- Homepage grid with game thumbnails
- Game cards with name, thumbnail, and description
- Tag-based filtering using client-side JavaScript
- Game preview on hover (optional, client-side only)
- Simple navigation between games
- No server-side processing required

## 9. Deployment
- Single Docker container with:
  - Zig for building
  - Bash/Go/Zig scripts for automation
  - Nginx for serving static files
  - Cron for scheduling rebuilds
- Optimized Nginx config for WASM files
- Volume mount for persistent hashes and built games