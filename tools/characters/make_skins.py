# Bunny Beat Down — recoloured skin variants for a normalized character.
#
#   blender --background --python tools/characters/make_skins.py -- <id> [--only skin,skin] [--debug DIR]
#
# Reads the recipe for <id> from tools/characters/skins_recipe.json and the
# character's GLB, and writes
#   assets/characters/<id>/skins/<skin>_<texture label>.jpg   (recoloured albedo)
#   assets/characters/<id>/skins.json                         (what the game reads)
# skins.json lists the default skin plus every variant as
#   {"id", "name", "albedo": {<Godot material resource_name>: "skins/<file>.jpg"}};
# materials a skin does not recolour are not listed (keep the GLB's texture).
#
# How a recolour works
#   * Every albedo texel knows its triangle (skin_maps.py), so a recipe REGION
#     can select texels by material, by dominant bone (regex), by 3D rest
#     position (glTF space: x = left, y = up, z = forward), by colour in
#     OKLCh (perceptual lightness / chroma / hue) and by 3D procedural
#     patterns (noise patches, ellipsoid blobs). Selectors are soft (0..1
#     ramps) and regions are claimed in order (first match wins, softly).
#   * A SKIN may also "paint" on top: [{"where": selector, "set": colour}]
#     in order (a T-shirt by bones, a print as a "polygon" pattern on the
#     front), each recoloured the same way.
#   * A SKIN maps regions to new colours ("set" keys are region names or
#     globs such as "fur*"; the last matching key wins, so a pattern
#     sub-region can follow its parent unless a skin overrides it; regions
#     driven by the same key share their colour statistics). For each
#     region the mean OKLab
#     colour is moved to the target (lightness L / chroma C / hue h, absolute
#     or relative) while every texel keeps its deviation from that mean:
#     lightness deviations scaled by the available headroom (painted shading
#     survives without blown highlights), colour deviations rotated with the
#     hue and scaled with the chroma. Fur strands, folds and painted
#     shadows therefore survive the recolour.
#   * Texture bleed padding around UV islands, and the rest of the
#     background between them, is refilled from the nearest recoloured texel
#     so mip-mapping does not show old colours (or a white background) at
#     seams. A recipe skin "default" with nothing to "set" writes the GLB's
#     own texture padded so (a model whose islands sit on white).
#   * Vertex colours (the bandit's material multiplies them) are left alone:
#     they act as baked shading on top of whatever albedo the skin provides.
import fnmatch
import json
import math
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import skin_maps as sm  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
CID = argv[0]
ONLY = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
DEBUG = argv[argv.index("--debug") + 1] if "--debug" in argv else None
with open(os.path.join(HERE, "skins_recipe.json")) as f:
    RECIPE = json.load(f)[CID]
CHAR_DIR = os.path.join(ROOT, "assets", "characters", CID)
OUT_DIR = os.path.join(CHAR_DIR, "skins")
os.makedirs(OUT_DIR, exist_ok=True)


def log(*a):
    print("SKINS", CID, *a)


# ----------------------------------------------------------------------------- selectors
def ramp(x, lo, hi, soft):
    """1 inside [lo, hi], linear fall-off over `soft` outside."""
    soft = max(soft, 1e-6)
    return np.clip(np.minimum((x - lo) / soft + 1.0, (hi - x) / soft + 1.0), 0.0, 1.0)


def hue_ramp(h, lo, hi, soft):
    """Hue interval on the colour wheel (lo > hi wraps through 0)."""
    width = (hi - lo) % 360.0
    d = (h - lo) % 360.0                     # 0..360 from the interval start
    inside = d <= width
    dist = np.where(inside, 0.0, np.minimum(d - width, 360.0 - d))
    return np.clip(1.0 - dist / max(soft, 1e-6), 0.0, 1.0)


def blur(m, r):
    """Separable box blur, radius r texels (r <= 0: no-op)."""
    r = int(round(r))
    if r <= 0:
        return m
    k = 2 * r + 1
    for ax in (0, 1):
        c = np.cumsum(np.pad(m, [(r + 1, r) if a == ax else (0, 0) for a in (0, 1)], mode="edge"), axis=ax)
        m = (np.take(c, np.arange(k, k + m.shape[ax]), axis=ax) - np.take(c, np.arange(0, m.shape[ax]), axis=ax)) / k
    return m


def value_noise(p, scale, seed, octaves=3):
    """Smooth 3D value noise (fBm) in 0..1 at points p (..., 3), feature size `scale` m."""
    out = np.zeros(p.shape[:-1])
    amp, tot, freq = 1.0, 0.0, 1.0 / scale
    for o in range(octaves):
        q = p * freq + seed * 17.13 + o * 31.7
        i = np.floor(q).astype(np.int64)
        f = q - i
        f = f * f * (3 - 2 * f)

        def h(dx, dy, dz):
            n = (i[..., 0] + dx) * 73856093 ^ (i[..., 1] + dy) * 19349663 ^ (i[..., 2] + dz) * 83492791 ^ (seed * 2654435761)
            n = (n ^ (n >> 13)) * 1274126177
            return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

        v = 0.0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                    v = v + w * h(dx, dy, dz)
        out += amp * v
        tot += amp
        amp *= 0.5
        freq *= 2.0
    return out / tot


def select(where, ctx):
    """Soft membership (H, W) of one selector dict."""
    m = np.ones(ctx["shape"])
    if "material" in where:
        ok = np.isin(ctx["prim_mat"], [i for i, n in enumerate(ctx["mat_names"]) if n in where["material"]])
        m = m * ok
    if "bones" in where:
        pat = re.compile("|".join(where["bones"]), re.I)
        ids = [i for i, n in enumerate(ctx["joints"]) if pat.search(n)]
        m = m * np.isin(ctx["bone"], ids)
    if "not_bones" in where:
        pat = re.compile("|".join(where["not_bones"]), re.I)
        ids = [i for i, n in enumerate(ctx["joints"]) if pat.search(n)]
        m = m * ~np.isin(ctx["bone"], ids)
    if "pos" in where:
        ps = where["pos"]
        s = ps.get("soft", 0.01)
        P = ctx["pos"]
        axes = {"x": P[..., 0], "y": P[..., 1], "z": P[..., 2], "ax": np.abs(P[..., 0])}
        for k, v in ps.items():
            if k in axes:
                m = m * ramp(axes[k], v[0], v[1], s)
    if "color" in where:
        cs = where["color"]
        soft = cs.get("soft", {})
        col = np.ones(ctx["shape"])
        if "L" in cs:
            col = col * ramp(ctx["L"], cs["L"][0], cs["L"][1], soft.get("L", 0.04))
        if "C" in cs:
            col = col * ramp(ctx["C"], cs["C"][0], cs["C"][1], soft.get("C", 0.015))
        if "h" in cs:
            col = col * hue_ramp(ctx["h"], cs["h"][0], cs["h"][1], soft.get("h", 12.0))
        m = m * blur(col, cs.get("blur", 1))
    for pt in where.get("patterns", []):
        m = m * pattern(pt, ctx)
    if where.get("invert"):
        m = 1.0 - m
    return m


def pattern(pt, ctx):
    P = ctx["pos"]
    if pt["type"] == "noise":
        v = value_noise(P, pt["scale"], pt.get("seed", 1), pt.get("octaves", 3))
        r = ramp(v, pt["threshold"], 2.0, pt.get("soft", 0.05))
    elif pt["type"] == "blob":
        c = np.array(pt["center"])
        rad = np.array(pt["radius"])
        if pt.get("mirror"):                          # the same blob on both sides (eyes, cheeks)
            P = P.copy()
            P[..., 0] = np.abs(P[..., 0]) * (1.0 if c[0] >= 0 else -1.0)
        d = np.sqrt((((P - c) / rad) ** 2).sum(axis=-1))
        r = np.clip((1.0 + pt.get("soft", 0.25) - d) / pt.get("soft", 0.25), 0.0, 1.0)
    elif pt["type"] == "polygon":
        # a flat shape on the front (a chest print): texels whose (x, y) is in
        # the polygon and that face forward (z above "min")
        pts = np.array(pt["points"], float)
        x, y = P[..., 0], P[..., 1]
        inside = np.zeros(x.shape, bool)
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            cross = ((yi > y) != (yj > y)) & (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi)
            inside ^= cross
            j = i
        r = (inside & (P[..., 2] > pt.get("min", -1e9))).astype(float)
    elif pt["type"] == "stripes":
        # bands along an axis (rings on a tail): period / duty in metres
        ax = {"x": 0, "y": 1, "z": 2}[pt["axis"]]
        ph = (P[..., ax] - pt.get("offset", 0.0)) / pt["period"] % 1.0
        r = ramp(ph, 0.0, pt["duty"], pt.get("soft", 0.08))
    else:
        raise ValueError("unknown pattern " + pt["type"])
    return 1.0 - r if pt.get("invert") else r


# ----------------------------------------------------------------------------- recolour
def lightness_curve(L, mean, target, contrast):
    """Move the region's mean lightness to `target`, scaling every texel's
    deviation by the headroom ratio (darkening a light region shrinks its
    painted shading proportionally instead of blowing out its highlights),
    never below 0.45 so shading stays readable; `contrast` multiplies on top."""
    mean = min(max(mean, 1e-3), 1 - 1e-3)
    k = max(min(target / mean, (1 - target) / (1 - mean)), 0.45) * contrast
    return np.clip(target + (L - mean) * k, 0.0, 1.0)


def recolour(lab, w, spec):
    """New OKLab for the texels of one region (w = soft mask used for stats)."""
    sw = w.sum()
    if sw < 1e-6:
        return lab
    mean = (lab * w[..., None]).sum(axis=(0, 1)) / sw
    Lm, am, bm = mean
    Cm = math.hypot(am, bm)
    hm = math.degrees(math.atan2(bm, am)) % 360.0
    Lt = spec.get("L", Lm + spec.get("dL", 0.0))
    Ct = spec.get("C", Cm * spec.get("Cs", 1.0))
    ht = spec.get("h", hm + spec.get("dh", 0.0))
    L = lightness_curve(lab[..., 0], Lm, Lt, spec.get("contrast", 1.0))
    da, db = lab[..., 1] - am, lab[..., 2] - bm
    rot = math.radians(ht - hm)
    k = spec.get("dev", min(max(Ct / max(Cm, 0.03), 0.15), 2.0))
    ra = (da * math.cos(rot) - db * math.sin(rot)) * k
    rb = (da * math.sin(rot) + db * math.cos(rot)) * k
    at, bt = Ct * math.cos(math.radians(ht)), Ct * math.sin(math.radians(ht))
    return np.stack([L, at + ra, bt + rb], axis=-1)


# ----------------------------------------------------------------------------- main
data = sm.load(os.path.join(CHAR_DIR, CID + ".glb"))
mat_names = [p["material"] for p in data["prims"]]
tex_label = RECIPE["textures"]                       # material -> output label
groups = {}
for p in data["prims"]:
    groups.setdefault(p["image"], []).append(p)

skins = [s for s in RECIPE["skins"] if ONLY is None or s["id"] in ONLY]
for s_ in skins:                                     # stale outputs of the skins being rebuilt
    for f in os.listdir(OUT_DIR):
        if f.startswith(s_["id"] + "_") and f.endswith(".jpg"):
            os.remove(os.path.join(OUT_DIR, f))
outputs = {s["id"]: {} for s in skins}
for img_i, prims in groups.items():
    mats = [p["material"] for p in prims]
    label = next((tex_label[m] for m in mats if m in tex_label), None)
    if label is None:
        continue                                      # texture never recoloured (eyes, teeth...)
    tex = data["images"][img_i]
    H, Wd = tex.shape[:2]
    rast = sm.rasterize(prims, (H, Wd))
    at = sm.texel_attributes(prims, rast, data["joints"])
    rgb = tex[..., :3].astype(np.float64)
    lab = sm.srgb_to_oklab(rgb)
    L, C, h = sm.lch(lab)
    ctx = {"shape": (H, Wd), "pos": at["pos"], "bone": at["bone"], "joints": data["joints"],
           "prim_mat": at["prim"], "mat_names": mats, "L": L, "C": C, "h": h}
    covered = rast["covered"]
    remaining = covered.astype(np.float64)
    masks = {}
    for reg in RECIPE["regions"]:
        if reg.get("texture", label) != label:
            continue
        sel = select(reg.get("where", {}), ctx)
        m = sel * remaining
        remaining = remaining - m
        masks[reg["name"]] = m
        log("region %-12s texels %7.0f" % (reg["name"], m.sum()))
    if DEBUG:
        os.makedirs(DEBUG, exist_ok=True)
        pal = np.array([[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [1, 0, 1], [0, 1, 1], [1, .5, 0],
                        [.5, 0, 1], [0, .5, 0], [.6, .6, .6], [.5, .25, 0], [1, .6, .8]], float)
        dbg = np.zeros((H, Wd, 3))
        for k, (n, m) in enumerate(masks.items()):
            dbg += m[..., None] * pal[k % len(pal)]
            log("debug colour", n, pal[k % len(pal)].tolist())
        sm.encode_jpeg(np.concatenate([rgb, dbg], axis=1), os.path.join(DEBUG, "%s_%s_regions.jpg" % (CID, label)))
    for skin in skins:
        new = lab.copy()
        # skin keys may be globs ("fur*"); the last matching key wins. Regions
        # recoloured by the same key share one set of colour statistics, so
        # e.g. head and body fur land on the same tone without a seam.
        matched = {}
        for rname in masks:
            key = None
            for k in skin["set"]:
                if fnmatch.fnmatchcase(rname, k):
                    key = k
            if key is not None:
                matched[rname] = key
        paints = [pa for pa in skin.get("paint", []) if pa.get("texture", label) == label]
        if not matched and not paints and skin["id"] != "default":
            continue                                  # skin leaves this texture alone
        for key in dict.fromkeys(matched.values()):
            group = [r for r, k in matched.items() if k == key]
            w_all = sum(masks[r] for r in group)
            tgt = recolour(lab, np.where(covered, w_all, 0.0), skin["set"][key])
            new = new + (tgt - new) * w_all[..., None]
        # paint on top (a T-shirt, chaps, a print): any selector, in order
        for pa in paints:
            m = np.where(covered, select(pa.get("where", {}), ctx), 0.0)
            if m.sum() > 0:
                tgt = recolour(lab, m, pa["set"])
                new = new + (tgt - new) * m[..., None]
        out = sm.oklab_to_srgb(new)
        # refill the bleed padding and the background from the nearest recoloured texel
        out = sm.fill_background(out, covered)
        name = "%s_%s.jpg" % (skin["id"], label)
        sm.encode_jpeg(out, os.path.join(OUT_DIR, name), quality=RECIPE.get("quality", 90))
        for m in mats:
            outputs[skin["id"]][m] = "skins/" + name
        log("wrote", name)

# skins.json: default first, then every variant (merged with existing entries when --only)
path = os.path.join(CHAR_DIR, "skins.json")
existing = {}
if ONLY and os.path.exists(path):
    with open(path) as f:
        existing = {e["id"]: e for e in json.load(f)}
entries = [{"id": "default", "name": RECIPE.get("default_name", "Classic")}]
for s in RECIPE["skins"]:
    if s["id"] == "default":
        # a recipe "default" skin touches up the GLB's own texture (still listed first)
        if s["id"] in outputs:
            entries[0]["albedo"] = outputs[s["id"]]
        elif s["id"] in existing and "albedo" in existing[s["id"]]:
            entries[0]["albedo"] = existing[s["id"]]["albedo"]
        continue
    if s["id"] in outputs:
        entries.append({"id": s["id"], "name": s["name"], "albedo": outputs[s["id"]]})
    elif s["id"] in existing:
        entries.append(existing[s["id"]])
# textures every skin uses whatever its fur (recipe "extra_albedo": e.g. the
# squirrel's eyeballs, redrawn with whites)
for e in entries:
    for mat, tex in RECIPE.get("extra_albedo", {}).items():
        e.setdefault("albedo", {})[mat] = tex
with open(path, "w") as f:
    json.dump(entries, f, indent=2)
    f.write("\n")
log("wrote", path, [e["id"] for e in entries])
