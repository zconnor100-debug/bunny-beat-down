#!/usr/bin/env python3
"""Write assets/credits/characters.json from the roster + cached Sketchfab metadata.

    python3 tools/characters/write_credits.py

For every character in tools/characters/roster.json that has been normalized
(assets/characters/<id>/<id>.glb exists) this takes the real title, author,
profile URL, model URL and license from tools/_cache/characters/<id>/meta.json
(written by sketchfab_fetch.py from the Sketchfab API) and the "used_for" /
"changes" text from the roster. Only CC-BY and CC0 sources are accepted; any
other license aborts. A final entry credits the tool scripts and generated
preview images as project work. Output follows docs/ASSET_PIPELINE.md.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LICENSES = {
    "by": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
    "cc0": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
}


def main():
    with open(os.path.join(HERE, "roster.json")) as f:
        roster = {k: v for k, v in json.load(f).items() if not k.startswith("_")}
    out = []
    for cid, cfg in roster.items():
        rel = "assets/characters/%s/" % cid
        if not os.path.exists(os.path.join(ROOT, rel, cid + ".glb")):
            continue
        with open(os.path.join(ROOT, "tools", "_cache", "characters", cid, "meta.json")) as f:
            meta = json.load(f)
        if meta["uid"] != cfg["uid"]:
            sys.exit("%s: cached download %s does not match roster uid %s" % (cid, meta["uid"], cfg["uid"]))
        if meta["license_slug"] not in LICENSES:
            sys.exit("%s: license %r is not allowed" % (cid, meta["license_label"]))
        label, url = LICENSES[meta["license_slug"]]
        out.append({
            "asset": meta["name"],
            "author": meta["author"],
            "author_url": meta["author_url"],
            "source_url": meta["viewer_url"],
            "license": label,
            "license_url": url,
            "changes": cfg["changes"],
            "used_for": cfg["used_for"],
            "files": [rel + cid + ".glb", rel + cid + ".rig.json", rel + "preview.png"],
        })
        if cfg.get("note"):
            out[-1]["note"] = cfg["note"]
    out.append({
        "asset": "Character pipeline tools (Sketchfab fetch, bind-pose rebuild, normalization, previews, lineup)",
        "author": "Bunny Beat Down project",
        "author_url": "",
        "source_url": "",
        "license": "MIT (project)",
        "license_url": "",
        "changes": "Original project work. preview.png and lineup.png are renders of the credited models above.",
        "used_for": "Asset pipeline (characters)",
        "files": ["tools/characters/", "assets/characters/lineup.png"],
    })
    dst = os.path.join(ROOT, "assets", "credits", "characters.json")
    with open(dst, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("wrote", dst, len(out), "entries")


if __name__ == "__main__":
    main()
