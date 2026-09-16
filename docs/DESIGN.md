# Design notes

The README covers *what this does*. This file covers *why it is built this way*.
Usage, options and exit codes live in the README, not here.

## The problems it exists for

Calling `herdr agent prompt` directly fails **silently** in several ways. Every
item below was observed in practice.

1. A response of `agent_prompted` does not mean the text arrived.
2. Text can land in the input box without ever being submitted.
3. The `revision` field is a snapshot taken before the input is applied, so it
   cannot confirm delivery.
4. Sending a command to a pane that already runs an agent types it into that
   agent's TUI, not the shell.
5. A terminal reply sequence left over from `Ctrl-C` (`9;5:1u`) corrupts the
   next command.
6. Answers arrive buried in TUI chrome.

## The correlation marker

The underlying problem is that **an observed screen or status cannot be
attributed to a particular request**. An identical question sitting in the
scrollback, a `working` state left from an earlier call, a request that finished
before the first poll — each of them reads as success.

So every request carries a unique marker, prepended to the question:

```
[cb:cb-12345-1757930000-4821] the actual question...
```

| Observation | Meaning |
|---|---|
| Marker absent from the screen | Delivery unconfirmed — it may still be in flight, so never reported as "not sent" |
| Marker on an echo line (`›`) | Submitted |
| Marker present but still in the input box | Inserted only — needs Enter |
| From the first column-0 `•`/`⚠` after the echo, to the next `›` | **this request's answer** |

Two details that look like nitpicks and are not:

- The answer is anchored on the **first** echo carrying the marker, not the
  last. An answer that quotes the question back would otherwise lose everything
  before the quote.
- The opening bullet must be at **column 0**. The TUI indents the continuation
  lines of a multi-line question, so an indented bullet is still the question.
  Matching after `lstrip()` makes any question containing a bullet list return
  part of itself as the answer.

`inserted` and `submitted` are tracked separately. Collapsing them sends a
stray Enter to an already-submitted request, which fires an empty one.

Completion is **not** covered by the marker: it comes from the agent returning
to `idle`/`done`. That signal can arrive before the text is flushed, which is
why the answer is re-read a few times before an empty result is accepted.

## It never resends

If the first send was merely slow, resending runs the same question twice. So a
failed delivery check ends the run. That is why exit code 4 means **"delivery
unconfirmed — it may well have arrived"**, not "delivery failed"; the wording is
load-bearing, because the natural reaction to "failed" is to retry.

## Boundaries

- `lib/herdr.sh` is the only file that calls herdr. Its **JSON field names and
  exit codes** never leave it.

  Status strings are a different matter. The adapter defines a normalized
  vocabulary — `idle|working|done|none` — and callers compare against *that*.
  Today those values happen to match herdr's own, which hides the seam; if herdr
  renamed `working` to `busy`, the mapping would change in `herdr.sh` and every
  caller would stay put. The boundary is not "no strings escape", it is "the
  adapter owns the vocabulary".
- `lib/render.sh` is pure. It never calls herdr.
- Mapping outcomes to exit codes belongs to `bin/codex-bridge`. The libraries
  return success or failure.

## Why an interactive TUI and not `codex exec`

`codex exec -s read-only -a never -C DIR PROMPT` returns an answer directly.
Going that way would delete the herdr delivery, the marker, the screen parsing
and the startup logic. It is genuinely simpler.

The reason for the TUI is **multi-turn context**. An advisor has to answer the
next question while remembering the last one and its own reply ("of the three
things you raised, I fixed the second like this — better?"). `exec` starts a new
process per call and has none of that. A pane a human can watch is wanted for
the same reason.

Put differently: **all the complexity here is the price of a conversation that
persists.** For one-shot questions, call `codex exec` directly instead.

## It does not kill an existing agent

Replacing a live session can destroy work in progress, so `start` refuses by
default and only replaces with `--replace`.

## Test strategy

No dependency on `bats`, `shellcheck`, or a running herdr. Two layers:

1. **State machine** — a fake adapter is injected to exercise `agent.sh`.
2. **Adapter contract** — a fake `herdr` executable earlier on `PATH`, running
   the *real* `lib/herdr.sh`, checks arguments, output, and malformed responses.

`sleep` and the clock are injectable, so the whole suite finishes in about two
seconds.
