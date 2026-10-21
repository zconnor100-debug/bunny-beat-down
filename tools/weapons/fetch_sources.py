#!/usr/bin/env python3
"""Download the third-party inputs listed in sources.json.

Everything lands in tools/_cache/weapons/ (git-ignored):

    _cache/weapons/polyhaven/<id>/<id>_<map>_<res>.jpg   Poly Haven CC0 textures
    _cache/weapons/hdri/<id>_<res>.hdr                   Poly Haven CC0 HDRI (preview lighting)
    _cache/weapons/sketchfab/<key>/model.glb             Sketchfab CC0 / CC BY scans
    _cache/weapons/sources_meta.json                     title/author/licence/url per source

The metadata file is what build_all.py turns into assets/credits/weapons_props.json,
so credits always describe exactly what was downloaded.

Sketchfab needs an API token in ~/.config/sketchfab/token (never printed or
written anywhere). The licence of every Sketchfab model is re-checked at download
time and anything that is not CC0 / CC BY is refused.

Usage:  python3 tools/weapons/fetch_sources.py [--force]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = ROOT / "tools" / "_cache" / "weapons"
SOURCES = HERE / "sources.json"
TOKEN_FILE = Path.home() / ".config" / "sketchfab" / "token"

PH_API = "https://api.polyhaven.com"
SF_API = "https://api.sketchfab.com/v3"
ALLOWED_SF_LICENSES = {
    "CC0 Public Domain": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "CC Attribution": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
}
UA = {"User-Agent": "bunny-beat-down-asset-tools/1.0"}


def _get_json(url: str, headers: dict | None = None) -> dict:
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def _download(url: str, dest: Path, headers: dict | None = None) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            tmp.replace(dest)
            return
        except OSError as e:  # network hiccup: retry a couple of times
            print(f"   retry {attempt + 1}: {e}")
            time.sleep(2)
    raise RuntimeError(f"download failed: {url}")


def _ph_authors(asset_id: str) -> tuple[str, str, str, dict]:
    info = _get_json(f"{PH_API}/info/{asset_id}")
    names = list(info.get("authors", {}).keys())
    author = ", ".join(names)
    # Poly Haven has per-author listing pages; link the first (primary) author.
    author_url = "https://polyhaven.com/all?a=" + urllib.parse.quote(names[0]) if names else "https://polyhaven.com"
    return info.get("name", asset_id), author, author_url, info


def fetch_polyhaven_texture(asset_id: str, spec: dict, force: bool) -> dict:
    res = spec.get("res", "2k")
    files = _get_json(f"{PH_API}/files/{asset_id}")
    out = {}
    for m in spec["maps"]:
        # "Diffuse=col_1" picks a colour variant but files it under the usual key
        key, _, src = m.partition("=")
        src = src or key
        if src not in files:
            raise RuntimeError(f"{asset_id}: map {src} not on Poly Haven")
        entry = files[src][res]["jpg"]
        dest = CACHE / "polyhaven" / asset_id / f"{asset_id}_{src}_{res}.jpg"
        if force or not dest.exists():
            print(f"   {asset_id} {src} {res}")
            _download(entry["url"], dest)
        out[key] = str(dest.relative_to(CACHE))
    title, author, author_url, info = _ph_authors(asset_id)
    return {
        "kind": "polyhaven_texture",
        "title": title,
        "author": author,
        "author_url": author_url,
        "source_url": f"https://polyhaven.com/a/{asset_id}",
        "license": "CC0 1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "real_size_mm": info.get("dimensions"),
        "files": out,
        "used_for": spec["used_for"],
    }


def fetch_polyhaven_hdri(asset_id: str, spec: dict, force: bool) -> dict:
    res = spec.get("res", "1k")
    files = _get_json(f"{PH_API}/files/{asset_id}")
    entry = files["hdri"][res]["hdr"]
    dest = CACHE / "hdri" / f"{asset_id}_{res}.hdr"
    if force or not dest.exists():
        print(f"   hdri {asset_id} {res}")
        _download(entry["url"], dest)
    title, author, author_url, _ = _ph_authors(asset_id)
    return {
        "kind": "polyhaven_hdri",
        "title": title,
        "author": author,
        "author_url": author_url,
        "source_url": f"https://polyhaven.com/a/{asset_id}",
        "license": "CC0 1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "files": {"hdr": str(dest.relative_to(CACHE))},
        "used_for": spec["used_for"],
    }


def fetch_ambientcg(asset_id: str, spec: dict, force: bool) -> dict:
    """ambientCG (CC0): download the zip into its own folder and extract the maps safely."""
    import zipfile
    res = spec.get("res", "1K-PNG")
    folder = CACHE / "ambientcg" / asset_id
    zpath = folder / f"{asset_id}_{res}.zip"
    if force or not zpath.exists():
        print(f"   ambientcg {asset_id} {res}")
        _download(f"https://ambientcg.com/get?file={asset_id}_{res}.zip", zpath)
    files = {}
    with zipfile.ZipFile(zpath) as z:
        for name in z.namelist():
            base = Path(name).name                    # flatten; never trust archive paths
            if not base or base.startswith(".") or not base.lower().endswith((".png", ".jpg")):
                continue
            dest = folder / "maps" / base
            if force or not dest.exists():
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(z.read(name))
            for key in ("Color", "Opacity", "NormalGL", "Roughness"):
                if f"_{key}." in base:
                    files[key] = str(dest.relative_to(CACHE))
    info = _get_json(f"https://ambientcg.com/api/v2/full_json?id={asset_id}")["foundAssets"][0]
    return {
        "kind": "ambientcg_material",
        "title": info.get("displayName", asset_id),
        "author": "ambientCG (Lennart Demes)",
        "author_url": "https://ambientcg.com",
        "source_url": f"https://ambientcg.com/view?id={asset_id}",
        "license": "CC0 1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "files": files,
        "used_for": spec["used_for"],
    }


def fetch_sketchfab(key: str, spec: dict, token: str, force: bool) -> dict:
    uid = spec["uid"]
    auth = {"Authorization": "Token " + token}
    info = _get_json(f"{SF_API}/models/{uid}", auth)
    label = (info.get("license") or {}).get("label")
    if label not in ALLOWED_SF_LICENSES:
        raise RuntimeError(f"{key}: licence {label!r} is not allowed")
    lic, lic_url = ALLOWED_SF_LICENSES[label]
    # each download gets its own directory: downloaded files are untrusted data
    dest = CACHE / "sketchfab" / key / "model.glb"
    if force or not dest.exists():
        print(f"   sketchfab {key} ({uid})")
        dl = _get_json(f"{SF_API}/models/{uid}/download", auth)
        # the temporary storage URL must be fetched WITHOUT the auth header
        _download(dl["glb"]["url"], dest)
    user = info["user"]
    return {
        "kind": "sketchfab_model",
        "title": info["name"],
        "author": user.get("displayName") or user["username"],
        "author_url": user.get("profileUrl") or f"https://sketchfab.com/{user['username']}",
        "source_url": info.get("viewerUrl") or f"https://sketchfab.com/3d-models/{uid}",
        "license": lic,
        "license_url": lic_url,
        "files": {"glb": str(dest.relative_to(CACHE))},
        "used_for": spec["used_for"],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="re-download even if cached")
    args = ap.parse_args()

    spec = json.loads(SOURCES.read_text())
    CACHE.mkdir(parents=True, exist_ok=True)
    meta: dict[str, dict] = {}

    print("Poly Haven textures:")
    for aid, s in spec["polyhaven_textures"].items():
        meta[aid] = fetch_polyhaven_texture(aid, s, args.force)
    print("Poly Haven HDRIs:")
    for aid, s in spec["polyhaven_hdris"].items():
        meta[aid] = fetch_polyhaven_hdri(aid, s, args.force)
    print("ambientCG materials:")
    for aid, s in spec.get("ambientcg_materials", {}).items():
        meta[aid] = fetch_ambientcg(aid, s, args.force)
    print("Sketchfab models:")
    token = TOKEN_FILE.read_text().strip() if TOKEN_FILE.exists() else ""
    for key, s in spec["sketchfab_models"].items():
        if not token and not (CACHE / "sketchfab" / key / "model.glb").exists():
            print(f"   !! no Sketchfab token, cannot fetch {key}", file=sys.stderr)
            return 1
        meta[key] = fetch_sketchfab(key, s, token, args.force)

    (CACHE / "sources_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"wrote {CACHE / 'sources_meta.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
