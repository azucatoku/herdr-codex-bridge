#!/usr/bin/env bash
# herdr CLI 어댑터. codex-bridge 에서 herdr 를 직접 호출하는 유일한 파일.
# herdr 의 JSON 필드명·상태 문자열·종료코드는 이 파일 밖으로 새지 않는다.

herdr::_json() {  # stdin=JSON, $1=python 표현식 (data 변수 사용)
  CB_EXPR="$1" python3 -c '
import json,sys,os
try: data=json.load(sys.stdin)
except Exception: sys.exit(1)
try: v=eval(os.environ["CB_EXPR"], {"data": data, "next": next})
except Exception: sys.exit(1)
print("" if v is None else v)'
}

# 정규화된 상태: idle|working|done|none  (조회 실패는 종료코드 1)
herdr::agent_status() {
  local pane="$1" out
  out=$(herdr agent list 2>/dev/null) || return 1
  CB_PANE="$pane" printf '%s' "$out" | CB_PANE="$pane" python3 -c '
import json,sys,os
p=os.environ["CB_PANE"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
for a in agents:
    if a.get("pane_id")==p:
        print(a.get("agent_status") or "none"); break
else: print("none")'
}

# 패널에서 실행 중인 에이전트 종류 (없으면 빈 문자열)
herdr::agent_kind() {
  local pane="$1" out
  out=$(herdr agent list 2>/dev/null) || return 1
  CB_PANE="$pane" printf '%s' "$out" | CB_PANE="$pane" python3 -c '
import json,sys,os
p=os.environ["CB_PANE"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a.get("agent","") for a in agents if a.get("pane_id")==p), ""))'
}

# 종류로 패널 찾기 (첫 번째)
herdr::find_agent() {
  local kind="$1" out
  out=$(herdr agent list 2>/dev/null) || return 1
  CB_KIND="$kind" printf '%s' "$out" | CB_KIND="$kind" python3 -c '
import json,sys,os
k=os.environ["CB_KIND"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a["pane_id"] for a in agents if a.get("agent")==k), ""))'
}

# 에이전트 목록 (pane<TAB>kind<TAB>status<TAB>cwd)
herdr::list_agents() {
  local out
  out=$(herdr agent list 2>/dev/null) || return 1
  printf '%s' "$out" | python3 -c '
import json,sys
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
for a in agents:
    print("\t".join([a.get("pane_id",""), a.get("agent",""),
                     a.get("agent_status",""), a.get("cwd","")]))'
}

# 패널 화면을 평문으로 (ANSI 없음)
herdr::pane_text() {
  local pane="$1" lines="${2:-200}"
  herdr pane read "$pane" --source recent --lines "$lines" --format text 2>/dev/null
}

# 입력창 근처만 (제출 여부 판정용)
herdr::pane_input_area() {
  herdr pane read "$1" --lines "${2:-8}" --format text 2>/dev/null
}

herdr::send_prompt() { herdr agent prompt "$1" "$2" >/dev/null 2>&1; }
herdr::send_key()    { herdr pane send-keys "$1" "$2" >/dev/null 2>&1; }
herdr::run()         { local p="$1"; shift; herdr pane run "$p" "$@" >/dev/null 2>&1; }

herdr::pane_current() {
  herdr pane current 2>/dev/null | herdr::_json 'data["result"]["pane"]["pane_id"]'
}

herdr::pane_split() {
  herdr pane split "$1" --direction "${2:-right}" 2>/dev/null \
    | herdr::_json 'data["result"]["pane"]["pane_id"]'
}

herdr::available() { command -v herdr >/dev/null 2>&1; }
