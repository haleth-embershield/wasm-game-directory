# Docker Setup Guide

This document explains how to run the WASM Game Directory using Docker Compose.

## Prerequisites

- Docker and Docker Compose installed on your system
- Git (to clone the repository)

## Getting Started

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/wasm-game-directory.git
   cd wasm-game-directory
   ```

2. Edit `games.json` to include your game repositories:
   ```json
   [
     {
       "name": "game-name",
       "repo_url": "https://github.com/username/game-repo.git",
       "description": "A short description of the game",
       "tags": ["arcade", "puzzle"],
       "thumbnail": "thumbnail.png",
       "build_command": "zig build deploy"
     }
   ]
   ```

3. Start the container:
   ```bash
   docker compose up -d
   ```

4. Access your games at: `http://localhost/`

## Configuration Options

### Environment Variables

You can customize the behavior by adjusting these variables in `docker-compose.yml`:

- `REBUILD_FREQUENCY`: How often (in hours) to check repositories for updates (default: 6)
- `TZ`: Timezone for cron jobs (default: UTC)

### Docker Compose Configuration

The `docker-compose.yml` defines:

1. **Persistent Volumes**:
   - `games_data`: Stores built games
   - `hash_data`: Keeps hash files for rebuild checking

2. **Port Mapping**:
   - Maps container port 80 to host port 80

3. **File Mounts**:
   - `./games.json:/config/games.json`: Game repository configuration

## Maintenance

### Viewing Logs

```bash
docker compose logs -f
```

### Rebuilding Games Manually

```bash
docker compose exec wasm-games /scripts/build_games.sh /config/games.json
```

### Restarting the Service

```bash
docker compose restart
```

### Updating the Container

After making changes to Dockerfile or scripts:

```bash
docker compose down
docker compose build
docker compose up -d
```

## Troubleshooting

- **Game doesn't appear**: Check the container logs for build errors
- **Game doesn't update**: Delete the hash file to force a rebuild
  ```bash
  docker compose exec wasm-games rm /hashes/game-name.hash
  ```

## Advanced Configuration

### Custom Nginx Configuration

To customize the Nginx configuration:

1. Edit `nginx/nginx.conf`
2. Restart the container:
   ```bash
   docker compose restart
   ```

### Custom Build Scripts

To modify the build process:

1. Edit files in the `scripts/` directory
2. Rebuild and restart:
   ```bash
   docker compose down
   docker compose build
   docker compose up -d
   ```
``` 