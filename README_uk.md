# openvpn-watchdog

[🇬🇧 English README](README.md)

**openvpn-watchdog** — це невеликий watchdog для OpenVPN, який може одночасно стежити за кількома OpenVPN-профілями та перезапускати тільки той VPN-сервіс, у якому виявлена проблема.

> Важливо: цей пакет **не перезавантажує комп’ютер**.  Логіку автоматичного reboot краще винести в окремий пакет, щоб не змішувати дві різні задачі: контроль OpenVPN і контроль стану всієї машини.

---

## Для чого потрібен

OpenVPN-сервіс може виглядати по-різному залежно від ситуації:

- service впав або має стан `failed`;
- service формально `active`, але клієнтський тунель фактично не працює;
- один VPN-профіль зламався, а інші працюють нормально;
- на сервері OpenVPN service працює, але зараз немає активних клієнтів — це не повинно вважатися проблемою.

`openvpn-watchdog` вирішує це просто:

| Тип профілю | Що перевіряється | Коли виконується restart |
|---|---|---|
| `SERVER` | тільки systemd service | якщо service не `active` |
| `CLIENT` без `ping=` | тільки systemd service | якщо service не `active` |
| `CLIENT` з `ping=` | systemd service + ping VPN-адреси | якщо service не `active` або ping недоступний кілька циклів |

Окремого параметра `check=` немає. Поведінка визначається через `type` і необов’язковий `ping`, тому конфіг залишається простим і зрозумілим.

---

## Основна логіка

### `SERVER`

Для сервера достатньо перевіряти systemd service:

```bash
systemctl is-active openvpn-server@main-server.service
```

Сервер **не потрібно обов’язково перевіряти ping-ом**, бо OpenVPN-сервер може бути справний навіть тоді, коли зараз немає підключених клієнтів або VPN-адреса недоступна з локального контексту.

### `CLIENT`

Для клієнта service-статусу часто недостатньо.  Наприклад:

```text
openvpn-client@office-client.service = active
```

але тунель може не працювати.  Тому для клієнта можна додати `ping=` — адресу всередині VPN, яка має відповідати, коли тунель справний.

---

## Приклад конфігурації

Файл:

```bash
/etc/openvpn-watchdog.conf
```

Приклад:

```bash
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

Для стандартних systemd-сервісів з неї автоматично формується service name:

| Тип | Формат service |
|---|---|
| `SERVER` | `openvpn-server@<name>-server.service` |
| `CLIENT` | `openvpn-client@<name>-client.service` |

Наприклад:

```bash
"name=office type=CLIENT ping=10.8.0.1"
```

буде перевіряти:

```bash
openvpn-client@office-client.service
```

А:

```bash
"name=main type=SERVER"
```

буде перевіряти:

```bash
openvpn-server@main-server.service
```

### `type`

Тип OpenVPN-профілю.

Дозволені значення:

```bash
SERVER
CLIENT
```

Логіка максимально проста:

```text
SERVER -> тільки systemd service
CLIENT -> systemd service + ping, якщо ping заданий
```

### `ping`

Необов’язковий параметр.  Має сенс переважно для `CLIENT`.

Можна вказати одну адресу:

```bash
ping=10.8.0.1
```

або кілька адрес через кому:

```bash
ping=10.8.0.1,10.8.0.2
```

Якщо вказано кілька адрес, достатньо, щоб відповідала хоча б одна.

Для `SERVER` профілів `ping=` зазвичай не потрібен і краще його не задавати.

### `restart_cycles`

Кількість невдалих ping-циклів для `CLIENT`, після яких буде виконано restart OpenVPN service.

```bash
restart_cycles=3
```

Це означає: якщо VPN-адреса не відповідає 3 перевірки поспіль — перезапустити відповідний OpenVPN client.

> Якщо сам service не `active`, restart виконується одразу, без очікування `restart_cycles`.

### `service`

Необов’язковий параметр для нестандартних назв systemd-сервісів.

```bash
"name=office type=CLIENT service=openvpn-client@office.service ping=10.8.0.1 restart_cycles=3"
```

Якщо `service=` заданий, watchdog використовує саме його і не формує назву автоматично.

---

## Глобальна перевірка інтернету

Для клієнтських VPN є додатковий захист від зайвих restart.

Якщо весь сервер/комп’ютер втратив інтернет, VPN ping також може не працювати.  У такій ситуації watchdog не повинен перезапускати всі OpenVPN clients без потреби.

Параметри:

```bash
INTERNET_CHECK_ENABLED="YES"
PING_SERVER_INT="8.8.8.8,1.1.1.1"
SKIP_CLIENT_PING_WHEN_INTERNET_DOWN="YES"
```

Якщо інтернет недоступний, service-стани все одно перевіряються, але ping-перевірки клієнтів можуть бути пропущені.

---

## Логи

Звичайні логи:

```bash
/var/log/openvpn-watchdog/YYYY.MM.DD-hostname.log
```

Структурований event log:

```bash
/var/log/openvpn-watchdog/events.log
```

Приклад рядка event log:

```text
2026-05-03T13:15:01+0300 severity=WARNING profile=office type=CLIENT service=openvpn-client@office-client.service event=vpn_ping_unavailable message=VPN target is unavailable: 10.8.0.1. Failure cycle: 1/3
```

Цей формат зроблений спеціально, щоб у майбутньому його було легко аналізувати окремим скриптом або відправляти події у Matrix/Email/Zabbix.

---

## Аналіз journalctl

У конфігу вже закладено базову логіку для майбутнього аналізу проблем:

```bash
LOG_ANALYSIS_ENABLED="YES"
LOG_ANALYSIS_LINES=120
LOG_ANALYSIS_MAX_MATCHES=5
LOG_ANALYSIS_PATTERNS="AUTH_FAILED|TLS Error|Inactivity timeout|Connection reset|Cannot resolve host address|VERIFY ERROR|Options error|Exiting due to fatal error"
```

Поточна поведінка:

- якщо виявлена проблема service або ping;
- watchdog дивиться останні рядки `journalctl` для відповідного service;
- шукає типові OpenVPN-помилки;
- записує окрему structured event-подію `log_pattern_detected`.

Поки аналіз логів **не приймає самостійних рішень про restart**.  Він лише збирає корисну інформацію для діагностики та майбутніх сповіщень.

---

## Заготовка під Email / Matrix

У конфігу є hook для майбутніх сповіщень:

```bash
NOTIFICATIONS_ENABLED="NO"
NOTIFY_SCRIPT=""
```

Пізніше можна включити:

```bash
NOTIFICATIONS_ENABLED="YES"
NOTIFY_SCRIPT="/usr/local/bin/openvpn-watchdog-notify.sh"
```

Hook отримає такі змінні оточення:

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

Це дозволить окремо реалізувати:

- Email-сповіщення;
- Matrix-сповіщення;
- відправку в моніторинг;
- аналіз повторюваних помилок;
- правила ескалації для критичних OpenVPN-проблем.

Приклад hook-скрипта:

```bash
examples/openvpn-watchdog-notify.example.sh
```

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
```

Якщо systemd не знайдено, буде встановлено cron-файл:

```text
/etc/cron.d/openvpn-watchdog
```

Існуючий `/etc/openvpn-watchdog.conf` не перезаписується.

---

## Перевірка без restart

```bash
sudo openvpn-watchdog --dry-run
```

У цьому режимі watchdog:

- читає конфіг;
- перевіряє профілі;
- пише логи;
- **не перезапускає services**;
- **не викликає notification hook**.

---

## Ручний запуск і діагностика

```bash
sudo openvpn-watchdog
```

Перевірити timer:

```bash
systemctl status openvpn-watchdog.timer
```

Переглянути запуск service:

```bash
journalctl -u openvpn-watchdog.service -n 100 --no-pager
```

---

## Міграція зі старого `auto-restart-openvpn`

Старий підхід був прив’язаний до одного профілю:

```bash
NAME_SERVICE='client_openvpn'
TYPE='CLIENT'
PING_SERVER_VPN='10.8.0.1'
```

Новий підхід:

```bash
OPENVPN_PROFILES=(
    "name=client_openvpn type=CLIENT ping=10.8.0.1 restart_cycles=3"
)
```

Якщо раніше був server:

```bash
NAME_SERVICE='main'
TYPE='SERVER'
```

тепер:

```bash
OPENVPN_PROFILES=(
    "name=main type=SERVER restart_cycles=3"
)
```

---

## Що принципово прибрано

З цього пакета прибрано:

- автоматичний reboot комп’ютера;
- логіку `REBOOT_AFTER_CYCLES`;
- запуск `AUTOMATION_SCRIPT` перед reboot.

Це потрібно винести в окремий майбутній watchdog-пакет для контролю стану всієї машини.

---

## Рекомендований наступний розвиток

1. Окремий пакет для reboot/system watchdog.
2. Окремий notification hook для Matrix.
3. Окремий notification hook для Email.
4. Скрипт аналізу `/var/log/openvpn-watchdog/events.log`.
5. Порогові правила: наприклад, якщо `AUTH_FAILED` повторюється N разів — надсилати критичне сповіщення.
6. Інтеграція з моніторингом: Zabbix, Prometheus exporters або власна health-панель.
