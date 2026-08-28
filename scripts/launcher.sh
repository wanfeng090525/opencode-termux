#!/data/data/com.termux/files/usr/bin/bash
# scripts/launcher.sh — OpenCode launcher: TTY/lock cleanup + exec wrapped runtime
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SELF_DIR/../lib/opencode/runtime/opencode"

cleanup_tty_full() {
  if [ -t 1 ]; then printf '\033[?1049l\033[?25h\033[0m' >/dev/tty 2>/dev/null || true; fi
  if command -v stty >/dev/null 2>&1; then stty sane 2>/dev/null || true; fi
  if command -v tput >/dev/null 2>&1; then tput rmcup >/dev/null 2>&1 || true; fi
}
cleanup_tty_soft() {
  if command -v stty >/dev/null 2>&1; then stty sane 2>/dev/null || true; fi
  if [ -t 1 ]; then printf '\033[?25h\033[0m' >/dev/tty 2>/dev/null || true; fi
}
cleanup_locks() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
  [ -d "$d" ] && find "$d" -maxdepth 1 -type f -name '*.lock' -delete 2>/dev/null || true
}
trap 'cleanup_tty_full; exit 130' INT TERM HUP QUIT
cleanup_locks
: "${OPENCODE_DISABLE_DEFAULT_PLUGINS:=1}"
export OPENCODE_DISABLE_DEFAULT_PLUGINS

[[ -x "$RUN" ]] || { echo "opencode: runtime not found" >&2; exit 1; }
if "$RUN" "$@"; then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ]; then cleanup_tty_soft; else cleanup_tty_full; fi
exit "$rc"