# herdr-codex-bridge

Ask OpenAI Codex a question from Claude Code, and get just the answer back.

Claude Code writes the code; Codex reads it from a second angle and pushes back.
`codex-bridge` is the plumbing between them — it runs Codex in a
[herdr](https://herdr.dev) pane, delivers your question reliably, and prints the
reply with none of the TUI noise around it.

```console
$ codex-bridge start
$ codex-bridge ask "What does this design miss?"
• The delivery check can't attribute an observation to a specific request.
  If the same question is already in the scrollback, it reports success
  before anything was actually sent.
```

## Why this exists

Calling `herdr agent prompt` directly fails **silently** in several ways. All of
these were observed in practice, not imagined:

1. A response of `agent_prompted` does not mean the text arrived.
2. Text can land in the input box without ever being submitted.
3. The `revision` field is a snapshot taken before the input is applied, so it
   cannot be used to confirm delivery.
4. Sending a command to a pane that already runs an agent types it **into that
   agent's TUI**, not the shell.
5. A terminal reply sequence left over from `Ctrl-C` corrupts the next command.
6. Answers arrive buried in TUI chrome.

`codex-bridge` handles all six, and tells you honestly when it cannot.

## Install

Requires [herdr](https://herdr.dev), the
[Codex CLI](https://developers.openai.com/codex/cli), bash 4+, python3, `flock`,
and GNU `readlink -f`.

```bash
git clone https://github.com/azucatoku/herdr-codex-bridge.git
cd herdr-codex-bridge && ./install.sh          # symlinks into ~/.local/bin
./install.sh uninstall
```

Symlinks, so edits to the checkout take effect immediately. `ask-codex` and
`start-codex` are installed as aliases for `ask` and `start`.

## Usage

```
codex-bridge start [-m advisor|writer] [-d DIR] [-p PANE] [-M MODEL] [--replace]
codex-bridge ask   [-p PANE] [-t SEC] [-w SEC] "question"
codex-bridge list
```

| Flag | Meaning |
|---|---|
| `-m` | `advisor` (default, read-only) or `writer` (can edit files) |
| `-d` | Working directory (default: current) |
| `-p` | Target pane (default: auto-discover, or split a new one) |
| `-M` | Model, e.g. `gpt-6-astra` |
| `-t` | Answer timeout in seconds (default 300) |
| `-w` | How long to wait if the agent is busy (default 180) |
| `--replace` | Replace an agent already running in that pane |

### Advisor and writer

| Mode | Sandbox | Use |
|---|---|---|
| `advisor` (default) | `read-only` | Review. Same working tree as Claude |
| `writer` | `workspace-write` | Codex edits files directly |

**Do not isolate the reviewer.** A second opinion has to see the code under
review, so `advisor` attaches to the *same* working tree. Read-only means it
will not edit your files, so two agents in one tree do not fight over them. Use
`writer` only when Codex should actually edit something; it still cannot touch
`.git`, so commits stay with Claude.

## Trust and limits

**Answers are untrusted input.** They are a second opinion, not a verdict. Check
each finding against the code before acting on it, drop the ones you can
disprove, and keep ownership of the decision. This is not just about the model
being wrong: whatever Codex reads in the working tree — `AGENTS.md`, project
skills, a rules file, a comment in a source file — reaches it as *instructions*,
not data. A repository can therefore steer its own reviewer.

**What `advisor` does and does not guarantee.** `start -m advisor` launches
Codex with `-s read-only -a never`, and those flags outrank any user or project
config. But two gaps are worth knowing:

- A `.rules` file with `decision = "allow"` lets matching commands run *outside*
  the sandbox with no prompt, and the interactive Codex TUI has no
  `--ignore-rules`. So "read-only" holds for ordinary config, not against rules
  you have installed yourself.
- `ask` talks to a pane; it does not inspect how that session was started. If
  you point it at a `writer` session, or at a Codex someone launched by hand,
  the read-only property is whatever *that* session got. Only sessions this tool
  started as `advisor` carry the guarantee.

**Flag surface is closed by construction.** The Codex command line is assembled
from a fixed array, and unknown options are rejected rather than forwarded. A
future write-enabling Codex flag cannot reach the sandbox through passthrough.
This is an `advisor` invariant; `writer` is a deliberate exception.

## Exit codes

`ask` prints the answer on stdout and diagnostics on stderr, so scripts can rely
on the split.

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Internal error, herdr failure, or the answer could not be extracted |
| 2 | Bad arguments |
| 3 | No pane, no agent in it, or the agent there is not Codex |
| 4 | **Delivery unconfirmed** — it may well have arrived. Do not blindly retry |
| 5 | Agent still busy, or the pane is locked by another `ask` |
| 6 | Timed out (stdout holds a partial answer) |

Errors that mean *no second opinion is available* (codes 3, and a missing
`codex` CLI) also print a `FALLBACK:` line telling the caller to proceed
without one, so an automated caller knows what to do next.

Code 4 is deliberately *not* called "delivery failed". If the first send was
merely slow, resending runs the same question twice — so `codex-bridge` never
retries on its own. Read the pane (`herdr pane read <pane>`) before deciding.

## How it works

Every request carries a unique marker:

```
[cb:cb-12345-1757930000-4821] your question here
```

Without it, nothing can be attributed to *this* request: an identical question
sitting in the scrollback, a `working` state left over from a previous call, or
a request that finished before the first poll all read as success. The marker
settles delivery, submission, completion, and where the answer starts and ends.

```
lib/herdr.sh    the only file that calls herdr
lib/render.sh   pure function: screen text in, answer out
lib/agent.sh    delivery / submission / completion state machine
bin/codex-bridge  dispatcher, owns the exit-code mapping
```

See [docs/DESIGN.md](docs/DESIGN.md) (Korean) for the reasoning.

## Tests

```bash
./tests/run.sh          # 28 checks, ~2s
./tests/run.sh render   # filter by name
```

No `bats`, no `shellcheck`, no running herdr. Two layers: a fake `herdr` earlier
on `PATH` exercises the real `lib/herdr.sh`, and injected time makes the state
machine tests instant.

## License

MIT
