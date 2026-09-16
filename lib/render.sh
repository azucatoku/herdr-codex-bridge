#!/usr/bin/env bash
# Pure functions that pull the answer out of screen text. Never calls herdr.

# render::answer MARKER < screen_text
#   Answer = [first column-0 bullet after this request's echo, next input line)
#   Returns 0 on success (the answer may legitimately be empty),
#           1 if the marker is absent (extraction failed — distinct from empty).
render::answer() {
  CB_MARKER="$1" python3 -c '
import sys,re,os
marker=os.environ["CB_MARKER"]
lines=[l.rstrip("\n").rstrip() for l in sys.stdin]

hits=[i for i,l in enumerate(lines) if marker in l]
if not hits:
    sys.exit(1)                      # no marker = extraction failed, not an empty answer

# The marker is unique per request, so this request is echoed on the first line
# carrying it next to the prompt glyph. Anchoring on the FIRST echo (not the
# last) keeps the answer intact when it quotes the question back.
echoes=[i for i in hits if "›" in lines[i]]
start=echoes[0] if echoes else hits[0]

# The answer opens with a bullet, or with a Codex warning. Both count as body:
# dropping warnings would turn "the model reported an error" into "no answer".
#
# It must sit at column 0. The TUI indents the continuation lines of a
# multi-line question, so an indented bullet is still part of the question.
# Comparing after lstrip() makes any question containing "- item" style bullets
# leak its own text back as the answer.
begin=next((i for i in range(start+1, len(lines))
            if lines[i][:1] in ("•", "⚠")), None)
if begin is None:
    print(""); sys.exit(0)           # answer has not arrived yet

# Stop at the next input line. Everything past it is TUI chrome, so chrome
# quoted inside the answer is never mistaken for it.
end=next((i for i in range(begin, len(lines)) if lines[i].lstrip().startswith("›")),
         len(lines))

drop=re.compile(r"^\s*[─━]+\s*$|^\s*gpt-[\w.\-]+ \w+ ·|^\s*─ Worked for ")
kept=[l for l in lines[begin:end] if not drop.search(l)]
while kept and not kept[-1].strip(): kept.pop()
print("\n".join(kept))'
}

# render::has_marker MARKER < screen_text  -> 0 present / 1 absent
render::has_marker() { grep -qF -- "$1"; }

# render::marker_submitted MARKER < screen_text
#   Submitted once the marker appears on an echo line (next to the prompt glyph).
render::marker_submitted() {
  CB_MARKER="$1" python3 -c '
import sys,os
m=os.environ["CB_MARKER"]
for l in sys.stdin:
    if m in l and "›" in l: sys.exit(0)
sys.exit(1)'
}
