# openvpn-watchdog 0.2.1 packaging

Packaging files for openvpn-watchdog 0.2.1.

Source archive used by both Arch Linux and RPM packaging:

```text
https://github.com/snuglinux/openvpn-watchdog/archive/refs/tags/0.2.1.zip
```

## Arch Linux

Files:

```text
packaging/arch/PKGBUILD
packaging/arch/.SRCINFO
packaging/arch/openvpn-watchdog.install
```

Build:

```bash
cd packaging/arch
updpkgsums
makepkg --printsrcinfo > .SRCINFO
makepkg -s
```

`sha256sums=('SKIP')` is temporary. Replace it with the real checksum before publishing.

The package declares:

```bash
conflicts=('auto-restart-openvpn')
replaces=('auto-restart-openvpn')
provides=('openvpn-watchdog' 'auto-restart-openvpn')
```

The install hook disables/removes old manual `auto-restart-openvpn` service/timer/cron leftovers and saves the old config backup if present.

## ClearOS / CentOS 7 RPM

File:

```text
packaging/rpm/openvpn-watchdog.spec
```

Prepare source:

```bash
mkdir -p ~/rpmbuild/SOURCES
curl -L -o ~/rpmbuild/SOURCES/openvpn-watchdog-0.2.1.zip \
  https://github.com/snuglinux/openvpn-watchdog/archive/refs/tags/0.2.1.zip
```

Build:

```bash
rpmbuild -ba packaging/rpm/openvpn-watchdog.spec
```

The RPM package declares:

```spec
Obsoletes: auto-restart-openvpn
Provides:  auto-restart-openvpn = %{version}-%{release}
```

It also disables/removes old manual `auto-restart-openvpn` service/timer/cron leftovers in `%post`.
