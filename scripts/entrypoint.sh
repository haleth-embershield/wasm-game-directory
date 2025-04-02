#!/bin/bash
set -e

echo "Starting WASM Game Directory Container"

# Start Xvfb for headless browser with WebGL support
# echo "Starting Xvfb virtual display..."
# Xvfb :99 -screen 0 1280x720x24 -ac &
# sleep 1
# echo "Xvfb started with DISPLAY=:99"

# Get rebuild frequency from environment variable (default to 6 hours)
REBUILD_FREQUENCY=${REBUILD_FREQUENCY:-6}
echo "Setting rebuild frequency to every ${REBUILD_FREQUENCY} hours"

# Set up cron job with dynamic frequency for Ubuntu (not Alpine)
echo "0 */${REBUILD_FREQUENCY} * * * root /scripts/build_games.sh /config/games.json" > /etc/cron.d/game-builds
chmod 0644 /etc/cron.d/game-builds

# Run the build script initially (builds games, generates HTML, starts thumbnail generation in background)
echo "Running initial build..."
/scripts/build_games.sh /config/games.json

# Start cron daemon for Ubuntu
echo "Starting cron service..."
service cron start

# Start nginx in foreground (thumbnails will continue generating in background)
echo "Starting nginx..."
nginx -g "daemon off;" 