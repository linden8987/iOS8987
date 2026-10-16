#!/usr/bin/env bash
# setup_tools.sh - install prerequisites and fetch the latest upstream tools into $IOSTOOL_ROOT/bin
set -euo pipefail

# Resolve repo root once, allowing override via env; otherwise derive from script path.
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
mkdir -p "$BIN_DIR" "$LOG_DIR" "$IOSTOOL_IPA_DIR"
LOG_FILE="$LOG_DIR/setup_tools.log"
GITHUB_API="https://api.github.com/repos"

log() {
    local lvl="${1:-INFO}"
    local msg="${2:-}"
    printf '%s [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$lvl" "$msg" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

install_prereqs() {
    if ! command -v apt-get >/dev/null 2>&1; then
        error_exit "apt-get is required but not present on this system"
    fi

    log INFO "Installing prerequisites via apt-get"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >> "$LOG_FILE" 2>&1 || true
    apt-get install -y libimobiledevice-utils usbmuxd curl jq unzip ca-certificates >> "$LOG_FILE" 2>&1 || error_exit "apt-get install failed; see $LOG_FILE"
    log INFO "Prerequisites installed"
}

download_release_asset() {
    local repo="$1"
    local pattern="$2"
    local out_name="$3"

    local api_url="$GITHUB_API/$repo/releases/latest"
    local release_json
    if ! release_json=$(curl -fsSL "$api_url"); then
        log "WARN" "Failed to query GitHub release API: $api_url"
        return 1
    fi

    local asset_url
    asset_url=$(printf '%s' "$release_json" | jq -r --arg pat "$pattern" '.assets[] | select(.name | test($pat)) | .browser_download_url' | head -n1)
    if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
        log "WARN" "No matching asset found for $repo using pattern '$pattern'"
        return 2
    fi

    local out_path="$BIN_DIR/$out_name"
    log INFO "Downloading $asset_url -> $out_path"
    if ! curl -L --fail --progress-bar -o "$out_path" "$asset_url"; then
        log "WARN" "Download failed for $asset_url"
        return 3
    fi

    chmod +x "$out_path" || true
    log INFO "Saved executable: $out_path"
    return 0
}

main() {
    log INFO "Starting setup_tools.sh"
    install_prereqs

    # Best-effort: fetch official iLoader binary if available from GitHub releases
    download_release_asset "nab138/iLoader" "linux|arm64|aarch64|x86_64" "iloader" || log "WARN" "iLoader not available or download failed; skipping"

    mkdir -p "$IOSTOOL_IPA_DIR"
    chmod 755 "$IOSTOOL_IPA_DIR"

    log INFO "Setup complete; BIN_DIR=$BIN_DIR IPA_DIR=$IOSTOOL_IPA_DIR"
}

main "$@"
