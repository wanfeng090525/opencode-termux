#!/usr/bin/env bash
# scripts/package_pacman.sh — Build the pacman .pkg.tar.xz for Termux from the
# staged prefix (artifacts/staged/prefix). Assembles the archive manually
# (.PKGINFO + .MTREE + .INSTALL + data/...) so it needs no makepkg/pacman on the
# host (makepkg on Ubuntu is broken: alpm init fails without a pacman db).
# Layout mirrors Hope2333/opencode-termux's package() exactly.
# Usage: VERSION=1.18.23 ./scripts/package_pacman.sh
# Output: packing/pacman/opencode-<ver>-<rel>-aarch64.pkg.tar.xz
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_PREFIX="$ROOT/artifacts/staged/prefix"
PKGREL="${PKGREL:-1}"
ARCH="${ARCH:-aarch64}"
PACKAGER_NAME="${PACKAGER_NAME:-wanfeng090525 <wanfeng090525@users.noreply.github.com>}"
PREFIX_DIR="/data/data/com.termux/files/usr"
HOOK_RUNNER="{{PREFIX}}/lib/opencode/tools/run-system-skills.sh"

for c in tar bsdtar xz python3 du date; do
  command -v "$c" >/dev/null 2>&1 || fail "missing required tool: $c"
done

[[ -x "$STAGED_PREFIX/lib/opencode/runtime/opencode" ]] || fail "staged runtime missing — run 'make stage' first"
[[ -x "$STAGED_PREFIX/bin/opencode" ]] || fail "staged launcher missing — run 'make stage' first"

VER="${VERSION:-}"
if [[ -z "$VER" ]]; then
  VER="$("$STAGED_PREFIX/lib/opencode/runtime/opencode" --version 2>/dev/null || true)"
fi
VER="${VER:-1.18.23}"
log "packaging version $VER (pkgrel $PKGREL, arch $ARCH)"

PKGROOT="$ROOT/packing/pacman/pkgroot"
OUT_DIR="$ROOT/packing/pacman"
OUT="$OUT_DIR/opencode-$VER-$PKGREL-$ARCH.pkg.tar.xz"

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT$PREFIX_DIR" "$OUT_DIR"
cp -a "$STAGED_PREFIX/." "$PKGROOT$PREFIX_DIR/"

# --- .PKGINFO ---
BUILDDATE=$(date +%s)
SIZE=$(du -sk "$PKGROOT$PREFIX_DIR" | cut -f1)
cat > "$PKGROOT/.PKGINFO" <<EOF
pkgname = opencode
pkgbase = opencode
pkgver = $VER
pkgrel = $PKGREL
pkgdesc = OpenCode AI coding assistant for Termux (bun-termux-loader wrapped, plugin hooks)
url = https://github.com/anomalyco/opencode
builddate = $BUILDDATE
packager = $PACKAGER_NAME
size = $SIZE
arch = $ARCH
license = MIT
depend = bash
depend = ncurses
depend = glibc
depend = openssl-glibc
EOF

# --- .INSTALL (package life-cycle hooks) ---
cat > "$PKGROOT/.INSTALL" <<"EOF"
post_install() {
    HOOK_RUNNER="{{HOOK_RUNNER}}"
    if [[ -x "$HOOK_RUNNER" ]]; then
        OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "$HOOK_RUNNER" post_upgrade || true
    fi
    echo "OpenCode for Termux installed"
    echo "Run: opencode --version"
}
post_upgrade() {
    HOOK_RUNNER="{{HOOK_RUNNER}}"
    if [[ -x "$HOOK_RUNNER" ]]; then
        OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "$HOOK_RUNNER" post_upgrade || true
    fi
}
pre_remove() {
    HOOK_RUNNER="{{HOOK_RUNNER}}"
    if [[ -x "$HOOK_RUNNER" ]]; then
        OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "$HOOK_RUNNER" pre_remove || true
    fi
}
post_remove() {
    HOOK_RUNNER="{{HOOK_RUNNER}}"
    if [[ -x "$HOOK_RUNNER" ]]; then
        OPENCODE_HOOK_STRICT=0 OPENCODE_HOOK_ENABLE_NETWORK=0 "$HOOK_RUNNER" post_remove || true
    fi
}
EOF
# substitute the true, fixed Termux path for {{HOOK_RUNNER}}
sed -i "s#{{HOOK_RUNNER}}#$HOOK_RUNNER#" "$PKGROOT/.INSTALL"
sed -i "s#{{PREFIX}}#$PREFIX_DIR#" "$PKGROOT/.INSTALL"
chmod 644 "$PKGROOT/.INSTALL"

# --- .MTREE (file integrity manifest) ---
(cd "$PKGROOT" && bsdtar -c -f .MTREE --format=mtree --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' --exclude .PKGINFO --exclude .MTREE --exclude .INSTALL .)

# --- archive: .PKGINFO/.MTREE/.INSTALL first, then data ---
rm -f "$OUT"
tar -C "$PKGROOT" -cJf "$OUT" .PKGINFO .MTREE .INSTALL data
rm -rf "$PKGROOT"

echo "Pacman package created: $OUT ($(du -h "$OUT" | cut -f1))"