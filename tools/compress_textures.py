#!/usr/bin/env python3
"""Make every 3D model texture GPU-compressed (VRAM, with mipmaps) before an
export. Run it, then `godot --headless --import`, then export.

Godot extracts the textures embedded in the .glb models (trees, rocks, props,
critters, guns) on import. When that import runs from the command line (no
editor to notice they're used in 3D), they're stored *lossless*: several times
the download size and the video memory of the S3TC/BPTC formats the GPU reads
directly, for no visible gain at this game's scale. This sets them to VRAM
compression (normal maps as normal maps), caps scenery and props (trees, rocks,
logs, crates; not critters or guns, which you see up close) at 1024 px, and
leaves 2D images (icons, preview sheets, the HDR skies) alone. The terrain and
building textures' own .import files (committed) cap their normal and roughness
maps the same way. Idempotent: re-running changes nothing.

    python3 tools/compress_textures.py [--check]

--check only reports (exit 1 if any 3D texture is still lossless).
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# textures that belong to 3D models (the extracted ones, and the guns' own)
MODEL_TEXTURES = ["assets/env/*/*", "assets/props/*_*_*", "assets/characters/*/*_*", "assets/weapons/*"]
CAPPED = ("assets/env/", "assets/props/")      # scenery: 1024 px is plenty
SIZE_CAP = 1024
SKIP = re.compile(r"preview|closeup|icon|portrait|thumb", re.I)


def wanted(rel: str, name: str) -> dict:
    out = {"compress/mode": "2", "mipmaps/generate": "true"}
    if "normal" in name.lower():
        out["compress/normal_map"] = "1"
    if rel.startswith(CAPPED):
        out["process/size_limit"] = str(SIZE_CAP)
    return out


def main() -> int:
    check = "--check" in sys.argv
    changed = []
    for pattern in MODEL_TEXTURES:
        for imp in sorted(ROOT.glob(pattern + ".import")):
            name = imp.name[: -len(".import")]
            if not re.search(r"\.(png|jpe?g|webp)$", name, re.I) or SKIP.search(name):
                continue
            text = imp.read_text()
            if 'importer="texture"' not in text:
                continue
            new = text
            for key, value in wanted(str(imp.relative_to(ROOT)), name).items():
                new = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", new, flags=re.M)
            if new != text:
                changed.append(imp.relative_to(ROOT))
                if not check:
                    imp.write_text(new)
    verb = "not yet compressed (or capped) as they should be" if check else "updated"
    print(f"{len(changed)} model textures {verb}")
    for p in changed[:10]:
        print("  ", p)
    return 1 if check and changed else 0


if __name__ == "__main__":
    sys.exit(main())
