#!/bin/bash
# Star Rupture Server Entrypoint
# Initializes Wine, checks for updates, and starts the server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup function for graceful shutdown
cleanup() {
    log_info "Received shutdown signal..."

    # Stop the server gracefully
    if [ -f "${SCRIPTS_DIR}/stop.sh" ]; then
        "${SCRIPTS_DIR}/stop.sh"
    fi

    # Kill Xvfb
    if [ -n "$XVFB_PID" ] && kill -0 $XVFB_PID 2>/dev/null; then
        kill $XVFB_PID 2>/dev/null || true
    fi

    log_info "Shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGHUP

# Make sure WINEPREFIX directory exists
mkdir -p "${WINEPREFIX}" 2>/dev/null || true

# Pre-create game directories with correct ownership
# This prevents SteamCMD from creating them as root
log_info "Ensuring directory permissions..."
mkdir -p "${GAME_DIR}/StarRupture/Binaries/Win64" 2>/dev/null || true
mkdir -p "${GAME_DIR}/StarRupture/Content" 2>/dev/null || true
mkdir -p "${GAME_DIR}/StarRupture/Plugins" 2>/dev/null || true
mkdir -p "${GAME_DIR}/StarRupture/Saved" 2>/dev/null || true
mkdir -p "${GAME_DIR}/Engine" 2>/dev/null || true
mkdir -p "${GAME_DIR}/steamapps" 2>/dev/null || true

# Set up virtual display for Wine
log_info "Setting up virtual display..."
mkdir -p /tmp/.X11-unix 2>/dev/null || true

# Clean up stale X lock files (from previous container runs)
rm -f /tmp/.X99-lock 2>/dev/null || true

# Start Xvfb
Xvfb :99 -screen 0 1024x768x16 -ac &
XVFB_PID=$!
sleep 2

# Verify X server started
if ! ps -p $XVFB_PID >/dev/null 2>&1; then
    log_warning "Failed to start X server, trying alternate approach..."
    Xvfb :99 -nolisten tcp -screen 0 1024x768x16 &
    XVFB_PID=$!
    sleep 2
fi

# Initialize Wine
log_info "Initializing Wine..."
wine64 --version || log_warning "Wine version check failed (continuing anyway)"

# Start wine server persistent for faster startup
log_info "Starting persistent Wine server..."
wineserver --persistent

# Run custom command if provided
if [ "$1" ]; then
    log_info "Running command: $@"
    exec "$@"
    exit $?
fi

# Check for updates unless SKIP_UPDATE is set
if [ "${SKIP_UPDATE}" != "true" ]; then
    log_info "Checking for updates..."
    "${SCRIPTS_DIR}/update.sh" || log_warning "Update check failed, continuing with existing files"
else
    log_info "Skipping update check (SKIP_UPDATE=true)"
fi

# Start the server
log_info "Starting Star Rupture server..."
"${SCRIPTS_DIR}/start.sh" &
SERVER_PID=$!

# Wait a moment for server to initialize
sleep 5

# Tail logs to keep container alive (use -F for rotation handling)
LOG_DIR="${GAME_DIR}/StarRupture/Saved/Logs"
if [ -d "$LOG_DIR" ]; then
    log_info "Tailing server logs..."
    # Wait for log file to exist
    while [ ! -f "${LOG_DIR}/StarRupture.log" ]; do
        sleep 2
    done
    tail -F "${LOG_DIR}/StarRupture.log" 2>/dev/null &
fi

# Wait for server process
wait $SERVER_PID
