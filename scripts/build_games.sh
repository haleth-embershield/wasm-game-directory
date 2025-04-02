#!/bin/bash
set -e

# Configuration
CONFIG_FILE=${1:-"/config/games.json"}
REPO_DIR="/tmp/repos"
GAMES_DIR="/games"
HASH_DIR="/hashes"
WEB_DIR="/usr/share/nginx/html"

# Create directories if they don't exist
mkdir -p "$REPO_DIR" "$GAMES_DIR" "$HASH_DIR"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

echo "Starting game build process using config: $CONFIG_FILE"
echo "Build environment includes: Zig, Bun, Node.js, npm"

# Function to generate simple HTML for a game
generate_game_html() {
    local game_name=$1
    local game_desc=$2
    local game_tags=$3
    
    # Create game directory if it doesn't exist
    mkdir -p "$GAME_PATH"
    
    # Only generate info.html, not index.html (to preserve game's original index.html)
    mkdir -p "$GAME_PATH/info"
    cat > "$GAME_PATH/info/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${game_name} - Info</title>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body>
    <header>
        <nav>
            <a href="/">Home</a>
            <a href="/${game_name}">Play</a>
        </nav>
    </header>
    <main class="info-container">
        <h1>${game_name}</h1>
        <p class="description">${game_desc}</p>
        <div class="tags">
            ${game_tags}
        </div>
    </main>
</body>
</html>
EOF
}

# Function to generate homepage HTML
generate_homepage() {
    echo "Generating homepage..."
    
    # Start the HTML structure
    cat > "$WEB_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WASM Game Directory</title>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body>
    <header>
        <h1>WASM Game Directory</h1>
    </header>
    <main>
        <div class="game-grid">
EOF
    
    # Read games.json and generate game grid items
    jq -c '.[]' "$CONFIG_FILE" | while read -r game; do
        game_name=$(echo "$game" | jq -r '.name')
        game_desc=$(echo "$game" | jq -r '.description')
        
        # Always use default placeholder image since thumbnail generation is disabled
        game_thumb="/static/default-thumb.png"
        
        # Add game to grid
        cat >> "$WEB_DIR/index.html" << EOF
            <div class="game-card">
                <a href="/${game_name}">
                    <div class="game-thumb">
                        <img src="${game_thumb}" alt="${game_name}">
                    </div>
                    <div class="game-info">
                        <h2>${game_name}</h2>
                        <p>${game_desc}</p>
                    </div>
                </a>
                <a href="/${game_name}/info" class="info-link">Info</a>
            </div>
EOF
    done
    
    # Close the HTML structure
    cat >> "$WEB_DIR/index.html" << EOF
        </div>
    </main>
    <footer>
        <p>Powered by Zig + WebAssembly</p>
    </footer>
</body>
</html>
EOF
}

# Create basic CSS if it doesn't exist
if [ ! -f "$WEB_DIR/static/style.css" ]; then
    mkdir -p "$WEB_DIR/static"
    cat > "$WEB_DIR/static/style.css" << EOF
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: Arial, sans-serif;
    line-height: 1.6;
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

header {
    margin-bottom: 20px;
}

nav {
    display: flex;
    gap: 20px;
}

.game-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 20px;
}

.game-card {
    border: 1px solid #ddd;
    border-radius: 5px;
    overflow: hidden;
    transition: transform 0.3s ease;
}

.game-card:hover {
    transform: translateY(-5px);
}

.game-thumb img {
    width: 100%;
    height: 150px;
    object-fit: cover;
}

.game-info {
    padding: 15px;
}

.info-link {
    display: block;
    text-align: center;
    background: #f0f0f0;
    padding: 5px;
    text-decoration: none;
    color: #333;
}

.game-container {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 80vh;
}

footer {
    margin-top: 40px;
    text-align: center;
    color: #666;
}
EOF
fi

# Create default thumbnail if it doesn't exist
if [ ! -f "$WEB_DIR/static/default-thumb.png" ]; then
    mkdir -p "$WEB_DIR/static"
    # Create a simple default thumbnail using base64-encoded 1x1 transparent PNG
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" | base64 -d > "$WEB_DIR/static/default-thumb.png"
    echo "Created default thumbnail placeholder"
fi

# Process each game in the JSON file
jq -c '.[]' "$CONFIG_FILE" | while read -r game; do
    GAME_NAME=$(echo "$game" | jq -r '.name')
    REPO_URL=$(echo "$game" | jq -r '.repo_url')
    GAME_DESC=$(echo "$game" | jq -r '.description')
    BUILD_CMD=$(echo "$game" | jq -r '.build_command')
    
    # Process tags into HTML
    TAGS_JSON=$(echo "$game" | jq -r '.tags | join(" ")')
    GAME_TAGS=""
    for tag in $TAGS_JSON; do
        GAME_TAGS+="<span class=\"tag\">$tag</span> "
    done
    
    REPO_PATH="$REPO_DIR/$GAME_NAME"
    HASH_FILE="$HASH_DIR/$GAME_NAME.hash"
    GAME_PATH="$GAMES_DIR/$GAME_NAME"
    
    echo "Processing $GAME_NAME..."
    
    # Create game directory if it doesn't exist
    mkdir -p "$GAME_PATH"
    
    # Clone or update the repo
    if [ -d "$REPO_PATH" ]; then
        echo "Repository already exists, fetching updates..."
        cd "$REPO_PATH"
        git fetch origin
    else
        echo "Cloning repository..."
        git clone "$REPO_URL" "$REPO_PATH"
        cd "$REPO_PATH"
    fi
    
    # Get the latest commit hash
    LATEST_HASH=$(git rev-parse HEAD)
    echo "Latest commit hash: $LATEST_HASH"
    
    # Read stored hash if it exists
    STORED_HASH=""
    if [ -f "$HASH_FILE" ]; then
        STORED_HASH=$(cat "$HASH_FILE")
        echo "Stored hash: $STORED_HASH"
    else
        echo "No stored hash found."
    fi
    
    # Compare hashes to determine if rebuild is needed
    if [ "$LATEST_HASH" != "$STORED_HASH" ]; then
        echo "Changes detected. Building $GAME_NAME..."
        
        # Pull latest code and build
        git pull origin
        eval "$BUILD_CMD"
        
        # Copy build artifacts to game directory
        if [ -d "dist" ]; then
            echo "Copying build artifacts..."
            cp -r dist/* "$GAME_PATH/"
        else
            echo "Warning: 'dist' directory not found after build."
        fi
        
        # Save the new hash
        echo "$LATEST_HASH" > "$HASH_FILE"
        
        # Generate HTML files for the game
        generate_game_html "$GAME_NAME" "$GAME_DESC" "$GAME_TAGS"
    else
        echo "No changes detected for $GAME_NAME. Skipping build."
    fi
    
    # Link game assets to web directory
    echo "Linking game assets to web directory..."
    
    # Create parent directory if it doesn't exist
    mkdir -p "$WEB_DIR"
    
    # Remove existing symlink or directory
    if [ -e "$WEB_DIR/$GAME_NAME" ]; then
        rm -rf "$WEB_DIR/$GAME_NAME"
    fi
    
    # Create a symlink of the entire directory instead of individual files
    ln -sf "$GAME_PATH" "$WEB_DIR/$GAME_NAME"
    echo "Created symlink from $GAME_PATH to $WEB_DIR/$GAME_NAME"
    
    # Clean up repo to save space
    cd /
    rm -rf "$REPO_PATH"
done

# Generate thumbnails for all games (if enabled)
GENERATE_THUMBNAILS=${GENERATE_THUMBNAILS:-false}
# if [ "$GENERATE_THUMBNAILS" = "true" ]; then
#     echo "Starting thumbnail generation in background..."
#     if [ -f "/scripts/thumbnail_generator.sh" ]; then
#         # Run thumbnail generator in background
#         /scripts/thumbnail_generator.sh "$GAMES_DIR" "$WEB_DIR" "200x150" &
#         echo "Thumbnail generation running in background with PID $!"
#     else
#         echo "Warning: thumbnail_generator.sh not found. Trying alternative generators..."
#         # Try puppeteer version as fallback
#         if [ -f "/scripts/thumbnail_generator_puppeteer.sh" ]; then
#             /scripts/thumbnail_generator_puppeteer.sh "$GAMES_DIR" "$WEB_DIR" "200x150" &
#             echo "Puppeteer thumbnail generation running in background with PID $!"
#         else
#             echo "Error: No thumbnail generator found. Thumbnails will not be generated."
#         fi
#     fi
# else
#     echo "Thumbnail generation disabled by GENERATE_THUMBNAILS=$GENERATE_THUMBNAILS"
# fi
echo "Thumbnail generation disabled"

# Generate the homepage
generate_homepage

echo "Build process completed successfully." 