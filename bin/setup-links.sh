#!/bin/sh
# Register the procd init service.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
TARGET_DIR=$(dirname "$SCRIPT_DIR")

INIT_SOURCE="$TARGET_DIR/etc/init.d/ms_route"
INIT_DEST="/etc/init.d/ms_route"

# Validate source.
if [ ! -f "$INIT_SOURCE" ]; then
    echo "[-] Required init script not found: $INIT_SOURCE" >&2
    exit 1
fi

# Register service.
mkdir -p /etc/init.d || exit 1
chmod +x "$INIT_SOURCE" || exit 1

# Create or update symlink only when necessary.
if [ -L "$INIT_DEST" ] && [ "$(readlink "$INIT_DEST")" = "$INIT_SOURCE" ]; then
    echo "[*] Init service symlink already correct."
else
    rm -f "$INIT_DEST" || exit 1
    ln -s "$INIT_SOURCE" "$INIT_DEST" || exit 1
fi

# Enable boot startup.
"$INIT_DEST" enable || exit 1

echo "[+] Init service linked and enabled: $INIT_DEST"
