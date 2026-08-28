#!/usr/bin/env bash
# scripts/build.sh — Stage a Termux install prefix from runtime/opencode-termux.
# Installs: launcher -> bin/opencode, wrapped runtime -> lib/opencode/runtime/opencode,
# plugin tools + hook runner -> lib/opencode/tools, system skills -> lib/opencode/system-skills.
# Output: artifacts/staged/prefix (consumed by package_deb.sh / package_pacman.sh)
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OPENCODE_OUT_DIR:-$ROOT/artifacts/staged}"
PREFIX_DIR="$OUT/prefix"
RUNTIME_INPUT="${OPENCODE_RUNTIME_INPUT:-$ROOT/runtime/opencode-termux}"

for d in "$PREFIX_DIR/bin" "$PREFIX_DIR/lib/opencode/runtime" "$PREFIX_DIR/lib/opencode/tools" "$PREFIX_DIR/lib/opencode/system-skills"; do
  ensure_dir "$d"
done

[[ -x "$RUNTIME_INPUT" ]] || {
  ls -la "$ROOT/runtime" 2>/dev/null || true
  fail "no runtime at $RUNTIME_INPUT — run 'make wrap' (scripts/produce.sh) first"
}

install -m 755 "$RUNTIME_INPUT" "$PREFIX_DIR/lib/opencode/runtime/opencode"
log "installed runtime ($(du -h "$PREFIX_DIR/lib/opencode/runtime/opencode" | cut -f1))"

install -m 755 "$ROOT/scripts/launcher.sh" "$PREFIX_DIR/bin/opencode"
log "installed launcher"

for f in "$ROOT/scripts/tools/plugin-manager.sh" "$ROOT/scripts/tools/plugin-selfcheck.sh" "$ROOT/scripts/hooks/run-system-skills.sh"; do
  [[ -f "$f" ]] || { log "skip (not found): $f"; continue; }
  install -m 755 "$f" "$PREFIX_DIR/lib/opencode/tools/$(basename "$f")"
done
log "installed plugin tools + hook runner"

if [[ -d "$ROOT/pkg/packing/system-skills" ]]; then
  cp -a "$ROOT/pkg/packing/system-skills/." "$PREFIX_DIR/lib/opencode/system-skills/"
fi
log "installed system-skills"

write_build_meta "$ROOT/artifacts/opencode/build.meta" \
  "component=opencode" \
  "prefix=$PREFIX_DIR" \
  "runtime_path=$PREFIX_DIR/lib/opencode/runtime/opencode" \
  "launcher_path=$PREFIX_DIR/bin/opencode"

log "staged build ready: $PREFIX_DIR"