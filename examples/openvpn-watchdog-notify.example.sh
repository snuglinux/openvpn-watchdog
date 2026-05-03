#!/usr/bin/env bash
#
# Example notification hook for openvpn-watchdog.
#
# This file is intentionally simple and does not send Email/Matrix yet.  Copy it
# to /usr/local/bin/openvpn-watchdog-notify.sh, make it executable, and replace
# the TODO blocks with real Matrix/Email sending logic.
#
# The main script passes event details through environment variables:
#   OPENVPN_WATCHDOG_TIME
#   OPENVPN_WATCHDOG_SEVERITY
#   OPENVPN_WATCHDOG_PROFILE
#   OPENVPN_WATCHDOG_TYPE
#   OPENVPN_WATCHDOG_SERVICE
#   OPENVPN_WATCHDOG_EVENT
#   OPENVPN_WATCHDOG_MESSAGE
#   OPENVPN_WATCHDOG_LOG_FILE
#   OPENVPN_WATCHDOG_EVENT_LOG

set -euo pipefail

LOG_FILE="/var/log/openvpn-watchdog/notifications.log"
mkdir -p "$(dirname "$LOG_FILE")"

printf '%s [%s] profile=%s event=%s message=%s\n' \
    "${OPENVPN_WATCHDOG_TIME:-unknown-time}" \
    "${OPENVPN_WATCHDOG_SEVERITY:-INFO}" \
    "${OPENVPN_WATCHDOG_PROFILE:-unknown-profile}" \
    "${OPENVPN_WATCHDOG_EVENT:-unknown-event}" \
    "${OPENVPN_WATCHDOG_MESSAGE:-}" >> "$LOG_FILE"

# TODO: Matrix example can be added here later.
# TODO: Email example can be added here later.

exit 0
