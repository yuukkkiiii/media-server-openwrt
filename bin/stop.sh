#!/bin/sh
# Stop the procd-managed Flask service. stop_service cleans app-owned network state.

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$BIN_DIR/config.sh" || exit 1

if [ -x /etc/init.d/ms_route ]; then
    echo "[*] Stopping local media server service..."
    /etc/init.d/ms_route stop
else
    /bin/sh "$BIN_DIR/network.sh" cleanup
fi

echo "[-] Media server stopped and local shortcut removed."
