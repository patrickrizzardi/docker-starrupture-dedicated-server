#!/bin/bash
# Star Rupture Server Status Script
# Checks if the server is running and displays info

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PID_FILE="${GAME_DIR}/server.pid"
APP_MANIFEST="${GAME_DIR}/steamapps/appmanifest_${STAR_APPID}.acf"

# Get server PID
get_server_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    local pid=$(pgrep -f "StarRuptureServerEOS" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi

    echo "0"
    return 1
}

# Get installed build ID
get_build_id() {
    if [ -f "$APP_MANIFEST" ]; then
        grep -oP '"buildid"\s*"\K[^"]+' "$APP_MANIFEST" 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Main
main() {
    echo -e "${BLUE}=== Star Rupture Server Status ===${NC}"
    echo ""

    # Server process status
    local server_pid=$(get_server_pid)
    if [ "$server_pid" != "0" ]; then
        echo -e "Status:    ${GREEN}RUNNING${NC} (PID: $server_pid)"

        # Show uptime if possible
        if [ -f "/proc/$server_pid/stat" ]; then
            local start_time=$(stat -c %Y /proc/$server_pid 2>/dev/null || echo "")
            if [ -n "$start_time" ]; then
                local now=$(date +%s)
                local uptime=$((now - start_time))
                local hours=$((uptime / 3600))
                local mins=$(((uptime % 3600) / 60))
                echo -e "Uptime:    ${hours}h ${mins}m"
            fi
        fi
    else
        echo -e "Status:    ${RED}STOPPED${NC}"
    fi

    # Build info
    local build_id=$(get_build_id)
    echo -e "Build ID:  $build_id"

    # Port info
    echo -e "Game Port: ${SERVER_PORT:-7777}/udp"
    echo -e "Query:     ${QUERY_PORT:-27015}/udp"

    # Disk usage
    if [ -d "$GAME_DIR" ]; then
        local size=$(du -sh "$GAME_DIR" 2>/dev/null | cut -f1)
        echo -e "Disk:      $size"
    fi

    echo ""

    # Return exit code based on status
    [ "$server_pid" != "0" ]
}

main "$@"
