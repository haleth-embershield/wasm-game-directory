#!/bin/bash
set -e

# Thumbnail Generator for WASM Game Directory
# Uses Bun + Puppeteer to generate thumbnails from game screens with GPU acceleration

GAMES_DIR=${1:-"/games"}
WEB_DIR=${2:-"/usr/share/nginx/html"}
THUMB_SIZE=${3:-"200x150"}
PUPPETEER_TIMEOUT=${PUPPETEER_TIMEOUT:-60000}
DEBUG=${DEBUG:-"false"}

echo "Starting thumbnail generation for games in $GAMES_DIR"
echo "Using Puppeteer timeout of $PUPPETEER_TIMEOUT ms"
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

# Check GPU availability 
echo "GPU Information:"
ls -la /dev/dri/ || echo "No DRI devices found"
glxinfo | grep "OpenGL renderer" || echo "glxinfo not available"

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
    
    debugLog('Launching browser with GPU acceleration');
    
    // Global timeout for the entire process
    const globalTimeout = setTimeout(() => {
        debugLog(\`ERROR: Global timeout reached for \${gameDir} after 120 seconds\`);
        console.error(\`Thumbnail generation for \${gameDir} timed out after 120 seconds\`);
    }, 120000);
    
    // Launch browser with GPU support
    const browser = await puppeteer.launch({ 
        headless: 'new',
        args: [
          '--no-sandbox', 
          '--disable-setuid-sandbox',
          '--enable-gpu',
          '--ignore-gpu-blocklist',
          '--enable-webgl',
          '--enable-webgpu',
          '--disable-web-security',
          '--disable-features=IsolateOrigins,site-per-process',
          '--window-size=1280,720'
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

        // Inject WebGL debug info extractor
        await page.evaluateOnNewDocument(() => {
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

        // Load the game with safety timeout
        const fileUrl = \`file://\${path.resolve(gamePath)}\`;
        debugLog(\`Attempting to load \${fileUrl}\`);
        
        // Set a safety timeout to prevent hanging
        const safetyTimeout = setTimeout(() => {
            debugLog('ERROR: Page load safety timeout triggered after 30 seconds');
            // We'll continue execution even if page.goto hangs
        }, 30000);
        
        try {
            debugLog('Starting page navigation...');
            await Promise.race([
                page.goto(fileUrl, { 
                    waitUntil: 'networkidle0',
                    timeout: PUPPETEER_TIMEOUT / 2
                }),
                // Secondary timeout as extra safety
                new Promise((_, reject) => 
                    setTimeout(() => reject(new Error('Navigation timeout')), 
                    PUPPETEER_TIMEOUT / 2)
                )
            ]);
            
            clearTimeout(safetyTimeout);
            debugLog('Page loaded successfully');
            
            // Check if WebGL is available and log info with a timeout
            debugLog('Extracting WebGL info...');
            try {
                const webglTimeout = setTimeout(() => {
                    debugLog('ERROR: WebGL info extraction timeout after 10 seconds');
                }, 10000);
                
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
                    debugLog('WebGL is supported! Using GPU rendering');
                } else {
                    debugLog('WebGL not supported. Game may not render correctly:', webglInfo.reason);
                }
            } catch (webglError) {
                debugLog('ERROR: WebGL info extraction failed:', webglError);
                debugLog('Continuing despite WebGL extraction failure');
            }
        } catch (loadError) {
            clearTimeout(safetyTimeout);
            debugLog('ERROR: Page load failed', loadError);
            
            // Try a different approach with simpler loading options
            debugLog('Attempting simplified page load...');
            try {
                await page.goto(fileUrl, { 
                    waitUntil: 'domcontentloaded',
                    timeout: 10000
                });
                debugLog('Simplified page load completed');
            } catch (retryError) {
                debugLog('Simplified load also failed:', retryError);
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
        await sleep(5000);
        
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
            await sleep(2000);
        } catch (interactError) {
            debugLog('Error during interaction:', interactError);
        }

        // Take screenshot with timeout
        const thumbPath = path.join(outputDir, \`thumbnail.png\`);
        debugLog(\`Attempting to capture screenshot to \${thumbPath}\`);
        
        try {
            const screenshotTimeout = setTimeout(() => {
                debugLog('ERROR: Screenshot timeout triggered after 15 seconds');
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
            
            // Also save as standard thumbnail.png for easier reference
            await sharp(thumbPath)
                .resize(width, height)
                .toFile(path.join(outputDir, \`thumbnail.png\`));
                
            console.log(\`Generated thumbnail for \${gameDir}\`);
        } catch (screenshotError) {
            debugLog('ERROR: Screenshot capture failed:', screenshotError);
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
        clearTimeout(globalTimeout);
        debugLog('Closing browser');
        await browser.close();
        debugLog('Browser closed');
    }
}

async function main() {
    const gamesDir = process.argv[2] || '.';
    const width = parseInt(process.argv[3]) || 200;
    const height = parseInt(process.argv[4]) || 150;
    
    // Verify GPU and environment
    debugLog('DISPLAY environment variable:', process.env.DISPLAY || '(not set)');
    debugLog('Puppeteer executable path:', process.env.PUPPETEER_EXECUTABLE_PATH || '(default)');
    
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
    
    // Process each game directory with a timeout
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
        
        // Add a small delay between games to let GPU resources recover
        await sleep(1000);
    }
}

main().catch(err => {
    console.error('Thumbnail generation failed:', err);
    process.exit(1);
});
EOF

# Run the script with our parameters and enable debugging
echo "Generating thumbnails..."
DEBUG=true PUPPETEER_TIMEOUT=$PUPPETEER_TIMEOUT bun generate-thumbnails.js "$GAMES_DIR" "$WIDTH" "$HEIGHT"

# No need to copy thumbnails since we're using directory symlinks
echo "Thumbnail generation complete! Thumbnails will be available automatically through symlinks."

# Clean up
rm -rf "$TEMP_DIR"

echo "Thumbnail generation complete!" 