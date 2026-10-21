#!/usr/bin/env python3
"""Rebuild every weapon, projectile and prop from code - the one entry point.

    python3 tools/weapons/build_all.py                 # everything
    python3 tools/weapons/build_all.py --only carrot_lmg loot_crate
    python3 tools/weapons/build_all.py --skip-fetch --no-preview --godot

Steps
  1. fetch_sources.py          Poly Haven CC0 textures/HDRI + Sketchfab scans -> tools/_cache/weapons/
  2. blender/prep_scans.py     unwrap the carrot & acorn scans into texture strips (cached)
  3. blender/build_asset.py    model -> bake 1 PBR atlas -> assets/{weapons,props}/<id>.glb
  4. blender/render_preview.py + compose_sheet.py -> preview_sheet.png (+ helmet close-up)
  5. assets/props/manifest.json and assets/credits/weapons_props.json from the build reports
  6. (--godot) godot_check.py  import check in a throwaway project under /tmp/bbd-propcheck
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = ROOT / "tools" / "_cache" / "weapons"
BUILD = CACHE / "build"
BLENDER_DIR = HERE / "blender"
WEAPON_SHEET = ["carrot_pistol", "carrot_shotgun", "carrot_lmg", "carrot_rocket_launcher", "carrot_bolt",
                "carrot_shell_pellet", "carrot_rocket"]
PROP_SHEET = ["acorn_helmet", "pickup_health", "pickup_armor", "ammo_light", "ammo_shells", "ammo_heavy",
              "ammo_rocket", "loot_crate", "supply_drop", "dandelion_glider", "dropship_balloon"]
ORIGINS = {
    "weapon": ("main (trigger) grip", "barrel along -Z, +Y up"),
    "projectile": ("centre of the projectile", "tip / flight direction -Z"),
    "pickup": ("bottom centre (rests on the ground)", "front faces +Z"),
    "prop": ("bottom centre (rests on the ground)", "front faces +Z"),
    "vehicle": ("centre of the basket floor", "flies toward -Z"),
}
ORIGIN_OVERRIDES = {
    "acorn_helmet": ("helmet attach point: put it at bun model space (0, 0.875, -0.010), upright, scale 1",
                     "opening faces -Y, front faces +Z (bowl authored tipped back 15 deg on the skull)"),
    "dandelion_glider": ("hand grip on the seed handle", "pappus overhead along +Y"),
}
BUN = ROOT / "assets" / "characters" / "bun" / "bun.glb"
PROJECT = {"author": "Bunny Beat Down project", "author_url": "", "license": "MIT (project)", "license_url": ""}


def blender(script: str, *args: str, blender_bin: str) -> None:
    cmd = [blender_bin, "--background", "--factory-startup", "--python", str(BLENDER_DIR / script), "--", *args]
    t0 = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    for line in out.splitlines():
        if (line.startswith(("BUILT", "FAILED", "Traceback", "carrot_skin", "acorn_strip")) or "Error" in line) \
                and "HIPEW" not in line:
            print("   " + line)
    if res.returncode != 0:
        print(out[-4000:])
        raise SystemExit(f"{script} failed ({res.returncode})")
    print(f"   {script} done in {time.time() - t0:.0f}s")


def registry() -> dict:
    """Per-asset build reports (written by blender/build_asset.py) keyed by id."""
    out = {}
    for rp in sorted(BUILD.glob("*.json")):
        r = json.loads(rp.read_text())
        if "kind" in r:
            out[r["id"]] = r
    return out


def rel(p) -> str:
    return str(Path(p).resolve().relative_to(ROOT))


def write_manifest(reports: dict) -> Path:
    entries = []
    for i in WEAPON_SHEET + PROP_SHEET:
        r = reports.get(i)
        if not r:
            continue
        origin, facing = ORIGIN_OVERRIDES.get(i, ORIGINS[r["kind"]])
        entries.append({
            "id": i,
            "file": rel(r["file"]),
            "kind": r["kind"],
            "use": r["use"],
            "size_m": r["size_m"],
            "max_extent_m": max(r["size_m"]),
            "aabb_min": r["aabb_min"],
            "aabb_max": r["aabb_max"],
            "origin": origin,
            "orientation": facing,
            "tris": r["tris_total"],
            "texture_px": r["texture_px"],
            "markers": r["markers"],
            "nodes": {k: v for k, v in r["nodes"].items() if k != i},
            "notes": r.get("notes", ""),
        })
        fit = BUILD / "previews" / "acorn_helmet_fit.json"
        if i == "acorn_helmet" and fit.exists():
            entries[-1]["fit_check_on_bun"] = json.loads(fit.read_text())
    out = ROOT / "assets" / "props" / "manifest.json"
    out.write_text(json.dumps(entries, indent=2) + "\n")
    return out


CHANGES = {
    "polyhaven_texture": "Sampled (box/UV projected, rescaled, tinted) inside procedural Blender materials that add "
                         "edge wear, cavity dirt and paint chipping, then baked by tools/weapons into each asset's "
                         "own 512-2048 px PBR atlas. The original image files are not shipped.",
    "polyhaven_hdri": "Used only to light the preview renders (preview_sheet.png / acorn_helmet_closeup.png); not "
                      "included in any glb.",
    "sketchfab_model": "Re-skinned by tools/weapons/blender/prep_scans.py: the scan is unwrapped onto a fitted "
                       "surface of revolution (Cycles selected-to-active bake) into a cylindrical colour + normal "
                       "strip (colour calibrated, normals high-passed, holes filled); the strip is mapped onto "
                       "procedurally modelled geometry and baked into each asset's atlas. The scan mesh itself is "
                       "not shipped.",
}
KIND_LABEL = {"polyhaven_texture": "texture", "polyhaven_hdri": "HDRI", "sketchfab_model": "photoscan"}


def write_credits(reports: dict) -> Path:
    meta = json.loads((CACHE / "sources_meta.json").read_text())
    entries = []
    for key, m in meta.items():
        if m["kind"] == "polyhaven_hdri":
            files = ["assets/weapons/preview_sheet.png", "assets/props/preview_sheet.png",
                     "assets/props/acorn_helmet_closeup.png"]
        else:
            files = sorted(rel(r["file"]) for r in reports.values() if key in r.get("sources", []))
        if not files:
            continue
        entries.append({
            "asset": f"{m['title']} ({KIND_LABEL[m['kind']]})",
            "author": m["author"],
            "author_url": m["author_url"],
            "source_url": m["source_url"],
            "license": m["license"],
            "license_url": m["license_url"],
            "changes": CHANGES[m["kind"]],
            "used_for": m["used_for"],
            "files": files,
        })
    for i in WEAPON_SHEET + PROP_SHEET:
        r = reports.get(i)
        if not r:
            continue
        module = {"weapon": "weapons.py", "projectile": "projectiles.py", "vehicle": "balloon.py"}.get(r["kind"],
                                                                                                         "props.py")
        if i == "acorn_helmet":
            module = "helmet.py"
        entries.append({
            "asset": i.replace("_", " ").title(),
            **PROJECT,
            "source_url": f"tools/weapons/blender/assets/{module}",
            "changes": "Original model generated from code (Blender Python): procedural geometry, scripted "
                       "materials and a baked PBR atlas. Third-party textures/scans it samples are credited "
                       "separately.",
            "used_for": r["use"],
            "files": [rel(r["file"])],
        })
    out = ROOT / "assets" / "credits" / "weapons_props.json"
    out.write_text(json.dumps(entries, indent=2) + "\n")
    return out


def previews(ids: list[str], blender_bin: str, samples: int) -> None:
    sys.path.insert(0, str(HERE))
    import compose_sheet
    tiles = BUILD / "previews"
    glbs = [str(ROOT / "assets" / ("weapons" if i in WEAPON_SHEET else "props") / f"{i}.glb") for i in ids]
    blender("render_preview.py", "--out", str(tiles), "--tile", "400", "--samples", str(samples), *glbs,
            blender_bin=blender_bin)
    if "acorn_helmet" in ids:
        blender("render_preview.py", "--out", str(tiles), "--tile", "320", "--samples", str(samples * 2), "--hero",
                str(ROOT / "assets" / "props" / "acorn_helmet.glb"), blender_bin=blender_bin)
        shots = [tiles / f"acorn_helmet_hero{k}.png" for k in (0, 3)]
        title = "acorn_helmet close-up"
        if BUN.exists():   # worn by the real hero, attached exactly like the game does
            blender("fit_helmet.py", "--out", str(tiles), "--samples", str(samples), blender_bin=blender_bin)
            shots += [tiles / f"acorn_helmet_on_bun_{v}.png" for v in ("front", "side", "front34", "back34")]
            title += "  |  rows 2-3: worn by bun (attach point (0, 0.875, -0.010))"
        compose_sheet.closeup(title, shots, ROOT / "assets" / "props" / "acorn_helmet_closeup.png")
    present = lambda lst: [i for i in lst if (ROOT / "assets" / ("weapons" if i in WEAPON_SHEET else "props")
                                              / f"{i}.glb").exists()]
    compose_sheet.sheet("Bunny Beat Down - carrot weapons", present(WEAPON_SHEET), tiles, BUILD,
                        ROOT / "assets" / "weapons" / "preview_sheet.png", cols=4, tile=260)
    compose_sheet.sheet("Bunny Beat Down - props & pickups", present(PROP_SHEET), tiles, BUILD,
                        ROOT / "assets" / "props" / "preview_sheet.png", cols=4, tile=260)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*", help="asset ids to rebuild (default: all)")
    ap.add_argument("--skip-fetch", action="store_true")
    ap.add_argument("--rescan", action="store_true", help="redo the photoscan unwrap even if cached")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--samples", type=int, default=64, help="preview render samples")
    ap.add_argument("--godot", action="store_true", help="run the throwaway-project Godot import check")
    ap.add_argument("--blender", default="/snap/bin/blender")
    args = ap.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    ids = args.only or (WEAPON_SHEET + PROP_SHEET)
    print("1/6 sources")
    if not args.skip_fetch or not (CACHE / "sources_meta.json").exists():
        subprocess.run([sys.executable, str(HERE / "fetch_sources.py")], check=True)
    print("2/6 photoscan strips")
    if args.rescan or not (CACHE / "derived" / "acorn_strip.json").exists():
        blender("prep_scans.py", blender_bin=args.blender)
    print(f"3/6 build {len(ids)} assets")
    blender("build_asset.py", *ids, blender_bin=args.blender)
    if not args.no_preview:
        print("4/6 previews")
        previews(ids, args.blender, args.samples)
    print("5/6 manifest + credits")
    reports = registry()
    print("   " + rel(write_manifest(reports)))
    print("   " + rel(write_credits(reports)))
    if args.godot:
        print("6/6 Godot import check (/tmp/bbd-propcheck)")
        return subprocess.run([sys.executable, str(HERE / "godot_check.py")]).returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
