#!/usr/bin/env bash
# scripts/package_deb.sh — Build the .deb for Termux from runtime/opencode-termux
# Uses plain `ar` so the "aarch64" architecture is accepted regardless of host dpkg.
# Usage:
#   VERSION=1.18.23 ./scripts/package_deb.sh     # env (default 1.18.23)
# Output: opencode_<ver>_aarch64.deb
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-aarch64}"
VER="${VERSION:-}"
if [[ -z "$VER" ]]; then
  [[ -f "$ROOT/runtime/VERSION" ]] && VER="$(cat "$ROOT/runtime/VERSION")"
  VER="${VER:-1.18.23}"
fi
MAINTAINER="${MAINTAINER:-wanfeng090525 <wanfeng090525@users.noreply.github.com>}"
PREFIX="/data/data/com.termux/files/usr"

for c in ar tar find md5sum; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing required tool: $c" >&2; exit 1; }
done

RUN="$ROOT/runtime/opencode-termux"
[[ -x "$RUN" ]] || { echo "missing $RUN — run scripts/produce.sh first" >&2; exit 1; }

DEB="$ROOT/opencode_${VER}_${ARCH}.deb"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# data tree
DATA="$BUILD/data/$PREFIX"
mkdir -p "$DATA/bin" "$DATA/lib/opencode/runtime"
install -m 755 "$RUN" "$DATA/lib/opencode/runtime/opencode"
install -m 755 "$ROOT/scripts/launcher.sh" "$DATA/bin/opencode"

# control tarball
CTRL="$BUILD/ctrl"
mkdir -p "$CTRL"
cat > "$CTRL/control" <<EOF
Package: opencode
Version: $VER
Architecture: $ARCH
Maintainer: $MAINTAINER
Section: utils
Priority: optional
Description: OpenCode AI coding assistant for Termux (bun-termux-loader wrapped)
Depends: bash, ncurses, glibc, openssl-glibc
Installed-Size: $(du -sk "$DATA" | cut -f1)
EOF
cat > "$CTRL/postinst" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
echo "OpenCode for Termux installed"
echo "Run: opencode --version ($VER)"
exit 0
EOF
chmod 755 "$CTRL/postinst"
(cd "$BUILD/data" && find . -type f -print0 | xargs -0 md5sum) > "$CTRL/md5sums"

# assemble deb
printf '2.0\n' > "$BUILD/debian-binary"
tar -C "$CTRL" -czf "$BUILD/control.tar.gz" .
tar -C "$BUILD/data" -cJf "$BUILD/data.tar.xz" .
rm -f "$DEB"
ar rcs "$DEB" "$BUILD/debian-binary" "$BUILD/control.tar.gz" "$BUILD/data.tar.xz"

echo "DEB created: $DEB ($(du -h "$DEB" | cut -f1))"