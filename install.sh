#!/usr/bin/env bash
#
# Installer for openvpn-watchdog.
#
# This installer is intended for manual/source installation. Distribution
# packages should use the provided PKGBUILD or RPM spec instead.
#
# Responsibilities:
#   * install the watchdog script and default configuration;
#   * install either a systemd timer or a cron fallback;
#   * preserve an existing openvpn-watchdog configuration;
#   * cleanly disable/remove legacy manual auto-restart-openvpn leftovers.

set -euo pipefail

APP_NAME="openvpn-watchdog"
LEGACY_NAME="auto-restart-openvpn"
INSTALL_LANGUAGE="${OPENVPN_WATCHDOG_LANGUAGE:-auto}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
LOCALE_SRC="${SCRIPT_DIR}/locale"
SCRIPT_SRC="${SCRIPT_DIR}/openvpn-watchdog"
CONF_SRC="${SCRIPT_DIR}/openvpn-watchdog.conf"
SERVICE_SRC="${SCRIPT_DIR}/openvpn-watchdog.service"
TIMER_SRC="${SCRIPT_DIR}/openvpn-watchdog.timer"
CRON_SRC="${SCRIPT_DIR}/openvpn-watchdog.crontab"

BIN_DST="/usr/bin/${APP_NAME}"
CONF_DST="/etc/${APP_NAME}.conf"
SYSTEMD_DIR="/etc/systemd/system"
CRON_DST="/etc/cron.d/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
STATE_DIR="/var/lib/${APP_NAME}"
SHARE_DIR="/usr/share/${APP_NAME}"
LOCALE_DST="${SHARE_DIR}/locale"

LEGACY_CONF="/etc/${LEGACY_NAME}.conf"
LEGACY_CONF_BACKUP="/etc/${LEGACY_NAME}.conf.${APP_NAME}-migration-backup"

normalize_language() {
    local value="${1:-auto}"
    value="${value,,}"
    if [ "$value" = "auto" ] || [ -z "$value" ]; then
        value="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
        value="${value,,}"
    fi
    case "$value" in
        uk|uk_*|uk.*|ua|ua_*|ua.*) printf 'uk' ;;
        *) printf 'en' ;;
    esac
}

LANGUAGE_CODE="$(normalize_language "$INSTALL_LANGUAGE")"

locale_file_for_lang() {
    local lang="$(normalize_language "${1:-en}")"
    printf '%s/%s.conf' "$LOCALE_SRC" "$lang"
}

tr_msg() {
    local key="$1"
    shift || true
    local file
    local var_name
    local template=""

    file="$(locale_file_for_lang "$LANGUAGE_CODE")"
    var_name="I18N_install_${key}"

    if [ -f "$file" ]; then
        # shellcheck disable=SC1090
        template="$({ source "$file"; printf '%s' "${!var_name:-}"; } 2>/dev/null || true)"
    fi

    if [ -z "$template" ] && [ "$LANGUAGE_CODE" != "en" ]; then
        file="$(locale_file_for_lang en)"
        if [ -f "$file" ]; then
            # shellcheck disable=SC1090
            template="$({ source "$file"; printf '%s' "${!var_name:-}"; } 2>/dev/null || true)"
        fi
    fi

    if [ -z "$template" ]; then
        case "$key" in
            need_root) template='ERROR: run install.sh as root' ;;
            *) template="$key" ;;
        esac
    fi

    # shellcheck disable=SC2059
    printf "$template" "$@"
}

msg() {
    echo "[${APP_NAME}] $(tr_msg "$@")"
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "$(tr_msg need_root)" >&2
        exit 1
    fi
}

# Disable old auto-restart-openvpn units and remove files that were commonly
# created by the old manual installer. The old configuration is not deleted; it
# is copied to a migration backup so the admin can manually convert it to the new
# OPENVPN_PROFILES format.
remove_legacy_auto_restart_openvpn() {
    msg checking_legacy "$LEGACY_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "${LEGACY_NAME}.timer" >/dev/null 2>&1 || true
        systemctl disable --now "${LEGACY_NAME}.service" >/dev/null 2>&1 || true
    fi

    if [ -f "$LEGACY_CONF" ] && [ ! -f "$LEGACY_CONF_BACKUP" ]; then
        msg preserve_old_config "$LEGACY_CONF_BACKUP"
        cp -a "$LEGACY_CONF" "$LEGACY_CONF_BACKUP"
    fi

    rm -f \
        "/usr/bin/${LEGACY_NAME}" \
        "/etc/cron.d/${LEGACY_NAME}" \
        "/etc/systemd/system/${LEGACY_NAME}.service" \
        "/etc/systemd/system/${LEGACY_NAME}.timer" \
        "/usr/lib/systemd/system/${LEGACY_NAME}.service" \
        "/usr/lib/systemd/system/${LEGACY_NAME}.timer"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

# Install the executable, configuration, and runtime directories. Existing
# /etc/openvpn-watchdog.conf is intentionally preserved.
install_main_files() {
    msg install_script "$BIN_DST"
    install -D -m 0755 "$SCRIPT_SRC" "$BIN_DST"

    msg create_dirs
    install -d -m 0755 "$LOG_DIR"
    install -d -m 0755 "$STATE_DIR"

    if [ -f "$CONF_DST" ]; then
        msg config_keep "$CONF_DST"
        msg config_example "$CONF_SRC"
    else
        msg config_install "$CONF_DST"
        install -D -m 0644 "$CONF_SRC" "$CONF_DST"
    fi
}

# Install external translation files used by both the watchdog script and the
# notification interface.  Keeping translations under /usr/share makes it easier
# to add languages later without touching the main watchdog logic.
install_locale_files() {
    msg install_locale "$LOCALE_DST"
    install -d -m 0755 "$LOCALE_DST"

    if [ -d "$LOCALE_SRC" ]; then
        find "$LOCALE_SRC" -maxdepth 1 -type f -name '*.conf' -print0 \
            | while IFS= read -r -d '' locale_file; do
                install -D -m 0644 "$locale_file" "$LOCALE_DST/$(basename "$locale_file")"
            done
    fi
}

# Systemd mode is the preferred mode for Arch Linux, ClearOS/CentOS 7, and most
# modern Linux distributions.
install_systemd_timer() {
    msg install_systemd
    install -D -m 0644 "$SERVICE_SRC" "${SYSTEMD_DIR}/${APP_NAME}.service"
    install -D -m 0644 "$TIMER_SRC" "${SYSTEMD_DIR}/${APP_NAME}.timer"

    systemctl daemon-reload
    systemctl enable --now "${APP_NAME}.timer"
    msg timer_enabled "${APP_NAME}.timer"
}

# Cron fallback is kept for non-systemd systems only. The Arch/RPM packages do
# not install this file as an active cron job to avoid double scheduling.
install_cron() {
    msg install_cron "$CRON_DST"
    install -D -m 0644 "$CRON_SRC" "$CRON_DST"
}

print_finish_message() {
    printf '\n'
    tr_msg finish_text "$CONF_DST" "$BIN_DST" "$BIN_DST" "$LOG_DIR" "$STATE_DIR" "$LEGACY_NAME" "$LEGACY_CONF_BACKUP"
    printf '\n'
}

main() {
    need_root
    remove_legacy_auto_restart_openvpn
    install_main_files
    install_locale_files

    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        install_systemd_timer
    else
        install_cron
    fi

    print_finish_message
}

main "$@"
