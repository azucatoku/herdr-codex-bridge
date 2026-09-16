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

## 상관 마커 (correlation marker) — 설계의 중심

Codex 리뷰에서 드러난 근본 문제: **관측한 화면과 상태를 "이번 요청"에 귀속시킬 방법이
없으면** 전달 판정·완료 판정·답변 추출이 전부 무너진다. scrollback에 같은 질문이 이미
있거나, 이전 요청 때문에 `working`이거나, 빠르게 끝난 요청이면 전부 오판한다.

해결: **요청마다 고유 마커를 질문 앞에 붙인다.**

```
[cb:cb-12345-1757930000] 실제 질문 내용...
```

이 마커 하나로 다음이 전부 결정된다:

| 관측 | 판정 |
|---|---|
| 화면에 마커 없음 | 전달 안 됨 |
| 마커가 입력 에코(`›`) 줄에 있음 | 제출됨 |
| 마커가 있는데 입력창에 머물러 있음 | 삽입만 됨 → Enter 필요 |
| 마커 에코 줄 이후 | **이번 요청의 답변 영역** |

scrollback에 과거 질문이 있어도 마커가 다르므로 오판하지 않는다. 답변 추출도 "질문
앞 24자의 마지막 출현" 같은 휴리스틱이 아니라 마커 기준으로 정확히 잘린다.

## 상태 모델

`inserted` / `submitted` / `working` / `completed` 를 구분한다. 특히
**`inserted`와 `submitted`를 구분하지 않으면** 이미 제출된 요청에 Enter를 한 번 더
보내 빈 요청을 만든다(Codex가 지적한 실제 시나리오).

Enter는 **마커가 입력창 영역에 남아 있다는 증거가 있을 때만 1회** 보낸다.

## 재전송은 기본 비활성

첫 전송이 단지 느렸을 뿐인데 재전송하면 같은 질문이 두 번 실행된다. 따라서
**자동 재전송을 하지 않는다.** 확인 실패 시 종료코드 4로 끝내고, 호출자가
중복 실행을 감수하겠다고 `--retry`를 명시할 때만 1회 재전송한다.

같은 이유로 코드 4의 의미는 "전달 실패"가 아니라 **"전달 확인 실패 — 실제로는
전달됐을 수 있음"** 이다. 호출자가 무심코 재시도하지 않도록 메시지에 명시한다.

## 동시성

패널 하나에 동시에 두 개의 ask가 들어가면 관측이 뒤섞인다. `flock`으로 패널별
잠금을 걸고, 이미 잠겨 있으면 대기하거나 종료코드 5로 거절한다.

## 모듈 구조

```
bin/codex-bridge      디스패처 (start|ask|list)
lib/herdr.sh          herdr API 래퍼 — 이 파일만이 herdr를 직접 호출한다
lib/agent.sh          전달·제출·완료대기 등 에이전트 상호작용
lib/render.sh         pane 출력에서 답변 본문만 추출
tests/run.sh          의존성 없는 테스트 러너 (bats/shellcheck 불필요)
install.sh            ~/.local/bin 에 심볼릭 링크 설치
```

`lib/herdr.sh`가 유일한 herdr 접점이다. 단 그 전제가 유지되려면 **herdr의 JSON
필드명·상태 문자열·종료코드가 이 파일 밖으로 새면 안 된다.** wrapper는 정규화된
계약만 노출한다:

```
herdr::agent_status PANE   -> idle|working|done|none
herdr::pane_text PANE N    -> 평문 (ANSI 제거)
herdr::send_prompt PANE TEXT
herdr::send_key PANE KEY
herdr::run PANE CMD...
herdr::find_agent KIND     -> pane_id
```

`render.sh`는 **순수 함수**로 둔다. 화면 한 장이 아니라 (마커, 화면) 을 받아 답변만
돌려준다. 현재 화면만 보고 추출하면 과거 출력과 구별할 수 없다.

**설치 경로**: `~/.local/bin/codex-bridge`가 심볼릭 링크이므로 `$0` 기준으로 `../lib`를
찾으면 라이브러리를 못 찾는다. 실행 시 `readlink -f "$0"`로 실경로를 구해 해석한다.

## 종료코드

| 코드 | 의미 |
|---|---|
| 0 | 정상 |
| 1 | 내부 오류 / herdr 자체 실패 / 비정상 응답 |
| 2 | 인자 오류 |
| 3 | 패널 확보 실패 |
| 4 | **전달 확인 실패** — 실제로는 전달됐을 수 있음. 무심코 재시도하지 말 것 |
| 5 | 상대가 계속 working, 또는 패널 잠김 (끼어들지 않고 중단) |
| 6 | 응답 타임아웃 (stdout은 부분 답변) |
| 128+n | 시그널 종료 (관례) |

**출력 계약**: stdout은 답변 본문만, stderr은 진단·진행 상태. 타임아웃 시 stdout
내용은 부분 답변이며 코드 6. 추출 실패와 "정상적인 빈 답변"은 구분한다(전자는 코드 1).

`start`의 코드 0은 "프로세스를 띄웠다"가 아니라 **"입력 가능한 준비 상태를 확인했다"**
는 뜻이다.

## 테스트 전략

`bats`와 `shellcheck`는 sudo가 필요해 의존하지 않는다. `tests/run.sh`가 순수 bash로 돈다.

**두 계층으로 나눈다.** `lib/herdr.sh` 파일을 물리적으로 교체하는 방식은 병렬 실행이
어렵고 실제 설치 구조를 검증하지 못하므로 쓰지 않는다.

1. **상태 머신 테스트** — 의존성 주입으로 가짜 adapter를 넣어 `agent.sh` 로직 검증
2. **adapter 계약 테스트** — `PATH` 앞에 가짜 `herdr` 실행 파일을 두고 **실제**
   `lib/herdr.sh`를 실행해 인자·stdout/stderr·비정상 응답 처리를 검증. 실제 herdr
   출력 샘플을 fixture로 보관해 파서 회귀 테스트를 한다.

`sleep`과 현재 시각도 주입 가능하게 한다. 그렇지 않으면 전달 실패 테스트 하나가
20초 이상 걸리고 경쟁 테스트가 불안정해진다.

검증 항목:

- 정상 질의응답
- 전달 실패 → 재전송 → 종료코드 4
- 미제출 상태 → Enter 전송
- 상대가 working → 종료코드 5
- 타임아웃 → 중간 출력 + 종료코드 6
- 답변 안에 질문이 재인용돼도 앞부분이 잘리지 않음
- 이미 에이전트가 떠 있는 패널에 start → 기본은 거절, `--replace` 에서만 교체
- 첫 전송이 늦게 도착 + 재전송까지 도착하는 중복 실행
- 질문이 이미 scrollback에 존재 (마커로 구분되는지)
- `working`을 폴링 사이에 놓치는 즉시 완료
- idle 확인 직후 다른 호출이 먼저 전송하는 동시성 경쟁
- status는 idle인데 출력 flush가 늦는 경우
- herdr hang, 비정상 출력, pane 소멸·재사용
- Ctrl-C/TERM 중 종료 및 이후 pane 상태
- 여러 줄 / 아주 짧은 질문 / 선행 `-` / 제어문자 포함 질문

## 비목표

- Codex가 직접 git을 다루게 하지 않는다. 커밋은 항상 Claude가 한다.
- herdr 외의 터미널 멀티플렉서(tmux 등)는 지원하지 않는다.
- **기존 에이전트를 기본으로 죽이지 않는다.** 작업 중인 세션을 파괴할 수 있으므로
  `start`는 기본적으로 재사용하거나 거절하고, `--replace`를 줬을 때만 교체한다.
