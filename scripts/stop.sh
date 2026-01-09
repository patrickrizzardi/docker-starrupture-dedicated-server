#!/bin/bash
# Star Rupture Server Stop Script
# Gracefully stops the server with timeout

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

PID_FILE="${GAME_DIR}/server.pid"
TIMEOUT=${SERVER_SHUTDOWN_TIMEOUT:-30}

# Get server PID
get_server_pid() {
    # Try PID file first
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Try to find by process name
    local pid=$(pgrep -f "StarRuptureServerEOS" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi

    echo "0"
    return 1
}

# Main
main() {
    log_info "Stopping Star Rupture server..."

    local server_pid=$(get_server_pid)

    if [ "$server_pid" = "0" ]; then
        log_info "Server is not running"
        rm -f "$PID_FILE"
        return 0
    fi

    log_info "Found server process: $server_pid"

    # Send SIGTERM for graceful shutdown
    log_info "Sending SIGTERM..."
    kill -TERM "$server_pid" 2>/dev/null || true

    # Wait for graceful shutdown
    local waited=0
    while [ $waited -lt $TIMEOUT ]; do
        if ! kill -0 "$server_pid" 2>/dev/null; then
            log_success "Server stopped gracefully"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))

        # Show progress every 5 seconds
        if [ $((waited % 5)) -eq 0 ]; then
            log_info "Waiting for shutdown... (${waited}/${TIMEOUT}s)"
        fi
    done

    # Force kill if still running
    log_warning "Timeout reached, forcing shutdown..."
    kill -9 "$server_pid" 2>/dev/null || true

    # Also kill any Wine processes
    pkill -9 -f "StarRuptureServerEOS" 2>/dev/null || true

    rm -f "$PID_FILE"
    log_success "Server force-stopped"
    return 0
}

main "$@"
