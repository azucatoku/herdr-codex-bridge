#!/usr/bin/env bash
# 에이전트 상호작용 상태 머신.
# herdr 호출은 전부 lib/herdr.sh 를 통한다. 시간·대기는 주입 가능하다.

: "${CB_SLEEP:=sleep}"          # 테스트에서 즉시 반환하는 것으로 교체 가능
: "${CB_NOW:=cb::_now}"
cb::_now() { date +%s; }

cb::sleep() { "$CB_SLEEP" "$1"; }
cb::now()   { "$CB_NOW"; }

# 요청마다 고유 마커. 화면/상태 관측을 이번 요청에 귀속시키는 유일한 수단.
agent::new_marker() { printf 'cb-%s-%s-%s' "$$" "$(cb::now)" "$((RANDOM))"; }

# agent::wait_idle PANE LIMIT_SEC → 0 idle / 5 계속 working / 1 조회실패
agent::wait_idle() {
  local pane="$1" limit="$2" deadline st
  deadline=$(( $(cb::now) + limit ))
  while :; do
    st=$(herdr::agent_status "$pane") || return 1
    [[ "$st" == "working" ]] || return 0
    (( $(cb::now) >= deadline )) && return 5
    cb::sleep 3
  done
}

# agent::deliver PANE MARKER QUESTION → 0 확인됨 / 1 확인실패
#   마커가 화면에 나타나면 전달된 것. 재전송은 하지 않는다(중복 실행 방지).
agent::deliver() {
  local pane="$1" marker="$2" q="$3" window=10 deadline
  herdr::send_prompt "$pane" "[$marker] $q"
  deadline=$(( $(cb::now) + window ))
  while :; do
    cb::sleep 2
    herdr::pane_text "$pane" 60 | render::has_marker "$marker" && return 0
    (( $(cb::now) >= deadline )) && return 1
  done
}

# agent::ensure_submitted PANE MARKER
#   마커가 입력창에 남아 있고 아직 제출 에코가 아니면 Enter 를 1회만 보낸다.
agent::ensure_submitted() {
  local pane="$1" marker="$2" screen
  screen=$(herdr::pane_text "$pane" 80)
  printf '%s\n' "$screen" | render::marker_submitted "$marker" && return 0
  if herdr::pane_input_area "$pane" 8 | render::has_marker "$marker"; then
    herdr::send_key "$pane" Enter
    cb::sleep 2
  fi
  return 0
}

# agent::wait_done PANE TIMEOUT_SEC → 0 완료 / 6 타임아웃 / 1 조회실패
agent::wait_done() {
  local pane="$1" timeout="$2" deadline st
  deadline=$(( $(cb::now) + timeout ))
  cb::sleep 2
  while :; do
    st=$(herdr::agent_status "$pane") || return 1
    [[ "$st" == "idle" || "$st" == "done" ]] && return 0
    (( $(cb::now) >= deadline )) && return 6
    cb::sleep 3
  done
}
