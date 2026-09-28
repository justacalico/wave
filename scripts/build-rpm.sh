#!/usr/bin/env bash
# Package a built Flutter Linux bundle as an RPM for Fedora and friends.
# Installs to /opt/wave with a /usr/bin/wave symlink, a desktop entry and
# the app icon, matching the layout used by the .deb built in CI.
#
# Usage: scripts/build-rpm.sh <bundle-dir> <version> <rpm-arch> <output-file> [release]
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-rpm.sh <bundle-dir> <version> <rpm-arch> <output-file> [release]}"
VERSION="${2:?usage: build-rpm.sh <bundle-dir> <version> <rpm-arch> <output-file> [release]}"
ARCH="${3:?usage: build-rpm.sh <bundle-dir> <version> <rpm-arch> <output-file> [release]}"
OUT="${4:?usage: build-rpm.sh <bundle-dir> <version> <rpm-arch> <output-file> [release]}"
RELEASE="${5:-1}"
ICON="${ICON:-}"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "build-rpm: rpmbuild not found (install the rpm/rpm-build package)" >&2
  exit 1
fi
if [ ! -d "$BUNDLE_DIR" ]; then
  echo "build-rpm: bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
  echo "build-rpm: unsupported arch: $ARCH" >&2
  exit 1
fi

# rpm forbids '-' in Version; '~' is the rpm convention for prereleases and
# sorts before the final release.
RPM_VERSION="$(printf '%s' "$VERSION" | tr '-' '~')"

TOPDIR="$(mktemp -d)"
trap 'rm -rf "$TOPDIR"' EXIT
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$TOPDIR/SPECS/wave.spec" <<'EOF'
Name: wave
Version: %{pkg_version}
Release: %{pkg_release}%{?dist}
Summary: Wave browser
License: AGPL-3.0-only
URL: https://gitlab.com/HttpAnimations/wave
Requires: webkit2gtk4.1

%global debug_package %{nil}
%global __os_install_post %{nil}
%global __provides_exclude_from ^/opt/wave/.*

%description
A quiet browser — vertical tabs, workspaces and Firefox Accounts sync
on the system webview.

%install
mkdir -p %{buildroot}/opt/wave %{buildroot}/usr/bin \
  %{buildroot}/usr/share/applications \
  %{buildroot}/usr/share/icons/hicolor/512x512/apps
cp -a %{bundle_dir}/. %{buildroot}/opt/wave/
ln -sf /opt/wave/wave %{buildroot}/usr/bin/wave
cat > %{buildroot}/usr/share/applications/wave.desktop <<'DESKTOP'
[Desktop Entry]
Name=Wave
Comment=A quiet browser
Exec=/opt/wave/wave
Icon=wave
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
if [ -n "%{icon_file}" ]; then
  cp %{icon_file} %{buildroot}/usr/share/icons/hicolor/512x512/apps/wave.png
fi

%files
/opt/wave
/usr/bin/wave
/usr/share/applications/wave.desktop
/usr/share/icons/hicolor/512x512/apps/wave.png
EOF

rpmbuild -bb \
  --target "$ARCH" \
  --define "_topdir $TOPDIR" \
  --define "pkg_version $RPM_VERSION" \
  --define "pkg_release $RELEASE" \
  --define "bundle_dir $(realpath "$BUNDLE_DIR")" \
  --define "icon_file $ICON" \
  "$TOPDIR/SPECS/wave.spec"

RPM_PATH="$(find "$TOPDIR/RPMS" -name '*.rpm' -print -quit)"
if [ -z "$RPM_PATH" ]; then
  echo "build-rpm: rpmbuild produced no rpm" >&2
  exit 1
fi
cp "$RPM_PATH" "$OUT"
echo "build-rpm: $RPM_PATH -> $OUT"
