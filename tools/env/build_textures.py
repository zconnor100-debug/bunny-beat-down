#!/usr/bin/env python3
"""Build terrain texture layers, the water normal map and copy the sky HDRIs.

    python3 -I tools/env/build_textures.py              # everything
    python3 -I tools/env/build_textures.py mud planks   # just these layers

Inputs come from the download cache (polyhaven_fetch.py / ambientcg_fetch.py);
outputs follow docs/ASSET_PIPELINE.md:

    assets/textures/<layer>/albedo.jpg     sRGB colour
    assets/textures/<layer>/normal.png     OpenGL convention (+Y / green up), 8-bit
    assets/textures/<layer>/roughness.jpg  linear greyscale
    assets/textures/<layer>/ao.jpg         linear greyscale (optional extra)
    assets/textures/<layer>/height.jpg     linear greyscale, for height-blended splatting (extra)
    assets/textures/water/normal.png       tileable ripple normal map (generated here)
    assets/sky/<hdri>_2k.hdr (+ _4k.hdr when <= 25 MB)

The water normal map is original work: a sum of periodic ripples whose integer
wave vectors make it tile seamlessly, converted from heights to normals.
"""
from __future__ import annotations

import json
import math
import random
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
CACHE = ROOT / "tools" / "_cache" / "env"
TEX = ROOT / "assets" / "textures"
SKY = ROOT / "assets" / "sky"

# layer -> (cache folder, albedo/normal size, short description used in credits)
LAYERS = {
    "forest_floor": ("ph_forest_leaves_02", 2048, "default forest ground: moss, grass and leaf litter"),
    "grass":        ("acg_Grass004", 2048, "lush grass meadow"),
    "dirt_path":    ("ph_dirt_floor", 2048, "packed-earth paths"),
    "moss":         ("acg_Moss002", 2048, "thick ground moss"),
    "rock":         ("ph_lichen_rock", 2048, "steep slopes and cliffs"),
    "leaf_litter":  ("ph_forest_floor", 1024, "autumn leaf litter under trees"),
    "sand":         ("ph_coast_sand_01", 1024, "island beach"),
    "bark":         ("ph_bark_brown_02", 1024, "generic tree bark for custom meshes/shaders"),
    "mud":          ("ph_brown_mud_leaves_01", 1024, "swamp mud with fallen leaves (terrain)"),
    "planks":       ("ph_planks_brown_10", 1024, "plank walls of the big buildings"),
    "floorboards":  ("ph_old_wood_floor", 1024, "floors, porches and ramps of the big buildings"),
    "thatch":       ("ph_reed_roof_04", 1024, "thatched roof of the woodcutter's lodge"),
    "slate_roof":   ("ph_roof_slates_02", 1024, "slate roof of the big red barn"),
    "tin_roof":     ("ph_rusty_corrugated_iron", 1024, "rusty tin roof of the swamp shacks"),
    "bedding":      ("ph_aerial_wood_snips", 2048, "hamster cage bedding: wood shavings (tinted pale in the shader)"),
    "snow":         ("ph_snow_02", 2048, "snow drifts of the hamster cage's winter corner"),
    "pebbles":      ("ph_clean_pebbles", 1024, "aquarium gravel under the hamster cage's lagoon"),
    "laminate":     ("ph_laminate_floor_02", 1024, "the room's wooden floor outside the hamster tank"),
    "gingham":      ("ph_fabric_pattern_07", 1024, "Toy Box Bash: the red gingham blanket over the pillow fort"),
    "plaid":        ("ph_fabric_pattern_05", 1024, "Toy Box Bash: pillows, and the play rug's weave"),
    "oak_floor":    ("ph_oak_wood_planks", 1024, "Toy Box Bash: the bedroom's oak floorboards"),
}

# Noise-like normal maps gain little from 2K but cost ~10 MB as PNG: cap them lower.
NORMAL_CAP = {"grass": 1024, "bedding": 1024, "snow": 1024}

HDRIS = ["kloofendal_48d_partly_cloudy_puresky", "qwantani_late_afternoon_puresky"]
HDRI_4K: set[str] = set()  # 4K copies dropped to stay inside the repo size budget (2K is used in game)


def source_maps(folder: Path) -> dict[str, Path]:
    """Find albedo/normal/rough/ao/height in a Poly Haven or ambientCG cache folder."""
    if folder.name.startswith("ph_"):
        names = {"albedo": "albedo.jpg", "normal": "normal.png", "roughness": "roughness.jpg",
                 "ao": "ao.jpg", "height": "height.png"}
        return {k: folder / v for k, v in names.items() if (folder / v).exists()}
    suffix = {"albedo": "_Color", "normal": "_NormalGL", "roughness": "_Roughness",
              "ao": "_AmbientOcclusion", "height": "_Displacement"}
    out = {}
    for k, s in suffix.items():
        hits = sorted(folder.glob(f"*{s}.jpg")) + sorted(folder.glob(f"*{s}.png"))
        if hits:
            out[k] = hits[0]
    return out


def build_layers(only: list[str] | None = None) -> list[dict]:
    jobs = []
    for layer, (folder, size, _desc) in LAYERS.items():
        if only and layer not in only:
            continue
        maps = source_maps(CACHE / folder)
        dst = TEX / layer
        dst.mkdir(parents=True, exist_ok=True)
        nsize = NORMAL_CAP.get(layer, size)
        spec = {"albedo": ("albedo.jpg", "rgb", size), "normal": ("normal.png", "rgb", nsize),
                "roughness": ("roughness.jpg", "gray", size), "ao": ("ao.jpg", "gray", 1024),
                "height": ("height.jpg", "gray", 1024)}
        for key, (name, mode, cap) in spec.items():
            if key in maps:
                jobs.append({"src": str(maps[key]), "dst": str(dst / name), "max": cap, "mode": mode,
                             "quality": 90})
    jf = Path("/tmp/bbd-envwork/texture_jobs.json")
    jf.parent.mkdir(parents=True, exist_ok=True)
    jf.write_text(json.dumps(jobs, indent=1))
    subprocess.run(["python3", "-I", str(TOOLS / "texconv.py"), str(jf)], check=True, stdout=subprocess.DEVNULL)
    return jobs


def water_normal(size: int = 1024, waves: int = 40, seed: int = 7) -> Image.Image:
    """Seamless ripple normal map. Heights are a sum of cosines with integer wave
    vectors (so they repeat exactly every texture), amplitude ~ 1/k^1.6."""
    rng = random.Random(seed)
    comps = []
    for _ in range(waves):
        while True:
            kx, ky = rng.randint(-24, 24), rng.randint(-24, 24)
            k = math.hypot(kx, ky)
            if 2.0 <= k <= 24.0:
                break
        comps.append((kx, ky, 1.0 / k ** 1.6, rng.uniform(0, 2 * math.pi)))
    # analytic derivatives -> normal; strength tuned for gentle pond ripples
    strength = 1.9
    tw = 2 * math.pi / size
    # precompute per-wave row/column phase tables to keep this pure-Python job fast
    px = [[kx * tw * x for x in range(size)] for kx, _, _, _ in comps]
    py = [[ky * tw * y for y in range(size)] for _, ky, _, _ in comps]
    out = bytearray(size * size * 3)
    for y in range(size):
        rows = [(kx, ky, a, ph + py[i][y], px[i]) for i, (kx, ky, a, ph) in enumerate(comps)]
        for x in range(size):
            dx = dy = 0.0
            for kx, ky, a, base, pxi in rows:
                s = -a * math.sin(pxi[x] + base)
                dx += s * kx
                dy += s * ky
            nx, ny, nz = -dx * strength / 6.0, -dy * strength / 6.0, 1.0
            inv = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            o = (y * size + x) * 3
            out[o] = int((nx * inv * 0.5 + 0.5) * 255 + 0.5)
            # image rows grow downwards; OpenGL normal maps want +Y (green) = up in UV space
            out[o + 1] = int((-ny * inv * 0.5 + 0.5) * 255 + 0.5)
            out[o + 2] = int((nz * inv * 0.5 + 0.5) * 255 + 0.5)
    return Image.frombytes("RGB", (size, size), bytes(out))


def copy_hdris() -> list[Path]:
    SKY.mkdir(parents=True, exist_ok=True)
    copied = []
    for h in HDRIS:
        src = CACHE / f"ph_{h}"
        for res in ("2k", "4k"):
            f = src / f"{h}_{res}.hdr"
            if not f.exists() or (res == "4k" and (h not in HDRI_4K or f.stat().st_size > 25_000_000)):
                continue
            shutil.copy2(f, SKY / f.name)
            copied.append(SKY / f.name)
    return copied


def main() -> None:
    only = sys.argv[1:]
    unknown = [o for o in only if o not in LAYERS]
    if unknown:
        raise SystemExit(f"unknown layers: {unknown}")
    build_layers(only)
    if only:
        return
    (TEX / "water").mkdir(parents=True, exist_ok=True)
    water_normal().save(TEX / "water" / "normal.png", optimize=True)
    copied = copy_hdris()
    for p in sorted(TEX.rglob("*")) + copied:
        if p.is_file():
            print(f"{p.relative_to(ROOT)}  {p.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
