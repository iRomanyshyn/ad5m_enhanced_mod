#!/usr/bin/env bash
# Verify a USB-UART adapter on the bench with its TX and RX pins deliberately
# shorted together. This tool is not an AD5M console, FEL, SWD, or flash tool.
set -euo pipefail

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  AD5M_UART_LOOPBACK_CONFIRM=TX_RX_SHORTED ./tools/uart-loopback-check.sh /dev/ttyUSB0

Before running, disconnect the adapter from every target, set it to 3.3 V if
it has a voltage selector, and short only its TX and RX pins together. Do not
connect VCC. The script sends one harmless text line to the selected adapter
and requires the same line to return through that bench loopback.
EOF
}

if [[ $# -ne 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    [[ $# -eq 1 ]] && exit 0
    exit 2
fi

port=$1
[[ "$port" == /dev/* ]] || fail "serial port must be an absolute /dev path"
[[ -c "$port" ]] || fail "not a character device: $port"
[[ "${AD5M_UART_LOOPBACK_CONFIRM:-}" == "TX_RX_SHORTED" ]] || \
    fail "set AD5M_UART_LOOPBACK_CONFIRM=TX_RX_SHORTED only after bench-looping TX to RX"

original_settings=$(stty -F "$port" -g) || fail "cannot read serial settings for $port"
restore_port() {
    stty -F "$port" "$original_settings" || true
}
trap restore_port EXIT

# 115200 8N1 is a common console configuration. The loopback result proves
# only the host adapter and cable/pin loop; it does not prove any AD5M setting.
stty -F "$port" 115200 cs8 -cstopb -parenb -ixon -ixoff -echo -icanon min 0 time 10
exec 3<>"$port"

nonce="AD5M-UART-LOOPBACK-${RANDOM}${RANDOM}"
printf '%s\n' "$nonce" >&3

for _attempt in 1 2 3; do
    if IFS= read -r -t 2 -u 3 received && [[ "$received" == "$nonce" ]]; then
        printf 'ok: UART loopback passed on %s at 115200 8N1\n' "$port"
        exit 0
    fi
done

fail "did not receive the test line; disconnect from targets and check TX↔RX, voltage mode, cable and permissions"
