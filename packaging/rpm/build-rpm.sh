#!/usr/bin/env bash
#
# build-rpm.sh - build RPM/SRPM for openvpn-watchdog.
#
# Notes:
#   - On ClearOS/CentOS/RHEL-like systems, normal rpmbuild dependency checks work.
#   - On Arch Linux, use --nodeps because rpmbuild checks the RPM database,
#     not the pacman database. Even if unzip/curl are installed with pacman,
#     rpmbuild can still report missing RPM dependencies.
#

set -Eeuo pipefail

PROJECT="openvpn-watchdog"
VERSION="0.2.1"
RELEASE="1"
GITHUB_URL="https://github.com/snuglinux/openvpn-watchdog"
SOURCE_URL="${GITHUB_URL}/archive/refs/tags/${VERSION}.zip"

RPM_TOPDIR="${RPM_TOPDIR:-${HOME}/rpmbuild}"

CLEAN="NO"
FORCE_DOWNLOAD="NO"
INSTALL_DEPS="NO"
NODEPS="NO"
RPM_ONLY="NO"
SRPM_ONLY="NO"

log() {
    printf '[INFO] %s\n' "$*" >&2
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

err() {
    printf '[ERROR] %s\n' "$*" >&2
}

usage() {
    cat <<EOF
Usage:
  ./build-rpm.sh [options]

Options:
  --version VERSION       Package version. Default: ${VERSION}
  --release RELEASE       Package release. Default: ${RELEASE}
  --topdir PATH           RPM build directory. Default: ${RPM_TOPDIR}
  --clean                 Remove old build artifacts for this package/version.
  --force-download        Re-download source archive.
  --install-deps          Install build tools using yum/dnf/pacman when possible.
  --nodeps                Pass --nodeps to rpmbuild.
                          Recommended on Arch Linux.
  --rpm-only              Build only binary RPM.
  --srpm-only             Build only source RPM.
  -h, --help              Show this help.

Examples:
  ./build-rpm.sh --clean
  ./build-rpm.sh --install-deps --clean
  ./build-rpm.sh --nodeps --clean
  ./build-rpm.sh --version 0.2.1 --nodeps --clean
EOF
}

detect_os_id() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s\n' "${ID:-unknown}"
    else
        printf 'unknown\n'
    fi
}

install_deps() {
    local os_id
    os_id="$(detect_os_id)"

    if command -v dnf >/dev/null 2>&1; then
        log "Installing build dependencies with dnf..."
        sudo dnf install -y rpm-build unzip curl
    elif command -v yum >/dev/null 2>&1; then
        log "Installing build dependencies with yum..."
        sudo yum install -y rpm-build unzip curl
    elif command -v pacman >/dev/null 2>&1; then
        log "Installing build dependencies with pacman..."
        sudo pacman -S --needed --noconfirm rpm-tools unzip curl
        warn "Arch Linux detected (${os_id}). Use --nodeps because rpmbuild checks RPM DB, not pacman DB."
    else
        warn "No supported package manager found. Install manually: rpmbuild, unzip, curl."
    fi
}

require_commands() {
    local missing=0

    for cmd in rpmbuild curl unzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            err "Required command not found: $cmd"
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        err "Install dependencies first or run: ./build-rpm.sh --install-deps"
        exit 1
    fi
}

prepare_dirs() {
    mkdir -p \
        "${RPM_TOPDIR}/BUILD" \
        "${RPM_TOPDIR}/BUILDROOT" \
        "${RPM_TOPDIR}/RPMS" \
        "${RPM_TOPDIR}/SOURCES" \
        "${RPM_TOPDIR}/SPECS" \
        "${RPM_TOPDIR}/SRPMS"
}

clean_old_artifacts() {
    log "Cleaning old build directories and old package artifacts..."
    rm -rf \
        "${RPM_TOPDIR}/BUILD/${PROJECT}-${VERSION}" \
        "${RPM_TOPDIR}/BUILDROOT/${PROJECT}-${VERSION}-${RELEASE}."* \
        "${RPM_TOPDIR}/SPECS/${PROJECT}.spec"

    find "${RPM_TOPDIR}/RPMS"  -type f -name "${PROJECT}-${VERSION}-${RELEASE}*.rpm" -delete 2>/dev/null || true
    find "${RPM_TOPDIR}/SRPMS" -type f -name "${PROJECT}-${VERSION}-${RELEASE}*.rpm" -delete 2>/dev/null || true
}

download_source() {
    local source_file="${RPM_TOPDIR}/SOURCES/${PROJECT}-${VERSION}.zip"

    if [[ "$FORCE_DOWNLOAD" == "YES" || ! -s "$source_file" ]]; then
        log "Downloading source archive: ${SOURCE_URL}"
        curl -L --fail --show-error \
            -o "$source_file" \
            "$SOURCE_URL"
    else
        log "Source archive already exists: $source_file"
    fi

    printf '%s\n' "$source_file"
}

write_spec() {
    local spec_file="${RPM_TOPDIR}/SPECS/${PROJECT}.spec"

    log "Writing RPM spec: $spec_file"

    cat > "$spec_file" <<'SPEC_EOF'
%{!?_unitdir:%global _unitdir /usr/lib/systemd/system}

Name:           __PROJECT__
Version:        __VERSION__
Release:        __RELEASE__%{?dist}
Summary:        Watchdog for multiple OpenVPN profiles with external multilingual messages

License:        Custom
URL:            https://github.com/snuglinux/openvpn-watchdog
Source0:        %{name}-%{version}.zip

BuildArch:      noarch
BuildRequires:  unzip
Requires:       bash
Requires:       curl
Requires:       iputils
Requires:       openvpn
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

# openvpn-watchdog replaces the deprecated auto-restart-openvpn package.
Obsoletes:      auto-restart-openvpn < %{version}-%{release}
Provides:       auto-restart-openvpn = %{version}-%{release}
Provides:       %{name} = %{version}-%{release}

%description
openvpn-watchdog monitors multiple OpenVPN CLIENT and SERVER profiles on Linux.
It checks OpenVPN systemd services and can optionally verify VPN client
connectivity with ICMP ping targets. The global Internet check can use HTTP(S)
through curl when ICMP is blocked by a provider or firewall. When a problem is
detected for several consecutive checks, only the affected OpenVPN service is
restarted.

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
%{_datadir}/%{name}/locale/en.conf
%{_datadir}/%{name}/locale/uk.conf

%changelog
* Mon May 04 2026 snuglinux <https://github.com/snuglinux> - __VERSION__-__RELEASE__
- Update packaging for openvpn-watchdog 0.2.1.
- Use source ZIP archive from GitHub tag.
- Add external English/Ukrainian locale files.
- Add HTTP(S) curl support for global Internet checks.
- Replace deprecated auto-restart-openvpn package.
SPEC_EOF

    sed -i \
        -e "s/__PROJECT__/${PROJECT}/g" \
        -e "s/__VERSION__/${VERSION}/g" \
        -e "s/__RELEASE__/${RELEASE}/g" \
        "$spec_file"

    printf '%s\n' "$spec_file"
}

build_rpm() {
    local spec_file="$1"
    local rpmbuild_args=()

    if [[ "$NODEPS" == "YES" ]]; then
        rpmbuild_args+=(--nodeps)
    fi

    rpmbuild_args+=(--define "_topdir ${RPM_TOPDIR}")

    if [[ "$RPM_ONLY" == "YES" ]]; then
        log "Building binary RPM only..."
        rpmbuild -bb "${rpmbuild_args[@]}" "$spec_file"
    elif [[ "$SRPM_ONLY" == "YES" ]]; then
        log "Building SRPM only..."
        rpmbuild -bs "${rpmbuild_args[@]}" "$spec_file"
    else
        log "Building SRPM and binary RPM..."
        rpmbuild -ba "${rpmbuild_args[@]}" "$spec_file"
    fi
}

print_results() {
    log "Build finished."

    if compgen -G "${RPM_TOPDIR}/RPMS/noarch/${PROJECT}-${VERSION}-${RELEASE}"'*.rpm' >/dev/null; then
        log "Binary RPM:"
        ls -lh "${RPM_TOPDIR}/RPMS/noarch/${PROJECT}-${VERSION}-${RELEASE}"*.rpm
    fi

    if compgen -G "${RPM_TOPDIR}/SRPMS/${PROJECT}-${VERSION}-${RELEASE}"'*.rpm' >/dev/null; then
        log "Source RPM:"
        ls -lh "${RPM_TOPDIR}/SRPMS/${PROJECT}-${VERSION}-${RELEASE}"*.rpm
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:?Missing value for --version}"
            SOURCE_URL="${GITHUB_URL}/archive/refs/tags/${VERSION}.zip"
            shift 2
            ;;
        --release)
            RELEASE="${2:?Missing value for --release}"
            shift 2
            ;;
        --topdir)
            RPM_TOPDIR="${2:?Missing value for --topdir}"
            shift 2
            ;;
        --clean)
            CLEAN="YES"
            shift
            ;;
        --force-download)
            FORCE_DOWNLOAD="YES"
            shift
            ;;
        --install-deps)
            INSTALL_DEPS="YES"
            shift
            ;;
        --nodeps)
            NODEPS="YES"
            shift
            ;;
        --rpm-only)
            RPM_ONLY="YES"
            shift
            ;;
        --srpm-only)
            SRPM_ONLY="YES"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "$RPM_ONLY" == "YES" && "$SRPM_ONLY" == "YES" ]]; then
    err "--rpm-only and --srpm-only cannot be used together."
    exit 1
fi

SOURCE_URL="${GITHUB_URL}/archive/refs/tags/${VERSION}.zip"

log "Project: ${PROJECT}"
log "Version: ${VERSION}"
log "Release: ${RELEASE}"
log "Source:  ${SOURCE_URL}"
log "RPM dir: ${RPM_TOPDIR}"

if [[ "$(detect_os_id)" == "arch" && "$NODEPS" != "YES" ]]; then
    warn "Arch Linux detected. rpmbuild checks RPM DB, not pacman DB."
    warn "Recommended command: ./build-rpm.sh --nodeps --clean"
fi

if [[ "$INSTALL_DEPS" == "YES" ]]; then
    install_deps
fi

require_commands
prepare_dirs

if [[ "$CLEAN" == "YES" ]]; then
    clean_old_artifacts
fi

download_source >/dev/null
spec_file="$(write_spec)"

if [[ ! -f "$spec_file" ]]; then
    err "Spec file was not created: $spec_file"
    exit 1
fi

build_rpm "$spec_file"
print_results
