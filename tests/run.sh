#!/usr/bin/env bash
# Dependency-free test runner: no bats, no shellcheck, no running herdr.
#
#   tests/run.sh            everything
#   tests/run.sh render     only tests whose name contains "render"
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
FIX="$ROOT/tests/fixtures"
FILTER="${1:-}"
PASS=0 FAIL=0

t()    { TEST_NAME="$1"; [[ -n "$FILTER" && "$TEST_NAME" != *"$FILTER"* ]] && return 1; return 0; }
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$TEST_NAME"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n     %s\n' "$TEST_NAME" "$1"; }
eq()   { [[ "$1" == "$2" ]] && ok || no "expected [$2], got [$1]"; }
code() { [[ "$1" == "$2" ]] && ok || no "expected exit $2, got $1"; }

# --- render: screen text in, answer out (pure) --------------------------------
source "$ROOT/lib/render.sh"
echo "render"

if t "render: extracts the answer and nothing else"; then
  eq "$(render::answer cb-111-222-333 < "$FIX/screen_normal.txt")" "• 2+2 is 4."
fi

if t "render: the question never leaks, however it is laid out"; then
  # One fixture covering all three ways the question used to bleed through:
  # a wrapped line, a blank line inside it, and its own bullet list.
  eq "$(render::answer cb-777 < "$FIX/screen_messy_question.txt")" \
     "$(printf '• First line of the answer.\n  Second line of the answer.')"
fi

if t "render: an answer quoting the question back keeps its opening"; then
  out=$(render::answer cb-111-222-333 < "$FIX/screen_requote.txt")
  [[ "$out" == *"To answer"* && "$out" == *"second paragraph"* ]] \
    && ok || no "paragraphs were cut: [$out]"
fi

if t "render: TUI chrome quoted inside the answer survives"; then
  out=$(render::answer cb-444 < "$FIX/screen_chrome_in_body.txt")
  [[ "$out" == *"Ask Codex to do anything"* && "$out" == *"part of the answer too"* ]] \
    && ok || no "the body line was dropped: [$out]"
fi

if t "render: a Codex warning is relayed as the body"; then
  eq "$(render::answer cb-555 < "$FIX/screen_codex_warning.txt")" \
     "⚠ Selected model is at capacity. Please try a different model."
fi

if t "render: no marker is a failure; no answer yet is empty success"; then
  # Only an older request's marker on screen, and no marker at all, are the
  # same failure (1). An answer that has not arrived is success with no output.
  render::answer cb-111-222-333 < "$FIX/screen_stale.txt" >/dev/null; r1=$?
  printf '• answer\n' | render::answer cb-absent >/dev/null; r2=$?
  out=$(printf '› [cb-test] question\n\n› Ask Codex to do anything\n' | render::answer cb-test); r3=$?
  [[ "$r1" == 1 && "$r2" == 1 && "$r3" == 0 && -z "$out" ]] \
    && ok || no "stale=$r1 absent=$r2 pending=$r3 out=[$out]"
fi

if t "render: submitted only when the marker sits on an echo line"; then
  render::marker_submitted cb-111-222-333 < "$FIX/screen_normal.txt" && r1=0 || r1=1
  printf '  [cb-111-222-333] still in the input box\n' \
    | render::marker_submitted cb-111-222-333 && r2=0 || r2=1
  [[ "$r1" == 0 && "$r2" == 1 ]] && ok || no "submitted/unsubmitted not distinguished ($r1/$r2)"
fi

# --- adapter: a fake herdr on PATH, the real lib/herdr.sh ---------------------
echo "herdr adapter"
FAKE=$(mktemp -d); trap 'rm -rf "$FAKE"' EXIT
cat > "$FAKE/herdr" <<FAKEEOF
#!/usr/bin/env bash
echo "\$*" >> "$FAKE/calls.log"
case "\$1 \$2" in
  "agent list") cat "$FIX/agent_list.json" ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
FAKEEOF
chmod +x "$FAKE/herdr"
PATH="$FAKE:$PATH"
source "$ROOT/lib/herdr.sh"

if t "adapter: normalizes status and kind for a pane"; then
  s=$(herdr::agent_status w5:p1); k=$(herdr::agent_kind w5:p1)
  none=$(herdr::agent_status w9:p9)          # unknown pane must read as none
  [[ "$s" == idle && "$k" == codex && "$none" == none ]] \
    && ok || no "status=$s kind=$k unknown=$none"
fi

if t "adapter: find_agent locates a pane by agent kind"; then
  eq "$(herdr::find_agent codex)" "w5:p1"
fi

if t "adapter: list_agents emits pane/kind/status/cwd rows"; then
  eq "$(herdr::list_agents | grep '^w5:p1' | cut -f2,3)" "$(printf 'codex\tidle')"
fi

if t "adapter: send_prompt delegates to herdr agent prompt"; then
  : > "$FAKE/calls.log"
  herdr::send_prompt w5:p1 "hello"
  grep -q "agent prompt w5:p1 hello" "$FAKE/calls.log" \
    && ok || no "calls logged: $(cat "$FAKE/calls.log")"
fi

if t "adapter: malformed JSON fails with 1"; then
  printf '#!/usr/bin/env bash\necho "not json"\n' > "$FAKE/herdr"; chmod +x "$FAKE/herdr"
  herdr::agent_status w5:p1 >/dev/null 2>&1; code "$?" 1
fi

# --- agent: the state machine, with time injected ----------------------------
echo "agent state machine"
export CB_SLEEP=:
source "$ROOT/lib/agent.sh"
CLOCK="$FAKE/clock"
cb_fake_now() { local n; n=$(cat "$CLOCK" 2>/dev/null || echo 0); n=$((n+5)); echo "$n" > "$CLOCK"; echo "$n"; }
export CB_NOW=cb_fake_now
clock_reset() { echo 0 > "$CLOCK"; }

if t "agent: each request gets a distinct marker"; then
  [[ "$(agent::new_marker)" != "$(agent::new_marker)" ]] && ok || no "markers collided"
fi

if t "agent: waiting on a busy agent gives up with 5, not an interruption"; then
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 5
fi

if t "agent: an idle agent passes immediately"; then
  herdr::agent_status() { echo idle; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 0
fi

if t "agent: a failed status query is an internal error, not a timeout"; then
  herdr::agent_status() { return 1; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 1
fi

if t "agent: waiting for an answer ends in 0 when done, 6 when it never does"; then
  herdr::agent_status() { echo done; }
  clock_reset; agent::wait_done w5:p1 10; r1=$?
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_done w5:p1 10; r2=$?
  [[ "$r1" == 0 && "$r2" == 6 ]] && ok || no "done=$r1 never=$r2"
fi

if t "agent: the marker on screen confirms delivery"; then
  herdr::send_prompt() { :; }
  herdr::pane_text() { echo "› [cb-test] question"; }
  clock_reset; agent::deliver w5:p1 cb-test "question"; code "$?" 0
fi

if t "agent: an absent marker fails without resending"; then
  SENDS="$FAKE/sends"; : > "$SENDS"
  herdr::send_prompt() { echo x >> "$SENDS"; }
  herdr::pane_text() { echo "an unrelated screen"; }
  clock_reset; agent::deliver w5:p1 cb-test "question"; rc=$?
  n=$(wc -l < "$SENDS")
  [[ "$rc" != 0 && "$n" == 1 ]] && ok || no "exit $rc, $n sends (expected nonzero / 1)"
fi

if t "agent: Enter is sent once, and only for input still in the box"; then
  KEYS="$FAKE/keys"
  herdr::send_key() { echo "$2" >> "$KEYS"; }
  # still in the input box -> exactly one Enter
  : > "$KEYS"
  herdr::pane_text()       { echo "  [cb-test] only in the input box"; }
  herdr::pane_input_area() { echo "  [cb-test] only in the input box"; }
  agent::ensure_submitted w5:p1 cb-test; a=$(cat "$KEYS")
  # already submitted -> nothing, even though the tail read still shows the echo
  : > "$KEYS"
  herdr::pane_text()       { echo "› [cb-test] already submitted"; }
  herdr::pane_input_area() { echo "› [cb-test] already submitted"; }
  agent::ensure_submitted w5:p1 cb-test; b=$(wc -c < "$KEYS")
  # marker nowhere -> nothing
  : > "$KEYS"
  herdr::pane_text()       { echo "an unrelated screen"; }
  herdr::pane_input_area() { echo "an unrelated screen"; }
  agent::ensure_submitted w5:p1 cb-test; c=$(wc -c < "$KEYS")
  [[ "$a" == Enter && "$b" == 0 && "$c" == 0 ]] \
    && ok || no "unsubmitted=[$a] submitted=$b absent=$c"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
