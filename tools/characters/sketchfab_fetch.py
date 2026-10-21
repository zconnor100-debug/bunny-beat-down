#!/usr/bin/env python3
"""Sketchfab helper for the Bunny Beat Down character roster.

Usage (run from the repo root):
    python3 tools/characters/sketchfab_fetch.py search "<query>" [count]
        Downloadable + rigged models, CC-BY and CC0 only (other licenses are
        never listed). Prints uid, title, author, license, faces, anims.
    python3 tools/characters/sketchfab_fetch.py info <uid>
        Title, author, profile URL, model URL, license, face/anim counts.
    python3 tools/characters/sketchfab_fetch.py fetch <uid> <id>
        Downloads the model (GLB preferred, else the glTF zip) into
        tools/_cache/characters/<id>/ together with meta.json (the API model
        record subset used for credits). Re-running skips existing downloads.

The API token is read from ~/.config/sketchfab/token. It is only ever sent to
api.sketchfab.com and is never printed or written anywhere. The temporary
download URL returned by the API is fetched WITHOUT the auth header.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

API = "https://api.sketchfab.com/v3"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "tools", "_cache", "characters")
ALLOWED = {"by": "CC BY 4.0", "cc0": "CC0 1.0"}   # API license slug -> credits label


def _token():
    with open(os.path.expanduser("~/.config/sketchfab/token")) as f:
        return f.read().strip()


def _get_json(url, auth=False):
    headers = {"User-Agent": "bunny-beat-down-tools/1.0"}
    if auth:
        headers["Authorization"] = "Token " + _token()
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def model_meta(uid):
    """The fields we need for vetting + credits."""
    m = _get_json(API + "/models/" + uid)
    lic = m.get("license") or {}
    return {
        "uid": uid,
        "name": m.get("name"),
        "author": m["user"].get("username"),
        "author_display": m["user"].get("displayName"),
        "author_url": m["user"].get("profileUrl"),
        "viewer_url": m.get("viewerUrl"),
        "license_label": lic.get("label"),
        "license_slug": lic.get("slug"),
        "license_url": lic.get("url"),
        "face_count": m.get("faceCount"),
        "vertex_count": m.get("vertexCount"),
        "animation_count": m.get("animationCount"),
        "is_downloadable": m.get("isDownloadable"),
        "tags": [t["name"] for t in m.get("tags", [])],
        "description": (m.get("description") or "")[:600],
    }


def search(query, count=24):
    seen = set()
    for slug in ALLOWED:
        params = {"type": "models", "q": query, "downloadable": "true", "rigged": "true",
                  "license": slug, "count": count, "sort_by": "-likeCount"}
        try:
            data = _get_json(API + "/search?" + urllib.parse.urlencode(params))
        except Exception as e:  # network hiccup: report and keep going
            print("search error (%s): %s" % (slug, e))
            continue
        for m in data.get("results", []):
            if m["uid"] in seen:
                continue
            seen.add(m["uid"])
            print("%s | %-50s | %-20s | %-16s | faces %7s | anims %s | likes %s" % (
                m["uid"], m["name"][:50], m["user"]["username"][:20],
                (m.get("license") or {}).get("label", "?")[:16],
                m.get("faceCount"), m.get("animationCount"), m.get("likeCount")))


def fetch(uid, cid):
    out_dir = os.path.join(CACHE, cid)
    os.makedirs(out_dir, exist_ok=True)
    meta = model_meta(uid)
    with open(os.path.join(out_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    if meta["license_slug"] not in ALLOWED:
        sys.exit("REFUSED %s: license %r is not CC-BY/CC0" % (uid, meta["license_label"]))
    for existing in ("source.glb", "source.zip"):
        if os.path.exists(os.path.join(out_dir, existing)):
            print("cached", os.path.join(out_dir, existing))
            return
    d = _get_json(API + "/models/" + uid + "/download", auth=True)
    if d.get("glb"):
        url, name = d["glb"]["url"], "source.glb"
    elif d.get("gltf"):
        url, name = d["gltf"]["url"], "source.zip"
    else:
        sys.exit("no GLB/glTF download offered for " + uid)
    dst = os.path.join(out_dir, name)
    req = urllib.request.Request(url, headers={"User-Agent": "bunny-beat-down-tools/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dst + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(dst + ".part", dst)
    print("saved", dst, os.path.getsize(dst), "bytes")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "search":
        search(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 24)
    elif cmd == "info":
        print(json.dumps(model_meta(sys.argv[2]), indent=1, ensure_ascii=False))
    elif cmd == "fetch":
        fetch(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
