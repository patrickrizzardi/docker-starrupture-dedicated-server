#!/bin/bash
# Star Rupture Server Update Script
# Downloads/updates the game via SteamCMD with build ID tracking

# Note: NOT using set -e because we need retry logic to handle SteamCMD failures

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

# Paths
CURRENT_BUILD_ID_FILE="${GAME_DIR}/current_build_id.txt"
APP_MANIFEST="${GAME_DIR}/steamapps/appmanifest_${STAR_APPID}.acf"

# Get the latest available build ID from Steam
get_current_build_id() {
    log_info "Querying Steam for latest build ID..."

    local steamcmd_output=$("${STEAM_DIR}/steamcmd.sh" +login anonymous +app_info_print ${STAR_APPID} +quit 2>/dev/null)

    local build_id=$(echo "$steamcmd_output" | \
        grep -A 150 "\"branches\"" | \
        grep -A 50 "\"public\"" | \
        grep -m 1 -oP "\"buildid\"\s*\"*\K[0-9]+" | \
        head -n 1 | \
        tr -d '[:space:]')

    if [ -z "$build_id" ] || ! [[ "$build_id" =~ ^[0-9]+$ ]]; then
        log_warning "Could not retrieve build ID from Steam"
        echo "unknown"
        return 1
    fi

    echo "$build_id"
}

# Get the installed build ID from app manifest
get_installed_build_id() {
    if [ ! -f "$APP_MANIFEST" ]; then
        log_info "No app manifest found (first install)"
        echo "none"
        return 0
    fi

    local build_id=$(grep -oP '"buildid"\s*"\K[^"]+' "$APP_MANIFEST" 2>/dev/null || echo "")

    if [ -z "$build_id" ]; then
        echo "unknown"
        return 1
    fi

    echo "$build_id"
}

# Check if update is needed
needs_update() {
    local current_build=$(get_current_build_id)
    local installed_build=$(get_installed_build_id)

    log_info "Steam build:     $current_build"
    log_info "Installed build: $installed_build"

    # Always update if no installation or unknown state
    if [ "$installed_build" = "none" ] || [ "$installed_build" = "unknown" ]; then
        return 0
    fi

    # Compare build IDs
    if [ "$current_build" != "$installed_build" ]; then
        log_success "Update available: $installed_build -> $current_build"
        return 0
    fi

    log_success "Server is up to date (build $installed_build)"
    return 1
}

# Check if files exist in staging area and move them
recover_staged_files() {
    local staging_dir="${GAME_DIR}/steamapps/downloading/${STAR_APPID}"
    local staged_exe="${staging_dir}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe"

    if [ -f "$staged_exe" ]; then
        log_info "Found staged files, recovering from failed verification..."

        # Remove potentially broken directories owned by root (from failed SteamCMD)
        # Then copy from staging
        for dir in StarRupture Engine; do
            if [ -d "${GAME_DIR}/${dir}" ]; then
                # Check if we can write to it
                if ! touch "${GAME_DIR}/${dir}/.writetest" 2>/dev/null; then
                    log_warning "Removing unwritable ${dir} directory..."
                    rm -rf "${GAME_DIR}/${dir}" 2>/dev/null || true
                else
                    rm -f "${GAME_DIR}/${dir}/.writetest"
                fi
            fi
        done

        # Copy staged content to game directory
        if [ -d "${staging_dir}/StarRupture" ]; then
            log_info "Copying StarRupture directory..."
            cp -r "${staging_dir}/StarRupture" "${GAME_DIR}/" 2>&1 || true
        fi
        if [ -d "${staging_dir}/Engine" ]; then
            log_info "Copying Engine directory..."
            cp -r "${staging_dir}/Engine" "${GAME_DIR}/" 2>&1 || true
        fi
        if [ -f "${staging_dir}/StarRuptureServerEOS.exe" ]; then
            cp "${staging_dir}/StarRuptureServerEOS.exe" "${GAME_DIR}/" 2>/dev/null || true
        fi

        # Check if recovery worked
        if [ -f "${GAME_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe" ]; then
            log_success "Successfully recovered staged files"
            return 0
        else
            log_error "Recovery failed - exe not found after copy"
        fi
    fi

    return 1
}

# Run SteamCMD with retry logic
run_steamcmd() {
    local validate_flag="$1"
    local max_retries=3
    local retry=0

    while [ $retry -lt $max_retries ]; do
        retry=$((retry + 1))
        log_info "SteamCMD attempt $retry of $max_retries..."

        "${STEAM_DIR}/steamcmd.sh" \
            +@sSteamCmdForcePlatformType windows \
            +force_install_dir "${GAME_DIR}" \
            +login anonymous \
            +app_update ${STAR_APPID} ${validate_flag} \
            +quit

        local status=$?

        # Check if successful or if exe exists
        if [ $status -eq 0 ]; then
            return 0
        fi

        # Check if exe exists in main location OR staging
        if [ -f "${GAME_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe" ]; then
            log_success "Server executable found despite exit code $status"
            return 0
        fi

        # Check staging directory (verification may have failed but files are usable)
        local staging_exe="${GAME_DIR}/steamapps/downloading/${STAR_APPID}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe"
        if [ -f "$staging_exe" ]; then
            log_success "Server executable found in staging (verification incomplete, but usable)"
            return 0
        fi

        # Try to recover from staging if verification failed
        if recover_staged_files; then
            return 0
        fi

        if [ $retry -lt $max_retries ]; then
            log_warning "Attempt $retry failed (exit code $status), retrying in 5s..."
            sleep 5
        fi
    done

    # Final attempt to recover staged files
    if recover_staged_files; then
        return 0
    fi

    return 1
}

# Perform the update
do_update() {
    log_info "Starting Star Rupture server download/update..."

    local start_time=$(date +%s)
    local is_fresh_install=false

    # Check if this is a fresh install (no exe yet)
    if [ ! -f "${GAME_DIR}/StarRupture/Binaries/Win64/StarRuptureServerEOS-Win64-Shipping.exe" ]; then
        is_fresh_install=true
        log_info "Fresh install detected - downloading without validate first"
    fi

    # Run SteamCMD with appropriate flags
    # Don't use validate on first install, it can cause issues
    if [ "$is_fresh_install" = true ]; then
        if ! run_steamcmd ""; then
            log_error "SteamCMD failed after multiple retries"
            log_info "Tip: If this persists, try removing the starrupture_data volume and starting fresh"
            return 1
        fi
    else
        if ! run_steamcmd "validate"; then
            log_error "SteamCMD validation failed after multiple retries"
            return 1
        fi
    fi

    local elapsed=$(($(date +%s) - start_time))
    log_success "Update completed in ${elapsed}s"

    # Update cached build ID
    local new_build=$(get_installed_build_id)
    if [ "$new_build" != "unknown" ] && [ "$new_build" != "none" ] && [ "$new_build" != "0" ]; then
        echo "$new_build" > "$CURRENT_BUILD_ID_FILE"
        log_info "Cached build ID: $new_build"
    fi

    # Cleanup temp files
    rm -rf "${STEAM_DIR}/Steam/logs/"* 2>/dev/null || true
    rm -rf /tmp/SteamCMD_* 2>/dev/null || true

    return 0
}

# Main
main() {
    log_info "=== Star Rupture Update Check ==="

    # Handle --force flag
    if [ "$1" = "--force" ]; then
        log_info "Force update requested"
        do_update
        exit $?
    fi

    # Check if update needed
    if needs_update; then
        do_update
        exit $?
    fi

    exit 0
}

main "$@"
