#!/bin/bash
# Star Rupture Server Stop Script
# Gracefully stops the server with timeout

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib_common.sh" 2>/dev/null || source "/scripts/lib_common.sh"

# Handle --help
if check_help_flag "$@"; then
    show_help "stop.sh" "Gracefully stops the Star Rupture server with timeout fallback"
    exit 0
fi

PID_FILE="${GAME_DIR}/server.pid"
TIMEOUT=${SERVER_SHUTDOWN_TIMEOUT:-30}

# Main
main() {
    log_info "Stopping Star Rupture server..."

    local server_pid
    server_pid=$(get_server_pid "$PID_FILE")

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
