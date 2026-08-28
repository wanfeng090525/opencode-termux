#!/usr/bin/env bash
# scripts/smoke_qemu.sh — Run-level validation of the inner aarch64 glibc Bun ELF
# of a bun-termux-loader wrapped binary, under QEMU user-mode.
#
# Why not the whole wrapper: the OUTERELF's interpreter is /system/bin/linker64
# (Android Bionic), which only exists on a real device; QEMU can't supply it.
# So we extract the inner glibc `opencode-linux-arm64` Bun ELF and run it with
# an aarch64 glibc sysroot — proof the actual opencode runtime starts and boots.
#
# Usage: ./scripts/smoke_qemu.sh [runtime] [expected_ver]
# Env:   SYSROOT  aarch64 glibc sysroot dir (default /usr/aarch64-linux-gnu)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${1:-$ROOT/runtime/opencode-termux}"
EXPECT="${2:-}"
SYSROOT="${SYSROOT:-/usr/aarch64-linux-gnu}"

for c in qemu-aarch64; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing $c - run: apt install qemu-user-static" >&2; exit 1; }
done
[[ -x "$RUNTIME" ]] || { echo "no runtime: $RUNTIME" >&2; exit 1; }
[[ -f "$SYSROOT/lib/ld-linux-aarch64.so.1" ]] || { echo "missing arm64 glibc sysroot at $SYSROOT (apt: dpkg --add-architecture arm64 && apt install libc6:arm64)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
INNER="$TMP/inner-bun"
python3 "$ROOT/scripts/verify.py" "$RUNTIME" --dump-inner "$INNER" >/dev/null
chmod +x "$INNER"

echo "=== running inner aarch64 Bun ELF via qemu-aarch64 (-L $SYSROOT) ==="
file -b "$INNER"
echo "--- version ---"
OUT="$(qemu-aarch64 -L "$SYSROOT" "$INNER" --version 2>&1 || true)"
echo "$OUT"
[[ -n "$OUT" ]] || { echo "FAIL: qemu run produced no output" >&2; exit 1; }
if [[ -n "$EXPECT" ]]; then
  if [[ "$OUT" != *"$EXPECT"* ]]; then
    echo "FAIL: version '$OUT' != expected '$EXPECT'" >&2
    exit 1
  fi
fi
echo "SMOKE_OK: inner opencode runtime boots and reports: $OUT"