#!/bin/sh
# Shared OpenWrt system settings, application environment loader, and logging.

# --------------------------------------------------
# Installation and log paths
# --------------------------------------------------

BASE_DIR="/opt/media-server-openwrt"
APP_LOG_FILE="/var/log/media_server.log"
ENV_FILE="$BASE_DIR/.env"

# --------------------------------------------------
# Wi-Fi LAN
# --------------------------------------------------

LAN_ROUTER_INTERFACE="br-lan"
ANCHOR_IP="1.1.1.1"

# --------------------------------------------------
# nftables table owned exclusively by this application
# --------------------------------------------------

FW_TABLE="ms_shortcuts"

# --------------------------------------------------
# Application environment
# --------------------------------------------------

load_app_env() {
    if [ ! -r "$ENV_FILE" ]; then
        echo "[-] ERROR: Application environment not found: $ENV_FILE" >&2
        return 1
    fi

    . "$ENV_FILE" || {
        echo "[-] ERROR: Failed to load $ENV_FILE" >&2
        return 1
    }

    : "${MEDIA_SERVER_PORT:=8081}"
    : "${MEDIA_SERVER_BIND:=0.0.0.0}"
    : "${VIDEO_DIR:=$BASE_DIR/media}"

    export MEDIA_SERVER_PORT MEDIA_SERVER_BIND VIDEO_DIR
    return 0
}

# --------------------------------------------------
# Runtime logging
# --------------------------------------------------

ms_log() {
    _ms_message="$*"
    _ms_timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -n "$_ms_timestamp" ] || _ms_timestamp="unknown-time"

    if [ -n "${APP_LOG_FILE:-}" ]; then
        _ms_log_dir=${APP_LOG_FILE%/*}
        [ "$_ms_log_dir" = "$APP_LOG_FILE" ] && _ms_log_dir="."

        mkdir -p "$_ms_log_dir" 2>/dev/null || return 0

        printf '%s [MEDIA_SERVER] %s\n' \
            "$_ms_timestamp" \
            "$_ms_message" >> "$APP_LOG_FILE" 2>/dev/null || :
    fi
}