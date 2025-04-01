#!/bin/bash
set -e

# Thumbnail Generator for WASM Game Directory
# Uses Bun + Playwright to generate thumbnails from game screens with WebGL support
# TODO: Future version will use Zig natively

GAMES_DIR=${1:-"/games"}
WEB_DIR=${2:-"/usr/share/nginx/html"}
THUMB_SIZE=${3:-"200x150"}
PLAYWRIGHT_TIMEOUT=${PLAYWRIGHT_TIMEOUT:-60000}
DEBUG=${DEBUG:-"false"}

echo "Starting thumbnail generation for games in $GAMES_DIR"
echo "Using Playwright timeout of $PLAYWRIGHT_TIMEOUT ms"
echo "Debug mode: $DEBUG"

# Make sure Xvfb is running
if ! pgrep Xvfb > /dev/null; then
  echo "Starting Xvfb virtual display..."
  Xvfb :99 -screen 0 1280x720x24 -ac &
  sleep 2
fi

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
bun add playwright-chromium sharp

# Enable debugging if needed
if [ "$DEBUG" = "true" ]; then
  export DEBUG="playwright:*"
fi

# Create the thumbnail generation script
cat > generate-thumbnails.js << EOF
const { chromium } = require('playwright-chromium');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

// Use timeout from environment variable
const PLAYWRIGHT_TIMEOUT = parseInt(process.env.PLAYWRIGHT_TIMEOUT || '60000');
const DEBUG = process.env.DEBUG === 'true';

// Helper function to log debug info
function debugLog(...args) {
  if (DEBUG || args[0] === 'ERROR') {
    console.log('[DEBUG]', ...args);
  }
}

async function generateThumbnail(gameDir, outputDir, width = 200, height = 150) {
    console.log(\`Processing \${gameDir}...\`);
    
    // Check if game has index.html
    const gamePath = path.join(gameDir, 'index.html');
    if (!fs.existsSync(gamePath)) {
        console.log(\`Skipping \${gameDir}: No index.html found\`);
        return;
    }
    
    debugLog('Launching browser with SwiftShader WebGL support');
    
    // Launch browser with SwiftShader for WebGL support
    const browser = await chromium.launch({
        executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
        args: [
            '--use-gl=angle',
            '--use-angle=swiftshader',
            '--ignore-gpu-blocklist',
            '--enable-gpu-rasterization',
            '--enable-oop-rasterization',
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--window-size=1280,720',
            '--disable-accelerated-video-decode',
            '--disable-gpu-sandbox'
        ],
        headless: true,
        timeout: PLAYWRIGHT_TIMEOUT
    });
    
    try {
        debugLog('Browser launched successfully');
        const context = await browser.newContext({
            viewport: { width: 1280, height: 720 },
            deviceScaleFactor: 1
        });
        
        // Enable debug logs for browser console
        if (DEBUG) {
            context.on('console', msg => {
                debugLog('CONSOLE:', msg.type(), msg.text());
            });
        }
        
        const page = await context.newPage();
        
        // Inject WebGL debug info extractor
        await page.addInitScript(() => {
            window.extractWebGLInfo = () => {
                try {
                    const canvas = document.createElement('canvas');
                    const gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
                    if (!gl) return { supported: false, reason: 'WebGL context creation failed' };
                    
                    return {
                        supported: true,
                        vendor: gl.getParameter(gl.VENDOR),
                        renderer: gl.getParameter(gl.RENDERER),
                        version: gl.getParameter(gl.VERSION),
                        shadingLanguageVersion: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
                        extensions: gl.getSupportedExtensions()
                    };
                } catch (err) {
                    return { supported: false, reason: err.toString() };
                }
            };
        });

        // Load the game
        const fileUrl = \`file://\${path.resolve(gamePath)}\`;
        debugLog(\`Attempting to load \${fileUrl}\`);
        
        try {
            await page.goto(fileUrl, { 
                waitUntil: 'networkidle',
                timeout: PLAYWRIGHT_TIMEOUT
            });
            debugLog('Page loaded successfully');
            
            // Check if WebGL is available and log info
            const webglInfo = await page.evaluate(() => window.extractWebGLInfo());
            debugLog('WebGL Info:', JSON.stringify(webglInfo, null, 2));
            
            if (webglInfo.supported) {
                debugLog('WebGL is supported! Using hardware/software rendering');
            } else {
                debugLog('WebGL not supported. Game may not render correctly:', webglInfo.reason);
            }
            
        } catch (loadError) {
            debugLog('ERROR: Page load failed', loadError);
            debugLog('Attempting to continue despite load error');
        }
        
        // Log DOM content
        if (DEBUG) {
            const pageContent = await page.content();
            debugLog('Page HTML length:', pageContent.length);
            fs.writeFileSync(\`\${outputDir}/debug-page-content.html\`, pageContent);
            debugLog('Saved page content to debug-page-content.html');
        }
        
        // Wait a bit longer for rendering
        debugLog('Waiting 5 seconds for game to render');
        await page.waitForTimeout(5000);
        
        // Try to interact with the page to trigger game rendering if needed
        try {
            await page.evaluate(() => {
                // Click in the middle of the screen to potentially start the game
                const event = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: window.innerWidth / 2,
                    clientY: window.innerHeight / 2
                });
                document.elementFromPoint(window.innerWidth/2, window.innerHeight/2)?.dispatchEvent(event);
            });
            debugLog('Triggered click event to start game');
            
            // Wait a bit more for the game to respond
            await page.waitForTimeout(1000);
        } catch (interactError) {
            debugLog('Error during interaction:', interactError);
        }

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
            const page = await browser.newPage();
            await page.goto(fileUrl, { timeout: 5000 }).catch(() => {});
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
    
    // Verify DISPLAY environment variable
    debugLog('DISPLAY environment variable:', process.env.DISPLAY || '(not set)');
    
    // Log environment info
    debugLog('Node version:', process.version);
    debugLog('Platform:', process.platform);
    debugLog('Architecture:', process.arch);
    debugLog('Playwright version:', require('playwright-chromium/package.json').version);
    debugLog('Chromium path:', process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || '(default)');
    debugLog('Timeout:', PLAYWRIGHT_TIMEOUT);
    
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
}

main().catch(err => {
    console.error('Thumbnail generation failed:', err);
    process.exit(1);
});
EOF

# Run the script with our parameters and enable debugging
echo "Generating thumbnails..."
DEBUG=true PLAYWRIGHT_TIMEOUT=$PLAYWRIGHT_TIMEOUT DISPLAY=:99 bun generate-thumbnails.js "$GAMES_DIR" "$WIDTH" "$HEIGHT"

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