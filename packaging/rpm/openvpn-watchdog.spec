%{!?_unitdir:%global _unitdir /usr/lib/systemd/system}

Name:           openvpn-watchdog
Version:        0.2.1
Release:        1%{?dist}
Summary:        Watchdog for multiple OpenVPN profiles with HTTP checks and multilingual messages

License:        Custom
URL:            https://github.com/snuglinux/openvpn-watchdog
Source0:        %{url}/archive/refs/tags/%{version}.zip#/%{name}-%{version}.zip

BuildArch:      noarch
BuildRequires:  unzip
Requires:       bash
Requires:       curl
Requires:       iputils
Requires:       openvpn
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

# openvpn-watchdog is the replacement for the old auto-restart-openvpn package.
Obsoletes:      auto-restart-openvpn
Provides:       auto-restart-openvpn = %{version}-%{release}
Provides:       %{name} = %{version}-%{release}

%description
openvpn-watchdog monitors multiple OpenVPN CLIENT and SERVER profiles on Linux.
It checks OpenVPN systemd services and can optionally verify VPN client
connectivity with ICMP ping targets. The global Internet check can use HTTP(S)
through curl when ICMP is blocked by a provider or firewall. Runtime messages are
loaded from external English/Ukrainian locale files. When a problem is detected
for several consecutive checks, only the affected OpenVPN service is restarted.

This package does not reboot the host. Automatic host reboot logic is planned as
a separate system watchdog package.

%prep
%setup -q -n %{name}-%{version}

%build
bash -n openvpn-watchdog
bash -n install.sh
if [ -f examples/openvpn-watchdog-notify.example.sh ]; then
    bash -n examples/openvpn-watchdog-notify.example.sh
fi
if [ -d locale ]; then
    bash -n locale/en.conf
    bash -n locale/uk.conf
fi

%install
rm -rf %{buildroot}

install -D -m 0755 openvpn-watchdog %{buildroot}%{_bindir}/openvpn-watchdog
install -D -m 0644 openvpn-watchdog.conf %{buildroot}%{_sysconfdir}/openvpn-watchdog.conf

install -D -m 0644 openvpn-watchdog.service %{buildroot}%{_unitdir}/openvpn-watchdog.service
install -D -m 0644 openvpn-watchdog.timer %{buildroot}%{_unitdir}/openvpn-watchdog.timer

install -D -m 0644 locale/en.conf %{buildroot}%{_datadir}/%{name}/locale/en.conf
install -D -m 0644 locale/uk.conf %{buildroot}%{_datadir}/%{name}/locale/uk.conf

# Cron is provided as documentation only. ClearOS/CentOS 7 uses the systemd timer.
install -D -m 0644 openvpn-watchdog.crontab %{buildroot}%{_docdir}/%{name}/openvpn-watchdog.crontab.example
install -D -m 0644 README.md %{buildroot}%{_docdir}/%{name}/README.md
if [ -f README_uk.md ]; then
    install -D -m 0644 README_uk.md %{buildroot}%{_docdir}/%{name}/README_uk.md
fi
if [ -f examples/openvpn-watchdog-notify.example.sh ]; then
    install -D -m 0755 examples/openvpn-watchdog-notify.example.sh %{buildroot}%{_docdir}/%{name}/examples/openvpn-watchdog-notify.example.sh
fi

install -d -m 0755 %{buildroot}%{_localstatedir}/log/openvpn-watchdog
install -d -m 0755 %{buildroot}%{_localstatedir}/lib/openvpn-watchdog

%post
legacy_name="auto-restart-openvpn"
legacy_conf="/etc/${legacy_name}.conf"
legacy_backup="/etc/${legacy_name}.conf.openvpn-watchdog-migration-backup"

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now "${legacy_name}.timer" >/dev/null 2>&1 || :
    systemctl disable --now "${legacy_name}.service" >/dev/null 2>&1 || :
fi

if [ -f "$legacy_conf" ] && [ ! -f "$legacy_backup" ]; then
    cp -a "$legacy_conf" "$legacy_backup" >/dev/null 2>&1 || :
fi

rm -f \
    "/usr/bin/${legacy_name}" \
    "/etc/cron.d/${legacy_name}" \
    "/etc/systemd/system/${legacy_name}.service" \
    "/etc/systemd/system/${legacy_name}.timer" \
    "/usr/lib/systemd/system/${legacy_name}.service" \
    "/usr/lib/systemd/system/${legacy_name}.timer"

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || :
    systemctl enable --now openvpn-watchdog.timer >/dev/null 2>&1 || :
fi

%preun
if [ "$1" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now openvpn-watchdog.timer >/dev/null 2>&1 || :
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || :
fi

%files
%{_bindir}/openvpn-watchdog
%config(noreplace) %{_sysconfdir}/openvpn-watchdog.conf
%{_unitdir}/openvpn-watchdog.service
%{_unitdir}/openvpn-watchdog.timer
%dir %{_localstatedir}/log/openvpn-watchdog
%dir %{_localstatedir}/lib/openvpn-watchdog
%doc %{_docdir}/%{name}
%dir %{_datadir}/%{name}
%dir %{_datadir}/%{name}/locale
%{_datadir}/%{name}/locale/en.conf
%{_datadir}/%{name}/locale/uk.conf

%changelog
* Sun May 03 2026 snuglinux <https://github.com/snuglinux> - 0.2.1-1
- Use the 0.2.1 GitHub ZIP source archive.
- Add HTTP(S) curl support for global Internet checks.
- Add external English/Ukrainian locale files.
- Add curl and iputils runtime dependencies.
- Replace deprecated auto-restart-openvpn package.
