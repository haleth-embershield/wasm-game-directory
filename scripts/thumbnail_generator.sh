#!/bin/bash
set -e

# Thumbnail Generator for WASM Game Directory
# Uses Bun + Puppeteer to generate thumbnails from game screens
# TODO: Future version will use Zig natively

GAMES_DIR=${1:-"/games"}
WEB_DIR=${2:-"/usr/share/nginx/html"}
THUMB_SIZE=${3:-"200x150"}

echo "Starting thumbnail generation for games in $GAMES_DIR"

# Extract width and height from THUMB_SIZE
WIDTH=$(echo $THUMB_SIZE | cut -d'x' -f1)
HEIGHT=$(echo $THUMB_SIZE | cut -d'x' -f2)

# Create temp dir for the Node.js/Bun project
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# Initialize Bun project and install dependencies
echo "Installing dependencies..."
bun init -y
bun add puppeteer sharp

# Create the thumbnail generation script
cat > generate-thumbnails.js << 'EOF'
const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

async function generateThumbnail(gameDir, outputDir, width = 200, height = 150) {
    console.log(`Processing ${gameDir}...`);
    
    // Check if game has index.html
    const gamePath = path.join(gameDir, 'index.html');
    if (!fs.existsSync(gamePath)) {
        console.log(`Skipping ${gameDir}: No index.html found`);
        return;
    }
    
    // Launch browser
    const browser = await puppeteer.launch({ 
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox'] 
    });
    
    try {
        const page = await browser.newPage();
        await page.setViewport({ width: 1280, height: 720 });

        // Load the game
        console.log(`Loading ${gamePath}`);
        await page.goto(`file://${path.resolve(gamePath)}`, { 
            waitUntil: 'networkidle0',
            timeout: 30000
        });
        
        // Wait for rendering
        await page.waitForTimeout(2000);

        // Take screenshot
        const thumbPath = path.join(outputDir, `thumbnail.png`);
        console.log(`Capturing screenshot to ${thumbPath}`);
        await page.screenshot({ path: thumbPath });

        // Resize to thumbnail
        await sharp(thumbPath)
            .resize(width, height)
            .toFile(path.join(outputDir, `thumbnail-${width}x${height}.png`));
            
        console.log(`Generated thumbnail for ${gameDir}`);
    } catch (error) {
        console.error(`Error generating thumbnail for ${gameDir}:`, error);
    } finally {
        await browser.close();
    }
}

async function main() {
    const gamesDir = process.argv[2] || '.';
    const width = parseInt(process.argv[3]) || 200;
    const height = parseInt(process.argv[4]) || 150;

    const gameDirs = fs.readdirSync(gamesDir)
        .filter(item => fs.statSync(path.join(gamesDir, item)).isDirectory());

    console.log(`Found ${gameDirs.length} potential game directories`);
    
    for (const dir of gameDirs) {
        const gamePath = path.join(gamesDir, dir);
        const outputDir = gamePath; // Save thumbnail in the game's directory
        
        // Create output dir if it doesn't exist
        if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
        }
        
        await generateThumbnail(gamePath, outputDir, width, height);
    }
}

main().catch(err => {
    console.error('Thumbnail generation failed:', err);
    process.exit(1);
});
EOF

# Run the script with our parameters
echo "Generating thumbnails..."
bun generate-thumbnails.js "$GAMES_DIR" "$WIDTH" "$HEIGHT"

# Copy thumbnails to web directories
echo "Copying thumbnails to web directories..."
for GAME_DIR in "$GAMES_DIR"/*; do
    if [ -d "$GAME_DIR" ]; then
        GAME_NAME=$(basename "$GAME_DIR")
        
        # Copy thumbnails if they exist
        if [ -f "$GAME_DIR/thumbnail-${WIDTH}x${HEIGHT}.png" ]; then
            mkdir -p "$WEB_DIR/$GAME_NAME"
            cp "$GAME_DIR/thumbnail-${WIDTH}x${HEIGHT}.png" "$WEB_DIR/$GAME_NAME/thumbnail.png"
            echo "Added thumbnail for $GAME_NAME"
        fi
    fi
done

# Clean up
rm -rf "$TEMP_DIR"

echo "Thumbnail generation complete!"

# TODO: Future Zig-based implementation
# The future Zig implementation would:
# 1. Use Wasmtime or Wasmer via Zig bindings to execute WASM
# 2. Capture rendering output using a WebGL or Canvas simulation
# 3. Use zigimg for image processing and resizing
# 4. Integrate directly with the Zig build system 