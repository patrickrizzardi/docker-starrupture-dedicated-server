#!/bin/bash
# Star Rupture Server Start Script
# Launches the server via Wine

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib_common.sh" 2>/dev/null || source "/scripts/lib_common.sh"

# Handle --help
if check_help_flag "$@"; then
    show_help "start.sh" "Starts the Star Rupture server using Wine"
    exit 0
fi

# Server executable path - check main location and staging fallback
SERVER_EXE="${GAME_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe"
STAGING_EXE="${GAME_DIR}/steamapps/downloading/${STAR_APPID}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe"
PID_FILE="${GAME_DIR}/server.pid"

# Use staging directory if main location not available
if [ ! -f "$SERVER_EXE" ] && [ -f "$STAGING_EXE" ]; then
    log_warning "Using staging directory (verification incomplete)"
    SERVER_EXE="$STAGING_EXE"
    GAME_BASE="${GAME_DIR}/steamapps/downloading/${STAR_APPID}"
else
    GAME_BASE="${GAME_DIR}"
fi

# Check if already running (uses shared get_server_pid with Bug #3 fix)
existing_pid=$(get_server_pid "$PID_FILE") || true
if [ "$existing_pid" != "0" ]; then
    log_warning "Server already running (PID: $existing_pid)"
    exit 0
fi

# Clean up stale PID file if exists
rm -f "$PID_FILE"

# Check if server executable exists
if [ ! -f "$SERVER_EXE" ]; then
    log_error "Server executable not found: $SERVER_EXE"
    log_info "Run update.sh first to download the server files"
    exit 1
fi

# Get ports and server name from environment or use defaults
PORT=${SERVER_PORT:-7777}
QUERY=${QUERY_PORT:-27015}
SERVER_NAME=${SERVER_NAME:-"StarRuptureServer"}

log_info "Starting Star Rupture server..."
log_info "  Server:     $SERVER_NAME"
log_info "  Game Port:  $PORT/udp+tcp"
log_info "  Query Port: $QUERY/udp"

# Create logs directory
mkdir -p "${GAME_BASE}/StarRupture/Saved/Logs" 2>/dev/null || true

# Launch server with Wine (Bug #5 fix - safe_cd validates directory)
safe_cd "${GAME_BASE}/StarRupture/Binaries/Win64"

# Use xvfb-run for cleaner display handling (like indifferentbroccoli's approach)
xvfb-run --auto-servernum wine64 "$SERVER_EXE" \
    -Log \
    -Port=$PORT \
    -QueryPort=$QUERY \
    -ServerName="$SERVER_NAME" \
    -MULTIHOME=0.0.0.0 \
    &

SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

log_success "Server started (PID: $SERVER_PID)"

# Wait for server to initialize and check if it's still running
sleep 10
if kill -0 "$SERVER_PID" 2>/dev/null; then
    log_success "Server is running"
else
    log_error "Server process died unexpectedly"
    rm -f "$PID_FILE"
    exit 1
fi

# Keep running (foreground mode for container)
wait $SERVER_PID
