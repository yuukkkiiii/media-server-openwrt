
#!/bin/sh
# Install/update the local media server on OpenWrt router.
# Skip package installation if --skip-install is present in the arguments.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
REPO_ROOT=$(dirname "$SCRIPT_DIR")
APP_NAME="media-server-openwrt"
TARGET_DIR="/opt/$APP_NAME"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo "[-] Run setup.sh as root." >&2
    exit 1
fi

[ -f "$REPO_ROOT/bin/config.sh" ] || {
    echo "[-] Error: bin/config.sh not found." >&2
    exit 1
}
[ -f "$REPO_ROOT/.env.template" ] || {
    echo "[-] Error: .env.template not found." >&2
    exit 1
}

printf '[*] Deploying to %s...\n' "$TARGET_DIR"
mkdir -p "$TARGET_DIR" || exit 1

if [ "$REPO_ROOT" != "$TARGET_DIR" ]; then
    ENV_BACKUP=""
    if [ -f "$TARGET_DIR/.env" ]; then
        ENV_BACKUP="/tmp/${APP_NAME}.env.$$.bak"
        cp -p "$TARGET_DIR/.env" "$ENV_BACKUP" || exit 1
    fi

    cp -R "$REPO_ROOT/." "$TARGET_DIR/" || {
        if [ -n "$ENV_BACKUP" ]; then
            cp -p "$ENV_BACKUP" "$TARGET_DIR/.env"
            rm -f "$ENV_BACKUP"
        fi
        echo "[-] Failed to copy repository files." >&2
        exit 1
    }

    if [ -n "$ENV_BACKUP" ]; then
        cp -p "$ENV_BACKUP" "$TARGET_DIR/.env" || exit 1
        rm -f "$ENV_BACKUP"
    fi
fi

if [ ! -f "$TARGET_DIR/.env" ]; then
    cp "$TARGET_DIR/.env.template" "$TARGET_DIR/.env" || exit 1
    echo "[+] Created $TARGET_DIR/.env from template."
fi

chmod 600 "$TARGET_DIR/.env" 2>/dev/null || :

# Load shared configuration and application settings.
. "$TARGET_DIR/bin/config.sh" || exit 1
load_app_env || exit 1

# Create configured media directories only when they do not already exist.
# Existing directories and symlinks are preserved.
ensure_media_dir() {
    _DIR="$1"

    if [ -L "$_DIR" ] || [ -d "$_DIR" ]; then
        printf '[*] Preserving existing: %s\n' "$_DIR"
    elif [ -e "$_DIR" ]; then
        printf '[-] Path exists but is not a directory or symlink: %s\n' "$_DIR" >&2
        return 1
    else
        mkdir -p "$_DIR" || {
            printf '[-] Failed to create directory: %s\n' "$_DIR" >&2
            return 1
        }
        printf '[+] Created directory: %s\n' "$_DIR"
    fi
}

ensure_media_dir "$VIDEO_DIR" || exit 1
ensure_media_dir "$VIDEO_TEST_DIR" || exit 1

# Prepare application log.
mkdir -p /var/log || exit 1
touch "$APP_LOG_FILE" || exit 1
chmod 640 "$APP_LOG_FILE" 2>/dev/null || :

# Install required OpenWrt packages.
if printf '%s\n' "$@" | grep -q -- '--skip-install'; then
    printf '[*] Skipping OpenWrt package installation.\n'
else
    printf '[*] Installing required OpenWrt packages...\n'

    opkg update || {
        echo "[-] opkg update failed; check router connectivity and package feeds." >&2
        exit 1
    }

    opkg install \
        python3-light \
        python3-flask \
        python3-dotenv \
        nftables \
        kmod-nft-nat \
        nftables-json \
        kmod-fs-exfat \
        curl || {
            echo "[-] Dependency installation failed." >&2
            exit 1
        }
fi

# Make runtime scripts executable.
find "$TARGET_DIR/bin" -type f -name '*.sh' -exec chmod +x {} \;
chmod +x "$TARGET_DIR/etc/init.d/ms_route" || exit 1

# Register the OpenWrt init service.
"$TARGET_DIR/bin/setup-links.sh" || exit 1

# Enable and start the media server.
printf '[*] Enabling and starting local media server...\n'

/etc/init.d/ms_route enable || exit 1
/etc/init.d/ms_route restart || /etc/init.d/ms_route start || exit 1

# Verify the local anchor and nftables configuration.
/bin/sh "$TARGET_DIR/bin/network.sh" ensure || {
    echo "[!] Local shortcut is not ready. Inspect $APP_LOG_FILE and run bin/monitor.sh." >&2
    exit 1
}

echo "[+] Setup complete. URL: http://$ANCHOR_IP:$MEDIA_SERVER_PORT"
