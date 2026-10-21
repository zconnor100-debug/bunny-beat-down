#!/usr/bin/env python3
"""Minimal Sketchfab Data API v3 client used by the environment asset tools.

Only CC0 and CC-BY (3.0/4.0) models are ever returned or downloaded -- every
other license is filtered out here so the rest of the pipeline cannot pick one
up by accident.

The API token is read from ~/.config/sketchfab/token (or $SKETCHFAB_TOKEN) and
is only ever sent to api.sketchfab.com.  It is never printed or written to disk.
The temporary download URLs returned by /download are fetched WITHOUT the
Authorization header (they are pre-signed CDN links).

CLI:
    sketchfab_api.py search "hollow log" [--max-faces 50000] [--count 24]
    sketchfab_api.py info <uid>
    sketchfab_api.py download <uid> <dest_dir>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.sketchfab.com/v3"
UA = "BunnyBeatDown-asset-tools/1.0 (+portfolio game)"

# license label (as reported by the API) -> (credits label, license url)
ALLOWED_LICENSES = {
    "CC Attribution": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
    "CC0 Public Domain": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
}


def _token() -> str:
    tok = os.environ.get("SKETCHFAB_TOKEN")
    if not tok:
        path = Path.home() / ".config" / "sketchfab" / "token"
        tok = path.read_text().strip()
    return tok


def _get_json(url: str, auth: bool = True) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    if auth:
        req.add_header("Authorization", "Token " + _token())
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:  # rate limit -> back off
            if e.code == 429 and attempt < 3:
                time.sleep(5 * (attempt + 1))
                continue
            raise
    raise RuntimeError("unreachable")


def license_ok(model: dict) -> bool:
    lic = (model.get("license") or {}).get("label", "")
    return lic in ALLOWED_LICENSES


def search(query: str, count: int = 24, max_faces: int | None = None) -> list[dict]:
    params = {"type": "models", "downloadable": "true", "q": query, "count": str(count)}
    if max_faces:
        params["max_face_count"] = str(max_faces)
    url = API + "/search?" + urllib.parse.urlencode(params)
    data = _get_json(url)
    return [m for m in data.get("results", []) if license_ok(m)]


def info(uid: str) -> dict:
    return _get_json(f"{API}/models/{uid}")


def download(uid: str, dest: Path) -> Path:
    """Download the glb (preferred) or gltf zip of a model into dest/.

    Also writes dest/meta.json with the license/author fields needed for credits.
    Returns the path of the model file.
    """
    meta = info(uid)
    if not license_ok(meta):
        raise SystemExit(f"{uid}: license {meta.get('license')} not allowed")
    dest.mkdir(parents=True, exist_ok=True)
    lic_label, lic_url = ALLOWED_LICENSES[meta["license"]["label"]]
    keep = {
        "uid": uid,
        "name": meta.get("name"),
        "author": meta["user"].get("displayName") or meta["user"].get("username"),
        "author_username": meta["user"].get("username"),
        "author_url": meta["user"].get("profileUrl"),
        "source_url": meta.get("viewerUrl"),
        "license": lic_label,
        "license_url": lic_url,
        "license_label_api": meta["license"]["label"],
        "face_count": meta.get("faceCount"),
        "vertex_count": meta.get("vertexCount"),
        "description": (meta.get("description") or "")[:2000],
        "tags": [t.get("name") for t in meta.get("tags", [])],
    }
    (dest / "meta.json").write_text(json.dumps(keep, indent=2))

    links = _get_json(f"{API}/models/{uid}/download")
    if "glb" in links:
        out = dest / f"{uid}.glb"
        _fetch(links["glb"]["url"], out)
        return out
    out = dest / f"{uid}_gltf.zip"
    _fetch(links["gltf"]["url"], out)
    with zipfile.ZipFile(out) as z:
        for name in z.namelist():  # refuse path traversal in untrusted zips
            if name.startswith("/") or ".." in Path(name).parts:
                raise SystemExit(f"suspicious path in zip: {name}")
        z.extractall(dest / "gltf")
    return dest / "gltf"


def _fetch(url: str, out: Path) -> None:
    # Pre-signed CDN URL: no Authorization header.
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(out, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)


def thumb_sheet(models: list[dict], out: Path, cols: int = 6, cell: int = 256) -> None:
    """Fetch search-result thumbnails into one labelled contact sheet (needs Pillow).

    Used while *choosing* assets: a human (or agent) looks at the sheet instead
    of trusting titles.  Thumbnails are public CDN images -> no auth header.
    """
    from io import BytesIO
    from PIL import Image, ImageDraw

    if not models:
        return
    rows = (len(models) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 28)), (30, 30, 30))
    draw = ImageDraw.Draw(sheet)
    for n, m in enumerate(models):
        imgs = sorted((m.get("thumbnails") or {}).get("images", []), key=lambda i: abs(i.get("width", 0) - cell))
        x, y = (n % cols) * cell, (n // cols) * (cell + 28)
        if imgs:
            try:
                req = urllib.request.Request(imgs[0]["url"], headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=30) as r:
                    im = Image.open(BytesIO(r.read())).convert("RGB")
                im.thumbnail((cell, cell))
                sheet.paste(im, (x, y))
            except Exception as e:  # thumbnails are best-effort
                draw.text((x + 4, y + 4), f"thumb error {e}"[:40], fill=(255, 80, 80))
        draw.text((x + 3, y + cell + 2), f"{n}: {m['name'][:34]}", fill=(255, 255, 255))
        draw.text((x + 3, y + cell + 14), f"{m.get('faceCount', 0)}f {m['user']['username'][:22]}", fill=(180, 180, 180))
    sheet.save(out)


def _main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("query")
    s.add_argument("--count", type=int, default=24)
    s.add_argument("--max-faces", type=int, default=None)
    s.add_argument("--sheet", type=Path, default=None, help="also write a thumbnail contact sheet here")
    i = sub.add_parser("info")
    i.add_argument("uid")
    t = sub.add_parser("thumbs", help="contact sheet of specific models (larger cells)")
    t.add_argument("sheet", type=Path)
    t.add_argument("uids", nargs="+")
    d = sub.add_parser("download")
    d.add_argument("uid")
    d.add_argument("dest", type=Path)
    a = ap.parse_args()

    if a.cmd == "search":
        results = search(a.query, a.count, a.max_faces)
        for n, m in enumerate(results):
            print(f"{n:2d} {m['uid']}  faces={m.get('faceCount', 0):>8}  lic={m['license']['label']:<18} "
                  f"by={m['user']['username'][:20]:<20} {m['name'][:60]}")
        if a.sheet:
            thumb_sheet(results, a.sheet)
    elif a.cmd == "info":
        m = info(a.uid)
        print(json.dumps({k: m.get(k) for k in ("name", "faceCount", "vertexCount", "viewerUrl", "license",
                                                  "isDownloadable", "description")}, indent=1)[:3000])
        print("author:", m["user"].get("username"), m["user"].get("profileUrl"))
    elif a.cmd == "thumbs":
        models = [info(u) for u in a.uids]
        for m in models:
            print(m["uid"], m.get("faceCount"), m["license"]["label"] if m.get("license") else None, m["name"])
        thumb_sheet(models, a.sheet, cols=3, cell=512)
    elif a.cmd == "download":
        print(download(a.uid, a.dest))


if __name__ == "__main__":
    _main()
