# codex-bridge 설계

## 목적

Claude Code(주작업자)가 herdr 패널에 떠 있는 Codex(조언자)와 대화할 때 생기는
마찰을 없앤다. 현재는 `herdr agent prompt` → `herdr pane read`를 손으로 반복하며
전달 실패·미제출·완료 대기를 매번 처리해야 한다.

## 해결하려는 실제 문제 (모두 실측된 것)

1. `herdr agent prompt`의 응답이 `agent_prompted`여도 텍스트가 전달되지 않을 수 있다.
2. 전달돼도 Enter가 눌리지 않아 입력창에 머무를 수 있다.
3. 응답의 `revision`은 입력 반영 전 스냅샷이라 전달 판정에 쓸 수 없다.
4. 이미 에이전트가 떠 있는 패널에 `herdr pane run`을 보내면 셸이 아니라 그 TUI의
   입력창으로 들어간다.
5. Ctrl-C 직후 터미널 응답 시퀀스(`9;5:1u`)가 남아 다음 명령을 깨뜨린다.
6. `herdr pane read` 출력에 TUI 장식이 섞여 답변만 뽑기 어렵다.

## CLI 표면

```
codex-bridge start [-m advisor|writer] [-d DIR] [-p PANE] [-M MODEL]
codex-bridge ask   [-p PANE] [-t SEC] [-w SEC] "질문"
codex-bridge list                     # 떠 있는 에이전트 패널 목록
```

`ask-codex` / `start-codex` 는 각각 `codex-bridge ask` / `codex-bridge start` 로
위임하는 얇은 심볼릭 링크로 유지한다(기존 사용법 호환).

## 모드

| 모드 | 샌드박스 | 용도 |
|---|---|---|
| `advisor` (기본) | `read-only` | Claude와 **같은 트리**에 붙여 리뷰. 쓰기 불가라 충돌 불가 |
| `writer` | `workspace-write` | 가끔 직접 수정. `.git`은 여전히 막히므로 커밋은 Claude가 |

## 모듈 구조

```
bin/codex-bridge      디스패처 (start|ask|list)
lib/herdr.sh          herdr API 래퍼 — 이 파일만이 herdr를 직접 호출한다
lib/agent.sh          전달·제출·완료대기 등 에이전트 상호작용
lib/render.sh         pane 출력에서 답변 본문만 추출
tests/run.sh          의존성 없는 테스트 러너 (bats/shellcheck 불필요)
install.sh            ~/.local/bin 에 심볼릭 링크 설치
```

`lib/herdr.sh`가 유일한 herdr 접점이므로, herdr API가 바뀌어도 이 파일만 고치면 된다.
테스트에서는 이 파일을 가짜 구현으로 교체해 herdr 없이 검증한다.

## 전달 판정 (핵심 로직)

`revision`을 쓰지 않는다. 전송 후 최대 10초 동안 아래 중 하나가 관측되면 전달 성공:

- `agent_status`가 `working`으로 전이
- 패널 화면에 질문의 앞 24자가 등장

10초 내 둘 다 없으면 1회 재전송하고, 그래도 없으면 종료코드 4로 실패 처리한다.
전달은 됐는데 `working`이 아니면 미제출로 보고 Enter를 보낸다.

## 종료코드

| 코드 | 의미 |
|---|---|
| 0 | 정상 |
| 2 | 인자 오류 |
| 3 | 패널 확보 실패 |
| 4 | 전달 실패 |
| 5 | 상대가 계속 working (끼어들지 않고 중단) |
| 6 | 응답 타임아웃 (중간 출력은 표시) |

호출자가 "완료된 답변"과 "잘린 중간 출력"을 구분할 수 있어야 하므로 타임아웃도
반드시 0이 아닌 코드로 끝낸다.

## 테스트 전략

`bats`와 `shellcheck`는 sudo가 필요해 의존하지 않는다. `tests/run.sh`가 순수 bash로
돌고, `lib/herdr.sh`를 가짜 구현으로 바꿔치기해 다음을 검증한다:

- 정상 질의응답
- 전달 실패 → 재전송 → 종료코드 4
- 미제출 상태 → Enter 전송
- 상대가 working → 종료코드 5
- 타임아웃 → 중간 출력 + 종료코드 6
- 답변 안에 질문이 재인용돼도 앞부분이 잘리지 않음
- 이미 에이전트가 떠 있는 패널에 start → 기존 종료 후 재기동

## 비목표

- Codex가 직접 git을 다루게 하지 않는다. 커밋은 항상 Claude가 한다.
- herdr 외의 터미널 멀티플렉서(tmux 등)는 지원하지 않는다.
