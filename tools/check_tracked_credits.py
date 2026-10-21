#!/usr/bin/env python3
"""List credited asset files that git does not track (so CI would not see them).

    python3 tools/check_tracked_credits.py      # exit 1 if any are missing
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
tracked = set(subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split("\n"))
missing = []
for f in sorted((ROOT / "assets" / "credits").glob("*.json")):
    for entry in json.loads(f.read_text()):
        for path in entry.get("files", []):
            if path.endswith("/"):
                if not any(t.startswith(path) for t in tracked):
                    missing.append(path)
            elif path not in tracked and (ROOT / path).exists():
                missing.append(path)
for m in missing:
    print("untracked:", m)
sys.exit(1 if missing else 0)
