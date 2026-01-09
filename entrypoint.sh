#!/bin/bash
# Star Rupture Server Entrypoint
# Initializes Wine, checks for updates, and starts the server

set -e

# Source shared library
source "/scripts/lib_common.sh" 2>/dev/null || {
    echo "[ERROR] Failed to source lib_common.sh"
    exit 1
}

# Cleanup function for graceful shutdown
cleanup() {
    log_info "Received shutdown signal..."

    # Stop the server gracefully
    if [ -f "${SCRIPTS_DIR}/stop.sh" ]; then
        "${SCRIPTS_DIR}/stop.sh"
    fi

    # Kill Xvfb (Bug #2 fix - quoted PID variable)
    if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
        kill "$XVFB_PID" 2>/dev/null || true
    fi

    log_info "Shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGHUP

# Make sure WINEPREFIX directory exists
mkdir -p "${WINEPREFIX}" 2>/dev/null || true

# Pre-create game directories with correct ownership (Perf #3 - batch creation)
# This prevents SteamCMD from creating them as root
log_info "Ensuring directory permissions..."
mkdir -p \
    "${GAME_DIR}/StarRupture/Binaries/Win64" \
    "${GAME_DIR}/StarRupture/Content" \
    "${GAME_DIR}/StarRupture/Plugins" \
    "${GAME_DIR}/StarRupture/Saved" \
    "${GAME_DIR}/Engine" \
    "${GAME_DIR}/steamapps" \
    2>/dev/null || log_warning "Some directories failed to create"

# Set up virtual display for Wine
log_info "Setting up virtual display..."
mkdir -p /tmp/.X11-unix 2>/dev/null || true

# Clean up stale X lock files (from previous container runs)
rm -f /tmp/.X99-lock 2>/dev/null || true

# Start Xvfb (Bug #1 fix - socket-based readiness check instead of PID)
Xvfb :99 -screen 0 1024x768x16 -ac &
XVFB_PID=$!

# Wait for X server socket (more reliable than PID check)
for i in {1..10}; do
    if [ -S /tmp/.X11-unix/X99 ]; then
        log_info "X server started successfully"
        break
    fi
    sleep 1
done

# Fallback if primary approach failed
if ! [ -S /tmp/.X11-unix/X99 ]; then
    log_warning "Primary X server failed, trying alternate approach..."
    # Kill the failed attempt first (Bug #1 fix)
    kill "$XVFB_PID" 2>/dev/null || true
    sleep 1

    Xvfb :99 -nolisten tcp -screen 0 1024x768x16 &
    XVFB_PID=$!

    for i in {1..10}; do
        if [ -S /tmp/.X11-unix/X99 ]; then
            log_info "X server started successfully (alternate approach)"
            break
        fi
        sleep 1
    done

    if ! [ -S /tmp/.X11-unix/X99 ]; then
        log_error "Failed to start X server after multiple attempts"
        exit 1
    fi
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

# Tail logs to keep container alive (Perf #1 - timeout for log file wait)
LOG_DIR="${GAME_DIR}/StarRupture/Saved/Logs"
if [ -d "$LOG_DIR" ]; then
    log_info "Waiting for server log file..."

    log_wait=0
    max_wait=60

    while [ $log_wait -lt $max_wait ]; do
        if [ -f "${LOG_DIR}/StarRupture.log" ]; then
            log_info "Tailing server logs..."
            tail -F "${LOG_DIR}/StarRupture.log" 2>/dev/null &
            break
        fi

        # Check if server still alive
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            log_error "Server died before creating log file"
            exit 1
        fi

        sleep 1
        log_wait=$((log_wait + 1))
    done

    if [ $log_wait -ge $max_wait ]; then
        log_warning "Log file not found after ${max_wait}s, continuing without tail"
    fi
fi

# Wait for server process
wait $SERVER_PID
