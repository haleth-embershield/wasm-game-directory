#!/bin/bash
set -e

# Thumbnail Generator for WASM Game Directory
# Uses Bun + Puppeteer to generate thumbnails from game screens
# TODO: Future version will use Zig natively

GAMES_DIR=${1:-"/games"}
WEB_DIR=${2:-"/usr/share/nginx/html"}
THUMB_SIZE=${3:-"200x150"}
PUPPETEER_TIMEOUT=${PUPPETEER_TIMEOUT:-60000}
DEBUG=${DEBUG:-"false"}

echo "Starting thumbnail generation for games in $GAMES_DIR"
echo "Using Puppeteer timeout of $PUPPETEER_TIMEOUT ms"
echo "Debug mode: $DEBUG"

# Extract width and height from THUMB_SIZE
WIDTH=$(echo $THUMB_SIZE | cut -d'x' -f1)
HEIGHT=$(echo $THUMB_SIZE | cut -d'x' -f2)

# Create temp dir for the Node.js/Bun project
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# Show system info
echo "System information:"
free -h || echo "free command not found"
df -h | grep -E '/$|/tmp' || echo "df command failed"

# Initialize Bun project and install dependencies
echo "Installing dependencies..."
bun init -y
bun add puppeteer sharp

# Enable Puppeteer debugging if needed
if [ "$DEBUG" = "true" ]; then
  export DEBUG="puppeteer:*"
fi

# Create the thumbnail generation script
cat > generate-thumbnails.js << EOF
const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

// Use timeout from environment variable
const PUPPETEER_TIMEOUT = parseInt(process.env.PUPPETEER_TIMEOUT || '60000');
const DEBUG = process.env.DEBUG === 'true';

// Helper function to log debug info
function debugLog(...args) {
  if (DEBUG || args[0] === 'ERROR') {
    console.log('[DEBUG]', ...args);
  }
}

// Helper function for timeout (since waitForTimeout isn't available in Bun)
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function generateThumbnail(gameDir, outputDir, width = 200, height = 150) {
    console.log(\`Processing \${gameDir}...\`);
    
    // Check if game has index.html
    const gamePath = path.join(gameDir, 'index.html');
    if (!fs.existsSync(gamePath)) {
        console.log(\`Skipping \${gameDir}: No index.html found\`);
        return;
    }
    
    debugLog('Launching browser with the following options:', {
      headless: 'new',
      args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu'],
      protocolTimeout: PUPPETEER_TIMEOUT,
      timeout: PUPPETEER_TIMEOUT
    });
    
    // Launch browser with increased timeout and more debug flags
    const browser = await puppeteer.launch({ 
        headless: 'new',
        args: [
          '--no-sandbox', 
          '--disable-setuid-sandbox',
          '--disable-gpu',
          '--disable-web-security',
          '--disable-features=IsolateOrigins,site-per-process',
          '--no-zygote',
          '--no-first-run',
          '--window-size=1280,720',
          '--disable-accelerated-2d-canvas',
          '--disable-gl-drawing-for-tests'
        ],
        protocolTimeout: PUPPETEER_TIMEOUT,
        dumpio: DEBUG // Log browser process stdout/stderr
    });
    
    try {
        debugLog('Browser launched successfully');
        const page = await browser.newPage();
        
        // Listen for console messages from the page
        page.on('console', message => debugLog('CONSOLE:', message.type(), message.text()));
        
        // Listen for errors
        page.on('error', err => debugLog('ERROR:', err.toString()));
        page.on('pageerror', err => debugLog('PAGE ERROR:', err.toString()));
        
        // Listen for request failures
        page.on('requestfailed', request => {
          debugLog('REQUEST FAILED:', request.url(), 'with error', request.failure().errorText);
        });
        
        await page.setViewport({ width: 1280, height: 720 });
        debugLog('Viewport set to 1280x720');

        // Load the game with extra debug info
        const fileUrl = \`file://\${path.resolve(gamePath)}\`;
        debugLog(\`Attempting to load \${fileUrl}\`);
        
        try {
            await page.goto(fileUrl, { 
                waitUntil: 'networkidle0',
                timeout: PUPPETEER_TIMEOUT
            });
            debugLog('Page loaded successfully');
        } catch (loadError) {
            debugLog('ERROR: Page load failed', loadError);
            
            // Try to proceed anyway - sometimes the page loads enough for a screenshot
            // even if not all resources finished loading
            debugLog('Attempting to continue despite load error');
        }
        
        // Log DOM content
        const pageContent = await page.content();
        debugLog('Page HTML length:', pageContent.length);
        if (DEBUG) {
            fs.writeFileSync(\`\${outputDir}/debug-page-content.html\`, pageContent);
            debugLog('Saved page content to debug-page-content.html');
        }
        
        // Wait a bit longer for rendering using setTimeout instead of waitForTimeout
        debugLog('Waiting 5 seconds for game to render');
        await sleep(5000);

        // Take screenshot
        const thumbPath = path.join(outputDir, \`thumbnail.png\`);
        debugLog(\`Attempting to capture screenshot to \${thumbPath}\`);
        await page.screenshot({ 
            path: thumbPath,
            fullPage: false,
            omitBackground: false
        });
        debugLog('Screenshot captured successfully');

        // Verify screenshot exists and has content
        if (fs.existsSync(thumbPath)) {
            const stats = fs.statSync(thumbPath);
            debugLog(\`Screenshot file size: \${stats.size} bytes\`);
            
            if (stats.size < 100) {
                debugLog('WARNING: Screenshot file is very small, might be empty');
            }
        } else {
            throw new Error('Screenshot file was not created');
        }

        // Resize to thumbnail
        debugLog('Resizing screenshot to thumbnail size');
        await sharp(thumbPath)
            .resize(width, height)
            .toFile(path.join(outputDir, \`thumbnail-\${width}x\${height}.png\`));
            
        console.log(\`Generated thumbnail for \${gameDir}\`);
    } catch (error) {
        console.error(\`Error generating thumbnail for \${gameDir}:\`, error);
        debugLog('ERROR: Stack trace:', error.stack);
        
        // Try to save a screenshot of whatever is visible even if there was an error
        try {
            const errorThumbPath = path.join(outputDir, \`error-thumbnail.png\`);
            debugLog('Attempting to save error screenshot');
            const page = (await browser.pages())[0];
            await page.screenshot({ path: errorThumbPath });
            debugLog(\`Saved error screenshot to \${errorThumbPath}\`);
        } catch (screenshotError) {
            debugLog('Failed to save error screenshot:', screenshotError);
        }
    } finally {
        debugLog('Closing browser');
        await browser.close();
        debugLog('Browser closed');
    }
}

async function main() {
    const gamesDir = process.argv[2] || '.';
    const width = parseInt(process.argv[3]) || 200;
    const height = parseInt(process.argv[4]) || 150;
    
    // Log environment info
    debugLog('Node version:', process.version);
    debugLog('Platform:', process.platform);
    debugLog('Architecture:', process.arch);
    debugLog('Puppeteer version:', require('puppeteer/package.json').version);
    debugLog('Puppeteer timeout:', PUPPETEER_TIMEOUT);
    
    // Check available memory
    try {
        const os = require('os');
        debugLog('Total memory:', Math.round(os.totalmem() / (1024 * 1024)), 'MB');
        debugLog('Free memory:', Math.round(os.freemem() / (1024 * 1024)), 'MB');
    } catch (e) {
        debugLog('Failed to get memory info:', e);
    }

    const gameDirs = fs.readdirSync(gamesDir)
        .filter(item => fs.statSync(path.join(gamesDir, item)).isDirectory());

    console.log(\`Found \${gameDirs.length} potential game directories\`);
    
    // Process each game directory
    for (const dir of gameDirs) {
        const gamePath = path.join(gamesDir, dir);
        const outputDir = gamePath; // Save thumbnail in the game's directory
        
        // Create output dir if it doesn't exist
        if (!fs.existsSync(outputDir)) {
            fs.mkdirSync(outputDir, { recursive: true });
        }
        
        try {
            await generateThumbnail(gamePath, outputDir, width, height);
        } catch (dirError) {
            debugLog('ERROR processing directory:', dirError);
        }
    }
    
    // Note about alternatives
    console.log('Note: If Puppeteer continues to fail, consider alternatives:');
    console.log('1. Try node.js instead of bun (may have better compatibility)');
    console.log('2. Consider Playwright as an alternative to Puppeteer');
    console.log('3. For simpler games, html2canvas might be sufficient');
}

main().catch(err => {
    console.error('Thumbnail generation failed:', err);
    process.exit(1);
});
EOF

# Run the script with our parameters and enable debugging
echo "Generating thumbnails..."
DEBUG=true PUPPETEER_TIMEOUT=$PUPPETEER_TIMEOUT bun generate-thumbnails.js "$GAMES_DIR" "$WIDTH" "$HEIGHT"

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
        
        # Also try the error thumbnail if it exists
        if [ ! -f "$WEB_DIR/$GAME_NAME/thumbnail.png" ] && [ -f "$GAME_DIR/error-thumbnail.png" ]; then
            mkdir -p "$WEB_DIR/$GAME_NAME"
            cp "$GAME_DIR/error-thumbnail.png" "$WEB_DIR/$GAME_NAME/thumbnail.png"
            echo "Added error thumbnail for $GAME_NAME (better than nothing)"
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