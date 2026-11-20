
#!/bin/sh
# Local diagnostic report. No tether, DNS, or public-IP diagnostics.

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$BIN_DIR/config.sh" || exit 1
load_app_env || exit 1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

status_line() {
    LABEL=$1
    OK=$2
    DETAIL=$3

    if [ "$OK" = "1" ]; then
        printf '   - %-27s %b%s%b\n' "$LABEL" "$GREEN" "$DETAIL" "$NC"
    else
        printf '   - %-27s %b%s%b\n' "$LABEL" "$RED" "$DETAIL" "$NC"
    fi
}

show_directory_status() {
    DIR_LABEL=$1
    DIR_PATH=$2
    REQUIRE_MOUNT=${3:-0}

    printf '   %s: %s\n' "$DIR_LABEL" "$DIR_PATH"

    if [ ! -d "$DIR_PATH" ]; then
        status_line "Status:" 0 "MISSING"
        FILE_COUNT=0
        DIR_COUNT=0
        return 1
    fi

    REAL_DIR=$(readlink -f "$DIR_PATH" 2>/dev/null)
    REAL_DIR=${REAL_DIR:-$DIR_PATH}

    FILE_COUNT=$(find -L "$DIR_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
    DIR_COUNT=$(find -L "$DIR_PATH" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

    FILE_COUNT=${FILE_COUNT:-0}
    DIR_COUNT=${DIR_COUNT:-0}

    printf '      Files:       %s\n' "$FILE_COUNT"
    printf '      Directories: %s\n' "$DIR_COUNT"

    if [ "$REQUIRE_MOUNT" = "1" ]; then
        if awk -v p="$REAL_DIR" '$2 == p { found=1 } END { exit !found }' /proc/mounts; then
            if [ "$FILE_COUNT" -eq 0 ]; then
                status_line "Status:" 0 "MOUNTED BUT EMPTY"
                return 1
            fi

            status_line "Status:" 1 "MOUNTED"
            return 0
        fi

        status_line "Status:" 0 "NOT MOUNTED"
        return 1
    fi

    if [ "$FILE_COUNT" -gt 0 ]; then
        status_line "Status:" 1 "AVAILABLE"
        return 0
    fi

    status_line "Status:" 0 "EMPTY"
    return 1
}

show_disk_device_info() {
    printf '\n%bDISK DEVICE INFO%b\n' "$BLUE" "$NC"
    printf '   Diagnostic information only; VIDEO_DIR may or may not be external storage.\n'

    printf '\n   - Block devices (/dev/sd*):\n'
    SD_DEVICES=$(ls /dev/sd* 2>/dev/null)

    if [ -n "$SD_DEVICES" ]; then
        printf '%s\n' "$SD_DEVICES" | sed 's/^/      /'
    else
        echo "      No /dev/sd* devices found."
    fi

    printf '\n   - block info:\n'
    if command -v block >/dev/null 2>&1; then
        block info 2>&1 | sed 's/^/      /'
    else
        echo "      block command not available."
    fi
}

ANCHOR_PRESENT=0
if ip -4 -o addr show dev "$LAN_ROUTER_INTERFACE" 2>/dev/null \
    | awk '{print $4}' | grep -Fx "$ANCHOR_IP/32" >/dev/null 2>&1; then
    ANCHOR_PRESENT=1
fi

printf '%b==============================================================%b\n' "$BLUE" "$NC"
printf '       LOCAL MEDIA SERVER - DIAGNOSTICS\n'
printf '%b==============================================================%b\n' "$BLUE" "$NC"

printf '\n%bLOCAL NETWORK STATUS%b\n' "$BLUE" "$NC"
printf '   - LAN interface:              %s\n' "$LAN_ROUTER_INTERFACE"
printf '   - Anchor address:             %s/32\n' "$ANCHOR_IP"
printf '   - Media URL:                  http://%s:%s\n' "$ANCHOR_IP" "$MEDIA_SERVER_PORT"

ANCHOR_DETAIL="MISSING"
[ "$ANCHOR_PRESENT" -eq 1 ] && ANCHOR_DETAIL="PRESENT"
status_line "Anchor IP alias:" "$ANCHOR_PRESENT" "$ANCHOR_DETAIL"

printf '\n%bSERVICE STATUS%b\n' "$BLUE" "$NC"
if [ -x /etc/init.d/ms_route ] && /etc/init.d/ms_route enabled >/dev/null 2>&1; then
    status_line "Boot autostart:" 1 ENABLED
else
    status_line "Boot autostart:" 0 DISABLED
fi

if pgrep -f "$BASE_DIR/app/media_server.py" >/dev/null 2>&1; then
    status_line "Flask process:" 1 RUNNING
else
    status_line "Flask process:" 0 STOPPED
fi

printf '\n%bWEB ACCESS CHECK%b\n' "$BLUE" "$NC"
if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
        "http://$ANCHOR_IP:$MEDIA_SERVER_PORT/" 2>/dev/null)

    case "$HTTP_CODE" in
        200|401)
            status_line "HTTP endpoint:" 1 "REACHABLE (HTTP $HTTP_CODE)"
            ;;
        *)
            status_line "HTTP endpoint:" 0 "FAILED (HTTP ${HTTP_CODE:-000})"
            ;;
    esac
else
    status_line "HTTP endpoint:" 0 "curl not installed"
fi

printf '\n%bNFTABLES SHORTCUT%b\n' "$BLUE" "$NC"
if nft list table inet "$FW_TABLE" >/dev/null 2>&1; then
    status_line "Table inet $FW_TABLE:" 1 PRESENT
    nft list table inet "$FW_TABLE"
else
    status_line "Table inet $FW_TABLE:" 0 MISSING
fi

printf '\n%bSTORAGE STATUS%b\n' "$BLUE" "$NC"

show_directory_status "VIDEO_DIR" "$VIDEO_DIR" 1
VIDEO_DIR_EXISTS=$?
VIDEO_DIR_FILES=$FILE_COUNT

if [ -n "${VIDEO_TEST_DIR:-}" ]; then
    printf '\n'
    show_directory_status "VIDEO_TEST_DIR" "$VIDEO_TEST_DIR"
fi

if [ "$VIDEO_DIR_EXISTS" -ne 0 ]; then
    show_disk_device_info
fi

printf '\n%bRECENT APPLICATION LOG%b\n' "$BLUE" "$NC"
if [ -f "$APP_LOG_FILE" ]; then
    tail -n 20 "$APP_LOG_FILE"
else
    echo "   Log file not found: $APP_LOG_FILE"
fi

printf '%b==============================================================%b\n' "$BLUE" "$NC"
