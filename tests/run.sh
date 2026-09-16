#!/usr/bin/env bash
# 의존성 없는 테스트 러너 (bats/shellcheck 불필요, herdr 불필요).
#
#   tests/run.sh            전체
#   tests/run.sh render     이름에 render 가 포함된 것만
set -uo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
FIX="$ROOT/tests/fixtures"
FILTER="${1:-}"
PASS=0 FAIL=0

t() {  # t "이름" ; 뒤이어 실제 검증 함수 호출
  TEST_NAME="$1"
  [[ -n "$FILTER" && "$TEST_NAME" != *"$FILTER"* ]] && return 1
  return 0
}
ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$TEST_NAME"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n     %s\n' "$TEST_NAME" "$1"; }
eq()   { [[ "$1" == "$2" ]] && ok || no "기대: [$2]  실제: [$1]"; }
code() { [[ "$1" == "$2" ]] && ok || no "종료코드 기대: $2  실제: $1"; }

# ── 계층 1: 순수 함수 (render) ────────────────────────────────────────────
source "$ROOT/lib/render.sh"
echo "render"

if t "render: 정상 화면에서 답변만 추출"; then
  eq "$(render::answer cb-111-222-333 < "$FIX/screen_normal.txt")" "• 2+2는 4입니다."
fi

if t "render: 답변이 질문을 재인용해도 앞부분을 잃지 않음"; then
  out=$(render::answer cb-111-222-333 < "$FIX/screen_requote.txt")
  [[ "$out" == *"질문하신"* && "$out" == *"두 번째 문단"* ]] \
    && ok || no "앞/뒤 문단이 잘렸습니다: [$out]"
fi

if t "render: 과거 요청의 마커만 있으면 추출 실패(코드 1)"; then
  render::answer cb-111-222-333 < "$FIX/screen_stale.txt" >/dev/null; code "$?" 1
fi

if t "render: 마커가 없으면 빈 답변이 아니라 실패로 구분"; then
  printf '• 답변\n' | render::answer cb-없는마커 >/dev/null; code "$?" 1
fi

if t "render: 화면에 감긴 질문의 나머지 줄이 답변에 섞이지 않음"; then
  eq "$(render::answer cb-777-888-999 < "$FIX/screen_wrapped.txt")" \
     "$(printf '• 답변 첫 줄입니다.\n  답변 둘째 줄입니다.')"
fi

if t "render: 질문 중간에 빈 줄이 있어도 질문 문단이 답변에 섞이지 않음"; then
  eq "$(render::answer cb-333 < "$FIX/screen_blankline_q.txt")" "• 진짜 답변입니다."
fi

if t "render: 질문에 불릿(•)이 들어 있어도 질문이 답변으로 새지 않음"; then
  eq "$(render::answer cb-999 < "$FIX/screen_bullet_in_question.txt")" "• 실제 답변입니다."
fi

if t "render: 본문에 TUI 안내 문구가 인용돼도 그 줄을 지우지 않음"; then
  out=$(render::answer cb-444 < "$FIX/screen_chrome_in_body.txt")
  [[ "$out" == *"Ask Codex to do anything"* && "$out" == *"이 줄도 답변의 일부"* ]] \
    && ok || no "본문이 삭제됐습니다: [$out]"
fi

if t "render: Codex 자신의 경고(⚠)도 본문으로 전달"; then
  eq "$(render::answer cb-555 < "$FIX/screen_codex_warning.txt")" \
     "⚠ Selected model is at capacity. Please try a different model."
fi

if t "render: 답변이 아직 없으면 성공하되 빈 문자열 (마커 없음과 구분)"; then
  out=$(printf '› [cb-test] 질문\n\n› Ask Codex to do anything\n' | render::answer cb-test); rc=$?
  [[ "$rc" == 0 && -z "$out" ]] && ok || no "코드 $rc, 출력 [$out]"
fi

if t "render: 제출 판정은 에코 줄('›')에 마커가 있을 때만"; then
  render::marker_submitted cb-111-222-333 < "$FIX/screen_normal.txt" && r1=0 || r1=1
  printf '  [cb-111-222-333] 입력창에만 있음\n' | render::marker_submitted cb-111-222-333 && r2=0 || r2=1
  [[ "$r1" == 0 && "$r2" == 1 ]] && ok || no "제출/미제출 구분 실패 (제출:$r1 미제출:$r2)"
fi

# ── 계층 2: 어댑터 계약 (가짜 herdr 를 PATH 앞에 두고 실제 lib/herdr.sh 실행) ──
echo "herdr adapter"
FAKE=$(mktemp -d); trap 'rm -rf "$FAKE"' EXIT
cat > "$FAKE/herdr" <<FAKEEOF
#!/usr/bin/env bash
# 가짜 herdr — 호출 인자를 기록하고 fixture 를 돌려준다
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

if t "adapter: agent_status 를 정규화된 값으로 반환"; then
  eq "$(herdr::agent_status w5:p1)" "idle"
fi

if t "adapter: 없는 패널의 상태는 none"; then
  eq "$(herdr::agent_status w9:p9)" "none"
fi

if t "adapter: agent_kind 로 종류 조회"; then
  eq "$(herdr::agent_kind w5:p1)" "codex"
fi

if t "adapter: find_agent 가 종류로 패널을 찾음"; then
  eq "$(herdr::find_agent codex)" "w5:p1"
fi

if t "adapter: list_agents 가 탭 구분 행을 냄"; then
  eq "$(herdr::list_agents | wc -l)" "2"
fi

if t "adapter: 비정상 JSON 응답이면 실패(코드 1)"; then
  cat > "$FAKE/herdr" <<'BADEOF'
#!/usr/bin/env bash
echo "not json at all"
BADEOF
  chmod +x "$FAKE/herdr"
  herdr::agent_status w5:p1 >/dev/null 2>&1; code "$?" 1
fi

if t "adapter: send_prompt 가 herdr agent prompt 로 위임"; then
  cat > "$FAKE/herdr" <<FAKEEOF2
#!/usr/bin/env bash
echo "\$*" >> "$FAKE/calls.log"
echo '{"result":{"type":"ok"}}'
FAKEEOF2
  chmod +x "$FAKE/herdr"
  : > "$FAKE/calls.log"
  herdr::send_prompt w5:p1 "안녕"
  grep -q "agent prompt w5:p1 안녕" "$FAKE/calls.log" \
    && ok || no "호출 기록: $(cat "$FAKE/calls.log")"
fi

# ── 계층 3: 상태 머신 (시간 주입으로 즉시 실행) ────────────────────────────
echo "agent 상태 머신"
export CB_SLEEP=:                      # sleep 을 no-op 으로 주입
source "$ROOT/lib/agent.sh"

if t "agent: 마커는 요청마다 달라야 함"; then
  m1=$(agent::new_marker); m2=$(agent::new_marker)
  [[ "$m1" != "$m2" ]] && ok || no "마커가 같습니다: $m1"
fi

# 가짜 시계: cb::now 는 명령치환(서브셸)에서 불리므로 카운터를 파일에 둔다
CLOCK="$FAKE/clock"
cb_fake_now() { local n; n=$(cat "$CLOCK" 2>/dev/null || echo 0); n=$((n+5)); echo "$n" > "$CLOCK"; echo "$n"; }
export CB_NOW=cb_fake_now
clock_reset() { echo 0 > "$CLOCK"; }

if t "agent: 상대가 계속 working 이면 끼어들지 않고 5"; then
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 5
fi

if t "agent: idle 이면 즉시 통과"; then
  herdr::agent_status() { echo idle; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 0
fi

if t "agent: 상태 조회 실패는 내부 오류 1"; then
  herdr::agent_status() { return 1; }
  clock_reset; agent::wait_idle w5:p1 10; code "$?" 1
fi

if t "agent: 응답이 끝나지 않으면 타임아웃 6"; then
  herdr::agent_status() { echo working; }
  clock_reset; agent::wait_done w5:p1 10; code "$?" 6
fi

if t "agent: 완료되면 0"; then
  herdr::agent_status() { echo done; }
  clock_reset; agent::wait_done w5:p1 10; code "$?" 0
fi

if t "agent: 마커가 화면에 나타나면 전달 확인"; then
  herdr::send_prompt() { :; }
  herdr::pane_text() { echo "› [cb-test] 질문"; }
  clock_reset; agent::deliver w5:p1 cb-test "질문"; code "$?" 0
fi

if t "agent: 마커가 끝내 안 보이면 실패, 재전송하지 않음"; then
  SENDS="$FAKE/sends"; : > "$SENDS"
  herdr::send_prompt() { echo x >> "$SENDS"; }
  herdr::pane_text() { echo "관련 없는 화면"; }
  clock_reset; agent::deliver w5:p1 cb-test "질문"
  rc=$?
  n=$(wc -l < "$SENDS")
  [[ "$rc" != 0 && "$n" == 1 ]] && ok || no "코드 $rc, 전송 횟수 $n (기대: 0 아님 / 1회)"
fi

if t "agent: 미제출이면 Enter 를 정확히 1회 보냄"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "  [cb-test] 질문이 입력창에만 있음"; }   # 에코(›) 아님
  herdr::pane_input_area() { echo "  [cb-test] 질문이 입력창에만 있음"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(cat "$KEYS")" "Enter"
fi

if t "agent: 이미 제출됐으면 Enter 를 보내지 않음"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "› [cb-test] 이미 제출된 질문"; }
  herdr::pane_input_area() { echo "  (빈 입력창)"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(wc -c < "$KEYS")" "0"
fi

if t "agent: 마커도 입력창도 없으면 Enter 를 보내지 않음"; then
  KEYS="$FAKE/keys"; : > "$KEYS"
  herdr::pane_text()       { echo "관련 없는 화면"; }
  herdr::pane_input_area() { echo "관련 없는 화면"; }
  herdr::send_key()        { echo "$2" >> "$KEYS"; }
  agent::ensure_submitted w5:p1 cb-test
  eq "$(wc -c < "$KEYS")" "0"
fi

printf '\n통과 %d  실패 %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
