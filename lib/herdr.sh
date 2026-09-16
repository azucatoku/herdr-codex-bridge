#!/usr/bin/env bash
# herdr CLI 어댑터. codex-bridge 에서 herdr 를 직접 호출하는 유일한 파일.
# herdr 의 JSON 필드명·상태 문자열·종료코드는 이 파일 밖으로 새지 않는다.

# 에이전트 목록에서 특정 패널의 필드 하나를 꺼낸다. 조회/파싱 실패는 종료코드 1.
herdr::_agent_field() {  # PANE FIELD
  herdr agent list 2>/dev/null \
    | CB_PANE="$1" CB_FIELD="$2" python3 -c '
import json,sys,os
pane, field = os.environ["CB_PANE"], os.environ["CB_FIELD"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a.get(field,"") for a in agents if a.get("pane_id")==pane), ""))'
}

# 정규화된 상태: idle|working|done|none
herdr::agent_status() {
  local st; st=$(herdr::_agent_field "$1" agent_status) || return 1
  printf '%s\n' "${st:-none}"
}

# 패널에서 실행 중인 에이전트 종류 (없으면 빈 문자열)
herdr::agent_kind() { herdr::_agent_field "$1" agent; }

# 종류로 패널 찾기 (첫 번째)
herdr::find_agent() {
  herdr agent list 2>/dev/null | CB_KIND="$1" python3 -c '
import json,sys,os
k=os.environ["CB_KIND"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a["pane_id"] for a in agents if a.get("agent")==k), ""))'
}

# 에이전트 목록 (pane<TAB>kind<TAB>status<TAB>cwd)
herdr::list_agents() {
  herdr agent list 2>/dev/null | python3 -c '
import json,sys
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
for a in agents:
    print("\t".join([a.get("pane_id",""), a.get("agent",""),
                     a.get("agent_status",""), a.get("cwd","")]))'
}

# 패널 화면을 평문으로. scrollback 포함.
herdr::pane_text() {
  herdr pane read "$1" --source recent --lines "${2:-200}" --format text 2>/dev/null
}

# 현재 보이는 입력창 근처만. 제출 여부 판정에 쓰므로 pane_text 와 합치면 안 된다.
herdr::pane_input_area() {
  herdr pane read "$1" --lines "${2:-8}" --format text 2>/dev/null
}

herdr::send_prompt() { herdr agent prompt "$1" "$2" >/dev/null 2>&1; }
herdr::send_key()    { herdr pane send-keys "$1" "$2" >/dev/null 2>&1; }
herdr::run()         { local p="$1"; shift; herdr pane run "$p" "$@" >/dev/null 2>&1; }

herdr::_pane_id() {  # stdin=JSON → result.pane.pane_id
  python3 -c '
import json,sys
try: print(json.load(sys.stdin)["result"]["pane"]["pane_id"])
except Exception: sys.exit(1)'
}

herdr::pane_current() { herdr pane current 2>/dev/null | herdr::_pane_id; }
herdr::pane_split()   { herdr pane split "$1" --direction right 2>/dev/null | herdr::_pane_id; }

herdr::available() { command -v herdr >/dev/null 2>&1; }
