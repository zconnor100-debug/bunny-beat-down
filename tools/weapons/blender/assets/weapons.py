"""Carrot guns: pistol, shotgun, LMG, rocket launcher.

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

from mathutils import Vector

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


ASSETS = {
    "carrot_pistol": dict(build=build_carrot_pistol, out="weapons", tex=1024, kind="weapon", target=0.28,
                          use="Sidearm: six-shot carrot revolver"),
    "carrot_shotgun": dict(build=build_carrot_shotgun, out="weapons", tex=1024, kind="weapon", target=0.75,
                           use="Shotgun: side-by-side coach gun firing carrot_shell_pellet spreads"),
    "carrot_lmg": dict(build=build_carrot_lmg, out="weapons", tex=1024, kind="weapon", target=0.9,
                       use="Light machine gun: pan-fed baby-carrot bolts"),
    "carrot_rocket_launcher": dict(build=build_carrot_rocket_launcher, out="weapons", tex=1024, kind="weapon",
                                   target=1.0, use="Rocket launcher firing carrot_rocket"),
}
