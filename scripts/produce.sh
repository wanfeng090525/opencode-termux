#!/usr/bin/env bash
# scripts/produce.sh — Wrap upstream opencode-linux-arm64 with bun-termux-loader
# Source:
#   --url <URL>  → 直接下载预编译 opencode-linux-arm64 二进制（直链，可 .tgz 或单个二进制）
#   否则         →   npm 发布包 opencode-linux-arm64@[VERSION]
# Usage:
#   ./scripts/produce.sh [VERSION] [--url <URL>]     # 默认 VERSION=1.18.23
#   VER=1.19.0 ./scripts/produce.sh                  # 或 set VER env
# Output: runtime/opencode-termux (self-contained aarch64 binary)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOADER_REPO="${LOADER_REPO:-https://github.com/Hope2333/bun-termux-loader}"
LOADER="$ROOT/.cache/bun-termux-loader"
OUT="$ROOT/runtime/opencode-termux"

VER="${VER:-1.18.23}"
URL=""
args=("$@")
while (($#)); do
  case "$1" in
    --url|-u) URL="${2:-}"; shift 2 ;;
    *) if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then VER="$1"; fi; shift ;;
  esac
done

for c in npm python3 git curl tar file; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing required tool: $c" >&2; exit 1; }
done

mkdir -p "$ROOT/runtime" "$ROOT/.cache"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[produce] source: ${URL:+direct-url }opencode-linux-arm64@$VER"
cd "$WORK"
if [[ -n "$URL" ]]; then
  curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$WORK/src-pkg"
  case "$URL" in
    *.tgz|*.tar.gz|*.tar.xz|*.tar.bz2)
      mkdir -p "$WORK/dl" && tar -xzf "$WORK/src-pkg" -C "$WORK/dl"
      RAW="$(find "$WORK/dl" -type f -path '*/bin/opencode' | head -n 1)"
      ;;
    *) RAW="$WORK/src-pkg"; chmod +x "$RAW" || true ;;
  esac
else
  npm pack "opencode-linux-arm64@$VER" >/dev/null
  tar -xzf "opencode-linux-arm64-$VER.tgz"
  RAW="$WORK/package/bin/opencode"
fi
[[ -x "$RAW" ]] || { echo "FATAL: no executable at $RAW" >&2; exit 1; }
echo "[produce] upstream: $(file -b "$RAW")"

# Clear early error: Termux needs the Bun CLI binary, NOT the desktop GUI package.
if [[ "$(head -c4 "$RAW")" != "$(printf '\177ELF')" ]]; then
  echo "FATAL: selected source is not an ELF binary: $(file -b "$RAW")" >&2
  echo "  For Termux you need the Bun CLI package: npm 'opencode-linux-arm64@<ver>' (default 1.18.23)." >&2
  echo "  Do NOT use desktop GUI packages (opencode-desktop-linux-*.rpm/.deb/AppImage)." >&2
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