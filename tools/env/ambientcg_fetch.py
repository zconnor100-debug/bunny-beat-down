#!/usr/bin/env python3
"""Download ambientCG (CC0) materials into tools/_cache/env/acg_<id>/.

    ambientcg_fetch.py Grass004 Moss002

Fetches the 2K-JPG zip, extracts it (refusing path traversal) and stores the
API record as info.json for build_credits.py.  ambientCG is used only where
Poly Haven has no suitable CC0 surface (lush grass and ground moss).
"""
from __future__ import annotations

import io
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

UA = "BunnyBeatDown-asset-tools/1.0 (+portfolio game)"
CACHE = Path(__file__).resolve().parents[1] / "_cache" / "env"
API = "https://ambientcg.com/api/v2/full_json"


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def fetch(asset_id: str, attribute: str = "2K-JPG") -> None:
    d = CACHE / f"acg_{asset_id}"
    d.mkdir(parents=True, exist_ok=True)
    q = urllib.parse.urlencode({"id": asset_id, "include": "downloadData,displayData"})
    info = json.loads(get(f"{API}?{q}"))["foundAssets"][0]
    (d / "info.json").write_text(json.dumps(info, indent=1))
    downloads = info["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"]
    link = next(x["fullDownloadPath"] for x in downloads if x["attribute"] == attribute)
    with zipfile.ZipFile(io.BytesIO(get(link))) as z:
        for name in z.namelist():
            p = Path(name)
            if p.is_absolute() or ".." in p.parts:
                raise SystemExit(f"suspicious path in zip: {name}")
        z.extractall(d)
    print(asset_id, sorted(p.name for p in d.iterdir()))


if __name__ == "__main__":
    for a in sys.argv[1:]:
        fetch(a)
