#!/usr/bin/env bash
# 화면에서 답변 본문만 추출하는 순수 함수. herdr 를 호출하지 않는다.

# render::answer MARKER < screen_text
#   답변 영역 = [이 요청의 에코 줄 다음 첫 '•' 줄, 다음 입력창('›') 줄 전)
#   반환: 0 정상(빈 문자열일 수 있음) / 1 마커를 찾지 못함(추출 실패)
render::answer() {
  CB_MARKER="$1" python3 -c '
import sys,re,os
marker=os.environ["CB_MARKER"]
lines=[l.rstrip("\n").rstrip() for l in sys.stdin]

hits=[i for i,l in enumerate(lines) if marker in l]
if not hits:
    sys.exit(1)                      # 마커 없음 = 추출 실패 (빈 답변과 구분)

# 마커는 요청마다 고유하므로 이 요청의 입력 에코는 "›" 가 붙은 첫 출현이다.
# 본문이 질문을 재인용해 마커가 다시 나와도 앞부분을 잃지 않는다.
echoes=[i for i in hits if "›" in lines[i]]
start=echoes[0] if echoes else hits[0]

# 답변은 "•" 로, Codex 자신의 경고/오류는 "⚠" 로 시작한다. 둘 다 본문으로 인정한다.
# (경고를 본문에서 빼면 "답변이 오지 않았다"는 엉뚱한 진단이 나간다)
#
# 반드시 행 첫 칸이어야 한다. 질문이 여러 줄이면 TUI 가 이어지는 줄을 들여쓰므로,
# 들여쓴 불릿은 아직 질문 영역이다. lstrip 으로 비교하면 질문에 "• ..." 가 들어간
# 순간 그 줄부터 답변으로 오인해 질문 일부를 답변으로 돌려준다.
begin=next((i for i in range(start+1, len(lines))
            if lines[i][:1] in ("•", "⚠")), None)
if begin is None:
    print(""); sys.exit(0)           # 아직 답변이 도착하지 않음

# 다음 입력창 줄에서 끊는다. 그 뒤는 TUI 장식이므로 본문과 헷갈릴 일이 없다.
end=next((i for i in range(begin, len(lines)) if lines[i].lstrip().startswith("›")),
         len(lines))

drop=re.compile(r"^\s*[─━]+\s*$|^\s*gpt-[\w.\-]+ \w+ ·|^\s*─ Worked for ")
kept=[l for l in lines[begin:end] if not drop.search(l)]
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
