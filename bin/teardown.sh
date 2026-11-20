#!/bin/sh
# Uninstall the local media server on OpenWrt router.
# Pass --keep-packages to retain installed OpenWrt packages.
#
# Application files and media directories under TARGET_DIR are preserved.

APP_NAME="media-server-openwrt"
TARGET_DIR="/opt/$APP_NAME"
INIT_SCRIPT="/etc/init.d/ms_route"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo "[-] Run teardown.sh as root." >&2
    exit 1
fi

# Load configuration before removing external application files.
if [ -f "$TARGET_DIR/bin/config.sh" ]; then
    . "$TARGET_DIR/bin/config.sh" 2>/dev/null || :
    load_app_env 2>/dev/null || :
fi

# Stop and disable the service.
printf '[*] Stopping and disabling local media server service...\n'

if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop 2>/dev/null || :
    "$INIT_SCRIPT" disable 2>/dev/null || :
fi

# Remove the copied init script outside TARGET_DIR.
rm -f "$INIT_SCRIPT"

# List configured media directories from .env.
printf '\n=== VIDEO_DIR: %s ===\n' "$VIDEO_DIR"
ls -l "$VIDEO_DIR" 2>/dev/null || :

printf '\n=== VIDEO_TEST_DIR: %s ===\n' "$VIDEO_TEST_DIR"
ls -l "$VIDEO_TEST_DIR" 2>/dev/null || :

printf '\n[*] Media directories and all files under %s are preserved.\n' "$TARGET_DIR"

# Remove OpenWrt packages unless explicitly skipped.
if printf '%s\n' "$@" | grep -q -- '--keep-packages'; then
    printf '[*] Skipping OpenWrt package removal (--keep-packages).\n'
else
    printf '[*] Removing OpenWrt packages...\n'

    opkg remove \
        python3-light \
        python3-flask \
        python3-dotenv \
        nftables \
        kmod-nft-nat \
        nftables-json \
        kmod-fs-exfat \
        curl 2>/dev/null || {
            echo "[!] Warning: Some packages could not be removed or were already uninstalled." >&2
        }

fi

echo "[+] Uninstallation complete."
