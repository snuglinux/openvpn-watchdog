#!/usr/bin/env bash
#
# Installer for openvpn-watchdog.
# Installs the script, default config, and either a systemd timer or cron file.
# Existing configuration is preserved.

set -euo pipefail

APP_NAME="openvpn-watchdog"
SCRIPT_SRC="./openvpn-watchdog"
CONF_SRC="./openvpn-watchdog.conf"
SERVICE_SRC="./openvpn-watchdog.service"
TIMER_SRC="./openvpn-watchdog.timer"
CRON_SRC="./openvpn-watchdog.crontab"

BIN_DST="/usr/bin/${APP_NAME}"
CONF_DST="/etc/${APP_NAME}.conf"
SYSTEMD_DIR="/etc/systemd/system"
CRON_DST="/etc/cron.d/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
STATE_DIR="/var/lib/${APP_NAME}"

msg() {
    echo "[${APP_NAME}] $*"
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: run install.sh as root" >&2
        exit 1
    fi
}

install_main_files() {
    msg "Installing main script: ${BIN_DST}"
    install -D -m 0755 "$SCRIPT_SRC" "$BIN_DST"

    msg "Creating runtime directories"
    install -d -m 0755 "$LOG_DIR"
    install -d -m 0755 "$STATE_DIR"

    if [ -f "$CONF_DST" ]; then
        msg "Configuration already exists, keeping it unchanged: ${CONF_DST}"
        msg "New example config is available in the current directory: ${CONF_SRC}"
    else
        msg "Installing default config: ${CONF_DST}"
        install -D -m 0644 "$CONF_SRC" "$CONF_DST"
    fi
}

install_systemd_timer() {
    msg "Installing systemd units"
    install -D -m 0644 "$SERVICE_SRC" "${SYSTEMD_DIR}/${APP_NAME}.service"
    install -D -m 0644 "$TIMER_SRC" "${SYSTEMD_DIR}/${APP_NAME}.timer"

    systemctl daemon-reload
    systemctl enable --now "${APP_NAME}.timer"
    msg "systemd timer enabled: ${APP_NAME}.timer"
}

install_cron() {
    msg "systemd is not detected; installing cron file: ${CRON_DST}"
    install -D -m 0644 "$CRON_SRC" "$CRON_DST"
}

print_finish_message() {
    cat <<MSG

Installed successfully ✅

Next steps:
  1. Edit config:
     nano ${CONF_DST}

  2. Test without restarting services:
     ${BIN_DST} --dry-run

  3. Run one real check:
     ${BIN_DST}

Logs:
  ${LOG_DIR}

State:
  ${STATE_DIR}

MSG
}

main() {
    need_root
    install_main_files

    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        install_systemd_timer
    else
        install_cron
    fi

    print_finish_message
}

main "$@"
