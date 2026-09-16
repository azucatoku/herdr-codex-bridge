#!/usr/bin/env bash
# herdr CLI adapter. The only file in codex-bridge that calls herdr directly.
# herdr's JSON field names and exit codes never leave this file; the status
# vocabulary (idle|working|done|none) is defined here and owned here.

# Pull one field for one pane out of the agent list. Returns 1 on query/parse failure.
herdr::_agent_field() {  # PANE FIELD
  herdr agent list 2>/dev/null \
    | CB_PANE="$1" CB_FIELD="$2" python3 -c '
import json,sys,os
pane, field = os.environ["CB_PANE"], os.environ["CB_FIELD"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a.get(field,"") for a in agents if a.get("pane_id")==pane), ""))'
}

# Normalized status: idle|working|done|none
herdr::agent_status() {
  local st; st=$(herdr::_agent_field "$1" agent_status) || return 1
  printf '%s\n' "${st:-none}"
}

# Which agent runs in this pane (empty if none)
herdr::agent_kind() { herdr::_agent_field "$1" agent; }

# First pane running an agent of this kind
herdr::find_agent() {
  herdr agent list 2>/dev/null | CB_KIND="$1" python3 -c '
import json,sys,os
k=os.environ["CB_KIND"]
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
print(next((a["pane_id"] for a in agents if a.get("agent")==k), ""))'
}

# All agents, as pane<TAB>kind<TAB>status<TAB>cwd
herdr::list_agents() {
  herdr agent list 2>/dev/null | python3 -c '
import json,sys
try: agents=json.load(sys.stdin)["result"]["agents"]
except Exception: sys.exit(1)
for a in agents:
    print("\t".join([a.get("pane_id",""), a.get("agent",""),
                     a.get("agent_status",""), a.get("cwd","")]))'
}

# Pane screen as plain text, scrollback included.
herdr::pane_text() {
  herdr pane read "$1" --source recent --lines "${2:-200}" --format text 2>/dev/null
}

# Only what is visible around the input box. Used to tell "inserted" from
# "submitted", so it must not be merged with pane_text.
herdr::pane_input_area() {
  herdr pane read "$1" --lines "${2:-8}" --format text 2>/dev/null
}

herdr::send_prompt() { herdr agent prompt "$1" "$2" >/dev/null 2>&1; }
herdr::send_key()    { herdr pane send-keys "$1" "$2" >/dev/null 2>&1; }
herdr::run()         { local p="$1"; shift; herdr pane run "$p" "$@" >/dev/null 2>&1; }

herdr::_pane_id() {  # stdin=JSON -> result.pane.pane_id
  python3 -c '
import json,sys
try: print(json.load(sys.stdin)["result"]["pane"]["pane_id"])
except Exception: sys.exit(1)'
}

herdr::pane_current() { herdr pane current 2>/dev/null | herdr::_pane_id; }
herdr::pane_split()   { herdr pane split "$1" --direction right 2>/dev/null | herdr::_pane_id; }

herdr::available() { command -v herdr >/dev/null 2>&1; }
