#!/usr/bin/env bash
# Symlink codex-bridge into ~/.local/bin. Pass "uninstall" to remove the links.
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
BIN="${PREFIX:-$HOME/.local}/bin"
LINKS=(codex-bridge ask-codex start-codex)

case "${1:-}" in
  "")        MODE=install ;;
  install)   MODE=install ;;
  uninstall) MODE=uninstall ;;
  *) echo "install: unknown argument '$1' (install|uninstall)" >&2; exit 2 ;;
esac

fail=0

if [[ "$MODE" == uninstall ]]; then
  for l in "${LINKS[@]}"; do
    if [[ -L "$BIN/$l" && "$(readlink -f "$BIN/$l")" == "$ROOT/bin/"* ]]; then
      if rm -f "$BIN/$l"; then echo "removed: $BIN/$l"
      else echo "install: could not remove $BIN/$l" >&2; fail=1; fi
    fi
  done
  exit "$fail"
fi

mkdir -p "$BIN" || { echo "install: cannot create $BIN" >&2; exit 1; }
for l in "${LINKS[@]}"; do
  target="$BIN/$l"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "install: $target exists and is not a symlink; skipping" >&2
    continue
  fi
  if ln -sf "$ROOT/bin/codex-bridge" "$target"; then
    echo "installed: $target -> $ROOT/bin/codex-bridge"
  else
    echo "install: could not install $target" >&2; fail=1
  fi
done

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "note: $BIN is not on your PATH" >&2 ;;
esac
exit "$fail"
