#!/usr/bin/env python3
"""Download Poly Haven (CC0) assets into the git-ignored tools/_cache/env/ folder.

Usage:
    polyhaven_fetch.py model   <id> [<id> ...]    # glTF @2k + alpha map (if any)
    polyhaven_fetch.py model --res 8k <id> ...    # other texture resolution (hero scans)
    polyhaven_fetch.py texture <id> [<id> ...]    # diffuse / nor_gl / rough / ao @2k
    polyhaven_fetch.py hdri    <id> [<id> ...]    # .hdr @2k (and 4k if <= 25 MB)

Every asset lands in tools/_cache/env/ph_<id>/ together with info.json (the
/info/<id> API record: name, authors, ...), which build_credits.py reads.
Downloads are verified against the md5 the API publishes and skipped if the
file is already present and valid, so the script is safe to re-run.
"""
from __future__ import annotations

import hashlib
import json
import sys
import urllib.request
from pathlib import Path

API = "https://api.polyhaven.com"
UA = "BunnyBeatDown-asset-tools/1.0 (+portfolio game)"
CACHE = Path(__file__).resolve().parents[1] / "_cache" / "env"
RES = "2k"


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(entry: dict, out: Path) -> Path:
    """Download one file record {url, md5, size} to out (skip if already valid)."""
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and out.stat().st_size == entry.get("size") and md5(out) == entry.get("md5"):
        return out
    req = urllib.request.Request(entry["url"], headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(out, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    if entry.get("md5") and md5(out) != entry["md5"]:
        raise SystemExit(f"md5 mismatch for {out}")
    print("  got", out.relative_to(CACHE), f"{out.stat().st_size / 1e6:.1f} MB")
    return out


def _safe_rel(name: str) -> Path:
    p = Path(name)
    if p.is_absolute() or ".." in p.parts:
        raise SystemExit(f"refusing suspicious include path {name!r}")
    return p


def asset_dir(asset_id: str) -> Path:
    d = CACHE / f"ph_{asset_id}"
    d.mkdir(parents=True, exist_ok=True)
    info = get_json(f"{API}/info/{asset_id}")
    (d / "info.json").write_text(json.dumps(info, indent=1))
    return d


def fetch_model(asset_id: str, res: str = RES) -> None:
    d = asset_dir(asset_id)
    files = get_json(f"{API}/files/{asset_id}")
    g = files["gltf"][res]["gltf"]
    fetch(g, d / Path(g["url"]).name)
    for rel, entry in g.get("include", {}).items():
        fetch(entry, d / _safe_rel(rel))
    # glTF from Poly Haven ships a JPEG diffuse; foliage cut-outs need the
    # separate alpha mask, which process_model.py merges into an RGBA PNG.
    alpha = files.get("Alpha", {}).get(res, {}).get("png") or files.get("Alpha", {}).get(res, {}).get("jpg")
    if alpha:
        fetch(alpha, d / "textures" / Path(alpha["url"]).name)


TEX_MAPS = {  # Poly Haven map name -> (preferred format, our filename)
    "Diffuse": ("jpg", "albedo"),
    "nor_gl": ("png", "normal"),
    "Rough": ("jpg", "roughness"),
    "AO": ("jpg", "ao"),
    "Displacement": ("png", "height"),
}


def fetch_texture(asset_id: str, res: str = RES) -> None:
    d = asset_dir(asset_id)
    files = get_json(f"{API}/files/{asset_id}")
    if "Diffuse" not in files:
        # some textures (the fabrics) come in colourways col_1, col_2, ...: take the first
        cols = sorted((k for k in files if k.lower().startswith("col")), key=lambda k: int("".join(c for c in k if c.isdigit()) or 0))
        if cols:
            files["Diffuse"] = files[cols[0]]
    for key, (fmt, ours) in TEX_MAPS.items():
        if key not in files:
            continue
        by_fmt = files[key][res]
        entry = by_fmt.get(fmt) or by_fmt.get("jpg") or by_fmt.get("png")
        ext = Path(entry["url"]).suffix
        fetch(entry, d / f"{ours}{ext}")


def fetch_hdri(asset_id: str, res: str = RES) -> None:
    d = asset_dir(asset_id)
    files = get_json(f"{API}/files/{asset_id}")
    fetch(files["hdri"]["2k"]["hdr"], d / f"{asset_id}_2k.hdr")
    four = files["hdri"].get("4k", {}).get("hdr")
    if four and four["size"] <= 25_000_000:
        fetch(four, d / f"{asset_id}_4k.hdr")
    # small tonemapped preview for eyeballing
    thumb = f"https://cdn.polyhaven.com/asset_img/primary/{asset_id}.png?height=256"
    fetch({"url": thumb}, d / "preview.png")


def thumb_sheet(ids: list[str], out: Path, cols: int = 6, cell: int = 256) -> None:
    """Labelled contact sheet of Poly Haven thumbnails, for choosing assets by eye."""
    from io import BytesIO
    from PIL import Image, ImageDraw

    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)
    for n, asset_id in enumerate(ids):
        x, y = (n % cols) * cell, (n // cols) * (cell + 16)
        url = f"https://cdn.polyhaven.com/asset_img/thumbs/{asset_id}.png?width={cell}&height={cell}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                im = Image.open(BytesIO(r.read())).convert("RGB")
            im.thumbnail((cell, cell))
            sheet.paste(im, (x, y))
        except Exception as e:
            draw.text((x + 4, y + 4), str(e)[:40], fill=(255, 80, 80))
        draw.text((x + 3, y + cell + 2), f"{n}: {asset_id}"[:40], fill=(255, 255, 255))
    sheet.save(out)


def main(argv: list[str]) -> None:
    if len(argv) >= 3 and argv[0] == "thumbs":  # thumbs <out.png> <id> [<id> ...]
        thumb_sheet(argv[2:], Path(argv[1]))
        return
    if len(argv) < 2 or argv[0] not in ("model", "texture", "hdri"):
        raise SystemExit(__doc__)
    fn = {"model": fetch_model, "texture": fetch_texture, "hdri": fetch_hdri}[argv[0]]
    args, res = argv[1:], RES
    if "--res" in args:
        i = args.index("--res")
        res = args[i + 1]
        args = args[:i] + args[i + 2:]
    for asset_id in args:
        print(f"[{argv[0]}] {asset_id} @{res}")
        fn(asset_id, res)


if __name__ == "__main__":
    main(sys.argv[1:])
