"""Carrot guns: pistol, shotgun, LMG, rocket launcher, SMG, assault rifle, sniper.

Each builder works in a convenient *layout* frame (bore axis at z = 0 or the
frame bottom at z = 0, +Y forward) and finally shifts everything so the main
(trigger) grip sits at the origin, as docs/ASSET_PIPELINE.md requires:
origin at the trigger grip, barrel along +Y (exported as -Z), +Z up, metres.

Markers (exported as named empties):
    Muzzle       projectile spawn point at the end of the bore
    SupportGrip  off-hand IK target
    Sight        eye point on the sight line (ADS camera sits here, looks along -Z)
    Eject        where spent carrot husks / backblast come out
"""
from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from bbd import geo, mats, parts
from bbd.util import place

# --------------------------------------------------------------------------- shared materials


def M():
    """Material palette shared by all guns (created lazily per Blender session)."""
    return {
        "walnut": mats.wood("walnut", "dark_wood", coords="src", tint="#d9b9a0", rough=0.42, wear=0.4),
        "walnut_grip": mats.wood("walnut_grip", "dark_wood", coords="src", rot=(0, 0, 90), tint="#d9b9a0",
                                 rough=0.45, wear=0.5),
        "walnut_box": mats.wood("walnut_box", "dark_wood", coords="box", tint="#d9b9a0", rough=0.45),
        "pine": mats.wood("pine", "coated_pine", coords="src", tint="#e8c9a0", rough=0.5),
        "pine_grip": mats.wood("pine_grip", "coated_pine", coords="src", rot=(0, 0, 90), tint="#e8c9a0", rough=0.5),
        "blued": mats.metal("blued", "blued"),
        "steel": mats.metal("steel", "steel"),
        "brass": mats.metal("brass", "brass", wear=0.6),
        "iron": mats.metal("iron", "iron"),
        "leather": mats.leather("leather"),
        "sage": mats.paint("paint_sage", "#5d7a46", under="galv", chip=0.65),
        "galv": mats.metal("galv", "galv"),
        "burlap": mats.burlap("burlap"),
    }


def shift(objs, markers, grip):
    """Move everything so `grip` becomes the origin."""
    g = Vector(grip)
    for o in objs:
        o.location -= g
    return {k: tuple(Vector(v) - g) for k, v in markers.items()}


def hull_loop(circles, y, offset, n=28):
    """Closed path hugging the convex hull of circles [(x, z, r)] in the plane at y."""
    pts = []
    for k in range(n):
        th = 2 * math.pi * k / n
        d = (math.cos(th), math.sin(th))
        best = max(circles, key=lambda c: c[0] * d[0] + c[1] * d[1] + c[2])
        rr = best[2] + offset
        pts.append((best[0] + rr * d[0], y, best[1] + rr * d[1]))
    return pts


def lashing(name, circles, y, turns=3, r=0.0017, gap=0.0036):
    """A few loops of twine around a bundle (barrels + carrot), plus a knot."""
    out = []
    for t in range(turns):
        yy = y + (t - (turns - 1) / 2) * gap
        loop = geo.sweep(f"{name}_{t}", hull_loop(circles, yy, r * 0.9), r, segs=5,
                         mat=mats.fibre("twine"), closed=True)
        loop["bbd_uv"] = "src"
        out.append(loop)
    return out


def grip_outline(top_front, top_back, bottom_front, bottom_back, belly=0.004, palm=0.004):
    """Pistol-grip side outline from four corners, with a finger swell and palm swell."""
    tf, tb, bf, bb = map(Vector, (top_front, top_back, bottom_front, bottom_back))
    front = [tf.lerp(bf, q) + Vector((belly * math.sin(math.pi * q) * (1 if 0.2 < q < 0.8 else 0.4), 0))
             for q in (0.0, 0.25, 0.5, 0.75, 1.0)]
    back = [bb.lerp(tb, q) + Vector((-palm * math.sin(math.pi * q), 0)) for q in (0.0, 0.3, 0.6, 1.0)]
    pts = front + [bf + Vector((-0.004, -0.003)), bb + Vector((0.004, -0.003))] + back
    return geo.chaikin([tuple(p) for p in pts], 1, sharp=(0, len(pts) - 1))


# --------------------------------------------------------------------------- pistol

def build_carrot_pistol():
    """Six-shot carrot revolver: brass drum loaded with baby carrots, carrot barrel shroud."""
    m = M()
    objs = []
    DZ = 0.022            # drum axis (frame bottom = 0)
    CH = 0.0125           # chamber offset from the drum axis
    BZ = DZ + CH          # bore height = top chamber

    # frame (blued) - side outline, overlapped by the drum
    frame_o = [(-0.046, 0.004), (-0.050, 0.026), (-0.044, 0.044), (-0.030, 0.050), (0.040, 0.050),
               (0.050, 0.046), (0.054, 0.036), (0.052, 0.010), (0.044, 0.0), (-0.008, 0.0), (-0.030, -0.004)]
    objs.append(geo.extrude_outline("frame", geo.chaikin(frame_o, 2, sharp=(4, 9)), 0.017, m["blued"],
                                    bevel=0.0022, bevel_segs=2))
    # top strap rib + rear sight
    objs.append(parts.notch_sight("rear_sight", (0, -0.036, 0.0495), w=0.012, h=0.008, notch=0.0035, depth=0.008))
    # drum: fluted brass cylinder with six baby-carrot noses in the chambers
    flutes = 6

    def flute(i, j, a, t, r):
        if i in (0, 1, len(prof) - 2, len(prof) - 1):
            return r
        c = math.cos(flutes * (a - math.pi / 2) + math.pi / flutes * flutes)
        return r - 0.0032 * max(0.0, -c) ** 0.5

    prof = [(-0.0005, 0.017), (0.0, 0.0205), (0.002, 0.0218), (0.010, 0.0218), (0.020, 0.0218), (0.030, 0.0218),
            (0.0385, 0.0218), (0.0405, 0.0205), (0.041, 0.017)]
    drum = geo.lathe("drum", prof, segs=36, mat=m["brass"], radius_fn=flute, sharp_angle=45)
    drum.location = (0, -0.0025, DZ)
    objs.append(drum)
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        cx, cz = CH * math.cos(a), DZ + CH * math.sin(a)
        nose = parts.carrot_part(f"chamber_carrot{k}", 0.03, 0.0042, pos=(cx, 0.0405 + 0.0035, cz),
                                 axis=(0, 1, 0), seed=10 + k, segs=8, rings=5, bumps=0.03, power=1.6)
        objs.append(nose)
    # cylinder pin
    objs.append(geo.cylinder("drum_pin", 0.0035, 0.008, 10, m["steel"], center=False, bevel=0.0008))
    objs[-1].location = (0, 0.037, DZ)

    # barrel: steel tube, carrot shroud lashed on with twine, brass ferrule at the cut
    objs.append(geo.tube("barrel", 0.0085, 0.0058, 0.172, 18, m["blued"]))
    objs[-1].location = (0, 0.043, BZ)
    objs.append(parts.band("muzzle_crown", (0, 0.212, BZ), (0, 1, 0), 0.0088, 0.006, m["steel"]))
    carrot = parts.carrot_part("barrel_carrot", 0.20, 0.0175, pos=(0, 0.053 + 0.20, BZ), axis=(0, 1, 0),
                               seed=3, segs=18, rings=12, cut=0.30, power=2.4, bumps=0.035, bend=0.0)
    objs.append(carrot)
    objs.append(parts.band("carrot_collar", (0, 0.054, BZ), (0, 1, 0), 0.0178, 0.010, m["brass"]))
    objs.append(parts.band("carrot_ferrule", (0, 0.193, BZ), (0, 1, 0), 0.0106, 0.012, m["brass"]))
    objs.append(parts.twine_sleeve("barrel_twine", (0, 0.122, BZ), (0, 1, 0), 0.0158, 0.018))
    objs += parts.knot("barrel_knot", (0.0, 0.122, BZ - 0.0175), 0.0045, seed=2)
    # front sight post on the ferrule
    objs.append(parts.post_sight("front_sight", (0, 0.195, BZ + 0.0105), h=0.0105, w=0.0024, depth=0.004))
    # carrot greens plume sprouting from the shroud's crown, swept back over the left side
    objs.append(parts.greens("plume", (-0.006, 0.058, BZ + 0.012), length=0.055, direction=(-0.55, -0.55, 0.65),
                             stems=3, seed=4, pairs=3, lobes=2, spread=22, droop=0.25))

    # hammer
    hammer_o = [(0.0, 0.0), (0.006, 0.0), (0.004, 0.012), (-0.006, 0.020), (-0.016, 0.021), (-0.018, 0.017),
                (-0.008, 0.013), (-0.004, 0.006)]
    h = geo.extrude_outline("hammer", geo.chaikin(hammer_o, 2, sharp=(0, 1)), 0.007, m["blued"], bevel=0.0012)
    h.location = (0, -0.046, 0.040)
    objs.append(h)
    # trigger + guard
    objs.append(parts.trigger("trigger", (0, 0.016, 0.001), scale=0.95))
    objs.append(parts.trigger_guard("guard", (0.038, 0.001), (-0.006, -0.020), 0.012))

    # walnut bird's-head grip with a brass toe strap and lanyard ring
    go = [(0.000, 0.004), (-0.004, -0.020), (-0.007, -0.034), (-0.004, -0.046), (-0.009, -0.060),
          (-0.016, -0.076), (-0.028, -0.088), (-0.046, -0.088), (-0.060, -0.080), (-0.068, -0.066),
          (-0.066, -0.048), (-0.058, -0.022), (-0.052, -0.004), (-0.050, 0.012), (-0.030, 0.006)]
    objs.append(geo.extrude_outline("grip", geo.chaikin(go, 2, sharp=(0, 14)), 0.029, m["walnut_grip"],
                                    bevel=0.0105, bevel_segs=3))
    toe = [(0.0, -0.016 - 0.0, -0.0765), (0.0, -0.024, -0.0855), (0.0, -0.036, -0.0905), (0.0, -0.048, -0.0905),
           (0.0, -0.060, -0.0835), (0.0, -0.068, -0.0700)]
    objs.append(geo.sweep("toe_strap", toe, 0.0085, segs=8, mat=m["brass"], flatten=0.25, up=(0, 0, -1)))
    ring = geo.sweep("lanyard", geo.arc_points((0, -0.042, -0.0985), 0.0055, 0, 360, 13, "YZ")[:-1], 0.0013,
                     segs=6, mat=m["brass"], closed=True)
    objs.append(ring)
    for sx in (1, -1):
        objs.append(parts.screw(f"grip_screw{sx}", (sx * 0.0142, -0.034, -0.040), (sx, 0, 0), 0.0030, m["brass"]))
        for k, yy in enumerate((-0.036, 0.046)):
            objs.append(parts.screw(f"frame_screw{k}{sx}", (sx * 0.0086, yy, 0.010), (sx, 0, 0), 0.0021))

    grip = (0.0, -0.034, -0.040)
    markers = {
        "Muzzle": (0, 0.2155, BZ),
        "SupportGrip": (-0.020, -0.030, -0.054),
        "Sight": (0, -0.040, 0.0495 + 0.008 - 0.0035),
        "Eject": (0.020, 0.018, DZ),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Six-shot revolver; drum front shows the loaded baby carrots. Sight marker sits in "
                                "the rear notch; front post on the brass ferrule is level with it."}}


# --------------------------------------------------------------------------- shotgun

def build_carrot_shotgun():
    """Side-by-side coach gun: twin blued barrels, carrot fore-end lashed underneath."""
    m = M()
    objs = []
    BL = 0.375                      # barrel length
    BX, BR, BI = 0.0145, 0.0138, 0.0102
    for sx, nm in ((1, "R"), (-1, "L")):
        b = geo.tube(f"barrel{nm}", BR, BI, BL, 20, m["blued"])
        b.location = (sx * BX, 0.0, 0.0)
        objs.append(b)
    # top rib + bottom filler rib between the barrels
    objs.append(geo.box("rib", (0.009, BL - 0.01, 0.004), (0, BL / 2, 0.0125), m["blued"], bevel=0.0012))
    objs.append(geo.box("rib_low", (0.010, BL - 0.03, 0.006), (0, BL / 2 - 0.01, -0.0105), m["blued"], bevel=0.0015))
    # brass muzzle band around both barrels (stadium-shaped loop)
    band = geo.sweep("muzzle_band", hull_loop([(BX, 0, BR), (-BX, 0, BR)], BL - 0.012, 0.0022, 24), 0.0035,
                     segs=6, mat=m["brass"], closed=True, flatten=0.45)
    objs.append(band)
    objs.append(parts.bead("bead", (0, BL - 0.010, 0.0165), 0.0028))

    # action (receiver): blued block with brass side plates and fences over the breech
    act_o = [(0.004, 0.017), (0.0, 0.020), (-0.020, 0.021), (-0.088, 0.016), (-0.094, 0.008), (-0.094, -0.020),
             (-0.080, -0.036), (-0.010, -0.036), (0.004, -0.024), (0.006, 0.0)]
    objs.append(geo.extrude_outline("action", geo.chaikin(act_o, 1, sharp=(4, 5)), 0.052, m["blued"],
                                    bevel=0.004, bevel_segs=2))
    for sx in (1, -1):
        plate_o = [(-0.012, 0.010), (-0.080, 0.010), (-0.086, -0.004), (-0.078, -0.028), (-0.016, -0.028),
                   (-0.008, -0.010)]
        p = geo.extrude_outline(f"sideplate{sx}", geo.chaikin(plate_o, 1), 0.003, m["brass"], offset=sx * 0.0262,
                                bevel=0.0009, bevel_segs=1)
        objs.append(p)
        objs.append(parts.screw(f"hinge_pin{sx}", (sx * 0.0278, -0.012, -0.022), (sx, 0, 0), 0.0042, m["steel"]))
        objs.append(parts.screw(f"lock_screw{sx}", (sx * 0.0278, -0.062, -0.006), (sx, 0, 0), 0.0030, m["steel"]))
        # external hammers
        ho = [(0.0, 0.0), (0.007, 0.0), (0.006, 0.014), (-0.004, 0.026), (-0.016, 0.029), (-0.019, 0.025),
              (-0.008, 0.018), (-0.003, 0.008)]
        hm = geo.extrude_outline(f"hammer{sx}", geo.chaikin(ho, 1, sharp=(0, 1)), 0.0065, m["blued"],
                                 bevel=0.0012, bevel_segs=1)
        hm.location = (sx * 0.0175, -0.078, 0.012)
        objs.append(hm)
    # top lever
    lv_o = [(0.0, 0.0), (0.004, 0.001), (0.006, 0.005), (-0.030, 0.009), (-0.034, 0.005), (-0.028, 0.002)]
    lever = geo.extrude_outline("top_lever", geo.chaikin(lv_o, 1), 0.010, m["blued"], plane="XY", bevel=0.0015,
                                bevel_segs=1)
    place(lever, (0.004, -0.040, 0.020), (0, 0, -12), apply=False)
    objs.append(lever)
    # triggers + guard
    objs.append(parts.trigger("trigger_front", (0, -0.030, -0.035), 1.0))
    objs.append(parts.trigger("trigger_back", (0, -0.046, -0.035), 0.95))
    objs.append(parts.trigger_guard("guard", (-0.006, -0.036), (-0.110, -0.040), 0.026, width=0.008))

    # walnut stock (straight English grip), leather butt pad
    st_o = [(-0.086, 0.017), (-0.110, 0.009), (-0.170, 0.005), (-0.300, 0.010), (-0.352, 0.014),
            (-0.356, 0.000), (-0.362, -0.050), (-0.365, -0.104), (-0.350, -0.110), (-0.260, -0.078),
            (-0.180, -0.044), (-0.120, -0.038), (-0.090, -0.036)]

    def taper(a, b):
        return 0.78 + 0.22 * min(1.0, max(0.0, (-a - 0.12) / 0.2))
    objs.append(geo.extrude_outline("stock", geo.chaikin(st_o, 1, sharp=(4, 8)), 0.044, m["walnut"],
                                    bevel=0.010, bevel_segs=3, taper=taper))
    pad_o = [(-0.352, 0.014), (-0.372, 0.013), (-0.377, -0.050), (-0.374, -0.106), (-0.351, -0.111),
             (-0.358, -0.050)]
    objs.append(geo.extrude_outline("butt_pad", geo.chaikin(pad_o, 1), 0.040, m["leather"], bevel=0.006,
                                    bevel_segs=2))
    # chequered panel suggestion: brass escutcheon + sling swivel
    objs.append(parts.rivet("escutcheon", (0, -0.25, -0.083), (0, 0.15, -1), 0.005))

    # carrot fore-end lashed under the barrels
    CZ, CR, CL = -0.031, 0.025, 0.25
    car = parts.carrot_part("forend_carrot", CL, CR, pos=(0, 0.012 + CL, CZ), axis=(0, 1, 0), seed=7,
                            segs=16, rings=12, power=1.5, bumps=0.05, tip_round=0.08)
    objs.append(car)
    objs.append(parts.band("forend_collar", (0, 0.016, CZ), (0, 1, 0), CR * 0.98, 0.012, m["brass"]))
    bundle = [(BX, 0, BR), (-BX, 0, BR), (0, CZ, CR * 0.92)]
    objs += lashing("lash_a", bundle, 0.075, turns=3)
    bundle2 = [(BX, 0, BR), (-BX, 0, BR), (0, CZ, CR * 0.6)]
    objs += lashing("lash_b", bundle2, 0.185, turns=3)
    objs += parts.knot("lash_knot", (0.0, 0.075, CZ - CR - 0.001), 0.005, seed=5)
    # leafy flag tied near the muzzle, leaning back over the left barrel
    objs.append(parts.greens("flag", (-0.006, BL - 0.045, 0.016), length=0.07, direction=(-0.45, -0.6, 0.7),
                             stems=3, seed=11, pairs=2, lobes=2, spread=20, droop=0.3))
    objs.append(parts.twine_sleeve("flag_twine", (-0.0145, BL - 0.045, 0.0), (0, 1, 0), BR, 0.012, rings=2))

    grip = (0.0, -0.140, -0.016)
    markers = {
        "Muzzle": (0, BL, 0.0),
        "SupportGrip": (0, 0.140, CZ),
        "Sight": (0, -0.012, 0.0165 + 0.0028),
        "Eject": (0, 0.002, 0.004),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Twin barrels at x = +/-0.0145 m; Muzzle is between them (alternate L/R in "
                                "code if desired). Sight sits on the rib line, level with the brass bead."}}


# --------------------------------------------------------------------------- LMG

def build_carrot_lmg():
    """Lewis-style LMG: giant carrot barrel shroud, pan magazine of radial baby carrots."""
    m = M()
    objs = []
    # receiver (blued) + brass side plates with rivets
    rc_o = [(0.062, 0.026), (0.058, 0.032), (-0.110, 0.032), (-0.124, 0.024), (-0.126, -0.020), (-0.116, -0.034),
            (0.040, -0.034), (0.062, -0.018)]
    objs.append(geo.extrude_outline("receiver", geo.chaikin(rc_o, 1), 0.054, m["blued"], bevel=0.004))
    for sx in (1, -1):
        pl = [(0.040, 0.020), (-0.100, 0.020), (-0.106, 0.010), (-0.106, -0.020), (-0.096, -0.026), (0.034, -0.026)]
        objs.append(geo.extrude_outline(f"plate{sx}", geo.chaikin(pl, 1), 0.003, m["brass"], offset=sx * 0.0275,
                                        bevel=0.0009, bevel_segs=1))
        for k in range(3):
            for zz in (0.014, -0.020):
                objs.append(parts.rivet(f"rv{sx}{k}{zz}", (sx * 0.029, 0.026 - k * 0.058, zz), (sx, 0, 0), 0.0026,
                                        segs=6))
    # charging knob on the right
    objs.append(parts.rivet("charge_knob", (0.030, -0.030, 0.004), (1, 0, 0), 0.0075, m["steel"]))
    objs.append(geo.cylinder("charge_stem", 0.003, 0.012, 8, m["steel"], axis="X", center=False))
    objs[-1].location = (0.026, -0.030, 0.004)

    # carrot barrel shroud
    SL, SR = 0.44, 0.046
    shroud = parts.carrot_part("shroud_carrot", SL, SR, pos=(0, 0.066 + SL, 0.0), axis=(0, 1, 0), seed=21,
                               segs=20, rings=12, cut=0.13, power=1.55, bumps=0.045)
    objs.append(shroud)
    objs.append(parts.band("shroud_collar", (0, 0.068, 0), (0, 1, 0), SR * 0.99, 0.016, m["brass"]))
    cut_y = 0.066 + SL - SL * 0.13
    objs.append(parts.band("shroud_ferrule", (0, cut_y + 0.003, 0), (0, 1, 0), 0.0135, 0.012, m["brass"]))
    objs.append(geo.tube("barrel", 0.0105, 0.0072, 0.10, 12, m["blued"]))
    objs[-1].location = (0, cut_y - 0.01, 0)
    # muzzle brake: slotted-looking stack of rings
    mb = [(0.0, 0.0072), (0.0, 0.0150), (0.004, 0.0158), (0.013, 0.0158), (0.014, 0.0118), (0.024, 0.0118),
          (0.025, 0.0158), (0.036, 0.0158), (0.038, 0.0140), (0.038, 0.0080)]
    brake = geo.lathe("brake", mb, segs=14, mat=m["steel"], cap0=False, cap1=True, sharp_angle=40)
    brake.location = (0, cut_y + 0.085, 0)
    objs.append(brake)
    muzzle_y = cut_y + 0.085 + 0.038
    objs.append(parts.twine_sleeve("shroud_twine", (0, 0.30, 0), (0, 1, 0), 0.032, 0.020, rings=2))
    objs += parts.knot("shroud_knot", (0.0, 0.30, -0.0345), 0.006, seed=8)

    # pan magazine on top: brass rim, steel floor + hub, radial baby carrots under three straps
    PY, PZ, PR = -0.034, 0.036, 0.086
    pan_prof = [(0.0, 0.0), (0.0, PR - 0.006), (0.002, PR), (0.026, PR), (0.030, PR - 0.004), (0.030, PR - 0.008),
                (0.024, PR - 0.008), (0.006, PR - 0.010)]
    pan = geo.lathe("pan", pan_prof, segs=32, mat=m["brass"], cap0=True, cap1=False, axis="Z", sharp_angle=40)
    pan.location = (0, PY, PZ)
    objs.append(pan)
    floor = geo.cylinder("pan_floor", PR - 0.009, 0.004, 24, m["blued"], axis="Z", center=False)
    floor.location = (0, PY, PZ + 0.004)
    objs.append(floor)
    hub_p = [(0.0, 0.019), (0.022, 0.019), (0.026, 0.016), (0.030, 0.012), (0.034, 0.010), (0.036, 0.0)]
    hub = geo.lathe("hub", hub_p, segs=14, mat=m["steel"], cap0=True, axis="Z", sharp_angle=40)
    hub.location = (0, PY, PZ + 0.004)
    objs.append(hub)
    n_car = 13
    for k in range(n_car):
        a = 2 * math.pi * k / n_car
        d = Vector((math.cos(a), math.sin(a), 0))
        c = Vector((0, PY, PZ + 0.0175)) + d * 0.050
        bc = parts.carrot_part(f"pan_carrot{k}", 0.060, 0.0095, pos=c - d * 0.030, axis=-d, seed=30 + k,
                               segs=7, rings=4, bumps=0.06, power=1.4)
        objs.append(bc)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        d = Vector((math.cos(a), math.sin(a), 0))
        strap = geo.sweep(f"pan_strap{k}", [Vector((0, PY, PZ + 0.029)) + d * 0.02, Vector((0, PY, PZ + 0.030)) + d * 0.05,
                                            Vector((0, PY, PZ + 0.029)) + d * 0.081],
                          0.0045, segs=6, mat=m["blued"], flatten=0.35, up=(0, 0, 1))
        objs.append(strap)
    objs.append(parts.rivet("hub_cap", (0, PY, PZ + 0.040), (0, 0, 1), 0.012, m["brass"]))

    # sights: tall rear leaf behind the pan, tall front post with a leafy flag
    SZ = 0.086
    post = geo.box("rear_tower", (0.010, 0.010, SZ - 0.032), (0, -0.131, (SZ + 0.032) / 2 - 0.006), m["blued"],
                   bevel=0.0015)
    objs.append(post)
    objs.append(parts.notch_sight("rear_sight", (0, -0.131, SZ - 0.006), w=0.018, h=0.010, notch=0.0045,
                                  depth=0.006))
    fpost_base = 0.0175
    objs.append(parts.band("front_band", (0, cut_y - 0.03, 0), (0, 1, 0), 0.0185, 0.010, m["brass"]))
    fp = geo.box("front_post", (0.004, 0.006, SZ - fpost_base + 0.004 - 0.004),
                 (0, cut_y - 0.03, (SZ + fpost_base) / 2 + 0.002), m["brass"], bevel=0.001)
    objs.append(fp)
    objs.append(parts.greens("flag", (-0.003, cut_y - 0.03, SZ - 0.020), length=0.06, direction=(-0.7, -0.5, 0.5),
                             stems=3, seed=13, pairs=2, lobes=2, spread=20, droop=0.3))

    # carry handle over the shroud
    hp = [(0.0, 0.17 + 0.09 * q, 0.042 + 0.030 * math.sin(math.pi * q)) for q in [i / 10 for i in range(11)]]
    objs.append(geo.sweep("handle", hp, 0.0045, segs=8, mat=m["steel"], flatten=0.5, up=(1, 0, 0)))
    for yy in (0.17, 0.26):
        objs.append(parts.band(f"handle_clamp{yy}", (0, yy, 0), (0, 1, 0), 0.036 if yy < 0.2 else 0.031, 0.010,
                               m["brass"]))

    # vertical walnut fore-grip
    fg_o = grip_outline((0.230, -0.026), (0.200, -0.026), (0.222, -0.112), (0.190, -0.108), belly=0.002, palm=0.002)
    objs.append(geo.extrude_outline("foregrip", fg_o, 0.030, m["walnut_grip"], bevel=0.009, bevel_segs=2))
    objs.append(parts.band("foregrip_clamp", (0, 0.214, 0), (0, 1, 0), 0.0345, 0.024, m["blued"]))

    # folded bipod legs along the shroud underside
    for sx in (1, -1):
        leg = [(sx * 0.010, 0.395, -0.020), (sx * 0.020, 0.33, -0.036), (sx * 0.026, 0.27, -0.045)]
        objs.append(geo.sweep(f"bipod{sx}", leg, 0.0035, segs=6, mat=m["blued"]))
        foot = parts.rivet(f"bipod_foot{sx}", (sx * 0.027, 0.265, -0.046), (0, -1, 0), 0.0055, m["iron"])
        objs.append(foot)
    objs.append(parts.band("bipod_clamp", (0, 0.40, 0), (0, 1, 0), 0.0215, 0.012, m["blued"]))

    # pistol grip, trigger, guard
    go = grip_outline((-0.040, -0.030), (-0.082, -0.030), (-0.062, -0.122), (-0.100, -0.114), belly=0.003, palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.032, m["walnut_grip"], bevel=0.010, bevel_segs=2))
    objs.append(parts.trigger("trigger", (0, -0.030, -0.034)))
    objs.append(parts.trigger_guard("guard", (0.0, -0.034), (-0.044, -0.050), 0.014))

    # spade butt stock
    st_o = [(-0.118, 0.024), (-0.180, 0.016), (-0.300, 0.020), (-0.318, 0.012), (-0.322, -0.040),
            (-0.318, -0.092), (-0.296, -0.098), (-0.210, -0.060), (-0.140, -0.036), (-0.118, -0.030)]
    objs.append(geo.extrude_outline("stock", geo.chaikin(st_o, 1, sharp=(3, 6)), 0.040, m["walnut"], bevel=0.009,
                                    bevel_segs=2))
    pad_o = [(-0.318, 0.012), (-0.330, 0.010), (-0.334, -0.040), (-0.330, -0.094), (-0.316, -0.094)]
    objs.append(geo.extrude_outline("butt_plate", geo.chaikin(pad_o, 1), 0.036, m["brass"], bevel=0.004))
    objs.append(parts.twine_sleeve("wrist_twine", (0, -0.150, -0.006), (0, 1, 0), 0.020, 0.022, rings=2))

    grip = (0.0, -0.075, -0.078)
    markers = {
        "Muzzle": (0, muzzle_y, 0.0),
        "SupportGrip": (0, 0.212, -0.070),
        "Sight": (0, -0.131, SZ - 0.006 + 0.010 - 0.0045),
        "Eject": (0.029, -0.010, 0.0),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Pan magazine is part of the main mesh (13 baby carrots). Sight line runs over the "
                                "pan from the rear tower to the brass front post."}}


# --------------------------------------------------------------------------- rocket launcher

def build_carrot_rocket_launcher():
    """Watering-can-green tube launcher with a rocket carrot loaded (separate `Rocket` node)."""
    from assets.projectiles import carrot_rocket_parts
    m = M()
    objs = []
    T0, T1, TR, TI = -0.355, 0.395, 0.057, 0.0515
    # tube body (painted), rolled front lip, flared exhaust bell (galvanised)
    # tube paint carries a sprayed cream carrot stencil on both flanks (node space = final, grip-relative coords)
    from bbd import textures
    tube_paint = mats.paint("paint_sage_stencil", "#5d7a46", under="galv", chip=0.65,
                            stencil=textures.stencil_carrot(), st_center=(0.168, 0.110), st_size=0.105)
    tube = geo.lathe("tube", [(T0 + 0.002, TR), (T1 - 0.004, TR)], segs=40, mat=tube_paint, cap0=False, cap1=False,
                     sharp_angle=None)
    objs.append(tube)
    inner = geo.lathe("tube_in", [(T1 - 0.004, TI), (T0 + 0.004, TI)], segs=32, mat=m["galv"], cap0=False,
                      cap1=False, sharp_angle=None)
    objs.append(inner)
    lip = [(T1 - 0.006, TR - 0.0005), (T1 - 0.004, TR + 0.003), (T1, TR + 0.0035), (T1 + 0.004, TR + 0.001),
           (T1 + 0.004, TI - 0.0005), (T1 - 0.006, TI - 0.0005)]
    objs.append(geo.lathe("front_lip", lip, segs=32, mat=m["brass"], cap0=False, cap1=False, sharp_angle=50))
    bell = [(T0 + 0.006, TI), (T0 + 0.006, TR + 0.0015), (T0, TR + 0.004), (T0 - 0.03, TR + 0.008),
            (T0 - 0.058, TR + 0.020), (T0 - 0.064, TR + 0.022), (T0 - 0.066, TR + 0.019), (T0 - 0.060, TR + 0.014),
            (T0 - 0.03, TI + 0.003), (T0 + 0.006, TI)]
    objs.append(geo.lathe("bell", bell, segs=32, mat=m["galv"], cap0=False, cap1=False, sharp_angle=45))
    for k, yy in enumerate((-0.27, -0.03, 0.30)):
        objs.append(parts.band(f"tube_band{k}", (0, yy, 0), (0, 1, 0), TR, 0.016, m["brass"]))
        for a in (0.0, math.pi):
            objs.append(parts.rivet(f"band_rivet{k}{a}", (math.cos(a) * (TR + 0.0015), yy, math.sin(a) * 0.0),
                                    (math.cos(a), 0, 0), 0.0028))

    # loaded rocket carrot (separate node so the game can hide it after firing)
    rparts, rlen = carrot_rocket_parts(scale=1.0, in_tube=True)
    tip_y = T1 + 0.20
    for o in rparts:
        o.location += Vector((0, tip_y - rlen / 2, 0))
        o["bbd_node"] = "Rocket"
    objs += rparts

    # trigger grip + bracket, trigger, guard
    objs.append(parts.band("grip_bracket", (0, -0.065, 0), (0, 1, 0), TR, 0.040, m["blued"]))
    br_o = [(-0.040, -0.040), (-0.090, -0.040), (-0.090, -0.072), (-0.040, -0.072)]
    objs.append(geo.extrude_outline("grip_block", br_o, 0.026, m["blued"], bevel=0.004))
    go = grip_outline((-0.050, -0.068), (-0.092, -0.068), (-0.070, -0.158), (-0.108, -0.150), belly=0.003,
                      palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.032, m["pine_grip"], bevel=0.010, bevel_segs=2))
    objs.append(parts.trigger("trigger", (0, -0.026, -0.070), 1.05))
    objs.append(parts.trigger_guard("guard", (-0.004, -0.070), (-0.050, -0.090), 0.016))
    # front grip
    objs.append(parts.band("front_bracket", (0, 0.200, 0), (0, 1, 0), TR, 0.030, m["blued"]))
    fg = grip_outline((0.215, -0.050), (0.185, -0.050), (0.208, -0.135), (0.178, -0.130), belly=0.002, palm=0.002)
    objs.append(geo.extrude_outline("front_grip", fg, 0.030, m["pine_grip"], bevel=0.009, bevel_segs=2))
    objs.append(geo.box("front_block", (0.022, 0.030, 0.012), (0, 0.200, -0.056), m["blued"], bevel=0.003))

    # shoulder rest: pine cradle under the tube rear, wrapped in burlap
    sr_o = [(-0.150, -0.050), (-0.320, -0.050), (-0.330, -0.068), (-0.310, -0.088), (-0.160, -0.080)]
    objs.append(geo.extrude_outline("shoulder_rest", geo.chaikin(sr_o, 1), 0.050, m["pine"], bevel=0.010,
                                    bevel_segs=3))
    objs.append(geo.lathe("shoulder_pad", [(-0.235, TR + 0.0005), (-0.233, TR + 0.006), (-0.225, TR + 0.0085),
                                            (-0.135, TR + 0.0085), (-0.127, TR + 0.006), (-0.125, TR + 0.0005)],
                          segs=32, mat=m["burlap"], cap0=False, cap1=False, sharp_angle=None))
    objs.append(parts.twine_sleeve("pad_twine_a", (0, -0.238, 0), (0, 1, 0), TR + 0.001, 0.010, rings=2))
    objs.append(parts.twine_sleeve("pad_twine_b", (0, -0.122, 0), (0, 1, 0), TR + 0.001, 0.010, rings=2))

    # sights: brass peep ring at the rear, post + leafy flag at the front
    SZ = 0.098
    objs.append(geo.box("peep_post", (0.006, 0.008, SZ - TR - 0.004), (0, -0.205, (SZ + TR) / 2 - 0.008),
                        m["blued"], bevel=0.0012))
    ring = geo.sweep("peep_ring", geo.arc_points((0, -0.205, SZ), 0.0085, 0, 360, 17, "XZ")[:-1], 0.0022, segs=6,
                     mat=m["brass"], closed=True)
    objs.append(ring)
    objs.append(geo.box("front_post", (0.004, 0.006, SZ - TR + 0.004), (0, 0.345, (SZ + TR) / 2 + 0.001),
                        m["brass"], bevel=0.0008))
    objs.append(parts.greens("flag", (-0.004, 0.345, TR + 0.012), length=0.075, direction=(-0.7, -0.45, 0.55),
                             stems=4, seed=17, pairs=2, lobes=2, spread=24, droop=0.3))
    objs.append(parts.twine_sleeve("flag_twine", (0, 0.345, 0), (0, 1, 0), TR, 0.012, rings=2))
    objs += parts.knot("flag_knot", (-0.010, 0.345, TR + 0.003), 0.006, seed=9, tail_dir=(-0.6, -0.2, -0.6))

    grip = (0.0, -0.080, -0.110)
    markers = {
        "Muzzle": (0, T1 + 0.004, 0.0),
        "SupportGrip": (0, 0.197, -0.092),
        "Sight": (0, -0.205, SZ),
        "Eject": (0, T0 - 0.066, 0.0),
    }
    markers = shift(objs, markers, grip)
    rocket_center = Vector((0, tip_y - rlen / 2, 0)) - Vector(grip)
    return {"objects": objs, "markers": markers, "pivots": {"Rocket": tuple(rocket_center)},
            "report": {"notes": "Loaded rocket is the separate node `Rocket` (hide it after firing, show on "
                                "reload). Eject marks the rear exhaust bell = backblast origin. Sight is the "
                                "centre of the rear peep ring."}}


# --------------------------------------------------------------------------- shared bits for the new guns

def glass():
    return mats.plain("lens_glass", "#17343a", rough=0.04, coat=1.0, noise_amt=0.02, bump=0.0)


def carrot_coin(name, r, thick, pos, axis=(0, 1, 0)):
    """A carrot slice: skin round the rim, cut faces show core + cortex (flesh on the caps)."""
    prof = [(-thick / 2, r * 0.86), (-thick / 2 + 0.0012, r * 0.98), (thick / 2 - 0.0012, r * 0.98),
            (thick / 2, r * 0.86)]
    coin = geo.lathe(name, prof, segs=18, mat=mats.carrot_skin("carrot_skin_chunk", v_range=(0.45, 0.58)),
                     cap0=True, cap1=True, sharp_angle=40, v_norm=True)
    coin.data.materials.append(mats.carrot_flesh())
    for p in coin.data.polygons:
        if abs(p.normal.y) > 0.85:
            p.material_index = 1
    return parts.orient(coin, axis, pos)


def peep(name, center, r=0.0055, mat=None, post=0.008):
    """Aperture sight: a ring on a short post (ring in the XZ plane, looking along Y)."""
    c = Vector(center)
    ring = geo.sweep(name, geo.arc_points(c, r, 0, 360, 15, "XZ")[:-1], 0.0016, segs=6,
                     mat=mat or mats.metal("brass", "brass"), closed=True)
    stem = geo.box(name + "_post", (0.003, 0.004, post), (c.x, c.y, c.z - r - post / 2 + 0.0008),
                   mat or mats.metal("brass", "brass"), bevel=0.0008, segs=1)
    return [ring, stem]


# --------------------------------------------------------------------------- SMG

def build_carrot_smg():
    """Scrappy Sten-style SMG: tube receiver, side magazine of baby carrots, wire stock."""
    m = M()
    objs = []
    # tube receiver with a barrel nut, ejection port and cocking knob
    rec = geo.lathe("receiver", [(-0.094, 0.0), (-0.094, 0.0165), (-0.090, 0.0205), (0.056, 0.0205),
                                 (0.060, 0.0175), (0.062, 0.0125), (0.068, 0.0125), (0.069, 0.0)], segs=20,
                    mat=m["blued"], sharp_angle=40)
    objs.append(rec)
    objs.append(geo.box("eject_port", (0.006, 0.036, 0.012), (0.0185, 0.004, 0.006), m["iron"], bevel=0.0012,
                        segs=1))
    objs.append(geo.box("cock_slot", (0.004, 0.05, 0.005), (0.0195, -0.055, 0.0), m["iron"], bevel=0.001, segs=1))
    objs.append(parts.rivet("cock_knob", (0.026, -0.052, 0.0), (1, 0, 0), 0.0065, m["steel"], segs=8))
    objs.append(geo.cylinder("cock_stem", 0.0025, 0.01, 8, m["steel"], axis="X", center=False))
    objs[-1].location = (0.017, -0.052, 0.0)
    for k, yy in enumerate((-0.07, 0.035)):
        objs.append(parts.band(f"rec_band{k}", (0, yy, 0), (0, 1, 0), 0.0207, 0.008, m["brass"], segs=16))
    # side magazine well (left) + open wire frame holding a double stack of baby carrots
    tilt = Matrix.Rotation(math.radians(-8), 4, "Y")   # sags a little away from the gun
    well = geo.box("mag_well", (0.040, 0.050, 0.030), (-0.036, 0.0, 0.0), m["blued"], bevel=0.003)
    objs.append(well)
    mag = []
    for yy in (-0.026, 0.026):
        for zz in (-0.0125, 0.0125):
            mag.append(geo.sweep(f"mag_rod{yy}{zz}", [Vector((-0.055, yy, zz)), Vector((-0.168, yy, zz))], 0.0024,
                                 segs=6, mat=m["steel"]))
    mag.append(geo.box("mag_floor", (0.006, 0.060, 0.034), (-0.170, 0.0, 0.0), m["brass"], bevel=0.0025))
    for k in range(7):
        x = -0.064 - k * 0.0158
        zz = 0.0042 if k % 2 == 0 else -0.0042
        mag.append(parts.carrot_part(f"mag_carrot{k}", 0.052, 0.0088, pos=(x, 0.026, zz), axis=(0, 1, 0),
                                     seed=200 + k, segs=8, rings=5, bumps=0.06, power=1.5))
    bpy.context.view_layer.update()     # orient() set loc/rot; refresh matrix_world before composing
    for o in mag:
        o.matrix_world = tilt @ o.matrix_world
    objs += mag
    # short carrot barrel shroud, twine lashing, steel barrel + slotted compensator
    BL = 0.205
    objs.append(geo.tube("barrel", 0.0075, 0.0048, BL - 0.055, 14, m["blued"]))
    objs[-1].location = (0, 0.055, 0)
    objs.append(parts.carrot_part("shroud", 0.15, 0.0195, pos=(0, 0.066 + 0.15, 0), axis=(0, 1, 0), seed=211,
                                  segs=16, rings=10, cut=0.30, power=2.0, bumps=0.04))
    objs.append(parts.band("shroud_collar", (0, 0.068, 0), (0, 1, 0), 0.0196, 0.008, m["brass"]))
    objs.append(parts.band("shroud_ferrule", (0, 0.168, 0), (0, 1, 0), 0.0122, 0.009, m["brass"]))
    objs.append(parts.twine_sleeve("shroud_twine", (0, 0.115, 0), (0, 1, 0), 0.0168, 0.014, rings=2))
    comp = [(0.0, 0.0048), (0.0, 0.0105), (0.003, 0.0112), (0.010, 0.0112), (0.011, 0.0085), (0.015, 0.0085),
            (0.016, 0.0112), (0.024, 0.0112), (0.026, 0.0095), (0.026, 0.0048)]
    c = geo.lathe("compensator", comp, segs=12, mat=m["steel"], cap0=False, cap1=True, sharp_angle=40)
    c.location = (0, BL - 0.026, 0)
    objs.append(c)
    # sights: brass peep at the back, post on the compensator (co-witnessed at SZ)
    SZ = 0.0345
    objs += peep("rear_peep", (0, -0.078, SZ), 0.0058, m["brass"], post=SZ - 0.0205 - 0.0058 + 0.001)
    objs.append(geo.box("front_post", (0.003, 0.004, SZ - 0.0105), (0, BL - 0.010, (SZ + 0.0105) / 2),
                        m["brass"], bevel=0.0007, segs=1))
    # pistol grip (pine, twine-wrapped), trigger + guard
    go = grip_outline((-0.012, -0.016), (-0.050, -0.016), (-0.030, -0.100), (-0.064, -0.094), belly=0.003,
                      palm=0.003)
    objs.append(geo.extrude_outline("grip", go, 0.030, m["pine_grip"], bevel=0.009, bevel_segs=2))
    objs.append(geo.box("grip_block", (0.026, 0.05, 0.012), (0, -0.030, -0.017), m["blued"], bevel=0.003))
    objs.append(parts.trigger("trigger", (0, 0.006, -0.021), 0.95))
    objs.append(parts.trigger_guard("guard", (0.030, -0.021), (-0.012, -0.036), 0.014))
    # folding wire stock: two rods, a bent butt loop, brass hinge, twine cheek wrap, leafy charm
    hinge = geo.cylinder("stock_hinge", 0.006, 0.026, 10, m["brass"], axis="X", bevel=0.0015)
    hinge.location = (0, -0.096, -0.004)
    objs.append(hinge)
    top = [Vector((0, -0.094, 0.010)), Vector((0, -0.17, 0.004)), Vector((0, -0.238, -0.001))]
    bot = [Vector((0, -0.094, -0.016)), Vector((0, -0.17, -0.042)), Vector((0, -0.238, -0.068))]
    objs.append(geo.sweep("stock_top", top, 0.0036, segs=6, mat=m["steel"]))
    objs.append(geo.sweep("stock_bot", bot, 0.0036, segs=6, mat=m["steel"]))
    loop = geo.chaikin([(-0.014, 0.004), (0.014, 0.004), (0.014, -0.074), (-0.014, -0.074)], 2)
    objs.append(geo.sweep("stock_butt", [Vector((x, -0.243, z)) for x, z in loop], 0.0038, segs=6,
                          mat=m["steel"], closed=True))
    objs.append(parts.twine_sleeve("cheek_wrap", top[1].lerp(top[2], 0.3), (top[2] - top[1]), 0.0036, 0.05,
                                   rings=3, thick=0.0034))
    objs.append(parts.greens("charm", (0.004, -0.205, -0.056), length=0.04, direction=(0.5, -0.4, 0.75), stems=2,
                             seed=31, pairs=2, lobes=2, spread=18, droop=0.25))
    objs += parts.knot("charm_knot", (0.004, -0.205, -0.056), 0.0045, seed=4, tail_dir=(0.3, 0.2, -1.0))

    grip = (0.0, -0.036, -0.058)
    markers = {
        "Muzzle": (0, BL, 0.0),
        "SupportGrip": (-0.030, 0.0, -0.002),
        "Sight": (0, -0.084, SZ),
        "Eject": (0.021, 0.004, 0.006),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Sten-style SMG; the open-frame magazine of baby carrots sticks out to the LEFT. "
                                "SupportGrip sits on the magazine well (Sten hold); Sight = rear peep centre, "
                                "front post co-witnessed."}}


# --------------------------------------------------------------------------- assault rifle

def build_carrot_rifle():
    """AK-style rifle: walnut furniture, bent-carrot banana magazine, greens front-sight tuft, reflex sight."""
    m = M()
    objs = []
    rc = [(-0.100, 0.016), (0.092, 0.016), (0.100, 0.010), (0.100, -0.024), (0.084, -0.030), (-0.088, -0.030),
          (-0.100, -0.020)]
    objs.append(geo.extrude_outline("receiver", geo.chaikin(rc, 1), 0.040, m["blued"], bevel=0.003))
    cover = geo.lathe("dust_cover", [(-0.098, 0.0), (-0.098, 0.016), (-0.094, 0.0195), (0.080, 0.0195),
                                     (0.090, 0.012), (0.091, 0.0)], segs=16, mat=m["blued"], sharp_angle=40)
    for v in cover.data.vertices:          # half-round lid: squash the lower half into the receiver
        if v.co.z < 0:
            v.co.z *= 0.2
    cover.location = (0, 0, 0.012)
    objs.append(cover)
    objs.append(geo.box("eject_port", (0.004, 0.055, 0.014), (0.0205, 0.020, 0.004), m["iron"], bevel=0.001,
                        segs=1))
    lever = [(0.0, 0.0), (0.03, 0.0), (0.05, -0.004), (0.054, -0.012), (0.05, -0.014), (0.03, -0.006), (0.0, -0.006)]
    sel = geo.extrude_outline("selector", lever, 0.003, m["steel"], offset=0.0215, bevel=0.0008, bevel_segs=1)
    sel.location = (0, -0.06, 0.008)
    objs.append(sel)
    objs.append(geo.tube("barrel", 0.0085, 0.0052, 0.34, 14, m["blued"]))
    objs[-1].location = (0, 0.095, 0)
    brake = [(0.0, 0.0052), (0.0, 0.0115), (0.004, 0.0122), (0.026, 0.0122), (0.030, 0.0105), (0.032, 0.0062),
             (0.032, 0.0052)]
    b = geo.lathe("brake", brake, segs=14, mat=m["steel"], cap0=False, cap1=False, sharp_angle=40)
    b.location = (0, 0.418, 0)
    objs.append(b)
    MUZ = 0.45
    # gas block + tube, walnut handguards with a twine wrap
    objs.append(geo.box("gas_block", (0.020, 0.024, 0.028), (0, 0.285, 0.010), m["blued"], bevel=0.003))
    objs.append(geo.sweep("gas_tube", [Vector((0, 0.098, 0.021)), Vector((0, 0.285, 0.021))], 0.0065, segs=10,
                          mat=m["blued"]))
    up = [(0.10, 0.015), (0.245, 0.015), (0.25, 0.022), (0.245, 0.032), (0.105, 0.034), (0.10, 0.026)]
    objs.append(geo.extrude_outline("upper_guard", geo.chaikin(up, 1, sharp=(0, 1)), 0.026, m["walnut"],
                                    bevel=0.006, bevel_segs=2))
    lo = [(0.10, 0.006), (0.255, 0.006), (0.262, -0.010), (0.255, -0.034), (0.22, -0.038), (0.19, -0.034),
          (0.16, -0.038), (0.13, -0.034), (0.10, -0.036)]
    objs.append(geo.extrude_outline("lower_guard", geo.chaikin(lo, 1, sharp=(0,)), 0.044, m["walnut"],
                                    bevel=0.010, bevel_segs=2))
    objs.append(parts.band("guard_cap", (0, 0.258, -0.006), (0, 1, 0), 0.0215, 0.010, m["blued"]))
    objs.append(parts.twine_sleeve("guard_twine", (0, 0.205, 0.002), (0, 1, 0), 0.0135, 0.016, rings=2))
    # front sight block with a carrot-greens tuft as the sight post
    FSZ = 0.050
    objs.append(geo.box("fs_block", (0.016, 0.022, 0.016), (0, 0.392, 0.009), m["blued"], bevel=0.003))
    ears_o = [(-0.008, 0.0), (0.008, 0.0), (0.008, 0.03), (0.005, 0.034), (0.005, 0.014), (-0.005, 0.014),
              (-0.005, 0.034), (-0.008, 0.03)]
    fe = geo.extrude_outline("fs_ears", ears_o, 0.010, m["blued"], plane="XZ", bevel=0.0012, bevel_segs=1)
    fe.location = (0, 0.392, 0.015)
    objs.append(fe)
    objs.append(geo.box("fs_post", (0.0028, 0.004, FSZ - 0.024), (0, 0.392, (FSZ + 0.024) / 2), m["brass"],
                        bevel=0.0006, segs=1))
    objs.append(parts.greens("sight_tuft", (0, 0.396, FSZ - 0.004), length=0.045, direction=(-0.15, -0.35, 1.0),
                             stems=3, seed=41, pairs=2, lobes=2, spread=26, droop=0.3))
    # reflex sight on the dust cover: brass tube, dark glass window, rail clamp
    RZ = FSZ
    refl = geo.tube("reflex", 0.0158, 0.0125, 0.034, 18, m["brass"])
    refl.location = (0, -0.040, RZ)
    objs.append(refl)
    lens = geo.cylinder("reflex_lens", 0.0127, 0.002, 18, glass(), axis="Y")
    lens.location = (0, -0.010, RZ)
    objs.append(lens)
    objs.append(geo.box("reflex_mount", (0.016, 0.030, RZ - 0.0158 - 0.030), (0, -0.023, (RZ - 0.0158 + 0.030) / 2),
                        m["blued"], bevel=0.002))
    objs.append(parts.screw("reflex_knob", (0.0165, -0.023, RZ), (1, 0, 0), 0.004, m["steel"]))
    # bent-carrot banana magazine out of a short well
    objs.append(geo.box("mag_well", (0.034, 0.050, 0.016), (0, 0.045, -0.036), m["blued"], bevel=0.003))
    L, R, BR = 0.175, 0.0235, 0.30
    mag = geo.carrot("magazine", L, R, segs=16, rings=12, mat=mats.carrot_skin(), seed=47, bumps=0.05, power=1.9,
                     tip_round=0.2)
    mag["bbd_uv"] = "src"
    geo.bend_yz(mag, BR)                # geo.carrot lays the carrot along +Y from its tip (y = 0)
    th = L / BR
    crown = Vector((0, BR * math.sin(th), BR * (1 - math.cos(th))))
    chord = crown.normalized()
    perp = (Vector((0, 0, 1)) - chord * chord.z).normalized()
    src = Matrix((Vector((1, 0, 0)), chord, perp)).transposed()
    # map the bent carrot so its crown sits in the well, the chord runs down/back and the
    # concave side faces forward (a banana magazine); X is mirrored to keep the rotation proper
    tgt = Matrix((Vector((-1, 0, 0)), Vector((0, -0.38, 1)).normalized(), Vector((0, 1, 0.38)).normalized())).transposed()
    rot = (tgt @ src.transposed()).to_4x4()
    mag.matrix_world = Matrix.Translation(Vector((0, 0.045, -0.040)) - (rot @ crown)) @ rot
    objs.append(mag)
    objs.append(parts.band("mag_collar", (0, 0.045, -0.047), (0, -0.35, -1), 0.0205, 0.012, m["brass"]))
    # pistol grip, trigger + guard, stock with steel butt plate and sling loop
    go = grip_outline((-0.050, -0.026), (-0.086, -0.026), (-0.068, -0.122), (-0.104, -0.112), belly=0.003, palm=0.004)
    objs.append(geo.extrude_outline("grip", go, 0.030, m["walnut_grip"], bevel=0.009, bevel_segs=2))
    objs.append(parts.trigger("trigger", (0, -0.022, -0.030)))
    objs.append(parts.trigger_guard("guard", (0.012, -0.030), (-0.044, -0.042), 0.017))
    st = [(-0.098, 0.012), (-0.20, 0.004), (-0.36, -0.010), (-0.368, -0.020), (-0.372, -0.112), (-0.355, -0.120),
          (-0.25, -0.092), (-0.15, -0.054), (-0.11, -0.036), (-0.098, -0.026)]
    objs.append(geo.extrude_outline("stock", geo.chaikin(st, 1, sharp=(2, 5)), 0.040, m["walnut"], bevel=0.009,
                                    bevel_segs=2))
    bp = [(-0.360, -0.008), (-0.373, -0.010), (-0.378, -0.060), (-0.377, -0.114), (-0.356, -0.122), (-0.368, -0.060)]
    objs.append(geo.extrude_outline("butt_plate", geo.chaikin(bp, 1), 0.040, m["steel"], bevel=0.004, bevel_segs=1))
    objs.append(geo.sweep("sling_loop", geo.arc_points((0, -0.30, -0.104), 0.008, 0, 360, 11, "YZ")[:-1], 0.0016,
                          segs=5, mat=m["steel"], closed=True))

    grip = (0.0, -0.077, -0.072)
    markers = {
        "Muzzle": (0, MUZ, 0.0),
        "SupportGrip": (0, 0.185, -0.022),
        "Sight": (0, -0.057, RZ),
        "Eject": (0.022, 0.020, 0.004),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Assault rifle; the banana magazine is a bent carrot. Sight = rear of the reflex "
                                "tube, co-witnessed with the front post under the greens tuft."}}


# --------------------------------------------------------------------------- sniper

def build_carrot_sniper():
    """"The Long Carrot": bolt-action sniper, long slim carrot barrel, brass scope, carrot-slice lens cap."""
    m = M()
    objs = []
    rec = geo.lathe("receiver", [(-0.082, 0.0), (-0.082, 0.010), (-0.076, 0.0165), (0.115, 0.0165),
                                 (0.122, 0.0135), (0.124, 0.0)], segs=18, mat=m["blued"], sharp_angle=40)
    objs.append(rec)
    objs.append(geo.box("eject_port", (0.004, 0.050, 0.013), (0.0155, 0.028, 0.005), m["iron"], bevel=0.001,
                        segs=1))
    # bolt: shroud at the back + handle sweeping down on the right with a brass knob
    objs.append(geo.lathe("bolt_shroud", [(-0.098, 0.0), (-0.098, 0.008), (-0.092, 0.0125), (-0.082, 0.0125)],
                          segs=14, mat=m["steel"], cap1=False, sharp_angle=40))
    bh = [Vector((0.012, -0.040, 0.006)), Vector((0.030, -0.042, 0.004)), Vector((0.044, -0.048, -0.008)),
          Vector((0.050, -0.054, -0.024))]
    objs.append(geo.sweep("bolt_handle", bh, 0.0042, segs=8, mat=m["steel"]))
    knob = geo.lathe("bolt_knob", [(-0.009, 0.0), (-0.007, 0.006), (0.0, 0.009), (0.007, 0.006), (0.009, 0.0)],
                     segs=12, mat=m["brass"], axis="Z")
    knob.location = (0.051, -0.055, -0.030)
    objs.append(knob)
    # long slim carrot barrel (bore liner pokes out at the muzzle), brass collar and bands
    CL = 0.86
    objs.append(geo.tube("barrel", 0.0066, 0.0042, 0.69, 12, m["blued"]))
    objs[-1].location = (0, 0.112, 0)
    objs.append(parts.carrot_part("barrel_carrot", CL, 0.0172, pos=(0, 0.126 + CL, 0), axis=(0, 1, 0), seed=301,
                                  segs=16, rings=16, cut=0.30, power=2.0, bumps=0.035, bend=0.0))
    cut_y = 0.126 + CL * 0.70
    objs.append(parts.band("carrot_collar", (0, 0.128, 0), (0, 1, 0), 0.0172, 0.010, m["brass"]))
    objs.append(parts.band("carrot_ferrule", (0, cut_y + 0.004, 0), (0, 1, 0), 0.0102, 0.012, m["brass"]))
    brake = [(0.0, 0.0042), (0.0, 0.0105), (0.003, 0.0110), (0.012, 0.0110), (0.013, 0.0080), (0.017, 0.0080),
             (0.018, 0.0110), (0.027, 0.0110), (0.029, 0.0090), (0.029, 0.0042)]
    b = geo.lathe("brake", brake, segs=12, mat=m["steel"], cap0=False, cap1=True, sharp_angle=40)
    b.location = (0, 0.772, 0)
    objs.append(b)
    MUZ = 0.801
    objs.append(parts.greens("wind_flag", (0, 0.735, 0.009), length=0.055, direction=(-0.35, -0.5, 0.8), stems=3,
                             seed=43, pairs=2, lobes=2, spread=18, droop=0.35))
    objs.append(parts.twine_sleeve("flag_twine", (0, 0.735, 0), (0, 1, 0), 0.0098, 0.010, rings=1))
    # walnut stock: long fore-end, wrist + pistol grip, raised cheek comb
    st = [(0.405, -0.006), (0.12, -0.006), (-0.076, -0.006), (-0.10, 0.004), (-0.16, 0.026), (-0.33, 0.030),
          (-0.356, 0.022), (-0.362, -0.020), (-0.366, -0.104), (-0.346, -0.112), (-0.24, -0.088), (-0.135, -0.062),
          (-0.108, -0.068), (-0.098, -0.118), (-0.064, -0.124), (-0.046, -0.086), (-0.030, -0.040), (0.05, -0.036),
          (0.36, -0.030), (0.405, -0.022)]

    def taper(a, b_):
        return 0.82 if a > 0.05 else 1.0
    objs.append(geo.extrude_outline("stock", geo.chaikin(st, 1, sharp=(0, 1, 2, 6, 19)), 0.042, m["walnut"],
                                    bevel=0.009, bevel_segs=2, taper=taper))
    pad = [(-0.356, 0.022), (-0.372, 0.020), (-0.378, -0.045), (-0.376, -0.110), (-0.348, -0.114), (-0.362, -0.045)]
    objs.append(geo.extrude_outline("butt_pad", geo.chaikin(pad, 1), 0.040, m["leather"], bevel=0.005, bevel_segs=1))
    objs.append(parts.band("forend_band", (0, 0.398, -0.003), (0, 1, 0), 0.0185, 0.010, m["brass"]))
    objs.append(parts.trigger("trigger", (0, -0.012, -0.034)))
    objs.append(parts.trigger_guard("guard", (0.020, -0.036), (-0.040, -0.050), 0.016))
    # scope: brass tube, objective + eyepiece bells, turrets, steel rings, glass, leather eyecup
    SZ = 0.064
    tube = geo.lathe("scope", [(-0.112, 0.0195), (-0.098, 0.0195), (-0.088, 0.0155), (0.168, 0.0155),
                               (0.192, 0.0235), (0.246, 0.0245), (0.250, 0.0228), (0.250, 0.0205), (0.244, 0.0205)],
                     segs=24, mat=m["brass"], cap0=False, cap1=False, sharp_angle=40)
    tube.location = (0, 0, SZ)
    objs.append(tube)
    cup = geo.lathe("eyecup", [(-0.150, 0.0175), (-0.150, 0.0215), (-0.144, 0.0225), (-0.112, 0.0205),
                               (-0.110, 0.0185)], segs=20, mat=m["leather"], cap0=False, cap1=False, sharp_angle=40)
    cup.location = (0, 0, SZ)
    objs.append(cup)
    for nm, y, r in (("lens_front", 0.245, 0.0207), ("lens_rear", -0.146, 0.0178)):
        ln = geo.cylinder(nm, r, 0.002, 20, glass(), axis="Y")
        ln.location = (0, y, SZ)
        objs.append(ln)
    for nm, ax, pos in (("turret_top", "Z", (0, 0.035, SZ + 0.0155)), ("turret_side", "X", (0.0155, 0.035, SZ))):
        t = geo.lathe(nm, [(0.0, 0.0105), (0.010, 0.0105), (0.011, 0.0095), (0.019, 0.0095), (0.020, 0.0)], segs=14,
                      mat=m["steel"], axis=ax, sharp_angle=40)
        t.location = pos
        objs.append(t)
    for k, y in enumerate((-0.045, 0.105)):
        objs.append(parts.band(f"ring{k}", (0, y, SZ), (0, 1, 0), 0.0158, 0.012, m["blued"], segs=18))
        objs.append(geo.box(f"ring_base{k}", (0.016, 0.012, SZ - 0.0158 - 0.012), (0, y, (SZ - 0.0158 + 0.012) / 2),
                            m["blued"], bevel=0.002))
    # flip-up lens cap: a carrot slice hinged on top of the objective
    # (leaning ~35 deg forward so the shooter sees the cut face with its pale core)
    hinge = Vector((0, 0.252, SZ + 0.0245))
    objs.append(geo.cylinder("cap_hinge", 0.003, 0.012, 8, m["brass"], axis="X"))
    objs[-1].location = hinge
    lean = math.radians(35)
    objs.append(carrot_coin("lens_cap", 0.0255, 0.007,
                            hinge + Vector((0, math.sin(lean) * 0.026, math.cos(lean) * 0.026)),
                            axis=(0, math.cos(lean), -math.sin(lean))))
    # folded bipod under the fore-end + slack leather sling
    objs.append(parts.band("bipod_clamp", (0, 0.36, -0.016), (0, 1, 0), 0.020, 0.012, m["blued"]))
    for sx in (1, -1):
        leg = [Vector((sx * 0.010, 0.358, -0.034)), Vector((sx * 0.014, 0.28, -0.044)),
               Vector((sx * 0.016, 0.20, -0.047))]
        objs.append(geo.sweep(f"bipod{sx}", leg, 0.0042, segs=6, mat=m["blued"]))
        objs.append(parts.rivet(f"bipod_foot{sx}", (sx * 0.016, 0.196, -0.048), (0, -1, 0), 0.0065, m["brass"]))
    for y, z in ((0.33, -0.037), (-0.26, -0.096)):
        objs.append(geo.sweep(f"swivel{y}", geo.arc_points((0, y, z - 0.006), 0.006, 0, 360, 9, "YZ")[:-1], 0.0014,
                              segs=5, mat=m["steel"], closed=True))
    sl = [Vector((0, 0.33, -0.048)), Vector((0, 0.22, -0.11)), Vector((0, 0.05, -0.15)), Vector((0, -0.12, -0.15)),
          Vector((0, -0.22, -0.125)), Vector((0, -0.26, -0.107))]
    objs.append(geo.sweep("sling", sl, 0.011, segs=8, mat=m["leather"], flatten=0.2, up=(1, 0, 0)))

    grip = (0.0, -0.075, -0.088)
    markers = {
        "Muzzle": (0, MUZ, 0.0),
        "SupportGrip": (0, 0.26, -0.030),
        "Sight": (0, -0.156, SZ),
        "Eject": (0.018, 0.028, 0.006),
    }
    markers = shift(objs, markers, grip)
    return {"objects": objs, "markers": markers,
            "report": {"notes": "Bolt-action sniper. Sight = just behind the scope eyepiece on the scope axis "
                                "(ADS looks through the scope, 0.064 m above the bore). The carrot-slice lens cap "
                                "is flipped up and clear of the view."}}


ASSETS = {
    "carrot_pistol": dict(build=build_carrot_pistol, out="weapons", tex=1024, kind="weapon", target=0.28,
                          use="Sidearm: six-shot carrot revolver"),
    "carrot_shotgun": dict(build=build_carrot_shotgun, out="weapons", tex=1024, kind="weapon", target=0.75,
                           use="Shotgun: side-by-side coach gun firing carrot_shell_pellet spreads"),
    "carrot_lmg": dict(build=build_carrot_lmg, out="weapons", tex=1024, kind="weapon", target=0.9,
                       use="Light machine gun: pan-fed baby-carrot bolts"),
    "carrot_smg": dict(build=build_carrot_smg, out="weapons", tex=1024, kind="weapon", target=0.45,
                       use="Submachine gun: side magazine of baby carrots, folding wire stock"),
    "carrot_rifle": dict(build=build_carrot_rifle, out="weapons", tex=1024, kind="weapon", target=0.8,
                         use="Assault rifle: bent-carrot banana magazine, greens front sight, reflex sight"),
    "carrot_sniper": dict(build=build_carrot_sniper, out="weapons", tex=1024, kind="weapon", target=1.15,
                          use="Sniper rifle 'The Long Carrot': bolt action, brass scope (ADS through the scope)"),
    "carrot_rocket_launcher": dict(build=build_carrot_rocket_launcher, out="weapons", tex=1024, kind="weapon",
                                   target=1.0, use="Rocket launcher firing carrot_rocket"),
}
