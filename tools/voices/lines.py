"""How a line template is spoken: its parts in order (shared by every rogue).

A template is what the game shows, with blanks: {you} (your critter's name),
{them} (another rogue's), {k} / {w} (the score: their beat-downs of you and
yours of them). Spoken, a line is:

  ["t", text]        words, rendered as one clip (a rogue renders each once)
  ["you", p]         your name, said as it ends a phrase with `p` ("." "!"
                     "?" ","): rendered for each name ("Bun!", "Fox?")
  ["them", p]        a rogue's name, the same way
  ["num", "k"|"w"]   a number, rendered 0..99
  ["pause", seconds] a beat of silence (an ellipsis on its own)

Scores read out as "{k}–{w}" are left unsaid (the speech bubble shows them).
Words in capitals are shouted in the text; spoken they're just words.
"""
from __future__ import annotations

import re

SLOT = re.compile(r"\{(you|them|k|w)\}")
SCORE = re.compile(r"\s*\{k\}[–-]\{w\}[.!?]*")
PUNCT = ".!?,"


def parts(template: str) -> list[list]:
    text = SCORE.sub("", template).strip()
    out: list[list] = []
    pos = 0
    for m in SLOT.finditer(text):
        _words(out, text[pos:m.start()])
        slot = m.group(1)
        pos = m.end()
        if slot in ("k", "w"):
            out.append(["num", slot])
            continue
        # a name ends a phrase: say it with the punctuation that follows
        # (a run like "?!" or "..." counts as its first mark)
        p = text[pos] if pos < len(text) and text[pos] in PUNCT else "."
        while pos < len(text) and text[pos] in PUNCT:
            pos += 1
        out.append([slot, p])
    _words(out, text[pos:])
    return out


def _words(out: list, chunk: str) -> None:
    chunk = chunk.strip()
    if not chunk:
        return
    # punctuation before the words (after a number: "{w}... this is fine"):
    # an ellipsis is a beat, the rest a breath
    lead = re.match(r"^[.!?,…\s]+", chunk)
    if lead:
        out.append(["pause", 0.35 if "..." in lead.group(0) or "…" in lead.group(0) else 0.12])
        chunk = chunk[lead.end():]
    if re.search(r"[A-Za-z0-9]", chunk):
        out.append(["t", spoken(chunk)])


def spoken(chunk: str) -> str:
    """Shouted words in plain case (TTS reads ALL CAPS as letters sometimes)."""
    s = re.sub(r"\b[A-Z][A-Z']+\b", lambda m: m.group(0).lower(), chunk)
    return re.sub(r"\bi('m|'ll|'ve|'d)?\b", lambda m: "I" + (m.group(1) or ""), s)


def names_said(templates: dict) -> dict:
    """Which ([slot, punctuation]) name clips the templates need."""
    need = {"you": set(), "them": set()}
    for t in templates.values():
        for p in parts(t):
            if p[0] in need:
                need[p[0]].add(p[1])
    return need


if __name__ == "__main__":
    import json
    import sys
    from pathlib import Path
    data = json.loads((Path(__file__).parent / "lines.json").read_text())
    for k, t in data["templates"].items():
        if len(sys.argv) < 2 or sys.argv[1] in k:
            print(f"{k:28s} {t!r}\n{'':28s} {parts(t)}")
    print(names_said(data["templates"]))
