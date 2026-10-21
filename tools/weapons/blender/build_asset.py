"""Build, bake and export one or more assets (Blender entry point).

    blender --background --factory-startup --python build_asset.py -- carrot_pistol [more ids...]

For each id: fresh scene -> builder from assets/ -> atlas bake -> glb in
assets/weapons|props/ -> report JSON in tools/_cache/weapons/build/<id>.json
(triangles, bounds, marker positions in Godot coordinates, sources used).
"""
from __future__ import annotations

import json
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assets import REGISTRY  # noqa: E402
from bbd import bake, util  # noqa: E402


def build(asset_id: str) -> dict:
    entry = REGISTRY[asset_id]
    util.reset_scene()
    spec = entry["build"]()
    out_dir = util.OUT_WEAPONS if entry["out"] == "weapons" else util.OUT_PROPS
    report = bake.assemble_and_export(asset_id, spec, out_dir / f"{asset_id}.glb", size=entry.get("tex", 1024),
                                      ao_distance=entry.get("ao", 0.08))
    report.update({"kind": entry["kind"], "use": entry["use"], "target_size_m": entry.get("target"),
                   "tri_budget": entry.get("budget")})
    (util.BUILD / f"{asset_id}.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> int:
    ids = util.script_args() or list(REGISTRY)
    unknown = [i for i in ids if i not in REGISTRY]
    if unknown:
        print("unknown asset ids:", unknown, "known:", sorted(REGISTRY))
        return 2
    util.BUILD.mkdir(parents=True, exist_ok=True)
    failed = []
    for i in ids:
        t0 = time.time()
        try:
            r = build(i)
            print(f"BUILT {i}: {r['tris_total']} tris, size {r['size_m']} m, {r['bytes'] / 1024:.0f} KiB, "
                  f"{time.time() - t0:.1f}s")
        except Exception:
            traceback.print_exc()
            failed.append(i)
    if failed:
        print("FAILED:", failed)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
