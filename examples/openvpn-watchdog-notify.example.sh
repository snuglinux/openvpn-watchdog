#!/usr/bin/env bash
#
# Example multilingual notification hook for openvpn-watchdog.
#
# This file is intentionally simple and does not send Email/Matrix yet. Copy it
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
#   OPENVPN_WATCHDOG_LANGUAGE
#   OPENVPN_WATCHDOG_MESSAGE
#   OPENVPN_WATCHDOG_MESSAGE_EN
#   OPENVPN_WATCHDOG_MESSAGE_UK
#   OPENVPN_WATCHDOG_LOG_FILE
#   OPENVPN_WATCHDOG_EVENT_LOG

set -euo pipefail

LOG_FILE="/var/log/openvpn-watchdog/notifications.log"
mkdir -p "$(dirname "$LOG_FILE")"

LANGUAGE_CODE="${OPENVPN_WATCHDOG_LANGUAGE:-en}"
MESSAGE="${OPENVPN_WATCHDOG_MESSAGE:-}"

# Example: force a specific notification language here if needed.
# case "$LANGUAGE_CODE" in
#     uk) MESSAGE="${OPENVPN_WATCHDOG_MESSAGE_UK:-$MESSAGE}" ;;
#     *)  MESSAGE="${OPENVPN_WATCHDOG_MESSAGE_EN:-$MESSAGE}" ;;
# esac

printf '%s [%s] lang=%s profile=%s event=%s message=%s\n' \
    "${OPENVPN_WATCHDOG_TIME:-unknown-time}" \
    "${OPENVPN_WATCHDOG_SEVERITY:-INFO}" \
    "$LANGUAGE_CODE" \
    "${OPENVPN_WATCHDOG_PROFILE:-unknown-profile}" \
    "${OPENVPN_WATCHDOG_EVENT:-unknown-event}" \
    "$MESSAGE" >> "$LOG_FILE"

# TODO: Matrix example can be added here later.
# Suggested data:
#   title:   "OpenVPN watchdog: ${OPENVPN_WATCHDOG_PROFILE}"
#   body:    "$MESSAGE"
#   severity:"${OPENVPN_WATCHDOG_SEVERITY}"
#
# TODO: Email example can be added here later.
# Suggested subject:
#   "[${OPENVPN_WATCHDOG_SEVERITY}] OpenVPN watchdog: ${OPENVPN_WATCHDOG_PROFILE}"

exit 0
