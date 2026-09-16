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

t() {  # t "name", then a check below
  TEST_NAME="$1"
  [[ -n "$FILTER" && "$TEST_NAME" != *"$FILTER"* ]] && return 1
  return 0
}
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$TEST_NAME"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n     %s\n' "$TEST_NAME" "$1"; }
eq()   { [[ "$1" == "$2" ]] && ok || no "expected [$2], got [$1]"; }
code() { [[ "$1" == "$2" ]] && ok || no "expected exit $2, got $1"; }

# --- layer 1: pure functions (render) ---------------------------------------
source "$ROOT/lib/render.sh"
echo "render"

if t "render: extracts only the answer from a normal screen"; then
  eq "$(render::answer cb-111-222-333 < "$FIX/screen_normal.txt")" "• 2+2 is 4."
fi

if t "render: keeps the opening when the answer quotes the question back"; then
  out=$(render::answer cb-111-222-333 < "$FIX/screen_requote.txt")
  [[ "$out" == *"To answer"* && "$out" == *"second paragraph"* ]] \
    && ok || no "paragraphs were cut: [$out]"
fi

if t "render: fails (1) when only an older request's marker is present"; then
  render::answer cb-111-222-333 < "$FIX/screen_stale.txt" >/dev/null; code "$?" 1
fi

if t "render: a missing marker is a failure, not an empty answer"; then
  printf '• answer\n' | render::answer cb-no-such-marker >/dev/null; code "$?" 1
fi

if t "render: wrapped question lines do not leak into the answer"; then
  eq "$(render::answer cb-777-888-999 < "$FIX/screen_wrapped.txt")" \
     "$(printf '• First line of the answer.\n  Second line of the answer.')"
fi

if t "render: a blank line inside the question does not leak it into the answer"; then
  eq "$(render::answer cb-333 < "$FIX/screen_blankline_q.txt")" "• The real answer."
fi

if t "render: bullets inside the question do not leak into the answer"; then
  eq "$(render::answer cb-999 < "$FIX/screen_bullet_in_question.txt")" "• The real answer."
fi

if t "render: keeps a line that quotes TUI chrome inside the answer"; then
  out=$(render::answer cb-444 < "$FIX/screen_chrome_in_body.txt")
  [[ "$out" == *"Ask Codex to do anything"* && "$out" == *"part of the answer too"* ]] \
    && ok || no "the body line was dropped: [$out]"
fi

if t "render: a Codex warning (⚠) is relayed as the body"; then
  eq "$(render::answer cb-555 < "$FIX/screen_codex_warning.txt")" \
     "⚠ Selected model is at capacity. Please try a different model."
fi

if t "render: no answer yet is success with empty output (distinct from no marker)"; then
  out=$(printf '› [cb-test] question\n\n› Ask Codex to do anything\n' | render::answer cb-test); rc=$?
  [[ "$rc" == 0 && -z "$out" ]] && ok || no "exit $rc, output [$out]"
fi

if t "render: submitted only when the marker sits on an echo line"; then
  render::marker_submitted cb-111-222-333 < "$FIX/screen_normal.txt" && r1=0 || r1=1
  printf '  [cb-111-222-333] still in the input box\n' | render::marker_submitted cb-111-222-333 && r2=0 || r2=1
  [[ "$r1" == 0 && "$r2" == 1 ]] && ok || no "submitted/unsubmitted not distinguished ($r1/$r2)"
fi

# --- layer 2: adapter contract (a fake herdr on PATH, the real lib/herdr.sh) --
echo "herdr adapter"
FAKE=$(mktemp -d); trap 'rm -rf "$FAKE"' EXIT
cat > "$FAKE/herdr" <<FAKEEOF
#!/usr/bin/env bash
# fake herdr: record the arguments, return a fixture
echo "\$*" >> "$FAKE/calls.log"
case "\$1 \$2" in
  "agent list") cat "$FIX/agent_list.json" ;;
  "pane read")  cat "$FIX/screen_normal.txt" ;;
  "pane current") echo '{"result":{"pane":{"pane_id":"w1:p1"}}}' ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
FAKEEOF
chmod +x "$FAKE/herdr"
PATH="$FAKE:$PATH"
source "$ROOT/lib/herdr.sh"

if t "adapter: agent_status returns a normalized value"; then
  eq "$(herdr::agent_status w5:p1)" "idle"
fi

if t "adapter: an unknown pane reports none"; then
  eq "$(herdr::agent_status w9:p9)" "none"
fi

if t "adapter: agent_kind reports which agent runs there"; then
  eq "$(herdr::agent_kind w5:p1)" "codex"
fi

if t "adapter: find_agent locates a pane by agent kind"; then
  eq "$(herdr::find_agent codex)" "w5:p1"
fi

if t "adapter: list_agents emits tab-separated rows"; then
  eq "$(herdr::list_agents | wc -l)" "2"
fi

if t "adapter: malformed JSON fails with 1"; then
  cat > "$FAKE/herdr" <<'BADEOF'
#!/usr/bin/env bash
echo "not json at all"
BADEOF
  chmod +x "$FAKE/herdr"
  herdr::agent_status w5:p1 >/dev/null 2>&1; code "$?" 1
fi

if t "adapter: send_prompt delegates to herdr agent prompt"; then
  cat > "$FAKE/herdr" <<FAKEEOF2
#!/usr/bin/env bash
echo "\$*" >> "$FAKE/calls.log"
echo '{"result":{"type":"ok"}}'
FAKEEOF2
  chmod +x "$FAKE/herdr"
  : > "$FAKE/calls.log"
  herdr::send_prompt w5:p1 "hello"
  grep -q "agent prompt w5:p1 hello" "$FAKE/calls.log" \
    && ok || no "calls logged: $(cat "$FAKE/calls.log")"
fi

# --- layer 3: state machine (time injected, so it runs instantly) ------------
echo "agent state machine"
export CB_SLEEP=:                      # inject a no-op sleep
source "$ROOT/lib/agent.sh"

if t "agent: each request gets a distinct marker"; then
  m1=$(agent::new_marker); m2=$(agent::new_marker)
  [[ "$m1" != "$m2" ]] && ok || no "markers collided: $m1"
fi

# Fake clock: cb::now runs in a subshell, so the counter lives in a file.
CLOCK="$FAKE/clock"
cb_fake_now() { local n; n=$(cat "$CLOCK" 2>/dev/null || echo 0); n=$((n+5)); echo "$n" > "$CLOCK"; echo "$n"; }
export CB_NOW=cb_fake_now
clock_reset() { echo 0 > "$CLOCK"; }

if t "agent: still working means 5, not an interruption"; then
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 5
fi

if t "agent: idle passes immediately"; then
  herdr::agent_status() { echo idle; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 0
fi

if t "agent: a failed status query is an internal error (1)"; then
  herdr::agent_status() { return 1; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 1
fi

if t "agent: an answer that never ends times out with 6"; then
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_done w5:p1 10; code "$?" 6
fi

if t "agent: completion returns 0"; then
  herdr::agent_status() { echo done; }
  clock_reset; agent::wait_done w5:p1 10; code "$?" 0
fi

if t "agent: the marker appearing on screen confirms delivery"; then
  herdr::send_prompt() { :; }
  herdr::pane_text() { echo "› [cb-test] question"; }
  clock_reset; agent::deliver w5:p1 cb-test "question"; code "$?" 0
fi

if t "agent: an absent marker fails without resending"; then
  SENDS="$FAKE/sends"; : > "$SENDS"
  herdr::send_prompt() { echo x >> "$SENDS"; }
  herdr::pane_text() { echo "an unrelated screen"; }
  clock_reset; agent::deliver w5:p1 cb-test "question"
  rc=$?
  n=$(wc -l < "$SENDS")
  [[ "$rc" != 0 && "$n" == 1 ]] && ok || no "exit $rc, $n sends (expected nonzero / 1)"
fi

if t "agent: unsubmitted input gets exactly one Enter"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "  [cb-test] only in the input box"; }   # not an echo line
  herdr::pane_input_area() { echo "  [cb-test] only in the input box"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(cat "$KEYS")" "Enter"
fi

if t "agent: an already-submitted request gets no Enter"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "› [cb-test] already submitted"; }
  herdr::pane_input_area() { echo "  (empty input box)"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(wc -c < "$KEYS")" "0"
fi

if t "agent: no marker anywhere means no Enter"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "an unrelated screen"; }
  herdr::pane_input_area() { echo "an unrelated screen"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(wc -c < "$KEYS")" "0"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
