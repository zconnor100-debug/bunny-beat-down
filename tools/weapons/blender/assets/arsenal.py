"""Your arsenal (the game's Arsenal: guns only you carry): the Root Rumbler, the Carrot Lobber, the Big Root .50.

Garden contraptions like the carrot guns in weapons.py (same palette, same pieces, same frame: bore along +Y,
+Z up, metres, shifted so the trigger grip is the origin, Muzzle / SupportGrip / Sight / Eject markers), each
in its own enamel and each a size up from anything a bot carries:

    root_rumbler   six carrot barrels round a copper spindle, a motor drum wrapped in roots, a belt of baby
                   carrots out of a seed box
    carrot_lobber  a six-shot revolving drum with carrot bombs nosing out of its chambers, a hollowed-carrot
                   barrel ending in a flower pot, a twig ladder sight
    big_root_50    a fat carrot barrel with a copper muzzle brake, a box magazine of carrot slugs, an acorn
                   bolt knob, a long bamboo scope, a deployed twig bipod and a stock grown from a gnarled root
"""
from __future__ import annotations

import math

from mathutils import Vector

from bbd import geo, mats, parts
from assets.weapons import M, acorn, grip_outline, glass, rose, shift, twig


def _belt(name, pts, m):
    """A belt of baby carrots along `pts` (twine between them), each lying across the belt."""
    out = []
    path = [Vector(p) for p in pts]
    belt = geo.sweep(name + "_twine", path, 0.0026, segs=6, mat=mats.fibre("twine"), flatten=0.5, up=(0, 0, 1))
    belt["bbd_uv"] = "src"
    out.append(belt)
    for k in range(1, len(path) - 1):
        d = (path[k + 1] - path[k - 1]).normalized()
        across = d.cross(Vector((0, 0, 1)))
        if across.length < 1e-3:
            across = Vector((1, 0, 0))
        across.normalize()
        out.append(parts.carrot_part(f"{name}_carrot{k}", 0.036, 0.0068, pos=path[k] + across * 0.018, axis=tuple(across),
                                     seed=60 + k, segs=7, rings=4, bumps=0.06, power=1.4))
    return out


# --------------------------------------------------------------------------- Root Rumbler

def build_root_rumbler():
    """Root Rumbler (minigun) in terracotta enamel: six carrot barrels round a copper spindle, held by a
    brass band and a front plate; a motor drum wrapped in roots with an acorn on its end cap; a wooden seed
    box on the right feeding a twine belt of baby carrots; a carry handle, a walnut fore-grip and pistol grip."""
    m = M("root_rumbler")
    objs = []
    # the motor drum, brass rings, roots wound round it, an acorn on the end cap
    DR, D0, D1 = 0.052, -0.120, 0.040
    objs.append(geo.lathe("drum", [(D0, 0.0), (D0, DR - 0.008), (D0 + 0.006, DR), (D1 - 0.006, DR), (D1, DR - 0.006),
                                   (D1, 0.0)], segs=28, mat=m["blued"], sharp_angle=40))
    for k, y in enumerate((D0 + 0.012, D1 - 0.012)):
        objs.append(parts.band(f"drum_ring{k}", (0, y, 0), (0, 1, 0), DR, 0.010, m["brass"], segs=28))
    for k in range(3):
        coil = geo.helix((0, D0 + 0.026, 0), (0, 1, 0), DR + 0.0035, 0.10, 0.85, pts_per_turn=14, phase=k * 2.1)
        objs.append(geo.sweep(f"root{k}", coil, 0.0048 - k * 0.0006, segs=7, mat=m["bark"]))
    objs += acorn("cap_acorn", (0, D0 - 0.048, 0), 0.05, axis=(0, 1, 0), m=m, segs=12)
    # spindle and the six barrels: a carrot sleeve over each copper tube
    LB = 0.46
    objs.append(geo.cylinder("spindle", 0.009, LB + 0.012, 12, m["steel"], center=False))
    objs[-1].location = (0, D1, 0)
    RB = 0.030
    for k in range(6):
        a = 2 * math.pi * k / 6 + math.pi / 6
        x, z = RB * math.cos(a), RB * math.sin(a)
        tb = geo.tube(f"barrel{k}", 0.0072, 0.0044, LB, 12, m["steel"])
        tb.location = (x, D1, z)
        objs.append(tb)
        objs.append(parts.carrot_part(f"barrel_carrot{k}", 0.36, 0.0128, pos=(x, D1 + 0.37, z), axis=(0, 1, 0), seed=200 + k,
                                      segs=12, rings=8, cut=0.18, power=1.6, bumps=0.04))
    objs.append(parts.band("barrel_band", (0, D1 + 0.20, 0), (0, 1, 0), RB + 0.0145, 0.016, m["brass"], segs=24))
    FP = D1 + 0.405
    objs.append(geo.cylinder("front_plate", RB + 0.0135, 0.010, 24, m["brass"], bevel=0.002))
    objs[-1].location = (0, FP, 0)
    MUZ = D1 + LB + 0.004
    # the seed box on the right (bulk on the left, by the cheek, would push the gun off the shoulder:
    # CritterPoser._head_clearance), and its belt of baby carrots up into the drum
    BX, BY, BZ = 0.082, -0.030, -0.062
    objs.append(geo.box("seed_box", (0.060, 0.110, 0.070), (BX, BY, BZ), m["walnut_box"], bevel=0.004))
    objs.append(geo.box("seed_box_lid", (0.064, 0.114, 0.008), (BX, BY, BZ + 0.039), m["blued"], bevel=0.002))
    belt = [(BX - 0.010, BY + 0.020, BZ + 0.043), (BX - 0.016, BY + 0.024, BZ + 0.066), (BX - 0.030, BY + 0.026, BZ + 0.082),
            (0.052, BY + 0.028, 0.006), (0.044, BY + 0.030, 0.0)]
    objs += _belt("belt", belt, m)
    # carry handle over the drum, with a twine wrap
    hp = [Vector((0.0, D0 + 0.022 + (D1 - D0 - 0.044) * q, DR - 0.002 + 0.024 * math.sin(math.pi * q) ** 0.6))
          for q in [i / 10 for i in range(11)]]
    objs.append(geo.sweep("handle", hp, 0.0055, segs=8, mat=m["steel"]))
    objs.append(parts.twine_sleeve("handle_twine", (0, (D0 + D1) / 2, DR + 0.022), (0, 1, 0), 0.0075, 0.040, rings=3))
    # sights: a notch on a post at the back of the drum, a post on the front plate, the line just over the
    # handle (kept low: a tall gun is held under the chin, out of a short arm's reach: CritterPoser._head_clearance)
    SZ = DR + 0.036
    objs.append(geo.box("rear_post", (0.010, 0.010, SZ - DR - 0.008), (0, D0 + 0.016, (SZ + DR) / 2 - 0.006), m["blued"],
                        bevel=0.0015))
    objs.append(parts.notch_sight("rear_sight", (0, D0 + 0.016, SZ - 0.006), w=0.018, h=0.010, notch=0.0045, depth=0.006))
    objs.append(geo.box("front_post", (0.004, 0.006, SZ - RB - 0.012), (0, FP, (SZ + RB + 0.012) / 2 - 0.008), m["brass"],
                        bevel=0.001))
    objs.append(parts.greens("flag", (0.030, FP, 0.0), length=0.04, direction=(1.0, -0.4, 0.2), stems=3, seed=17,
                             pairs=2, lobes=2, spread=20, droop=0.3))
    # walnut fore-grip under the barrels, on its own band
    FG = D1 + 0.105
    objs.append(parts.band("foregrip_band", (0, FG, 0), (0, 1, 0), RB + 0.0145, 0.026, m["blued"], segs=24))
    fg_o = grip_outline((FG + 0.016, -0.040), (FG - 0.014, -0.040), (FG + 0.008, -0.128), (FG - 0.024, -0.124),
                        belly=0.002, palm=0.002)
    objs.append(geo.extrude_outline("foregrip", fg_o, 0.030, m["walnut_grip"], bevel=0.009, bevel_segs=2))
    # pistol grip, trigger and guard under the drum
    go = grip_outline((-0.018, -0.046), (-0.060, -0.046), (-0.040, -0.140), (-0.078, -0.132), belly=0.003, palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.032, m["walnut_grip"], bevel=0.010, bevel_segs=2))
    objs.append(geo.box("grip_mount", (0.034, 0.060, 0.014), (0, -0.036, -0.050), m["blued"], bevel=0.003))
    objs.append(parts.trigger("trigger", (0, -0.008, -0.056)))
    objs.append(parts.trigger_guard("guard", (0.016, -0.056), (-0.026, -0.072), 0.014))

    grip = (0.0, -0.052, -0.092)
    markers = {
        "Muzzle": (0, MUZ, 0.0),
        "SupportGrip": (0, FG - 0.004, -0.084),
        "Sight": (0, D0 + 0.016, SZ - 0.006 + 0.010 - 0.0045),
        "Eject": (0.0, D1 - 0.020, -DR),   # (husks drop out underneath)
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Muzzle is the spindle's centre at the barrels' mouths (carrots leave from there). "
                                "Sight line runs over the drum from the rear notch to the front plate's post."}}


# --------------------------------------------------------------------------- Carrot Lobber

def build_carrot_lobber():
    """Carrot Lobber (grenade launcher) in beetroot enamel: a six-shot revolving drum under the bore with carrot
    bombs nosing out of its chambers, a short hollowed-carrot barrel ending in a terracotta flower pot, a twig
    ladder sight with brass rungs, a walnut fore-grip and pistol grip, and a folding twig stock."""
    m = M("carrot_lobber")
    pot = mats.plain("terracotta", "#c46a43", rough=0.75, noise_amt=0.12)
    objs = []
    # frame
    fr = [(0.050, 0.020), (-0.090, 0.020), (-0.104, 0.010), (-0.104, -0.026), (-0.090, -0.034), (0.050, -0.034)]
    objs.append(geo.extrude_outline("frame", geo.chaikin(fr, 1), 0.050, m["blued"], bevel=0.004))
    for sx in (1, -1):
        for k in range(3):
            objs.append(parts.rivet(f"rv{sx}{k}", (sx * 0.0255, 0.030 - k * 0.050, -0.008), (sx, 0, 0), 0.0026, segs=6))
    # the drum: around an axis under the bore, its top chamber lined up with the barrel
    DZ, DRAD, DY0, DY1 = -0.040, 0.064, -0.016, 0.104
    flute = lambda i, j, a, t, r: r * (1.0 - 0.16 * max(0.0, math.cos(6 * a)) ** 2) if 1 <= i <= 4 else r
    drum = geo.lathe("drum", [(DY0, 0.0), (DY0, DRAD - 0.010), (DY0 + 0.008, DRAD), (DY1 - 0.008, DRAD),
                              (DY1, DRAD - 0.010), (DY1, 0.0)], segs=36, mat=m["blued"], radius_fn=flute, sharp_angle=40)
    drum.location = (0, 0, DZ)
    objs.append(drum)
    objs.append(geo.cylinder("drum_axle", 0.012, DY1 - DY0 + 0.030, 12, m["steel"]))
    objs[-1].location = (0, (DY0 + DY1) / 2, DZ)
    for k, y in enumerate((DY0 + 0.014, DY1 - 0.014)):
        band = parts.band(f"drum_band{k}", (0, y, DZ), (0, 1, 0), DRAD - 0.001, 0.010, m["brass"], segs=36)
        objs.append(band)
    for k in range(6):
        a = math.pi / 2 + 2 * math.pi * k / 6
        x, z = 0.040 * math.cos(a), DZ + 0.040 * math.sin(a)
        if k == 0:
            continue   # (the top chamber's is up the barrel)
        objs.append(parts.carrot_part(f"bomb{k}", 0.044, 0.0165, pos=(x, DY1 + 0.042, z), axis=(0, 1, 0), seed=90 + k,
                                      segs=12, rings=5, power=0.9, bumps=0.05, tip_round=0.3))
        objs.append(parts.greens(f"bomb_top{k}", (x, DY1 + 0.002, z), length=0.016, direction=(x, -0.3, z - DZ), stems=2,
                                 seed=70 + k, pairs=1, lobes=2, spread=30, droop=0.2))
        objs.append(parts.band(f"chamber{k}", (x, DY1 + 0.001, z), (0, 1, 0), 0.0175, 0.004, m["brass"], segs=14))
    # barrel: a fat hollowed carrot, a brass ferrule, a flower pot for a mouth
    BL = 0.24
    objs.append(geo.tube("bore", 0.0215, 0.0185, BL + 0.02, 18, m["steel"]))
    objs[-1].location = (0, DY1 - 0.004, 0)
    objs.append(parts.carrot_part("barrel_carrot", BL, 0.034, pos=(0, DY1 + BL, 0), axis=(0, 1, 0), seed=95, segs=18,
                                  rings=10, cut=0.34, power=1.3, bumps=0.045))
    cut_y = DY1 + BL - BL * 0.34
    objs.append(parts.band("ferrule", (0, cut_y, 0), (0, 1, 0), 0.0232, 0.012, m["brass"], segs=20))
    pot_prof = [(0.0, 0.0215), (0.0, 0.0245), (0.040, 0.0330), (0.044, 0.0360), (0.054, 0.0362), (0.055, 0.0330),
                (0.050, 0.0300), (0.010, 0.0215)]
    flower_pot = geo.lathe("flower_pot", pot_prof, segs=28, mat=pot, cap0=False, cap1=False, sharp_angle=40)
    flower_pot.location = (0, cut_y + 0.004, 0)
    objs.append(flower_pot)
    MUZ = cut_y + 0.058
    # ladder sight: two twig rails and brass rungs on the barrel, a post on the pot's rim
    LY = DY1 + 0.030
    for sx in (1, -1):
        objs += twig(f"ladder{sx}", [(sx * 0.010, LY, 0.030), (sx * 0.010, LY - 0.004, 0.056), (sx * 0.010, LY - 0.008, 0.074)],
                     0.0026, m["twig"], nubs=())
    for k, zz in enumerate((0.044, 0.058, 0.070)):
        objs.append(geo.cylinder(f"rung{k}", 0.0016, 0.020, 6, m["brass"], axis="X"))
        objs[-1].location = (0, LY - 0.002 - k * 0.002, zz)
    objs.append(geo.box("ladder_base", (0.026, 0.020, 0.008), (0, LY, 0.032), m["blued"], bevel=0.0015))
    SZ = 0.070
    objs.append(geo.box("front_post", (0.004, 0.005, SZ - 0.034), (0, MUZ - 0.010, (SZ + 0.034) / 2), m["brass"], bevel=0.001))
    # walnut fore-grip under the barrel, ahead of the drum
    FG = DY1 + 0.105
    objs.append(parts.band("foregrip_band", (0, FG, 0), (0, 1, 0), 0.036, 0.024, m["blued"], segs=24))
    fg_o = grip_outline((FG + 0.015, -0.032), (FG - 0.015, -0.032), (FG + 0.008, -0.118), (FG - 0.022, -0.114),
                        belly=0.002, palm=0.002)
    objs.append(geo.extrude_outline("foregrip", fg_o, 0.030, m["walnut_grip"], bevel=0.009, bevel_segs=2))
    # pistol grip, trigger, guard
    go = grip_outline((-0.042, -0.030), (-0.084, -0.030), (-0.064, -0.122), (-0.102, -0.114), belly=0.003, palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.032, m["walnut_grip"], bevel=0.010, bevel_segs=2))
    objs.append(parts.trigger("trigger", (0, -0.030, -0.034)))
    objs.append(parts.trigger_guard("guard", (-0.004, -0.034), (-0.046, -0.050), 0.014))
    # folding twig stock and a leather butt pad
    objs += twig("stock_top", [(0, -0.100, 0.012), (0, -0.180, 0.016), (0, -0.270, 0.012)], 0.0055, m["twig"], nubs=((0.5, 1.0),))
    objs += twig("stock_low", [(0, -0.100, -0.026), (0, -0.190, -0.056), (0, -0.270, -0.072)], 0.0055, m["twig"], nubs=())
    objs += parts.knot("stock_knot", (0, -0.150, 0.016), 0.006, seed=21)
    pad = [(-0.266, 0.024), (-0.282, 0.022), (-0.286, -0.030), (-0.282, -0.086), (-0.266, -0.088), (-0.272, -0.030)]
    objs.append(geo.extrude_outline("butt_pad", geo.chaikin(pad, 1), 0.036, m["leather"], bevel=0.005, bevel_segs=1))

    grip = (0.0, -0.075, -0.078)
    markers = {
        "Muzzle": (0, MUZ, 0.0),
        "SupportGrip": (0, FG - 0.004, -0.072),
        "Sight": (0, -0.080, 0.068),   # (the eye, behind the ladder: its top rung over the pot's post)
        "Eject": (0.026, 0.0, -0.004),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Revolving drum under the bore (its top chamber feeds the barrel). Sight = the "
                                "ladder's top rung over the front post on the flower pot's rim."}}


# --------------------------------------------------------------------------- Big Root .50

def build_big_root_50():
    """Big Root .50 (anti-materiel rifle) in delphinium enamel: a fat carrot barrel with a copper muzzle brake
    and a watering-can rose, a boxy receiver with brass plates and a box magazine of carrot slugs, an acorn bolt
    knob, a long bamboo scope on brass rings, a deployed twig bipod, a stock grown from a gnarled root with a
    leather cheek pad, and a walnut pistol grip."""
    m = M("big_root_50")
    objs = []
    # receiver and brass side plates
    rc = [(0.150, 0.026), (-0.100, 0.026), (-0.112, 0.014), (-0.112, -0.024), (-0.100, -0.034), (0.150, -0.034),
          (0.162, -0.020), (0.162, 0.014)]
    objs.append(geo.extrude_outline("receiver", geo.chaikin(rc, 1), 0.052, m["blued"], bevel=0.004))
    for sx in (1, -1):
        pl = [(0.120, 0.016), (-0.080, 0.016), (-0.086, 0.008), (-0.086, -0.022), (-0.078, -0.026), (0.120, -0.026)]
        objs.append(geo.extrude_outline(f"plate{sx}", geo.chaikin(pl, 1), 0.003, m["brass"], offset=sx * 0.0265,
                                        bevel=0.0009, bevel_segs=1))
        for k in range(4):
            objs.append(parts.rivet(f"rv{sx}{k}", (sx * 0.0285, 0.100 - k * 0.058, 0.008), (sx, 0, 0), 0.0026, segs=6))
    objs.append(geo.box("eject_port", (0.004, 0.060, 0.014), (0.0275, 0.040, 0.004), m["iron"], bevel=0.001, segs=1))
    # bolt: shroud at the back, handle on the right with an acorn for a knob
    objs.append(geo.lathe("bolt_shroud", [(-0.126, 0.0), (-0.126, 0.010), (-0.120, 0.015), (-0.110, 0.015)], segs=14,
                          mat=m["steel"], cap1=False, sharp_angle=40))
    bh = [Vector((0.020, -0.060, 0.008)), Vector((0.040, -0.062, 0.004)), Vector((0.058, -0.068, -0.010)),
          Vector((0.066, -0.074, -0.026))]
    objs.append(geo.sweep("bolt_handle", bh, 0.0052, segs=8, mat=m["steel"]))
    objs += acorn("bolt_acorn", (0.066, -0.075, -0.026), 0.030, axis=(0.3, 0, -1), m=m, segs=10)
    # the barrel: a copper tube in a fat carrot, brass collar and ferrule
    CL = 0.70
    objs.append(geo.tube("barrel", 0.0115, 0.0062, 0.84, 14, m["blued"]))
    objs[-1].location = (0, 0.150, 0)
    objs.append(parts.carrot_part("barrel_carrot", CL, 0.028, pos=(0, 0.160 + CL, 0), axis=(0, 1, 0), seed=501, segs=18,
                                  rings=16, cut=0.30, power=1.8, bumps=0.035))
    cut_y = 0.160 + CL * 0.70
    objs.append(parts.band("carrot_collar", (0, 0.162, 0), (0, 1, 0), 0.028, 0.012, m["brass"], segs=20))
    objs.append(parts.band("carrot_ferrule", (0, cut_y + 0.004, 0), (0, 1, 0), 0.0155, 0.014, m["brass"], segs=18))
    # the brake: a copper block with a port either side, then a watering-can rose
    BY = 0.990
    objs.append(geo.box("brake", (0.050, 0.070, 0.036), (0, BY, 0), m["steel"], bevel=0.006))
    for sx in (1, -1):
        objs.append(geo.box(f"brake_port{sx}", (0.006, 0.018, 0.022), (sx * 0.023, BY + 0.012, 0), m["iron"], bevel=0.002,
                            segs=1))
        objs.append(geo.box(f"brake_port_b{sx}", (0.006, 0.014, 0.022), (sx * 0.023, BY - 0.016, 0), m["iron"], bevel=0.002,
                            segs=1))
    objs += rose("rose", (0, BY + 0.035, 0), 0.0115, 0.020, 0.028, m=m, rings=(0.5, 0.85))
    MUZ = BY + 0.035 + 0.028
    # box magazine of carrot slugs under the receiver
    objs.append(geo.box("magazine", (0.036, 0.062, 0.080), (0, 0.030, -0.070), m["blued"], bevel=0.004))
    objs.append(geo.box("mag_plate", (0.040, 0.066, 0.008), (0, 0.030, -0.112), m["brass"], bevel=0.002))
    for k in range(2):
        objs.append(parts.carrot_part(f"slug{k}", 0.050, 0.0105, pos=(0, 0.058 + k * 0.004, -0.030 - k * 0.020),
                                      axis=(0, 1, 0), seed=520 + k, segs=10, rings=5, power=1.2, bumps=0.04))
    # the scope: bamboo, brass bells and rings, glass, a leather eyecup
    SZ = 0.078
    tube = geo.lathe("scope", [(-0.150, 0.024), (-0.134, 0.024), (-0.122, 0.0185), (0.200, 0.0185), (0.232, 0.029),
                               (0.300, 0.030), (0.305, 0.028), (0.305, 0.025), (0.298, 0.025)],
                     segs=24, mat=m["bamboo"], cap0=False, cap1=False, sharp_angle=40)
    tube.location = (0, 0, SZ)
    objs.append(tube)
    for k, y in enumerate((-0.090, 0.020, 0.150)):
        objs.append(parts.band(f"node{k}", (0, y, SZ), (0, 1, 0), 0.0195, 0.007, m["bamboo_node"], segs=24))
    cup = geo.lathe("eyecup", [(-0.192, 0.0215), (-0.192, 0.0260), (-0.186, 0.0272), (-0.150, 0.0250),
                               (-0.148, 0.0225)], segs=20, mat=m["leather"], cap0=False, cap1=False, sharp_angle=40)
    cup.location = (0, 0, SZ)
    objs.append(cup)
    for nm, y, r in (("lens_front", 0.300, 0.0252), ("lens_rear", -0.188, 0.0218)):
        ln = geo.cylinder(nm, r, 0.002, 20, glass(), axis="Y")
        ln.location = (0, y, SZ)
        objs.append(ln)
    for k, y in enumerate((-0.060, 0.120)):
        objs.append(parts.band(f"ring{k}", (0, y, SZ), (0, 1, 0), 0.0192, 0.014, m["brass"], segs=18))
        objs.append(geo.box(f"ring_base{k}", (0.018, 0.014, SZ - 0.0192 - 0.024), (0, y, (SZ - 0.0192 + 0.024) / 2),
                            m["blued"], bevel=0.002))
    # deployed bipod: twig legs splayed down and forward, brass feet
    BP = 0.620
    objs.append(parts.band("bipod_clamp", (0, BP, 0), (0, 1, 0), 0.0255, 0.016, m["blued"], segs=20))
    for sx in (1, -1):
        leg = [Vector((sx * 0.012, BP, -0.024)), Vector((sx * 0.034, BP + 0.030, -0.090)), Vector((sx * 0.052, BP + 0.056, -0.170))]
        objs += twig(f"bipod{sx}", leg, 0.0058, m["twig"], nubs=((0.5, sx),))
        objs.append(parts.rivet(f"bipod_foot{sx}", (sx * 0.053, BP + 0.058, -0.174), (0, 0, -1), 0.0085, m["brass"]))
    # the stock: a gnarled root (upper and lower beams joined at the butt), a cheek pad, a butt pad
    upper = [(0, -0.110, 0.018), (0.004, -0.200, 0.030), (-0.003, -0.300, 0.028), (0, -0.420, 0.020)]
    lower = [(0, -0.110, -0.030), (-0.004, -0.180, -0.060), (0.004, -0.300, -0.090), (0, -0.420, -0.110)]
    objs += twig("stock_upper", upper, 0.0105, m["bark"], nubs=((0.45, 1.0),))
    objs += twig("stock_lower", lower, 0.0095, m["bark"], nubs=((0.6, -1.0),))
    butt = [Vector((0, -0.420, 0.024)), Vector((0, -0.432, -0.040)), Vector((0, -0.420, -0.114))]
    objs.append(geo.sweep("stock_butt", butt, 0.012, segs=8, mat=m["bark"]))
    objs.append(geo.sweep("stock_brace", [Vector((0, -0.180, 0.026)), Vector((0, -0.240, -0.010)), Vector((0, -0.300, -0.088))],
                          0.006, segs=7, mat=m["bark"]))
    cheek = [(-0.180, 0.034), (-0.320, 0.036), (-0.330, 0.050), (-0.190, 0.050)]
    objs.append(geo.extrude_outline("cheek_pad", geo.chaikin(cheek, 1), 0.034, m["leather"], bevel=0.005, bevel_segs=1))
    pad = [(-0.432, 0.030), (-0.448, 0.028), (-0.452, -0.040), (-0.448, -0.120), (-0.432, -0.122), (-0.440, -0.040)]
    objs.append(geo.extrude_outline("butt_pad", geo.chaikin(pad, 1), 0.040, m["leather"], bevel=0.005, bevel_segs=1))
    objs.append(parts.twine_sleeve("stock_twine", (0, -0.140, 0.020), (0, 1, 0), 0.013, 0.022, rings=2))
    # pistol grip, trigger, guard
    go = grip_outline((-0.050, -0.032), (-0.092, -0.032), (-0.072, -0.124), (-0.110, -0.116), belly=0.003, palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.034, m["walnut_grip"], bevel=0.010, bevel_segs=2))
    objs.append(parts.trigger("trigger", (0, -0.034, -0.036)))
    objs.append(parts.trigger_guard("guard", (-0.006, -0.038), (-0.052, -0.054), 0.016))

    grip = (0.0, -0.085, -0.090)
    markers = {
        "Muzzle": (0, MUZ, 0.0),
        "SupportGrip": (0, 0.300, -0.030),
        "Sight": (0, -0.198, SZ),
        "Eject": (0.030, 0.040, 0.006),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Bolt-action .50: ADS through the scope (Sight just behind the eyecup, 0.078 m above "
                                "the bore). SupportGrip on the carrot barrel ahead of the receiver; the bipod is "
                                "deployed (its feet hang 0.17 m under the bore)."}}


ASSETS = {
    "root_rumbler": dict(build=build_root_rumbler, out="weapons", tex=1024, kind="weapon", target=0.7,
                         use="Your arsenal: Root Rumbler, a six-barrel carrot minigun (player only)"),
    "carrot_lobber": dict(build=build_carrot_lobber, out="weapons", tex=1024, kind="weapon", target=0.65,
                          use="Your arsenal: Carrot Lobber, a revolving carrot-bomb launcher (player only)"),
    "big_root_50": dict(build=build_big_root_50, out="weapons", tex=1024, kind="weapon", target=1.5,
                        use="Your arsenal: Big Root .50, an anti-materiel carrot rifle (player only)"),
}
