#!/usr/bin/env bash
# 화면에서 답변 본문만 추출하는 순수 함수. herdr 를 호출하지 않는다.

# render::answer MARKER < screen_text
#   마커가 찍힌 입력 에코 줄 이후를 답변으로 본다.
#   반환: 0 정상 / 1 마커를 찾지 못함(추출 실패)
render::answer() {
  CB_MARKER="$1" python3 -c '
import sys,re,os
marker=os.environ["CB_MARKER"]
lines=[l.rstrip("\n").rstrip() for l in sys.stdin]

hits=[i for i,l in enumerate(lines) if marker in l]
if not hits:
    sys.exit(1)                      # 마커 없음 = 추출 실패 (빈 답변과 구분)

# 마커는 질문 에코와 (줄바꿈으로 이어진) 본문에 걸쳐 나타날 수 있다.
# 마지막 출현 이후를 답변 영역으로 본다.
start=hits[-1]

# 질문이 여러 줄로 감긴 경우, 이어지는 들여쓴 질문 줄들을 건너뛴다.
i=start+1
while i < len(lines):
    s=lines[i].strip()
    if not s:
        i+=1; continue
    break

out=lines[i:]
drop=re.compile(
    r"Ask Codex to do anything"
    r"|^\s*[─━]+\s*$"
    r"|^\s*gpt-[\w.\-]+ \w+ ·"
    r"|\? for shortcuts"
    r"|^\s*⏎|^\s*esc to interrupt"
)
kept=[l for l in out if not drop.search(l)]
while kept and not kept[0].strip(): kept.pop(0)
while kept and not kept[-1].strip(): kept.pop()
print("\n".join(kept))'
}

# render::has_marker MARKER < screen_text  → 0 있음 / 1 없음
render::has_marker() { grep -qF -- "$1"; }

# render::marker_submitted MARKER < screen_text
#   마커가 입력 에코 줄('›')에 있으면 제출된 것으로 본다.
render::marker_submitted() {
  CB_MARKER="$1" python3 -c '
import sys,os
m=os.environ["CB_MARKER"]
for l in sys.stdin:
    if m in l and "›" in l: sys.exit(0)
sys.exit(1)'
}
