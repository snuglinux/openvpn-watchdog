# openvpn-watchdog

[🇺🇦 Українська версія / Ukrainian version](README_uk.md)

**openvpn-watchdog** is a small and predictable Bash watchdog for OpenVPN. It monitors multiple OpenVPN `CLIENT` and `SERVER` profiles and restarts only the OpenVPN service where a problem was detected.

> Important: this package **does not reboot the computer**. Automatic host reboot logic is planned as a separate watchdog package, so OpenVPN monitoring and whole-machine health monitoring stay cleanly separated.

---

## What changed in 0.2.0

- Multiple OpenVPN `CLIENT` and `SERVER` profiles.
- `SERVER` profiles are checked by systemd service state only.
- `CLIENT` profiles are checked by systemd service state and optional VPN-side ICMP `ping=` targets.
- Global `INTERNET_CHECK` can use HTTP(S) through `curl`, which is useful when ICMP is blocked by a provider or firewall.
- English/Ukrainian interface messages.
- English/Ukrainian notification hook message variables.
- Structured event log for future log analysis and Email/Matrix notifications.
- `--dry-run` mode is read-only and does not update persistent counters.
- Replaces the deprecated `auto-restart-openvpn` package.

---

## Core logic

| Profile type | What is checked | When restart is triggered |
|---|---|---|
| `SERVER` | systemd service only | when the service is not `active` |
| `CLIENT` without `ping=` | systemd service only | when the service is not `active` |
| `CLIENT` with `ping=` | systemd service + VPN-side ICMP ping | when the service is not `active`, or when all configured ping targets are unavailable for several cycles |

There is no separate `check=` option. Behavior is derived from `type` and optional `ping=`, which keeps the configuration clear.

HTTP(S)/`curl` checks are **not** used for VPN client profiles. They are supported only by the global `INTERNET_CHECK` block.

---

## Configuration example

Configuration file:

```bash
/etc/openvpn-watchdog.conf
```

Example:

```bash
OPENVPN_WATCHDOG_LANGUAGE="auto"

OPENVPN_PROFILES=(
    "name=office type=CLIENT ping=10.8.0.1 restart_cycles=3"
    "name=branch type=CLIENT ping=10.9.0.1,10.9.0.2 restart_cycles=3"
    "name=main type=SERVER restart_cycles=3"
)
```

---

## Profile parameters

### `name`

OpenVPN profile name.

For standard OpenVPN systemd units, the service name is generated automatically:

| Type | Generated service name |
|---|---|
| `SERVER` | `openvpn-server@<name>-server.service` |
| `CLIENT` | `openvpn-client@<name>-client.service` |

### `type`

Allowed values:

```bash
SERVER
CLIENT
```

Simple behavior:

```text
SERVER -> systemd service only
CLIENT -> systemd service + ping target if configured
```

### `ping`

Optional ICMP target list. This is the only VPN-side connectivity check supported for `CLIENT` profiles.

```bash
ping=10.8.0.1
ping=10.8.0.1,10.8.0.2
```

If several targets are configured, at least one successful reply is enough.

For `SERVER` profiles, `ping=` is ignored because an OpenVPN server can be healthy even when no clients are connected.

### `restart_cycles`

Number of failed `CLIENT` ping cycles before the service is restarted.

```bash
restart_cycles=3
```

If the systemd service itself is not `active`, restart is performed immediately and does not wait for `restart_cycles`.

### `service`

Optional exact systemd service name for non-standard OpenVPN units.

```bash
"name=office type=CLIENT service=openvpn-client@office.service ping=10.8.0.1 restart_cycles=3"
```

---

## Internet availability guard

For client VPN profiles, the watchdog can avoid unnecessary restarts when the whole host has no Internet access.

Some providers/firewalls block ICMP. For this reason `INTERNET_CHECK` can use HTTP(S) with `curl`, for example:

```bash
curl -4 -I --connect-timeout 8 https://google.com
```

Configuration:

```bash
INTERNET_CHECK_ENABLED="YES"
INTERNET_CHECK_METHOD="auto"
HTTP_SERVER_INT="https://google.com,https://cloudflare.com"
PING_SERVER_INT="8.8.8.8,1.1.1.1"
SKIP_CLIENT_PING_WHEN_INTERNET_DOWN="YES"
```

`INTERNET_CHECK_METHOD` supports:

| Method | Behavior |
|---|---|
| `auto` | try HTTP(S) first, then ping |
| `http` | use only HTTP(S) checks through `curl` |
| `ping` | use only ICMP ping checks |

HTTP settings used by the Internet check:

```bash
HTTP_CONNECT_TIMEOUT=8
HTTP_MAX_TIME=12
HTTP_IP_VERSION="4"        # 4, 6, or auto
HTTP_REQUEST_METHOD="HEAD" # HEAD or GET
```

When Internet access is down:

- OpenVPN systemd service states are still checked;
- VPN client ping checks may be skipped;
- this prevents restarting all OpenVPN clients because the upstream Internet link is unavailable.

---

## Language and external translation files

The interface language can be configured globally:

```bash
OPENVPN_WATCHDOG_LANGUAGE="auto"
OPENVPN_WATCHDOG_LOCALE_DIR="/usr/share/openvpn-watchdog/locale"
```

Supported language values:

```bash
auto
en
uk
```

Translation files are stored outside the main script:

```text
/usr/share/openvpn-watchdog/locale/en.conf
/usr/share/openvpn-watchdog/locale/uk.conf
```

When running from a source checkout, the script automatically uses local files from:

```text
./locale/en.conf
./locale/uk.conf
```

This keeps the watchdog logic separate from user-facing text and makes future translations easier to add.

The language can also be set for a single run:

```bash
sudo openvpn-watchdog --language uk --dry-run
sudo openvpn-watchdog --language en --dry-run
```

---

## Logs

Regular daily logs:

```bash
/var/log/openvpn-watchdog/YYYY.MM.DD-hostname.log
```

Structured event log:

```bash
/var/log/openvpn-watchdog/events.log
```

Example event log line:

```text
2026-05-03T13:15:01+0300 severity=WARNING profile=office type=CLIENT service=openvpn-client@office-client.service event=vpn_ping_unavailable language=en message=VPN ping target is unavailable: ping=10.8.0.1. Failure cycle: 1/3
```

The event log is intentionally structured so it can later be analyzed by another script or forwarded to Matrix, Email, Zabbix, or another monitoring system.

---

## Notification hook foundation

The main script can call a notification hook:

```bash
NOTIFICATIONS_ENABLED="YES"
NOTIFY_SCRIPT="/usr/local/bin/openvpn-watchdog-notify.sh"
```

The hook receives active-language text and translated variants:

```bash
OPENVPN_WATCHDOG_TIME
OPENVPN_WATCHDOG_SEVERITY
OPENVPN_WATCHDOG_PROFILE
OPENVPN_WATCHDOG_TYPE
OPENVPN_WATCHDOG_SERVICE
OPENVPN_WATCHDOG_EVENT
OPENVPN_WATCHDOG_LANGUAGE
OPENVPN_WATCHDOG_MESSAGE
OPENVPN_WATCHDOG_MESSAGE_EN
OPENVPN_WATCHDOG_MESSAGE_UK
OPENVPN_WATCHDOG_LOG_FILE
OPENVPN_WATCHDOG_EVENT_LOG
```

This allows future Email/Matrix hooks to choose the message language without parsing logs.

Example hook:

```bash
examples/openvpn-watchdog-notify.example.sh
```

---

## Basic journalctl analysis

The configuration already includes initial log analysis settings:

```bash
LOG_ANALYSIS_ENABLED="YES"
LOG_ANALYSIS_LINES=120
LOG_ANALYSIS_MAX_MATCHES=5
LOG_ANALYSIS_PATTERNS="AUTH_FAILED|TLS Error|Inactivity timeout|Connection reset|Cannot resolve host address|VERIFY ERROR|Options error|Exiting due to fatal error"
```

Current behavior:

- when a service or VPN ping problem is detected;
- watchdog checks recent `journalctl` lines for the affected service;
- common OpenVPN errors are written as structured events.

Log analysis does **not** make restart decisions yet. It only collects diagnostic information for future alerts and analysis.

---

## Installation

```bash
sudo ./install.sh
```

The script installs:

```text
/usr/bin/openvpn-watchdog
/etc/openvpn-watchdog.conf
/etc/systemd/system/openvpn-watchdog.service
/etc/systemd/system/openvpn-watchdog.timer
/usr/share/openvpn-watchdog/locale/en.conf
/usr/share/openvpn-watchdog/locale/uk.conf
```

If systemd is not found, it installs a cron file instead:

```text
/etc/cron.d/openvpn-watchdog
```

Existing `/etc/openvpn-watchdog.conf` is not overwritten.

---

## Dry run

```bash
sudo openvpn-watchdog --dry-run
```

In this mode the watchdog:

- reads the configuration;
- checks profiles;
- prints logs to stdout;
- does **not** restart services;
- does **not** call the notification hook;
- does **not** update persistent counters.

---

## Arch Linux package

Packaging files are included:

```text
packaging/arch/PKGBUILD
packaging/arch/openvpn-watchdog.install
```

Build:

```bash
cd packaging/arch
updpkgsums
makepkg --printsrcinfo > .SRCINFO
makepkg -s
```

`openvpn-watchdog` replaces the deprecated `auto-restart-openvpn` package.

---

## ClearOS / CentOS 7 RPM package

RPM spec file:

```text
packaging/rpm/openvpn-watchdog.spec
```

Source tarball for version `0.2.0`:

```text
https://github.com/snuglinux/openvpn-watchdog/archive/refs/tags/0.2.0.tar.gz
```

The RPM package obsoletes/replaces the deprecated `auto-restart-openvpn` package.
