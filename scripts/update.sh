#!/usr/bin/env bash
# jailbreak.sh - version-aware jailbreak orchestrator
set -euo pipefail

# Resolve repo root once; allow env override; use temp dir override via IOSTOOL_JB_TMP_DIR.
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

: "${IOSTOOL_JB_TMP_DIR:=/tmp/ios8987_bin}"
LOG_DIR="$IOSTOOL_ROOT/logs"
mkdir -p "$LOG_DIR" "$IOSTOOL_JB_TMP_DIR"
LOG_FILE="$LOG_DIR/jailbreak.log"
GITHUB_API="https://api.github.com/repos"

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

fetch_latest_asset() {
    local repo="$1"
    local pattern="$2"
    local out_name="$3"

    local api_url="$GITHUB_API/$repo/releases/latest"
    local release_json
    if ! release_json=$(curl -fsSL "$api_url"); then
        log "WARN" "Failed to query $api_url"
        return 1
    fi

    local asset_url
    asset_url=$(printf '%s' "$release_json" | jq -r --arg pat "$pattern" '.assets[] | select(.name | test($pat)) | .browser_download_url' | head -n1)
    if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
        log "WARN" "No matching asset found for $repo using pattern '$pattern'"
        return 2
    fi

    local out_path="$IOSTOOL_JB_TMP_DIR/$out_name"
    log INFO "Downloading $asset_url -> $out_path"
    if ! curl -L --fail --progress-bar -o "$out_path" "$asset_url"; then
        log "WARN" "Download failed for $asset_url"
        return 3
    fi

    chmod +x "$out_path" || true
    echo "$out_path"
    return 0
}

main() {
    log INFO "Starting jailbreak.sh"

    local udid
    if ! udid=$(check_device_connected); then
        error_exit "No iOS device connected. Connect device before jailbreak."
    fi
    log INFO "Connected device: ${udid%%$'\n'*}"

    if ! command -v ideviceinfo >/dev/null 2>&1; then
        error_exit "ideviceinfo not found. Install libimobiledevice-utils."
    fi

    local ios_version
    ios_version=$(ideviceinfo -u "$udid" -k ProductVersion 2>/dev/null || ideviceinfo -k ProductVersion 2>/dev/null) || error_exit "Unable to read ProductVersion from connected device"
    log INFO "Device iOS version: $ios_version"

    local major
    major=$(printf '%s' "$ios_version" | awk -F. '{print $1}')
    major=${major:-0}
    log INFO "Detected major iOS version: $major"

    if (( major >= 15 )); then
        log INFO "Routing to Dopamine for iOS >= 15"
        local dop_path
        dop_path=$(fetch_latest_asset "opa334/Dopamine" "linux|arm64|aarch64|x86_64|tar.gz" "dopamine" || true)
        if [[ -n "$dop_path" ]]; then
            log INFO "Dopamine fetched to $dop_path"
            "$dop_path" --help >> "$LOG_FILE" 2>&1 || true
        else
            log "WARN" "No Dopamine asset could be downloaded"
            exit 2
        fi
    else
        log INFO "Routing to palera1n for iOS < 15"
        local palera_path
        palera_path=$(fetch_latest_asset "palera1n/palera1n" "linux|arm64|aarch64|x86_64|tar.gz" "palera1n" || true)
        if [[ -n "$palera_path" ]]; then
            log INFO "palera1n fetched to $palera_path"
            "$palera_path" --version >> "$LOG_FILE" 2>&1 || true
        else
            log "WARN" "No palera1n asset could be downloaded"
            exit 2
        fi
    fi

    log INFO "jailbreak.sh completed successfully"
}

main "$@"
