#!/usr/bin/env python3
"""Write assets/credits/characters.json from the roster + cached Sketchfab metadata.

    python3 tools/characters/write_credits.py

For every character in tools/characters/roster.json that has been normalized
(assets/characters/<id>/<id>.glb exists) this takes the real title, author,
profile URL, model URL and license from tools/_cache/characters/<id>/meta.json
(written by sketchfab_fetch.py from the Sketchfab API) and the "used_for" /
"changes" text from the roster; recoloured skin variants listed in
assets/characters/<id>/skins.json are added to that model's entry (they are
derivatives of the same CC-BY work). Only CC-BY and CC0 sources are accepted; any
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
        changes = cfg["changes"]
        files = [rel + cid + ".glb", rel + cid + ".rig.json", rel + "preview.png"]
        skins_path = os.path.join(ROOT, rel, "skins.json")
        if os.path.exists(skins_path):
            with open(skins_path) as f:
                skins = [e for e in json.load(f) if e.get("albedo")]
            if skins:
                changes += (" Recoloured skin variants (%s): the base-colour texture recoloured per region "
                            "(fur, markings, clothing) in the OKLab colour space, keeping the original "
                            "painted shading and detail; some with painted-on clothes (a T-shirt with a "
                            "lightning bolt, chaps) or redrawn eyes." % ", ".join(e["name"] for e in skins))
                files.append(rel + "skins.json")
                files += sorted({rel + p for e in skins for p in e["albedo"].values()})
        out.append({
            "asset": meta["name"],
            "author": meta["author"],
            "author_url": meta["author_url"],
            "source_url": meta["viewer_url"],
            "license": label,
            "license_url": url,
            "changes": changes,
            "used_for": cfg["used_for"],
            "files": files,
        })
        if cfg.get("note"):
            out[-1]["note"] = cfg["note"]
    out.append({
        "asset": "Character pipeline tools (Sketchfab fetch, bind-pose rebuild, normalization, skin recolouring, previews, lineups)",
        "author": "Bunny Beat Down project",
        "author_url": "",
        "source_url": "",
        "license": "MIT (project)",
        "license_url": "",
        "changes": "Original project work. preview.png, lineup.png and skins_lineup.png are renders of the credited models above.",
        "used_for": "Asset pipeline (characters)",
        "files": ["tools/characters/", "assets/characters/lineup.png", "assets/characters/skins_lineup.png"],
    })
    dst = os.path.join(ROOT, "assets", "credits", "characters.json")
    with open(dst, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("wrote", dst, len(out), "entries")


if __name__ == "__main__":
    main()
