#!/bin/bash
# =============================================================================
# Star Rupture Server - Shared Library
# Common utilities for all server management scripts
# =============================================================================

# Prevent double-sourcing
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
readonly _LIB_COMMON_LOADED=1

# -----------------------------------------------------------------------------
# Color Definitions
# -----------------------------------------------------------------------------
readonly LOG_RED='\033[0;31m'
readonly LOG_GREEN='\033[0;32m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_NC='\033[0m'

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
log_info()    { echo -e "${LOG_BLUE}[INFO]${LOG_NC} $1"; }
log_success() { echo -e "${LOG_GREEN}[OK]${LOG_NC} $1"; }
log_warning() { echo -e "${LOG_YELLOW}[WARN]${LOG_NC} $1"; }
log_error()   { echo -e "${LOG_RED}[ERROR]${LOG_NC} $1"; }

# -----------------------------------------------------------------------------
# PID Detection (with Bug #3 fix - validates non-empty, numeric)
# -----------------------------------------------------------------------------
# Gets the server PID from PID file or by process search
# Args: $1 - Optional PID file path (default: ${GAME_DIR}/server.pid)
# Returns: PID on stdout, exit 0 if found, exit 1 if not found
# Note: Returns "0" if no server found (for compatibility)
get_server_pid() {
    local pid_file="${1:-${GAME_DIR}/server.pid}"

    # Check PID file - with empty/corrupt file protection (Bug #3 fix)
    if [ -f "$pid_file" ] && [ -s "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null | tr -d '[:space:]')

        # Validate PID is numeric and process exists
        if [ -n "$pid" ] && [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    # Fallback to process name search
    local pid
    pid=$(pgrep -f "StarRuptureServerEOS" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi

    echo "0"
    return 1
}

# -----------------------------------------------------------------------------
# Build ID Functions
# -----------------------------------------------------------------------------
# Gets build ID from the app manifest file
# Args: $1 - Optional manifest file path
# Returns: Build ID or "not_installed"/"unknown" on error
get_build_id_from_manifest() {
    local manifest_file="${1:-${GAME_DIR}/steamapps/appmanifest_${STAR_APPID}.acf}"

    if [ ! -f "$manifest_file" ]; then
        echo "not_installed"
        return 1
    fi

    local build_id
    build_id=$(grep -oP '"buildid"\s*"\K[^"]+' "$manifest_file" 2>/dev/null)

    if [ -z "$build_id" ]; then
        echo "unknown"
        return 1
    fi

    echo "$build_id"
}

# Validates a build ID is a positive integer (Bug #4 fix)
# Args: $1 - Build ID to validate
# Returns: 0 if valid, 1 if invalid
validate_build_id() {
    local build_id="$1"

    # Must be non-empty, numeric, and greater than 0
    if [ -z "$build_id" ]; then
        return 1
    fi

    if ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$build_id" -le 0 ]; then
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Path Resolution
# -----------------------------------------------------------------------------
# Resolves server executable path with staging fallback
# Args: $1 - Primary exe path, $2 - Staging exe path
# Returns: Valid path on stdout, exit 1 if neither exists
resolve_executable_path() {
    local primary_exe="$1"
    local staging_exe="$2"

    if [ -f "$primary_exe" ]; then
        echo "$primary_exe"
        return 0
    elif [ -f "$staging_exe" ]; then
        log_warning "Using staging directory (verification incomplete)"
        echo "$staging_exe"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Directory Utilities
# -----------------------------------------------------------------------------
# Safely changes to a directory with error handling (Bug #5 fix)
# Args: $1 - Directory path
# Returns: 0 on success, exits with error on failure
safe_cd() {
    local target_dir="$1"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: $target_dir"
        exit 1
    fi

    cd "$target_dir" || {
        log_error "Failed to change to directory: $target_dir"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Help System
# -----------------------------------------------------------------------------
# Shows usage/help for scripts
# Args: $1 - Script name, $2 - Description, $3+ - Options (optional)
show_help() {
    local script_name="$1"
    local description="$2"
    shift 2

    cat << EOF
Usage: ${script_name} [OPTIONS]

Description:
  ${description}

Options:
  -h, --help    Show this help message
EOF

    # Print additional options if provided
    while [ $# -gt 0 ]; do
        echo "  $1"
        shift
    done

    cat << EOF

Environment Variables:
  GAME_DIR       Game installation directory (default: /starrupture)
  STAR_APPID     Steam App ID (default: 3809400)
  SERVER_PORT    Game server port (default: 7777)
  QUERY_PORT     Query port (default: 27015)

EOF
}

# Check for help flags at script start
# Args: $@ - Script arguments
check_help_flag() {
    for arg in "$@"; do
        if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
            return 0
        fi
    done
    return 1
}
