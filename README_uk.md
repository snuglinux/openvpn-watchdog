# openvpn-watchdog

[🇬🇧 English README](README.md)

**openvpn-watchdog** — це невеликий і передбачуваний Bash-watchdog для OpenVPN. Він стежить за кількома OpenVPN `CLIENT` і `SERVER` профілями та перезапускає тільки той OpenVPN service, у якому виявлена проблема.

> Важливо: цей пакет **не перезавантажує комп’ютер**. Логіку автоматичного reboot планується винести в окремий watchdog-пакет, щоб контроль OpenVPN і контроль стану всієї машини залишалися розділеними задачами.

---

## Що змінено у 0.2.0

- Підтримка кількох OpenVPN `CLIENT` і `SERVER` профілів.
- `SERVER` перевіряється тільки за станом systemd service.
- `CLIENT` перевіряється за станом systemd service і необов’язковими VPN-side ICMP `ping=` цілями.
- Глобальний `INTERNET_CHECK` може використовувати HTTP(S) через `curl`, що корисно, коли провайдер або firewall блокує ICMP.
- Англійські та українські повідомлення інтерфейсу.
- Англійські та українські змінні повідомлень для notification hook.
- Структурований event log для майбутнього аналізу логів і Email/Matrix сповіщень.
- `--dry-run` режим не змінює persistent counters.
- Пакет замінює застарілий `auto-restart-openvpn`.

---

## Основна логіка

| Тип профілю | Що перевіряється | Коли виконується restart |
|---|---|---|
| `SERVER` | тільки systemd service | якщо service не `active` |
| `CLIENT` без `ping=` | тільки systemd service | якщо service не `active` |
| `CLIENT` з `ping=` | systemd service + VPN-side ICMP ping | якщо service не `active`, або якщо всі задані ping-цілі недоступні кілька циклів поспіль |

Окремого параметра `check=` немає. Поведінка визначається через `type` і необов’язковий `ping=`, тому конфіг залишається простим.

HTTP(S)/`curl` перевірки **не використовуються** для VPN client профілів. Вони підтримуються тільки в глобальному блоці `INTERNET_CHECK`.

---

## Приклад конфігурації

Файл конфігурації:

```bash
/etc/openvpn-watchdog.conf
```

Приклад:

```bash
OPENVPN_WATCHDOG_LANGUAGE="auto"

OPENVPN_PROFILES=(
    "name=office type=CLIENT ping=10.8.0.1 restart_cycles=3"
    "name=branch type=CLIENT ping=10.9.0.1,10.9.0.2 restart_cycles=3"
    "name=main type=SERVER restart_cycles=3"
)
```

---

## Параметри профілю

### `name`

Назва OpenVPN-профілю.

Для стандартних OpenVPN systemd units назва service формується автоматично:

| Тип | Назва service |
|---|---|
| `SERVER` | `openvpn-server@<name>-server.service` |
| `CLIENT` | `openvpn-client@<name>-client.service` |

### `type`

Дозволені значення:

```bash
SERVER
CLIENT
```

Проста поведінка:

```text
SERVER -> тільки systemd service
CLIENT -> systemd service + ping-ціль, якщо задано
```

### `ping`

Необов’язковий список ICMP-цілей. Це єдина VPN-side перевірка доступності для `CLIENT` профілів.

```bash
ping=10.8.0.1
ping=10.8.0.1,10.8.0.2
```

Якщо вказано кілька цілей, достатньо, щоб відповіла хоча б одна.

Для `SERVER` профілів `ping=` ігнорується, бо OpenVPN server може бути справним навіть тоді, коли зараз немає підключених клієнтів.

### `restart_cycles`

Кількість невдалих ping-циклів `CLIENT`, після яких service буде перезапущено.

```bash
restart_cycles=3
```

Якщо сам systemd service не `active`, restart виконується одразу і не очікує `restart_cycles`.

### `service`

Необов’язкова точна назва systemd service для нестандартних OpenVPN units.

```bash
"name=office type=CLIENT service=openvpn-client@office.service ping=10.8.0.1 restart_cycles=3"
```

---

## Глобальна перевірка інтернету

Для клієнтських VPN watchdog може не виконувати зайві restart, якщо на всьому хості немає інтернету.

Іноді провайдер або firewall блокує ICMP. Тому `INTERNET_CHECK` може використовувати HTTP(S) через `curl`, наприклад:

```bash
curl -4 -I --connect-timeout 8 https://google.com
```

Конфігурація:

```bash
INTERNET_CHECK_ENABLED="YES"
INTERNET_CHECK_METHOD="auto"
HTTP_SERVER_INT="https://google.com,https://cloudflare.com"
PING_SERVER_INT="8.8.8.8,1.1.1.1"
SKIP_CLIENT_PING_WHEN_INTERNET_DOWN="YES"
```

`INTERNET_CHECK_METHOD` підтримує:

| Метод | Поведінка |
|---|---|
| `auto` | спочатку HTTP(S), потім ping |
| `http` | тільки HTTP(S) через `curl` |
| `ping` | тільки ICMP ping |

HTTP-налаштування, які використовує Internet check:

```bash
HTTP_CONNECT_TIMEOUT=8
HTTP_MAX_TIME=12
HTTP_IP_VERSION="4"        # 4, 6 або auto
HTTP_REQUEST_METHOD="HEAD" # HEAD або GET
```

Коли інтернет недоступний:

- стани OpenVPN systemd services все одно перевіряються;
- ping-перевірки VPN client можуть бути пропущені;
- це захищає від масового restart усіх OpenVPN clients через проблему upstream/provider.

---

## Мова та зовнішні файли перекладу

Мову інтерфейсу можна налаштувати глобально:

```bash
OPENVPN_WATCHDOG_LANGUAGE="auto"
OPENVPN_WATCHDOG_LOCALE_DIR="/usr/share/openvpn-watchdog/locale"
```

Доступні значення мови:

```bash
auto
en
uk
```

Файли перекладу винесені окремо від основного скрипта:

```text
/usr/share/openvpn-watchdog/locale/en.conf
/usr/share/openvpn-watchdog/locale/uk.conf
```

Якщо запускати проєкт прямо з вихідного каталогу, скрипт автоматично використовує локальні файли:

```text
./locale/en.conf
./locale/uk.conf
```

Так логіка watchdog не змішується з текстами інтерфейсу, а нові переклади буде простіше додавати пізніше.

Також можна вказати мову для одного запуску:

```bash
sudo openvpn-watchdog --language uk --dry-run
sudo openvpn-watchdog --language en --dry-run
```

---

## Логи

Звичайні денні логи:

```bash
/var/log/openvpn-watchdog/YYYY.MM.DD-hostname.log
```

Структурований event log:

```bash
/var/log/openvpn-watchdog/events.log
```

Приклад рядка event log:

```text
2026-05-03T13:15:01+0300 severity=WARNING profile=office type=CLIENT service=openvpn-client@office-client.service event=vpn_ping_unavailable language=uk message=VPN ping-ціль недоступна: ping=10.8.0.1. Цикл помилки: 1/3
```

Формат зроблений так, щоб пізніше його було легко аналізувати окремим скриптом або відправляти у Matrix, Email, Zabbix чи іншу систему моніторингу.

---

## Основа для notification hook

Основний скрипт може викликати notification hook:

```bash
NOTIFICATIONS_ENABLED="YES"
NOTIFY_SCRIPT="/usr/local/bin/openvpn-watchdog-notify.sh"
```

Hook отримує активну мову та перекладені варіанти повідомлення:

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

Це дозволяє майбутнім Email/Matrix hooks вибирати мову повідомлень без парсингу логів.

Приклад hook:

```bash
examples/openvpn-watchdog-notify.example.sh
```

---

## Базовий аналіз journalctl

У конфігу вже є початкові налаштування аналізу логів:

```bash
LOG_ANALYSIS_ENABLED="YES"
LOG_ANALYSIS_LINES=120
LOG_ANALYSIS_MAX_MATCHES=5
LOG_ANALYSIS_PATTERNS="AUTH_FAILED|TLS Error|Inactivity timeout|Connection reset|Cannot resolve host address|VERIFY ERROR|Options error|Exiting due to fatal error"
```

Поточна поведінка:

- коли виявлено проблему service або VPN ping;
- watchdog перевіряє останні рядки `journalctl` відповідного service;
- типові OpenVPN-помилки записуються як structured events.

Аналіз логів поки **не приймає самостійних рішень про restart**. Він тільки збирає діагностичну інформацію для майбутніх сповіщень і аналізу.

---

## Встановлення

```bash
sudo ./install.sh
```

Скрипт встановить:

```text
/usr/bin/openvpn-watchdog
/etc/openvpn-watchdog.conf
/etc/systemd/system/openvpn-watchdog.service
/etc/systemd/system/openvpn-watchdog.timer
/usr/share/openvpn-watchdog/locale/en.conf
/usr/share/openvpn-watchdog/locale/uk.conf
```

Якщо systemd не знайдено, буде встановлено cron-файл:

```text
/etc/cron.d/openvpn-watchdog
```

Існуючий `/etc/openvpn-watchdog.conf` не перезаписується.

---

## Dry run

```bash
sudo openvpn-watchdog --dry-run
```

У цьому режимі watchdog:

- читає конфіг;
- перевіряє профілі;
- друкує логи в stdout;
- **не перезапускає services**;
- **не викликає notification hook**;
- **не змінює persistent counters**.

---

## Arch Linux пакет

Пакувальні файли:

```text
packaging/arch/PKGBUILD
packaging/arch/openvpn-watchdog.install
```

Збірка:

```bash
cd packaging/arch
updpkgsums
makepkg --printsrcinfo > .SRCINFO
makepkg -s
```

`openvpn-watchdog` замінює застарілий пакет `auto-restart-openvpn`.

---

## ClearOS / CentOS 7 RPM пакет

RPM spec файл:

```text
packaging/rpm/openvpn-watchdog.spec
```

Source tarball для версії `0.2.0`:

```text
https://github.com/snuglinux/openvpn-watchdog/archive/refs/tags/0.2.0.tar.gz
```

RPM пакет obsoletes/replaces застарілий пакет `auto-restart-openvpn`.
