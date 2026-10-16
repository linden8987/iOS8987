#!/usr/bin/env bash
# usb_helper.sh - shared helper utilities for iOS8987 scripts.
# Includes check_device_connected() using idevice_id -l.
set -euo pipefail

# Resolve repo root once, allowing override via environment; if absent, derive from this script path.
: "${IOSTOOL_ROOT:=}"
if [[ -z "$IOSTOOL_ROOT" ]]; then
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SCRIPT_SOURCE" ]; do
        DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
        SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
        [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
    done
    SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" >/dev/null 2>&1 && pwd )"
    IOSTOOL_ROOT="$( cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )"
fi

LOG_DIR="$IOSTOOL_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/usb_helper.log"

log() {
    local lvl="${1:-INFO}"
    local msg="${2:-}"
    printf '%s [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$lvl" "$msg" >> "$LOG_FILE"
}

die() {
    log "ERROR" "$*"
    echo "$*" >&2
    exit 1
}

check_device_connected() {
    if ! command -v idevice_id >/dev/null 2>&1; then
        log "ERROR" "idevice_id not found. Install libimobiledevice-utils."
        return 2
    fi

    local udids
    if ! udids=$(idevice_id -l 2>/dev/null); then
        log "ERROR" "idevice_id failed to run"
        return 2
    fi

    udids=$(printf '%s' "$udids" | tr -d '\r')
    if [[ -z "${udids//[$'\t\n ']/}" ]]; then
        log "INFO" "No iOS device detected"
        return 1
    fi

    printf '%s\n' "$udids"
    return 0
}
