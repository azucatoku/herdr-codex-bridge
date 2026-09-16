# codex-bridge

Claude Code(주작업자)가 herdr 패널에 떠 있는 Codex(조언자)와 대화하기 위한 다리.

Claude가 plan을 세운 뒤, 또는 한 phase를 끝낸 뒤 Codex에게 놓친 점을 묻는 흐름을
한 줄로 만든다. 답변은 TUI 장식 없이 본문만 stdout으로 나온다.

```bash
codex-bridge start                       # 조언자(읽기전용)로 현재 디렉토리에 기동
codex-bridge ask "이 설계에서 놓친 게 있나?"
```

## 설치

```bash
./install.sh            # ~/.local/bin 에 심볼릭 링크
./install.sh uninstall
```

링크이므로 저장소를 고치면 즉시 반영된다. `ask-codex` / `start-codex` 라는 이름으로도
설치되어 각각 `ask` / `start` 하위 명령으로 연결된다.

## 명령

```
codex-bridge start [-m advisor|writer] [-d DIR] [-p PANE] [-M MODEL] [--replace]
codex-bridge ask   [-p PANE] [-t SEC] [-w SEC] [--retry] "질문"
codex-bridge list
```

| 옵션 | 뜻 |
|---|---|
| `-m` | `advisor`(기본, 읽기전용) / `writer`(쓰기 가능) |
| `-d` | 작업 디렉토리 (기본: 현재 위치) |
| `-p` | 패널 지정 (기본: 자동 탐색 / 새 패널 분할) |
| `-M` | 모델 (예: `gpt-6-astra`) |
| `-t` | 응답 타임아웃 초, 기본 300 |
| `-w` | 상대가 작업 중일 때 대기 한도 초, 기본 180 |
| `--replace` | 이미 떠 있는 에이전트를 교체 |
| `--retry` | 전달 확인 실패 시 1회 재전송 (**중복 실행 가능**) |

## 모드

| 모드 | 샌드박스 | 용도 |
|---|---|---|
| `advisor` (기본) | `read-only` | Claude와 **같은 트리**에 붙여 리뷰. 쓰기 불가라 충돌 불가 |
| `writer` | `workspace-write` | 가끔 직접 수정. `.git`은 막혀 있으므로 커밋은 Claude가 |

Codex를 worktree나 clone으로 격리하지 않는 것이 핵심이다. 조언자는 리뷰할 코드를
봐야 하고, 읽기 전용이면 같은 트리에 있어도 충돌이 구조적으로 불가능하다.

## 종료코드

| 코드 | 의미 |
|---|---|
| 0 | 정상 |
| 1 | 내부 오류 / herdr 실패 / 답변 추출 실패 |
| 2 | 인자 오류 |
| 3 | 패널 확보 실패 |
| 4 | **전달 확인 실패** — 실제로는 전달됐을 수 있다. 무심코 재시도하지 말 것 |
| 5 | 상대가 계속 작업 중이거나 패널이 잠김 |
| 6 | 응답 타임아웃 (stdout은 부분 답변) |

stdout은 답변 본문만, stderr은 진단. 스크립트에서 쓸 때 이 분리에 의존해도 된다.

## 왜 이렇게 만들었나

`herdr agent prompt` 를 그냥 부르면 다음이 전부 조용히 어긋난다:

- 응답이 `agent_prompted` 여도 텍스트가 전달되지 않을 수 있다
- 전달돼도 Enter가 눌리지 않아 입력창에 머문다
- 응답의 `revision` 은 입력 반영 전 스냅샷이라 전달 판정에 쓸 수 없다
- 이미 에이전트가 떠 있는 패널에 명령을 보내면 셸이 아니라 그 TUI 입력창으로 들어간다
- Ctrl-C 직후 터미널 응답 시퀀스가 남아 다음 명령을 깨뜨린다

**요청마다 고유 마커를 질문 앞에 붙여** 관측한 화면과 상태를 그 요청에 귀속시키는 것이
설계의 중심이다. scrollback에 같은 질문이 있어도, 답변이 질문을 재인용해도 오판하지
않는다. 자세한 내용은 [docs/DESIGN.md](docs/DESIGN.md).

## 테스트

```bash
./tests/run.sh          # 전체
./tests/run.sh render   # 이름으로 필터
```

`bats` / `shellcheck` / `herdr` 없이 순수 bash로 돌고 2초 안에 끝난다. 가짜 `herdr` 를
PATH 앞에 두고 실제 `lib/herdr.sh` 를 실행하는 계약 테스트와, 시간을 주입한 상태 머신
테스트로 나뉜다.

## 구조

```
bin/codex-bridge   디스패처
lib/herdr.sh       herdr API 어댑터 — 여기서만 herdr 를 직접 호출한다
lib/render.sh      화면에서 답변 본문을 뽑는 순수 함수
lib/agent.sh       전달·제출·완료 대기 상태 머신 (시간 주입 가능)
tests/run.sh       테스트 러너
```

## 요구사항

herdr, Codex CLI, bash 4+, python3. 설치는 `~/.local/bin` 에 링크만 만든다.
