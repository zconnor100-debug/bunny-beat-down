#!/usr/bin/env python3
"""Summarise GLB files without Blender: size, meshes, triangles, materials, images.

    python3 -I tools/env/glb_info.py assets/env/*/*.glb

Reads the binary glTF container directly (JSON chunk + BIN chunk), so it is a
quick independent check of what the exporter actually wrote: alpha modes,
double-sidedness, image MIME types and pixel sizes, and per-image byte counts.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError(f"{path}: not a GLB")
    off, js, binary = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(chunk)
        elif ctype == b"BIN\x00":
            binary = chunk
        off += 8 + clen
    return js, binary


def image_size(blob: bytes) -> tuple[int, int]:
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", blob[16:24])
    if blob[:2] == b"\xff\xd8":  # walk JPEG markers to the SOF segment
        i = 2
        while i < len(blob):
            if blob[i] != 0xFF:
                i += 1
                continue
            marker = blob[i + 1]
            seg = struct.unpack(">H", blob[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", blob[i + 5:i + 9])
                return w, h
            i += 2 + seg
    return 0, 0


def summarise(path: Path) -> dict:
    js, binary = read_glb(path)
    tris = 0
    for mesh in js.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                tris += js["accessors"][prim["indices"]]["count"] // 3
            else:
                tris += js["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
    imgs = []
    for im in js.get("images", []):
        bv = js["bufferViews"][im["bufferView"]]
        blob = binary[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        w, h = image_size(blob)
        imgs.append(f"{im.get('mimeType', '?').split('/')[-1]} {w}x{h} {bv['byteLength'] / 1e6:.2f}MB")
    mats = []
    for m in js.get("materials", []):
        mats.append(f"{m.get('name')}:{m.get('alphaMode', 'OPAQUE')}{'/2s' if m.get('doubleSided') else ''}")
    pos = [js["accessors"][p["attributes"]["POSITION"]] for mesh in js.get("meshes", []) for p in mesh["primitives"]]
    lo = [min(a["min"][i] for a in pos) for i in range(3)]
    hi = [max(a["max"][i] for a in pos) for i in range(3)]
    return {"file": str(path), "mb": round(path.stat().st_size / 1e6, 2), "tris": tris,
            "aabb_min": [round(v, 2) for v in lo], "aabb_max": [round(v, 2) for v in hi],
            "materials": mats, "images": imgs, "nodes": len(js.get("nodes", []))}


if __name__ == "__main__":
    for p in sys.argv[1:]:
        s = summarise(Path(p))
        print(f"{Path(p).stem:24s} {s['mb']:6.2f}MB tris={s['tris']:6d} min={s['aabb_min']} max={s['aabb_max']}")
        print("    mats:", ", ".join(s["materials"]))
        print("    imgs:", "; ".join(s["images"]))
