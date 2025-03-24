Managing 20+ games manually in a script is prone to error and tedious. Automating the list of repositories to build is the way to go. Since you’re avoiding a database and want to keep things lightweight, both a `games-to-build.json` file and a `.env` file are viable options. Between the two, a JSON file is more flexible and easier to parse in Bash while scaling better for metadata (e.g., repo URL, name, branch). A `.env` file works but is less structured and harder to extend. Let’s break it down and recommend the best approach.

### Recommended Approach: Use `games-to-build.json`
A JSON file (`games-to-build.json`) is the better choice because:
- It’s structured and easy to parse in Bash with `jq` (a lightweight JSON processor that’s widely available and often preinstalled in minimal containers like `nginx:alpine`).
- It scales well if you want to add metadata later (e.g., branch, build flags, or game descriptions).
- It’s human-readable and maintainable.
- It fits your static setup—no need for a database or runtime state management.

#### 1. Format of `games-to-build.json`
Place this file in your container (e.g., `/config/games-to-build.json`). It lists all game repos and their names.

```json
[
    {
        "name": "geo-tower-d",
        "repo_url": "https://github.com/user/geo-tower-d.git"
    },
    {
        "name": "other-game",
        "repo_url": "https://github.com/user/other-game.git"
    }
]
```

- `name`: Used for directory names (`/games/<name>`), hash files, etc.
- `repo_url`: The Git URL to clone/pull from.

You can maintain this file outside the container (e.g., in your project directory) and copy it during the Docker build or mount it via Docker Compose.

#### 2. Update the Bash Script to Use `games-to-build.json`
Modify the `update_games.sh` script to read the JSON file using `jq`. Here’s the updated script:

```bash
#!/bin/bash

# Path to the JSON config file
CONFIG_FILE="/config/games-to-build.json"

# Directories
REPO_DIR="/repos"
GAMES_DIR="/games"
HASH_DIR="/hashes"

# Create directories if they don't exist
mkdir -p "$REPO_DIR" "$GAMES_DIR" "$HASH_DIR"

# Check if jq is installed (needed to parse JSON)
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Installing..."
    apk add jq  # For alpine-based images like nginx:alpine
fi

# Read the JSON file and iterate over each game
REPOS=$(jq -c '.[]' "$CONFIG_FILE")

# Loop through each repo entry
while IFS= read -r repo; do
    REPO_NAME=$(echo "$repo" | jq -r '.name')
    REPO_URL=$(echo "$repo" | jq -r '.repo_url')
    REPO_PATH="$REPO_DIR/$REPO_NAME"
    HASH_FILE="$HASH_DIR/$REPO_NAME.hash"

    echo "Processing $REPO_NAME..."

    # Clone or update the repo
    if [ -d "$REPO_PATH" ]; then
        cd "$REPO_PATH" || exit
        git fetch origin
    else
        git clone "$REPO_URL" "$REPO_PATH"
        cd "$REPO_PATH" || exit
    fi

    # Get the latest commit hash (default branch: main)
    LATEST_HASH=$(git rev-parse origin/main)

    # Read stored hash (if it exists)
    STORED_HASH=""
    if [ -f "$HASH_FILE" ]; then
        STORED_HASH=$(cat "$HASH_FILE")
    fi

    # Compare hashes
    if [ "$LATEST_HASH" != "$STORED_HASH" ]; then
        echo "Repo $REPO_NAME has updates. Building..."
        git pull origin main
        zig build deploy
        mkdir -p "$GAMES_DIR/$REPO_NAME"
        cp -r dist/* "$GAMES_DIR/$REPO_NAME/"
        echo "$LATEST_HASH" > "$HASH_FILE"
    else
        echo "No updates for $REPO_NAME."
    fi

    # Clean up
    rm -rf "$REPO_PATH"
done <<< "$REPOS"
```

#### 3. Dockerfile Adjustments
- Ensure `jq` is installed (already handled in the script above with `apk add jq`).
- Copy the `games-to-build.json` into the container during the build:
  ```dockerfile
  COPY games-to-build.json /config/games-to-build.json
  COPY update_games.sh /scripts/update_games.sh
  RUN chmod +x /scripts/update_games.sh
  CMD ["/scripts/update_games.sh && nginx -g 'daemon off;'"]
  ```
- Alternatively, mount it via Docker Compose to edit it without rebuilding the image:
  ```yaml
  volumes:
    - ./games-to-build.json:/config/games-to-build.json
  ```

#### 4. Benefits of JSON Approach
- **Scalability:** Add new games by appending to the JSON file—no script changes needed.
- **Extensibility:** Add fields like `branch`, `build_args`, or `enabled` later if needed.
- **Maintainability:** Easier to read and edit than a `.env` file with a long list.
- **Error Handling:** `jq` makes parsing robust; you can add checks for missing fields.

#### 5. Downsides
- Requires `jq` (adds ~1MB to the container, negligible for most setups).
- Slightly more complex than a raw list in Bash, but worth it for scalability.

### Alternative: `.env` File with a List
A `.env` file can work but is less flexible. It’s best for simple key-value pairs or a single delimited list, which can get messy with 20+ games.

#### 1. Format of `.env`
```env
GAME_REPOS="https://github.com/user/geo-tower-d.git geo-tower-d,https://github.com/user/other-game.git other-game"
```

#### 2. Update Bash Script to Parse `.env`
```bash
#!/bin/bash

# Load .env file
source /config/.env

# Convert comma-separated list to array
IFS=',' read -ra REPOS <<< "$GAME_REPOS"

# Directories
REPO_DIR="/repos"
GAMES_DIR="/games"
HASH_DIR="/hashes"

mkdir -p "$REPO_DIR" "$GAMES_DIR" "$HASH_DIR"

# Loop through each repo
for repo in "${REPOS[@]}"; do
    REPO_URL=$(echo "$repo" | cut -d' ' -f1)
    REPO_NAME=$(echo "$repo" | cut -d' ' -f2)
    REPO_PATH="$REPO_DIR/$REPO_NAME"
    HASH_FILE="$HASH_DIR/$REPO_NAME.hash"

    echo "Processing $REPO_NAME..."

    # Same logic as before: clone/fetch, compare hashes, build, cleanup
    if [ -d "$REPO_PATH" ]; then
        cd "$REPO_PATH" || exit
        git fetch origin
    else
        git clone "$REPO_URL" "$REPO_PATH"
        cd "$REPO_PATH" || exit
    fi

    LATEST_HASH=$(git rev-parse origin/main)
    STORED_HASH=""
    if [ -f "$HASH_FILE" ]; then
        STORED_HASH=$(cat "$HASH_FILE")
    fi

    if [ "$LATEST_HASH" != "$STORED_HASH" ]; then
        echo "Repo $REPO_NAME has updates. Building..."
        git pull origin main
        zig build deploy
        mkdir -p "$GAMES_DIR/$REPO_NAME"
        cp -r dist/* "$GAMES_DIR/$REPO_NAME/"
        echo "$LATEST_HASH" > "$HASH_FILE"
    else
        echo "No updates for $REPO_NAME."
    fi

    rm -rf "$REPO_PATH"
done
```

#### 3. Dockerfile/Compose for `.env`
- Copy or mount the `.env` file:
  ```dockerfile
  COPY .env /config/.env
  ```
  Or in Docker Compose:
  ```yaml
  volumes:
    - ./.env:/config/.env
  ```

#### 4. Downsides of `.env`
- Harder to manage with many entries—long comma-separated string gets unwieldy.
- No structure for metadata (e.g., branch, flags).
- Parsing in Bash (`cut`, `IFS`) is more error-prone than JSON with `jq`.

### Final Recommendation
Use `games-to-build.json` with `jq` in Bash. It’s more maintainable, scalable, and easier to extend than a `.env` file. The overhead of installing `jq` is minimal, and it’s a standard tool for JSON parsing. Maintain the JSON file outside the container (e.g., in your project repo) and mount it via Docker Compose for easy updates:
```yaml
services:
  games:
    image: my-games:latest
    build: .
    volumes:
      - ./games-to-build.json:/config/games-to-build.json
    labels:
      - "traefik.http.routers.games.rule=Host(`games.mydomain.com`)"
      - "traefik.http.routers.games.entrypoints=web"
```

This keeps your setup clean and lets you add/remove games by editing the JSON file without touching the script or rebuilding the image. If you need help with the JSON schema or script tweaks, let me know!

------------------
should this be the same games.json to build the homepage?