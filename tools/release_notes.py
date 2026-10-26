#!/usr/bin/env python3
"""Write a release's notes (used by .github/workflows/release.yml).

    python3 tools/release_notes.py VERSION PREVIOUS_TAG > notes.md

The hand-written highlights for a version line come from
docs/release_notes/<line>.md (e.g. 0.6.1.md for v0.6.1 and its builds) when
there is one; then what changed since the last release (its commit titles),
how to download and run it, and the trailers.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "https://github.com/zconnor100-debug/bunny-beat-down"


def main() -> None:
    version = sys.argv[1]
    previous = sys.argv[2] if len(sys.argv) > 2 else ""
    out = []
    line = ".".join(version.split(".")[:3])
    notes = ROOT / "docs" / "release_notes" / f"{line}.md"
    if notes.exists():
        out.append(notes.read_text().strip())
        out.append("")
    span = f"{previous}..HEAD" if previous else "HEAD"
    titles = subprocess.run(["git", "log", "--no-merges", "--pretty=format:%s", span], cwd=ROOT,
                            check=True, capture_output=True, text=True).stdout.strip().splitlines()
    if titles:
        out.append(f"### What's new since {previous}" if previous else "### What's in it")
        out.extend(f"- {t}" for t in titles)
        out.append("")
    out += [
        "### Download and play",
        "- **Windows:** `BunnyBeatDown-windows-x86_64.zip`. Unzip it and run `BunnyBeatDown.exe`: the whole game is in that one "
        "file, so you can put it anywhere. Windows may warn that it's from an unknown publisher (it isn't signed): click "
        "**More info → Run anyway**.",
        "- **Linux:** `BunnyBeatDown-linux-x86_64.tar.xz`. Extract it and run `BunnyBeatDown.x86_64`.",
        "- Already playing? The main menu tells you when there's a newer version, with a button to this page.",
        "",
        f"Every release: {REPO}/releases · the source: {REPO}",
        "",
        "Music in the trailers: \"Run Amok\" by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0.",
    ]
    print("\n".join(out))


if __name__ == "__main__":
    main()
