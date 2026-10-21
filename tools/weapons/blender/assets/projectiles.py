"""Projectiles: carrot bolt, carrot shell pellet, carrot rocket.

They are spawned a lot, so they are low poly and use 512 px atlases.
Origin = centre of the projectile, flying along +Y in Blender (-Z in Godot).
"""
from __future__ import annotations

import math

from mathutils import Vector

from bbd import geo, mats, parts


def carrot_rocket_parts(scale=1.0, fin_spread=0.30, in_tube=False):
    """Rocket carrot centred on the origin, tip toward +Y. Returns (objects, length)."""
    L, R = 0.45 * scale, 0.046 * scale
    objs = []
    body = parts.carrot_part("rocket_body", L * 0.93, R, pos=(0, L / 2, 0), axis=(0, 1, 0), seed=41, segs=18,
                             rings=13, power=1.6, bumps=0.045, tip_round=0.05)
    objs.append(body)
    crown_y = L / 2 - L * 0.93
    leaf = mats.leaf()
    stem = mats.leaf("carrot_stem", color="#6a9a3a", vein="#8fbf5a")
    n_fins = 4
    for k in range(n_fins):
        a = 2 * math.pi * k / n_fins + math.pi / 4
        radial = Vector((math.cos(a), 0, math.sin(a)))
        tang = Vector((-math.sin(a), 0, math.cos(a)))
        spread = fin_spread * (0.45 if in_tube else 1.0)
        d = (Vector((0, -1, 0)) + radial * spread).normalized()
        base = Vector((0, crown_y + 0.03 * scale, 0)) + radial * (R * 0.35)
        fin = geo.pinnate_leaf(f"fin{k}", base, d, tang, 0.105 * scale, pairs=4, lobes=2,
                               leaf_width=0.32 if in_tube else 0.42, mat=leaf, stem_mat=stem,
                               stem_r=0.0026 * scale, curl=0.05, leaflet_scale=0.30 if in_tube else 0.40)
        objs.append(fin)
    # stubby stalks where the fins sprout + twine binding round the crown
    objs.append(parts.twine_sleeve("rocket_twine", (0, crown_y + 0.045 * scale, 0), (0, 1, 0), R * 0.93,
                                   0.022 * scale, rings=3))
    objs += parts.knot("rocket_knot", (0, crown_y + 0.045 * scale, -(R * 0.93 + 0.003)), 0.006 * scale, seed=3,
                       tails=False)
    return objs, L


def build_carrot_rocket():
    objs, L = carrot_rocket_parts(1.0)
    crown_y = L / 2 - L * 0.93
    return {"objects": objs, "markers": {"Trail": (0, crown_y - 0.01, 0)},
            "report": {"notes": "Origin at the rocket centre, tip toward -Z. `Trail` marks the rear for the "
                                "exhaust/leaf-trail particles."}}


def build_carrot_bolt():
    L, R = 0.14, 0.0115
    objs = [parts.carrot_part("bolt_body", L * 0.95, R, pos=(0, L / 2, 0), axis=(0, 1, 0), seed=51, segs=10,
                              rings=8, power=1.25, bumps=0.05, tip_round=0.05)]
    crown = Vector((0, L / 2 - L * 0.95, 0))
    for k in range(3):
        a = 2 * math.pi * k / 3
        d = Vector((math.cos(a) * 0.55, -1.0, math.sin(a) * 0.55)).normalized()
        objs.append(parts.greens(f"sprig{k}", crown + Vector((0, 0.004, 0)), length=0.032, direction=d, stems=1,
                                 seed=60 + k, pairs=1, lobes=2, spread=8, droop=0.12, stem_segs=3))
    return {"objects": objs, "markers": {"Trail": tuple(crown)},
            "report": {"notes": "Origin at the bolt centre, tip toward -Z; three leaf sprigs at the back."}}


def build_carrot_shell_pellet():
    """Chunky carrot coin: skin round the rim, cut faces show core + cortex rings."""
    R, T = 0.023, 0.020
    prof = [(-T / 2, R * 0.82), (-T / 2 + 0.0015, R * 0.97), (-T / 2 + 0.004, R),
            (T / 2 - 0.004, R * 0.985), (T / 2 - 0.0012, R * 0.95), (T / 2, R * 0.78)]
    # skin: normalised v samples a short band of the carrot strip (a slice is ~2 cm of carrot)
    coin = geo.lathe("pellet", prof, segs=18, mat=mats.carrot_skin("carrot_skin_chunk", v_range=(0.45, 0.58)),
                     cap0=True, cap1=True, sharp_angle=40, v_norm=True)
    coin.data.materials.append(mats.carrot_flesh())
    for p in coin.data.polygons:
        if abs(p.normal.y) > 0.85:
            p.material_index = 1
    geo.displace_noise(coin, 0.0012, 60.0, seed=4)
    # chunky: shear one face so it reads as a hacked-off chunk, not a coin
    for v in coin.data.vertices:
        if v.co.y > 0:
            v.co.y += v.co.x * 0.18
    coin["bbd_uv"] = "smart"
    return {"objects": [coin], "markers": {},
            "report": {"notes": "Origin at the chunk centre. Spawn several per shotgun blast with random spin."}}


ASSETS = {
    "carrot_bolt": dict(build=build_carrot_bolt, out="weapons", tex=512, kind="projectile", target=0.14,
                        use="Projectile for carrot_pistol and carrot_lmg"),
    "carrot_shell_pellet": dict(build=build_carrot_shell_pellet, out="weapons", tex=512, kind="projectile",
                                target=0.05, use="Shotgun pellet (spawn 6-8 per shot)"),
    "carrot_rocket": dict(build=build_carrot_rocket, out="weapons", tex=512, kind="projectile", target=0.45,
                          use="Projectile for carrot_rocket_launcher"),
}
