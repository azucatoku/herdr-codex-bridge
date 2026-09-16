#!/usr/bin/env bash
# codex-bridge 를 ~/.local/bin 에 심볼릭 링크로 설치한다.
# 링크이므로 저장소를 수정하면 즉시 반영된다. 제거는 uninstall 인자.
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
BIN="${PREFIX:-$HOME/.local}/bin"
LINKS=(codex-bridge ask-codex start-codex)

case "${1:-}" in
  "")        MODE=install ;;
  install)   MODE=install ;;
  uninstall) MODE=uninstall ;;
  *) echo "install: 알 수 없는 인자 '$1' (install|uninstall)" >&2; exit 2 ;;
esac

fail=0

if [[ "$MODE" == uninstall ]]; then
  for l in "${LINKS[@]}"; do
    if [[ -L "$BIN/$l" && "$(readlink -f "$BIN/$l")" == "$ROOT/bin/"* ]]; then
      if rm -f "$BIN/$l"; then echo "제거: $BIN/$l"
      else echo "install: $BIN/$l 제거 실패" >&2; fail=1; fi
    fi
  done
  exit "$fail"
fi

mkdir -p "$BIN" || { echo "install: $BIN 를 만들 수 없습니다" >&2; exit 1; }
for l in "${LINKS[@]}"; do
  target="$BIN/$l"
  if [[ -e "$target" && ! -L "$target" ]]; then
    echo "install: $target 이(가) 이미 있고 심볼릭 링크가 아닙니다. 건너뜁니다" >&2
    continue
  fi
  if ln -sf "$ROOT/bin/codex-bridge" "$target"; then
    echo "설치: $target -> $ROOT/bin/codex-bridge"
  else
    echo "install: $target 설치 실패" >&2; fail=1
  fi
done

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "주의: $BIN 이 PATH 에 없습니다" >&2 ;;
esac
exit "$fail"
