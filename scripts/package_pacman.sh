#!/usr/bin/env bash
# scripts/package_pacman.sh — Build the pacman .pkg.tar.xz for Termux from the
# staged prefix (artifacts/staged/prefix). Uses `makepkg -A` so it works on any
# host arch (CI is x86_64, target aarch64) and pulls a sane makepkg.conf.
# Usage: VERSION=1.18.23 ./scripts/package_pacman.sh
# Output: packing/pacman/opencode-<ver>-1-aarch64.pkg.tar.xz
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_PREFIX="$ROOT/artifacts/staged/prefix"
PACKAGER_NAME="${PACKAGER_NAME:-wanfeng090525 <wanfeng090525@users.noreply.github.com>}"
PKGREL="${PKGREL:-1}"

for c in makepkg; do
  command -v "$c" >/dev/null 2>&1 || fail "missing required tool: $c (install pacman on the host / CI step)"
done

[[ -x "$STAGED_PREFIX/lib/opencode/runtime/opencode" ]] || fail "staged runtime missing — run 'make stage' first"
[[ -x "$STAGED_PREFIX/bin/opencode" ]] || fail "staged launcher missing — run 'make stage' first"

VER="${VERSION:-}"
if [[ -z "$VER" ]]; then
  VER="$("$STAGED_PREFIX/lib/opencode/runtime/opencode" --version 2>/dev/null || true)"
fi
VER="${VER:-1.18.23}"
log "packaging version $VER (pkgrel $PKGREL)"

# pick a makepkg.conf
CONF="$ROOT/packing/pacman/.makepkg.conf"
for src in /data/data/com.termux/files/usr/etc/makepkg.conf /etc/makepkg.conf; do
  if [[ -f "$src" ]]; then cp "$src" "$CONF"; break; fi
done
if [[ ! -f "$CONF" ]]; then
  {
    echo 'CARCH="x86_64"'
    echo 'CHOST="x86_64-unknown-linux-gnu"'
    echo 'CFLAGS="-O2 -pipe"'
    echo 'CXXFLAGS="-O2 -pipe"'
    echo 'MAKEFLAGS="-j2"'
    echo "PKGDEST=\"$ROOT/packing/pacman/\""
    echo "PKGEXT='.pkg.tar.xz'"
    echo "PACKAGER=\"$PACKAGER_NAME\""
  } > "$CONF"
else
  printf '\nPACKAGER=%q\nPKGDEST=%q\n' "$PACKAGER_NAME" "$ROOT/packing/pacman/" >> "$CONF"
fi

PKGBUILD="$ROOT/packing/pacman/.PKGBUILD"
cp "$ROOT/packing/pacman/PKGBUILD" "$PKGBUILD"
sed -i "s/^pkgver=.*/pkgver=$VER/" "$PKGBUILD"
sed -i "s/^pkgrel=.*/pkgrel=$PKGREL/" "$PKGBUILD"

mkdir -p "$ROOT/packing/pacman"
cd "$ROOT/packing/pacman"
rm -rf pkg src
STAGE_DIR="$STAGED_PREFIX" STAGED_PREFIX="$STAGED_PREFIX" \
  makepkg -A --config "$CONF" -f --noconfirm -p "$PKGBUILD"

rm -f "$CONF" "$PKGBUILD"
echo "Pacman package created under: $ROOT/packing/pacman"