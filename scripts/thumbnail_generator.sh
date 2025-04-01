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
        
        // Set a safety timeout to prevent hanging
        const safetyTimeout = setTimeout(() => {
            debugLog('ERROR: Safety timeout triggered after 30 seconds');
            // Continue execution even if page.goto hangs
            throw new Error('Navigation timeout - safety mechanism');
        }, 30000);
        
        try {
            debugLog('Starting page navigation...');
            await Promise.race([
                page.goto(fileUrl, { 
                    waitUntil: 'networkidle',
                    timeout: PLAYWRIGHT_TIMEOUT / 2 // Use shorter timeout for navigation
                }),
                // Secondary timeout as additional safety
                new Promise((_, reject) => 
                    setTimeout(() => reject(new Error('Navigation timeout')), 
                    PLAYWRIGHT_TIMEOUT / 2)
                )
            ]);
            debugLog('Page navigation completed');
            
            // Clear the safety timeout since navigation succeeded
            clearTimeout(safetyTimeout);
            
            debugLog('Page loaded successfully');
            
            // Check if WebGL is available and log info with a timeout
            debugLog('Extracting WebGL info...');
            try {
                // Set a timeout for WebGL extraction
                const webglTimeout = setTimeout(() => {
                    debugLog('ERROR: WebGL info extraction timeout after 10 seconds');
                    throw new Error('WebGL extraction timeout');
                }, 10000);
                
                // Use Promise.race to ensure the evaluation doesn't hang
                const webglInfo = await Promise.race([
                    page.evaluate(() => window.extractWebGLInfo()),
                    new Promise((_, reject) => 
                        setTimeout(() => reject(new Error('WebGL info extraction timed out')), 
                        8000)
                    )
                ]);
                
                clearTimeout(webglTimeout);
                debugLog('WebGL Info:', JSON.stringify(webglInfo, null, 2));
                
                if (webglInfo.supported) {
                    debugLog('WebGL is supported! Using hardware/software rendering');
                } else {
                    debugLog('WebGL not supported. Game may not render correctly:', webglInfo.reason);
                }
            } catch (webglError) {
                debugLog('ERROR: WebGL info extraction failed:', webglError);
                debugLog('Continuing despite WebGL extraction failure');
            }
            
        } catch (loadError) {
            // Clear the safety timeout to prevent unexpected throws
            clearTimeout(safetyTimeout);
            
            debugLog('ERROR: Page load failed', loadError);
            debugLog('Attempting to continue despite load error');
            
            // Try a different approach with simpler loading options
            debugLog('Attempting simplified page load...');
            try {
                await page.goto(fileUrl, { 
                    waitUntil: 'domcontentloaded', // Less strict waiting condition
                    timeout: 10000 // Short timeout
                });
                debugLog('Simplified page load completed');
            } catch (retryError) {
                debugLog('Simplified load also failed:', retryError);
                // Continue anyway, might still be able to take a screenshot
            }
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
        
        try {
            // Set a timeout for the screenshot process
            const screenshotTimeout = setTimeout(() => {
                debugLog('ERROR: Screenshot timeout triggered after 15 seconds');
                throw new Error('Screenshot timeout');
            }, 15000);
            
            await page.screenshot({ 
                path: thumbPath,
                fullPage: false,
                omitBackground: false,
                timeout: 10000
            });
            
            clearTimeout(screenshotTimeout);
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
        } catch (screenshotError) {
            debugLog('ERROR: Screenshot capture failed:', screenshotError);
            // Continue to finally block for cleanup
        }
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
            // Set a global timeout for this game's thumbnail generation (2 minutes max)
            const gameTimeout = setTimeout(() => {
                debugLog(\`ERROR: Global timeout reached for \${dir} after 120 seconds\`);
                console.error(\`Thumbnail generation for \${dir} timed out after 120 seconds\`);
                // Can't really abort the operation, but this will log the timeout
                // The next game will still be processed
            }, 120000);
            
            await generateThumbnail(gamePath, outputDir, width, height);
            
            // Clear the timeout if successful
            clearTimeout(gameTimeout);
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