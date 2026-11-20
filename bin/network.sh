#!/bin/sh
# bin/network.sh
#
# Manages the local media server network shortcut.
#
# Architecture:
#   1. Bind ANCHOR_IP/32 to LAN_ROUTER_INTERFACE.
#   2. Create an application-owned nftables table.
#   3. Redirect anchor traffic arriving on LAN_ROUTER_INTERFACE
#      to the Flask media server.
#

# --------------------------------------------------
# Load configuration
# --------------------------------------------------

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1

. "$BIN_DIR/config.sh" || exit 1

load_app_env || exit 1


# --------------------------------------------------
# Validation
# --------------------------------------------------

valid_port() {
    case "$MEDIA_SERVER_PORT" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    [ "$MEDIA_SERVER_PORT" -ge 1 ] &&
    [ "$MEDIA_SERVER_PORT" -le 65535 ]
}

validate_config() {
    [ -n "$LAN_ROUTER_INTERFACE" ] || {
        ms_log "ERROR: LAN_ROUTER_INTERFACE is empty."
        return 1
    }

    [ -n "$ANCHOR_IP" ] || {
        ms_log "ERROR: ANCHOR_IP is empty."
        return 1
    }

    [ -n "$FW_TABLE" ] || {
        ms_log "ERROR: FW_TABLE is empty."
        return 1
    }

    if ! valid_port; then
        ms_log "ERROR: Invalid MEDIA_SERVER_PORT: $MEDIA_SERVER_PORT."
        return 1
    fi

    command -v ip >/dev/null 2>&1 || {
        ms_log "ERROR: ip command unavailable."
        return 1
    }

    command -v nft >/dev/null 2>&1 || {
        ms_log "ERROR: nft command unavailable."
        return 1
    }

    return 0
}


# --------------------------------------------------
# Check anchor IP
# --------------------------------------------------

anchor_ready() {
    ip -4 -o addr show dev "$LAN_ROUTER_INTERFACE" 2>/dev/null |
        awk -v expected="$ANCHOR_IP/32" '
            $4 == expected { found=1 }
            END { exit !found }
        '
}


# --------------------------------------------------
# Verify complete nftables configuration
# --------------------------------------------------

network_ready() {

    # 1. Verify anchor address.
    anchor_ready || return 1

    # 2. Verify application-owned nftables table.
    nft list table inet "$FW_TABLE" >/dev/null 2>&1 || return 1

    # 3. Verify prerouting NAT chain.
    _PRE_CHAIN=$(
        nft list chain inet "$FW_TABLE" dstnat 2>/dev/null
    ) || return 1

    printf '%s\n' "$_PRE_CHAIN" |
        grep -F 'type nat' >/dev/null 2>&1 || return 1

    printf '%s\n' "$_PRE_CHAIN" |
        grep -F 'hook prerouting' >/dev/null 2>&1 || return 1

    # 4. Verify redirect is restricted to the configured LAN interface,
    #    anchor IP, and TCP port.
    _SIGNATURE="iifname \"$LAN_ROUTER_INTERFACE\" ip daddr $ANCHOR_IP tcp dport $MEDIA_SERVER_PORT"
    _REDIRECT="redirect to :$MEDIA_SERVER_PORT"

    printf '%s\n' "$_PRE_CHAIN" |
        grep -F "$_SIGNATURE" |
        grep -F "$_REDIRECT" >/dev/null 2>&1 || return 1

    return 0
}


# --------------------------------------------------
# Apply network configuration
# --------------------------------------------------

apply_network() {

    ms_log "Applying local anchor and nftables configuration."

    validate_config || return 1

    # 1. Verify LAN interface.
    if ! ip link show dev "$LAN_ROUTER_INTERFACE" >/dev/null 2>&1; then
        ms_log "ERROR: LAN interface $LAN_ROUTER_INTERFACE does not exist."
        return 1
    fi

    # 2. Install the static anchor IP.
    if ! anchor_ready; then
        if ! ip addr add "$ANCHOR_IP/32" dev "$LAN_ROUTER_INTERFACE"; then
            ms_log "ERROR: Failed to bind $ANCHOR_IP/32 to $LAN_ROUTER_INTERFACE."
            return 1
        fi
    fi

    # 3. Remove the previous application-owned table.
    # Other OpenWrt firewall tables remain untouched.
    nft delete table inet "$FW_TABLE" >/dev/null 2>&1 || :

    # 4. Create the application-owned table.
    if ! nft add table inet "$FW_TABLE"; then
        ms_log "ERROR: Failed to create nftables table inet $FW_TABLE."
        return 1
    fi

    # 5. Create prerouting NAT chain.
    if ! nft "add chain inet $FW_TABLE dstnat { type nat hook prerouting priority -100; policy accept; }"; then
        nft delete table inet "$FW_TABLE" >/dev/null 2>&1 || :
        ms_log "ERROR: Failed to create prerouting chain."
        return 1
    fi

    # 6. Redirect incoming browser traffic on the LAN interface only.
    if ! nft add rule inet "$FW_TABLE" dstnat \
        iifname "$LAN_ROUTER_INTERFACE" \
        ip daddr "$ANCHOR_IP" \
        tcp dport "$MEDIA_SERVER_PORT" \
        counter redirect to ":$MEDIA_SERVER_PORT"; then

        nft delete table inet "$FW_TABLE" >/dev/null 2>&1 || :
        ms_log "ERROR: Failed to install prerouting redirect."
        return 1
    fi

    # 7. Verify the completed configuration.
    if ! network_ready; then
        ms_log "ERROR: Network installation completed but verification failed."
        return 1
    fi

    ms_log "Network ready: http://$ANCHOR_IP:$MEDIA_SERVER_PORT"
    ms_log "Anchor: $ANCHOR_IP/32 on $LAN_ROUTER_INTERFACE"
    ms_log "NFT table: inet $FW_TABLE"

    return 0
}


# --------------------------------------------------
# Remove network configuration
# --------------------------------------------------

cleanup_network() {

    ms_log "Removing application network configuration."

    # Remove only our own nftables table.
    nft delete table inet "$FW_TABLE" >/dev/null 2>&1 || :

    # Remove only our own anchor address.
    ip addr del "$ANCHOR_IP/32" dev "$LAN_ROUTER_INTERFACE" \
        >/dev/null 2>&1 || :

    ms_log "Removed nftables table $FW_TABLE and anchor $ANCHOR_IP/32."

    return 0
}


# --------------------------------------------------
# Command dispatcher
# --------------------------------------------------

case "${1:-apply}" in

    apply)
        apply_network
        exit $?
        ;;

    ensure)
        if network_ready; then
            exit 0
        fi

        ms_log "Network configuration incomplete; rebuilding."
        apply_network
        exit $?
        ;;

    check)
        if network_ready; then
            echo "[+] Anchor and nftables configuration are READY."
            exit 0
        else
            echo "[-] Anchor or nftables configuration is INCOMPLETE."
            exit 1
        fi
        ;;

    cleanup)
        cleanup_network
        exit $?
        ;;

    *)
        echo "Usage: $0 {apply|ensure|check|cleanup}" >&2
        exit 2
        ;;

esac