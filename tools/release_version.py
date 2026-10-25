#!/usr/bin/env python3
"""Decide whether a push gets a release, and its version (used by
.github/workflows/release.yml).

The game's version line lives in project.godot (application/config/version,
e.g. 0.6.1). The first release on a line is v0.6.1; every later release on
the same line adds a build number (v0.6.1.1, v0.6.1.2, ...), so the version
only ever goes up and the game's update check (src/ui/update_check.gd) can
compare numbers. Bump project.godot for a new feature release (0.7.0).

A release is only made when something players get has changed since the last
release: the game's code, assets, data, scenes or settings (not tests, tools,
docs or CI).

    python3 tools/release_version.py            # prints release=, version=, previous= (GITHUB_OUTPUT lines)
    python3 tools/release_version.py --stamp V  # writes V into project.godot (the build's own version)
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAME = ["src", "assets", "data", "scenes", "project.godot", "export_presets.cfg", "icon.svg", "icon.png", "docs/release_notes"]
KEY = re.compile(r'^config/version="([^"]*)"', re.M)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def parts(v: str) -> tuple:
    return tuple(int(x) for x in v.split("."))


def main() -> int:
    project = ROOT / "project.godot"
    if len(sys.argv) > 2 and sys.argv[1] == "--stamp":
        text = project.read_text()
        project.write_text(KEY.sub(f'config/version="{sys.argv[2]}"', text, count=1))
        return 0
    base = KEY.search(project.read_text()).group(1)
    tags = [t[1:] for t in git("tag", "-l", "v*").split() if re.fullmatch(r"v\d+(\.\d+)*", t)]
    tags.sort(key=parts)
    previous = f"v{tags[-1]}" if tags else ""
    if previous:
        # (the version line itself changing counts: that's a new feature release)
        changed = git("diff", "--name-only", previous, "HEAD", "--", *GAME)
        if not changed:
            print("release=no")
            print(f"previous={previous}")
            return 0
    if base not in tags:
        version = base
    else:
        builds = [parts(t)[len(parts(base))] for t in tags
                  if len(parts(t)) == len(parts(base)) + 1 and parts(t)[: len(parts(base))] == parts(base)]
        version = f"{base}.{max(builds, default=0) + 1}"
    if tags and parts(version) <= parts(tags[-1]):
        print(f"::error::version {version} isn't above the last release {previous}: bump project.godot", file=sys.stderr)
        return 1
    print("release=yes")
    print(f"version={version}")
    print(f"previous={previous}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
