# openvpn-watchdog

[🇺🇦 Українська версія / Ukrainian version](README_uk.md)

**openvpn-watchdog** is a small and predictable watchdog for OpenVPN.  It can monitor multiple OpenVPN profiles at the same time and restart only the profile whose service or VPN connectivity check has failed.

> Important: this package **does not reboot the computer**.  Automatic host reboot logic should live in a separate watchdog package, so OpenVPN monitoring and whole-machine health monitoring stay cleanly separated.

---

## Why this tool exists

OpenVPN failures are not always the same:

- a systemd service may stop or enter the `failed` state;
- a client service may still be `active`, while the tunnel itself no longer works;
- one VPN profile may be broken while other profiles continue to work normally;
- an OpenVPN server may be healthy even when no VPN client is currently connected.

`openvpn-watchdog` keeps the rules simple and easy to understand:

| Profile type | What is checked | When restart is triggered |
|---|---|---|
| `SERVER` | systemd service only | when the service is not `active` |
| `CLIENT` without `ping=` | systemd service only | when the service is not `active` |
| `CLIENT` with `ping=` | systemd service + VPN ping target | when the service is not `active`, or when the VPN ping target is unavailable for several cycles |

There is no separate `check=` option.  The behavior is derived from `type` and optional `ping`, which keeps the configuration clear.

---

## Core logic

### `SERVER`

For server profiles, the watchdog checks only the systemd service:

```bash
systemctl is-active openvpn-server@main-server.service
```

A server profile is **not required to pass a ping check**.  An OpenVPN server may be working correctly even when no client is connected, or when the VPN-side address is not reachable from the local context.

### `CLIENT`

For client profiles, service status alone is often not enough.  For example:

```text
openvpn-client@office-client.service = active
```

but the VPN tunnel may still be broken.  For that reason, a client profile may define `ping=` — one or more VPN-side addresses that should answer when the tunnel is healthy.

---

## Configuration example

Configuration file:

```bash
/etc/openvpn-watchdog.conf
```

Example:

```bash
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

Example:

```bash
"name=office type=CLIENT ping=10.8.0.1"
```

checks:

```bash
openvpn-client@office-client.service
```

And:

```bash
"name=main type=SERVER"
```

checks:

```bash
openvpn-server@main-server.service
```

### `type`

OpenVPN profile type.

Allowed values:

```bash
SERVER
CLIENT
```

The logic is intentionally simple:

```text
SERVER -> systemd service only
CLIENT -> systemd service + ping, if ping is configured
```

### `ping`

Optional parameter.  It is mainly useful for `CLIENT` profiles.

Single target:

```bash
ping=10.8.0.1
```

Multiple targets, separated by commas:

```bash
ping=10.8.0.1,10.8.0.2
```

If multiple targets are configured, at least one successful reply is enough to consider the VPN check healthy.

For `SERVER` profiles, `ping=` is normally not needed and should usually be omitted.

### `restart_cycles`

Number of failed VPN ping cycles for a `CLIENT` profile before the OpenVPN service is restarted.

```bash
restart_cycles=3
```

This means: if the VPN target is unavailable for 3 consecutive watchdog runs, restart the related OpenVPN client service.

> If the systemd service itself is not `active`, restart is performed immediately and does not wait for `restart_cycles`.

### `service`

Optional parameter for non-standard systemd service names.

```bash
"name=office type=CLIENT service=openvpn-client@office.service ping=10.8.0.1 restart_cycles=3"
```

If `service=` is set, the watchdog uses that exact service name instead of generating one automatically.

---

## Internet availability guard

For client VPN profiles, the watchdog can avoid unnecessary restarts when the whole host has no internet access.

Example settings:

```bash
INTERNET_CHECK_ENABLED="YES"
PING_SERVER_INT="8.8.8.8,1.1.1.1"
SKIP_CLIENT_PING_WHEN_INTERNET_DOWN="YES"
```

When internet access is down:

- OpenVPN systemd service states are still checked;
- client VPN ping checks may be skipped;
- this prevents restarting all OpenVPN clients just because the upstream internet link is unavailable.

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
2026-05-03T13:15:01+0300 severity=WARNING profile=office type=CLIENT service=openvpn-client@office-client.service event=vpn_ping_unavailable message=VPN target is unavailable: 10.8.0.1. Failure cycle: 1/3
```

The event log is intentionally structured so it can later be analyzed by another script or forwarded to Matrix, Email, Zabbix, or another monitoring system.

---

## Basic journalctl analysis

The configuration already contains a foundation for future problem analysis:

```bash
LOG_ANALYSIS_ENABLED="YES"
LOG_ANALYSIS_LINES=120
LOG_ANALYSIS_MAX_MATCHES=5
LOG_ANALYSIS_PATTERNS="AUTH_FAILED|TLS Error|Inactivity timeout|Connection reset|Cannot resolve host address|VERIFY ERROR|Options error|Exiting due to fatal error"
```

Current behavior:

- when a service or ping problem is detected;
- the watchdog reads recent `journalctl` lines for the affected service;
- it searches for common OpenVPN error patterns;
- it writes additional structured events such as `log_pattern_detected`.

Log analysis currently **does not make independent restart decisions**.  It only records useful diagnostic information for troubleshooting and future notifications.

---

## Notification hook for Email / Matrix

The configuration includes a hook for future notifications:

```bash
NOTIFICATIONS_ENABLED="NO"
NOTIFY_SCRIPT=""
```

Later it can be enabled like this:

```bash
NOTIFICATIONS_ENABLED="YES"
NOTIFY_SCRIPT="/usr/local/bin/openvpn-watchdog-notify.sh"
```

The hook receives these environment variables:

```bash
OPENVPN_WATCHDOG_TIME
OPENVPN_WATCHDOG_SEVERITY
OPENVPN_WATCHDOG_PROFILE
OPENVPN_WATCHDOG_TYPE
OPENVPN_WATCHDOG_SERVICE
OPENVPN_WATCHDOG_EVENT
OPENVPN_WATCHDOG_MESSAGE
OPENVPN_WATCHDOG_LOG_FILE
OPENVPN_WATCHDOG_EVENT_LOG
```

This makes it possible to implement separate integrations for:

- Email notifications;
- Matrix notifications;
- monitoring systems;
- repeated-error analysis;
- escalation rules for critical OpenVPN failures.

An example hook script is included:

```bash
examples/openvpn-watchdog-notify.example.sh
```

---

## Installation

```bash
sudo ./install.sh
```

The installer places files here:

```text
/usr/bin/openvpn-watchdog
/etc/openvpn-watchdog.conf
/etc/systemd/system/openvpn-watchdog.service
/etc/systemd/system/openvpn-watchdog.timer
```

If systemd is not available, it installs a cron file instead:

```text
/etc/cron.d/openvpn-watchdog
```

Existing `/etc/openvpn-watchdog.conf` is not overwritten.

---

## Dry run

Run without restarting services or calling notification hooks:

```bash
sudo openvpn-watchdog --dry-run
```

In dry-run mode, the watchdog:

- reads the configuration;
- checks profiles;
- writes logs;
- does **not** restart services;
- does **not** call the notification hook.

---

## Manual run and diagnostics

Run manually:

```bash
sudo openvpn-watchdog
```

Check the timer:

```bash
systemctl status openvpn-watchdog.timer
```

View recent service logs:

```bash
journalctl -u openvpn-watchdog.service -n 100 --no-pager
```

---

## Migration from the old `auto-restart-openvpn`

The old configuration was tied to a single profile:

```bash
NAME_SERVICE='client_openvpn'
TYPE='CLIENT'
PING_SERVER_VPN='10.8.0.1'
```

New configuration:

```bash
OPENVPN_PROFILES=(
    "name=client_openvpn type=CLIENT ping=10.8.0.1 restart_cycles=3"
)
```

Old server-style configuration:

```bash
NAME_SERVICE='main'
TYPE='SERVER'
```

New configuration:

```bash
OPENVPN_PROFILES=(
    "name=main type=SERVER restart_cycles=3"
)
```

---

## What was intentionally removed

This package no longer contains:

- automatic computer reboot logic;
- `REBOOT_AFTER_CYCLES`;
- `AUTOMATION_SCRIPT` execution before reboot.

That functionality should be implemented later as a separate host/system watchdog package.

---

## Recommended future development

1. A separate reboot/system watchdog package.
2. A dedicated Matrix notification hook.
3. A dedicated Email notification hook.
4. A parser/analyzer for `/var/log/openvpn-watchdog/events.log`.
5. Threshold rules, for example: if `AUTH_FAILED` repeats N times, send a critical notification.
6. Optional integration with monitoring systems such as Zabbix, Prometheus exporters, or custom health dashboards.
