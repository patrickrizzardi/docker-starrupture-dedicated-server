#!/bin/bash
# Star Rupture Server Start Script
# Launches the server via Wine

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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

# Check if already running
if [ -f "$PID_FILE" ]; then
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
        log_warning "Server already running (PID: $existing_pid)"
        exit 0
    fi
    # Stale PID file
    rm -f "$PID_FILE"
fi

# Check if server executable exists
if [ ! -f "$SERVER_EXE" ]; then
    log_error "Server executable not found: $SERVER_EXE"
    log_info "Run update.sh first to download the server files"
    exit 1
fi

# Get ports from environment or use defaults
PORT=${SERVER_PORT:-7777}
QUERY=${QUERY_PORT:-27015}

log_info "Starting Star Rupture server..."
log_info "  Game Port:  $PORT/udp"
log_info "  Query Port: $QUERY/udp"

# Create logs directory
mkdir -p "${GAME_BASE}/StarRupture/Saved/Logs" 2>/dev/null || true

# Launch server with Wine
cd "${GAME_BASE}/StarRupture/Binaries/Win64"

wine64 "$SERVER_EXE" \
    -Log \
    -port=$PORT \
    -queryport=$QUERY \
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
