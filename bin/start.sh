#!/bin/sh
# Restart the procd-managed Flask service and ensure the local shortcut.

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
. "$BIN_DIR/config.sh" || exit 1
load_app_env || exit 1

if [ ! -x /etc/init.d/ms_route ]; then
    echo "[-] /etc/init.d/ms_route is missing. Run bin/setup.sh first." >&2
    exit 1
fi

printf '[*] Restarting local media server service...\n'
/etc/init.d/ms_route restart || /etc/init.d/ms_route start || exit 1

/bin/sh "$BIN_DIR/network.sh" ensure || exit 1
sleep 2

if pgrep -f "$BASE_DIR/app/media_server.py" >/dev/null 2>&1; then
    echo "[+] Flask server process is running."
else
    echo "[-] Flask server process is not running. Check logread and $APP_LOG_FILE." >&2
    exit 1
fi

echo "[+] Local media URL: http://$ANCHOR_IP:$MEDIA_SERVER_PORT"
echo "[+] Log: $APP_LOG_FILE"
