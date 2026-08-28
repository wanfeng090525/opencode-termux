#!/usr/bin/env bash
# scripts/produce.sh — Wrap npm's opencode-linux-arm64 (aarch64 Bun CLI) with bun-termux-loader
# Usage:
#   ./scripts/produce.sh [VERSION]     # version or auto-latest
#   VER=1.19.0 ./scripts/produce.sh    # or set VER env
#   VER=1.18.25 LOADER_COMMIT=<sha> ./scripts/produce.sh
# Output: runtime/opencode-termux (self-contained aarch64 binary), cached in
#         $CACHE_DIR (default ~/.cache/opencode-termux) keyed by version+loader commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
veriffy() { python3 "$ROOT/scripts/verify.py" "$1" >/dev/null 2>&1; }

LOADER_REPO="${LOADER_REPO:-https://github.com/Hope2333/bun-termux-loader}"
LOADER_COMMIT="${LOADER_COMMIT:-2f26c286132a3bfbc3eaa1e4003a4ea457feeb96}"  # pinned, for reproducibility
LOADER="$ROOT/.cache/bun-termux-loader"
OUT="$ROOT/runtime/opencode-termux"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/opencode-termux}"
CACHE_KEY="${LOADER_COMMIT:0:8}"
mkdir -p "$CACHE_DIR"

for c in npm python3 git tar file; do
  command -v "$c" >/dev/null 2>&1 || { echo "missing required tool: $c" >&2; exit 1; }
done

# --- version resolution:  positional > $VER env > auto-latest from npm ---
VER="${1:-$VER}"
if [[ -z "$VER" ]]; then
  echo "[produce] NO version given -> resolving latest opencode-linux-arm64 from npm ..."
  VER="$(npm view opencode-linux-arm64 version)" || { echo "FATAL: npm latest lookup failed" >&2; exit 1; }
  echo "[produce] latest = $VER"
fi
echo "[produce] opencode-linux-arm64@$VER (loader $CACHE_KEY)"

CACHE_BIN="$CACHE_DIR/opencode-$VER-$CACHE_KEY"
if [[ -f "$CACHE_BIN" ]]; then
  echo "[produce] cache hit: $CACHE_BIN"
  install -m 755 "$CACHE_BIN" "$OUT"
  if veriffy "$OUT"; then
    printf '%s\n' "$VER" > "$ROOT/runtime/VERSION"
    echo "[produce] done (cached): $OUT ($(du -h "$OUT" | cut -f1))"
    exit 0
  fi
  echo "[produce] cached file failed verification -> rebuilding" >&2
  rm -f "$CACHE_BIN"
fi

printf '%s\n' "$VER" > "$ROOT/runtime/VERSION"
mkdir -p "$ROOT/runtime" "$ROOT/.cache"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
echo "[produce] npm pack opencode-linux-arm64@$VER"
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

# --- loader, pinned to a fixed commit for reproducibility ---
if [[ ! -d "$LOADER/.git" ]]; then
  echo "[produce] cloning bun-termux-loader"
  git clone "$LOADER_REPO" "$LOADER" >/dev/null 2>&1
fi
if ! git -C "$LOADER" cat-file -e "$LOADER_COMMIT^{commit}" 2>/dev/null; then
  echo "[produce] fetching pinned loader commit $LOADER_COMMIT"
  git -C "$LOADER" fetch --quiet origin "$LOADER_COMMIT" || { echo "FATAL: cannot fetch loader commit"; exit 1; }
fi
git -C "$LOADER" checkout --quiet "$LOADER_COMMIT"
echo "[produce] loader pinned @ $(git -C "$LOADER" rev-parse --short HEAD)"

echo "[produce] wrapping for Termux"
python3 "$LOADER/build.py" "$RAW" "$OUT" \
  --wrapper "$LOADER/wrapper" --shim "$LOADER/bunfs_shim.so"
[[ -f "$OUT" ]] || { echo "FATAL: wrapping produced no output" >&2; exit 1; }

veriffy "$OUT" || { echo "FATAL: wrapped binary failed structural verification" >&2; exit 1; }
install -m 755 "$OUT" "$CACHE_BIN"
echo "[produce] done: $OUT ($(du -h "$OUT" | cut -f1)), cached -> $CACHE_BIN"