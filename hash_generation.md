You can absolutely do the hash check with either Bash or Zig, since you’re already using them in your setup (Bash for scripting, Zig for building games). No extra languages needed. Bash is simpler for this task since it’s already part of your container’s environment (e.g., in `nginx:alpine`) and can handle Git operations and file hashing directly. Zig could work too but would require writing a small program, which is overkill for this. Let’s go with Bash since it’s more straightforward.

### Goal
Check if a game repository has been updated by comparing its current Git commit hash with a stored hash. If different, pull and rebuild the game.

### Bash Implementation
Here’s how you can do the hash check in a Bash script during container startup:

#### 1. Directory Setup
Assume the following:
- `/repos/` for temporary cloning of game repos.
- `/games/` for final built assets (`/games/<game-name>/` contains `.wasm`, etc.).
- `/hashes/` to store commit hashes (`/hashes/<game-name>.hash`).

#### 2. Bash Script (`update_games.sh`)
This script checks each repository, compares hashes, and updates if needed.

```bash
#!/bin/bash

# List of game repos (replace with your actual repos)
REPOS=(
    "https://github.com/user/game1.git game1"
    "https://github.com/user/game2.git game2"
)

# Directories
REPO_DIR="/repos"
GAMES_DIR="/games"
HASH_DIR="/hashes"

# Create directories if they don't exist
mkdir -p "$REPO_DIR" "$GAMES_DIR" "$HASH_DIR"

# Loop through each repo
for repo in "${REPOS[@]}"; do
    REPO_URL=$(echo "$repo" | cut -d' ' -f1)
    REPO_NAME=$(echo "$repo" | cut -d' ' -f2)
    REPO_PATH="$REPO_DIR/$REPO_NAME"
    HASH_FILE="$HASH_DIR/$REPO_NAME.hash"

    echo "Processing $REPO_NAME..."

    # Clone or update the repo
    if [ -d "$REPO_PATH" ]; then
        # Repo exists, fetch updates
        cd "$REPO_PATH" || exit
        git fetch origin
    else
        # Clone fresh
        git clone "$REPO_URL" "$REPO_PATH"
        cd "$REPO_PATH" || exit
    fi

    # Get the latest commit hash from the default branch (e.g., main)
    LATEST_HASH=$(git rev-parse origin/main)

    # Read stored hash (if it exists)
    STORED_HASH=""
    if [ -f "$HASH_FILE" ]; then
        STORED_HASH=$(cat "$HASH_FILE")
    fi

    # Compare hashes
    if [ "$LATEST_HASH" != "$STORED_HASH" ]; then
        echo "Repo $REPO_NAME has updates. Building..."

        # Pull the latest changes
        git pull origin main

        # Build the game
        zig build deploy

        # Copy built assets to /games/<game-name>/
        mkdir -p "$GAMES_DIR/$REPO_NAME"
        cp -r dist/* "$GAMES_DIR/$REPO_NAME/"

        # Store the new hash
        echo "$LATEST_HASH" > "$HASH_FILE"
    else
        echo "No updates for $REPO_NAME."
    fi

    # Clean up: Remove temp repo to save space
    rm -rf "$REPO_PATH"
done
```

#### 3. Explanation of Key Steps
- **Fetch Commit Hash:** `git rev-parse origin/main` gets the latest commit hash of the default branch (`main` here—adjust if your branch differs).
- **Compare Hashes:** Simple string comparison (`!=`) checks if the repo has updated.
- **Build and Deploy:** If hashes differ, `git pull`, run `zig build deploy`, and copy the `dist/` contents to `/games/<game-name>/`.
- **Store Hash:** Save the new hash to `/hashes/<game-name>.hash` for next time.
- **Cleanup:** Remove the temporary repo (`/repos/<game-name>`) to keep the container small.

#### 4. Integrate into Container
- Add the script to your container (e.g., `/scripts/update_games.sh`).
- Make it executable: `chmod +x /scripts/update_games.sh`.
- Run it during container startup (in your Dockerfile or entrypoint):
  ```dockerfile
  COPY update_games.sh /scripts/update_games.sh
  RUN chmod +x /scripts/update_games.sh
  CMD ["/scripts/update_games.sh && nginx -g 'daemon off;'"]
  ```
- Ensure `git` and `zig` are installed in your container (you likely already have this since you’re using Zig for building):
  ```dockerfile
  RUN apk add git  # For alpine-based images like nginx:alpine
  # Zig should already be installed if you're building games
  ```

### Why Bash Over Zig for This?
- **Simplicity:** Bash is built for scripting tasks like this—Git commands, file operations, and string comparisons are native and easy.
- **No Compilation:** A Zig program would need to be written, compiled, and maintained, adding unnecessary complexity for a simple task.
- **Dependencies:** Bash is already in your container; no extra installs needed beyond `git`.

### Downsides of Bash Approach
- **Error Handling:** Bash isn’t great at complex error handling. If `git pull` or `zig build` fails, you’ll need basic checks (e.g., `|| exit`) or logging.
- **Scalability:** If you have dozens of repos, Bash might feel clunky—though still workable for a home server setup.

### Zig Alternative (If You Prefer)
You *could* write a Zig program to do this, but it’s overkill. It would involve:
- Using Zig’s standard library to run Git commands (`std.ChildProcess`).
- Reading/writing files for hashes.
- Compiling the program into your container.
It works but adds complexity for no real gain over Bash here.

### Final Answer
Use Bash—it’s simpler, requires no extra languages, and fits your setup. The script above handles hash checks, updates, and cleanup efficiently. If you need tweaks (e.g., better error handling or logging), let me know!