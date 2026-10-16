#!/usr/bin/env bash
# sideload.sh - scan IPA directory and sideload valid 64-bit apps.
set -euo pipefail

# Resolve repo root once; allow override via IOSTOOL_ROOT and IPA dir override via IOSTOOL_IPA_DIR.
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

: "${IOSTOOL_IPA_DIR:=/mnt/storage/IPAs}"
BIN_DIR="$IOSTOOL_ROOT/bin"
LOG_DIR="$IOSTOOL_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sideload.log"

# shellcheck source=usb_helper.sh
source "$IOSTOOL_ROOT/scripts/usb_helper.sh" || { echo "usb_helper.sh not found" >&2; exit 1; }

log() {
    local lvl="${1:-INFO}"
    local msg="${2:-}"
    printf '%s [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$lvl" "$msg" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

main() {
    log INFO "Starting sideload.sh"

    local udid
    if ! udid=$(check_device_connected); then
        error_exit "No iOS device connected. Connect device and try again."
    fi
    log INFO "Detected device: ${udid%%$'\n'*}"

    mkdir -p "$IOSTOOL_IPA_DIR" || true
    shopt -s nullglob
    local ipas=( "$IOSTOOL_IPA_DIR"/*.ipa )
    if [[ ${#ipas[@]} -eq 0 ]]; then
        log "WARN" "No .ipa files found in $IOSTOOL_IPA_DIR"
        exit 0
    fi

    for ipa in "${ipas[@]}"; do
        log INFO "Inspecting $ipa"

        local entries
        entries=$(unzip -Z1 "$ipa" 2>/dev/null | grep -E '^Payload/[^/]+\.app/[^/]+$' || true)
        local found_armv7=0
        local found_arm64=0

        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            if unzip -p "$ipa" "$entry" 2>/dev/null | head -c 65536 | grep -a -q 'armv7'; then
                found_armv7=1
            fi
            if unzip -p "$ipa" "$entry" 2>/dev/null | head -c 65536 | grep -a -q 'arm64'; then
                found_arm64=1
            fi
        done <<< "$entries"

        if [[ $found_armv7 -eq 1 && $found_arm64 -eq 0 ]]; then
            log "ERROR" "Blocked legacy 32-bit-only app (armv7 without arm64): $ipa"
            continue
        fi

        local engine="$BIN_DIR/iloader"
        if [[ -x "$engine" ]]; then
            log INFO "Sideloading $ipa using $engine"
            if "$engine" -i "$ipa" >> "$LOG_FILE" 2>&1; then
                log INFO "Sideload succeeded: $ipa"
            else
                log "ERROR" "Sideload failed for $ipa. See $LOG_FILE"
            fi
        else
            log "WARN" "No sideload engine found at $engine. Run Setup & Fetch Tools first."
            exit 2
        fi
    done

    log INFO "sideload.sh complete"
}

main "$@"
