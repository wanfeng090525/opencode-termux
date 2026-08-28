#!/usr/bin/env bash
# scripts/produce.sh — Wrap npm's opencode-linux-arm64 (aarch64 Bun CLI) with bun-termux-loader
# Usage:
#   ./scripts/produce.sh [VERSION]     # 默认 VERSION=1.18.23
#   VER=1.19.0 ./scripts/produce.sh    # 或 set VER env
# Output: runtime/opencode-termux (self-contained aarch64 binary)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOADER_REPO="${LOADER_REPO:-https://github.com/Hope2333/bun-termux-loader}"
LOADER="$ROOT/.cache/bun-termux-loader"
OUT="$ROOT/runtime/opencode-termux"

VER="${1:-${VER:-1.18.23}}"

for c in npm python3 git tar file; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing required tool: $c" >&2; exit 1; }
done

mkdir -p "$ROOT/runtime" "$ROOT/.cache"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[produce] npm opencode-linux-arm64@$VER"
cd "$WORK"
npm pack "opencode-linux-arm64@$VER" >/dev/null
tar -xzf "opencode-linux-arm64-$VER.tgz"
RAW="$WORK/package/bin/opencode"
[[ -x "$RAW" ]] || { echo "FATAL: no executable at $RAW" >&2; exit 1; }
echo "[produce] upstream: $(file -b "$RAW")"

# Safety net: Termux needs the Bun CLI ELF. Always true with the npm source.
if [[ "$(head -c4 "$RAW")" != "$(printf '\177ELF')" ]]; then
  echo "FATAL: selected source is not an ELF binary: $(file -b "$RAW")" >&2
  echo "  The npm source is opencode-linux-arm64@<ver>; do not use desktop GUI packages." >&2
  exit 1
fi

if [[ ! -f "$LOADER/build.py" ]]; then
  echo "[produce] cloning bun-termux-loader"
  git clone --depth 1 "$LOADER_REPO" "$LOADER" >/dev/null 2>&1
fi

python3 "$LOADER/build.py" "$RAW" "$OUT" \
  --wrapper "$LOADER/wrapper" --shim "$LOADER/bunfs_shim.so"

printf '%s\n' "$VER" > "$ROOT/runtime/VERSION"
echo "[produce] done: $OUT ($(du -h "$OUT" | cut -f1))"