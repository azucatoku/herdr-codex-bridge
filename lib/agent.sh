#!/usr/bin/env bash
# Agent interaction state machine. All herdr calls go through lib/herdr.sh.
# Time and waiting are injectable so tests run instantly.

: "${CB_SLEEP:=sleep}"          # tests replace this with a no-op
: "${CB_NOW:=cb::_now}"
cb::_now() { date +%s; }

cb::sleep() { "$CB_SLEEP" "$1"; }
cb::now()   { "$CB_NOW"; }

# A unique marker per request — the only way to attribute an observed screen or
# status to this request rather than to something already in the scrollback.
agent::new_marker() { printf 'cb-%s-%s-%s' "$$" "$(cb::now)" "$((RANDOM))"; }

# agent::wait_idle PANE LIMIT_SEC -> 0 idle / 5 still working / 1 query failed
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

# agent::deliver PANE MARKER QUESTION -> 0 confirmed / 1 unconfirmed
#   The marker appearing on screen is the confirmation. Never resends: if the
#   first send was merely slow, a resend runs the same question twice.
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
#   Presses Enter once, and only with evidence that the marker is still sitting
#   in the input box. Skipping that check sends a stray empty request whenever
#   the text was already submitted.
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

# agent::wait_done PANE TIMEOUT_SEC -> 0 done / 6 timed out / 1 query failed
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
