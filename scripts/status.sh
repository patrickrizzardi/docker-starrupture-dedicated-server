#!/bin/bash
# Star Rupture Server Status Script
# Checks if the server is running and displays info

set -e

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib_common.sh" 2>/dev/null || source "/scripts/lib_common.sh"

# Handle --help
if check_help_flag "$@"; then
    show_help "status.sh" "Displays the current status of the Star Rupture server"
    exit 0
fi

PID_FILE="${GAME_DIR}/server.pid"
APP_MANIFEST="${GAME_DIR}/steamapps/appmanifest_${STAR_APPID}.acf"

# Main
main() {
    echo -e "${LOG_BLUE}=== Star Rupture Server Status ===${LOG_NC}"
    echo ""

    # Server process status
    local server_pid
    server_pid=$(get_server_pid "$PID_FILE")

    if [ "$server_pid" != "0" ]; then
        log_success "Server RUNNING (PID: $server_pid)"

        # Show uptime if possible
        if [ -f "/proc/$server_pid/stat" ]; then
            local start_time
            start_time=$(stat -c %Y "/proc/$server_pid" 2>/dev/null || echo "")
            if [ -n "$start_time" ]; then
                local now
                now=$(date +%s)
                local uptime=$((now - start_time))
                local hours=$((uptime / 3600))
                local mins=$(((uptime % 3600) / 60))
                echo -e "Uptime:    ${hours}h ${mins}m"
            fi
        fi
    else
        log_error "Server STOPPED"
    fi

    # Build info
    local build_id
    build_id=$(get_build_id_from_manifest "$APP_MANIFEST")
    echo -e "Build ID:  $build_id"

    # Port info
    echo -e "Game Port: ${SERVER_PORT:-7777}/udp+tcp"
    echo -e "Query:     ${QUERY_PORT:-27015}/udp"

    # Disk usage
    if [ -d "$GAME_DIR" ]; then
        local size
        size=$(du -sh "$GAME_DIR" 2>/dev/null | cut -f1)
        echo -e "Disk:      $size"
    fi

    echo ""

    # Return exit code based on status
    [ "$server_pid" != "0" ]
}

main "$@"
