#!/usr/bin/env bash
# Install codex-bridge.
#
#   ./install.sh            copy this checkout into ~/.local/share/codex-bridge
#                           and link the commands at it. Editing, moving or
#                           deleting the checkout afterwards changes nothing.
#   ./install.sh --link     point the commands at this checkout instead, so
#                           edits take effect immediately (for development).
#   ./install.sh uninstall  remove the commands and the installed copy.
#
# PREFIX overrides ~/.local.
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
SHARE="$PREFIX/share/codex-bridge"
LINKS=(codex-bridge ask-codex start-codex)

MODE=copy
case "${1:-}" in
  ""|install) ;;
  --link)     MODE=link ;;
  uninstall)  MODE=uninstall ;;
  *) echo "install: unknown argument '$1' (install|--link|uninstall)" >&2; exit 2 ;;
esac

fail=0
link_to() {  # link_to TARGET_DIR
  local l target
  for l in "${LINKS[@]}"; do
    target="$BIN/$l"
    if [[ -e "$target" && ! -L "$target" ]]; then
      echo "install: $target exists and is not a symlink; skipping" >&2
      continue
    fi
    if ln -sf "$1/bin/codex-bridge" "$target"; then
      echo "installed: $target -> $1/bin/codex-bridge"
    else
      echo "install: could not install $target" >&2; fail=1
    fi
  done
}

if [[ "$MODE" == uninstall ]]; then
  for l in "${LINKS[@]}"; do
    if [[ -L "$BIN/$l" ]]; then
      dest=$(readlink -f "$BIN/$l")
      if [[ "$dest" == "$ROOT/bin/"* || "$dest" == "$SHARE/bin/"* ]]; then
        rm -f "$BIN/$l" && echo "removed: $BIN/$l" || { echo "install: could not remove $BIN/$l" >&2; fail=1; }
      fi
    fi
  done
  if [[ -d "$SHARE" ]]; then
    rm -rf "$SHARE" && echo "removed: $SHARE" || { echo "install: could not remove $SHARE" >&2; fail=1; }
  fi
  exit "$fail"
fi

mkdir -p "$BIN" || { echo "install: cannot create $BIN" >&2; exit 1; }

if [[ "$MODE" == link ]]; then
  echo "note: linking to the checkout; edits to $ROOT take effect immediately" >&2
  link_to "$ROOT"
else
  rm -rf "$SHARE" || { echo "install: cannot replace $SHARE" >&2; exit 1; }
  mkdir -p "$SHARE" || { echo "install: cannot create $SHARE" >&2; exit 1; }
  for d in bin lib VERSION LICENSE; do
    cp -R "$ROOT/$d" "$SHARE/" || { echo "install: could not copy $d" >&2; exit 1; }
  done
  # Record what this copy was built from, so --version can name it.
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" describe --always --dirty --tags > "$SHARE/BUILD" 2>/dev/null
  fi
  echo "installed copy: $SHARE"
  link_to "$SHARE"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "note: $BIN is not on your PATH" >&2 ;;
esac
exit "$fail"
