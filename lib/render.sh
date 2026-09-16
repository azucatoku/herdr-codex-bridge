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

# 마커는 요청마다 고유하므로 이 요청의 입력 에코는 '›' 가 붙은 첫 출현이다.
# 답변 본문이 질문을 재인용해 마커가 다시 나와도 앞부분을 잃지 않으려면
# 마지막이 아니라 '첫' 에코를 기준으로 잘라야 한다.
echoes=[i for i in hits if "›" in lines[i]]
start=echoes[0] if echoes else hits[0]

out=lines[start+1:]
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
