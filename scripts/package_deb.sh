#!/usr/bin/env bash
# scripts/package_deb.sh — Build the .deb for Termux from the staged prefix
# (artifacts/staged/prefix, produced by scripts/build.sh).
# Uses plain `ar` so "aarch64" is accepted regardless of host dpkg.
# Includes plugin hooks: postinst/pre-remove/postrm trigger run-system-skills.sh.
# Usage: VERSION=1.18.23 ./scripts/package_deb.sh
# Output: opencode_<ver>_aarch64.deb
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-aarch64}"
VER="${VERSION:-}"
if [[ -z "$VER" ]]; then
  ## derive from staged runtime
  if [[ -x "$ROOT/artifacts/staged/prefix/lib/opencode/runtime/opencode" ]]; then
    VER="$("$ROOT/artifacts/staged/prefix/lib/opencode/runtime/opencode" --version 2>/dev/null || true)"
  fi
  [[ -f "$ROOT/runtime/VERSION" ]] && VER="${VER:-$(cat "$ROOT/runtime/VERSION")}"
  VER="${VER:-1.18.23}"
fi
MAINTAINER="${MAINTAINER:-wanfeng090525 <wanfeng090525@users.noreply.github.com>}"
HOOK_RUNNER="/data/data/com.termux/files/usr/lib/opencode/tools/run-system-skills.sh"
PREFIX="/data/data/com.termux/files/usr"

for c in ar tar find md5sum du; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing required tool: $c" >&2; exit 1; }
done

STAGE="$ROOT/artifacts/staged/prefix"
[[ -x "$STAGE/lib/opencode/runtime/opencode" ]] || fail "staged runtime missing at $STAGE — run 'make stage' (scripts/build.sh) first"
[[ -x "$STAGE/bin/opencode" ]] || fail "staged launcher missing — run 'make stage' first"

DEB="$ROOT/opencode_${VER}_${ARCH}.deb"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# data tree from staged prefix
DATA="$BUILD/data$PREFIX"
mkdir -p "$(dirname "$DATA")"
cp -a "$STAGE/." "$DATA/"

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
Description: OpenCode AI coding assistant for Termux (bun-termux-loader wrapped, plugin hooks)
Depends: bash, ncurses, glibc, openssl-glibc
Installed-Size: $(du -sk "$DATA" | cut -f1)
EOF
cat > "$CTRL/postinst" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
HOOK_RUNNER="$HOOK_RUNNER"
if [[ -x "\$HOOK_RUNNER" ]]; then
  OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "\$HOOK_RUNNER" post_upgrade || true
fi
echo "OpenCode for Termux installed (v$VER)"
echo "Run: opencode --version"
exit 0
EOF
cat > "$CTRL/prerm" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
HOOK_RUNNER="$HOOK_RUNNER"
if [[ -x "\$HOOK_RUNNER" ]]; then
  OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "\$HOOK_RUNNER" pre_remove || true
fi
exit 0
EOF
cat > "$CTRL/postrm" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e
HOOK_RUNNER="$HOOK_RUNNER"
if [[ -x "\$HOOK_RUNNER" ]]; then
  OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "\$HOOK_RUNNER" post_remove || true
fi
exit 0
EOF
chmod 755 "$CTRL/postinst" "$CTRL/prerm" "$CTRL/postrm"
(cd "$BUILD/data" && find . -type f -print0 | xargs -0 md5sum) > "$CTRL/md5sums"

# assemble deb
printf '2.0\n' > "$BUILD/debian-binary"
tar -C "$CTRL" -czf "$BUILD/control.tar.gz" .
tar -C "$BUILD/data" -cJf "$BUILD/data.tar.xz" .
rm -f "$DEB"
ar rcs "$DEB" "$BUILD/debian-binary" "$BUILD/control.tar.gz" "$BUILD/data.tar.xz"

echo "DEB created: $DEB ($(du -h "$DEB" | cut -f1))"