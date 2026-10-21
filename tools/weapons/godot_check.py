#!/usr/bin/env python3
"""Import every weapons/props glb in a THROWAWAY Godot project and verify it.

Never touches the real project: copies the glbs to /tmp/bbd-propcheck/glb/,
runs `godot4 --headless --import` there, then godot/check_glbs.gd, and checks
the required marker nodes and sizes. Writes /tmp/bbd-propcheck/report.json.

    python3 tools/weapons/godot_check.py [--godot ~/bin/godot4]
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PROJ = Path("/tmp/bbd-propcheck")
REQUIRED = {
    "weapon": ["Muzzle", "SupportGrip", "Sight"],
    "loot_crate": ["Lid"], "supply_drop": ["Lid", "Chute"], "carrot_rocket_launcher": ["Rocket"],
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=str(Path.home() / "bin" / "godot4"))
    args = ap.parse_args()
    if PROJ.exists():
        shutil.rmtree(PROJ)
    (PROJ / "glb").mkdir(parents=True)
    (PROJ / "project.godot").write_text('config_version=5\n\n[application]\n\nconfig/name="bbd-propcheck"\n')
    shutil.copy(HERE / "godot" / "check_glbs.gd", PROJ / "check_glbs.gd")
    glbs = sorted((ROOT / "assets" / "weapons").glob("*.glb")) + sorted((ROOT / "assets" / "props").glob("*.glb"))
    for g in glbs:
        shutil.copy(g, PROJ / "glb" / g.name)
    imp = subprocess.run([args.godot, "--headless", "--path", str(PROJ), "--import"], capture_output=True, text=True,
                         timeout=900)
    errs = [l for l in (imp.stdout + imp.stderr).splitlines() if "ERROR" in l or "error" in l.lower()]
    run = subprocess.run([args.godot, "--headless", "--path", str(PROJ), "-s", "res://check_glbs.gd"],
                         capture_output=True, text=True, timeout=900)
    rows = [json.loads(l.split(" ", 1)[1]) for l in run.stdout.splitlines() if l.startswith("GLBCHECK ")]
    weapons = {"carrot_pistol", "carrot_shotgun", "carrot_lmg", "carrot_rocket_launcher"}
    problems = []
    for r in rows:
        name = r["file"][:-4]
        need = list(REQUIRED.get(name, []))
        if name in weapons:
            need += REQUIRED["weapon"]
        missing = [n for n in need if n not in r.get("markers", {})]
        if "error" in r or missing:
            problems.append(f"{name}: {r.get('error', '')} missing={missing}")
        size = r.get("aabb_size", [0, 0, 0])
        print(f"{name:26s} tris {r.get('tris', 0):6d}  size {size[0]:.3f} x {size[1]:.3f} x {size[2]:.3f} m  "
              f"markers {json.dumps(r.get('markers', {}))}")
    (PROJ / "report.json").write_text(json.dumps({"rows": rows, "import_errors": errs, "problems": problems},
                                                 indent=2))
    if errs:
        print("import messages:\n  " + "\n  ".join(errs[:20]))
    if len(rows) != len(glbs):
        problems.append(f"only {len(rows)}/{len(glbs)} glbs reported")
    print("PROBLEMS:" if problems else "OK: all glbs imported, markers present", *problems, sep="\n  ")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
