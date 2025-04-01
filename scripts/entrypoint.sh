#!/bin/bash
set -e

echo "Starting WASM Game Directory Container"

# Get rebuild frequency from environment variable (default to 6 hours)
REBUILD_FREQUENCY=${REBUILD_FREQUENCY:-6}
echo "Setting rebuild frequency to every ${REBUILD_FREQUENCY} hours"

# Set up cron job with dynamic frequency
echo "0 */${REBUILD_FREQUENCY} * * * /scripts/build_games.sh /config/games.json" > /etc/crontabs/root

# Make scripts executable
echo "Setting script permissions..."
chmod +x /scripts/*.sh

# Run the build script initially
echo "Running initial build..."
/scripts/build_games.sh /config/games.json

# Start cron daemon
echo "Starting cron service..."
crond

# Start nginx in foreground
echo "Starting nginx..."
nginx -g "daemon off;" 