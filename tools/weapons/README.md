# Weapons & props generator

Every carrot gun, projectile, pickup, crate, the acorn helmet, the dandelion
glider and the dropship balloon in `assets/weapons/` and `assets/props/` is
**generated from code**: Blender Python builds the geometry, scripted materials
sample real CC0 / CC-BY scans, Cycles bakes everything into one PBR atlas per
asset and the result is exported as glTF. Nothing is hand-modelled, so any
asset can be rebuilt, tweaked or re-themed by editing a few numbers.

```
python3 tools/weapons/build_all.py                   # rebuild everything (~3 min on a GPU)
python3 tools/weapons/build_all.py --only carrot_lmg # one asset (+ its preview tiles)
python3 tools/weapons/build_all.py --godot           # ... and run the Godot import check
```

Requirements: Blender 5.x (`/snap/bin/blender`, override with `--blender`),
system Python 3 with Pillow, network access for the first run, a Sketchfab API
token in `~/.config/sketchfab/token` (only to download the two scans), and
optionally `~/bin/godot4` for the import check.

## Pipeline

| step | file | what it does |
|---|---|---|
| 1 | `fetch_sources.py` + `sources.json` | Downloads the Poly Haven CC0 textures/HDRI and the Sketchfab scans into `tools/_cache/weapons/` (git-ignored) and records title / author / licence for the credits. Sketchfab licences are re-checked at download time; only CC0 and CC BY pass. |
| 2 | `blender/prep_scans.py` | **Re-skins the photoscans.** Scan atlases are fragmented, so each scan is unwrapped instead: PCA finds the symmetry axis, a surface of revolution is fitted just inside the scan (following its bend), and Cycles bakes scan -> proxy into clean cylindrical strips (u = around, v = crown -> tip). Normals are high-passed, holes push-pull filled, the carrot colour calibrated. Output: `carrot_skin_*`, `acorn_strip_*`, `tulip_strip_*` in `_cache/weapons/derived/`. Flat things (leaves, a mushroom cap) get a **planar re-skin** instead: the scan is baked orthographically onto a plane above it into colour + alpha + high-passed normal (`maple_leaf_*`, `oak_leaf_*`, `parasol_cap_*`); the daisy head is cut out of an ambientCG (CC0) flower atlas. |
| 3 | `blender/build_asset.py` | Runs one builder from `blender/assets/`, then `bbd/bake.py`: seeds an `atlas` UV (clean lathe UVs or smart-project), normalises texel density (with optional per-part emphasis), joins parts per output node, packs, and bakes base colour / roughness / metallic (via emission re-routing) + tangent normals + AO on the GPU. numpy composes albedo, ORM (R=AO, G=rough, B=metal) and normal maps; a single material replaces the source materials; named empties are added; `.glb` exported. A JSON report (tris, bounds, markers in Godot axes, sources used) goes to `_cache/weapons/build/`. |
| 4 | `blender/render_preview.py`, `compose_sheet.py` | Imports the **exported** glbs (so previews show exactly what ships), renders a scale shot next to a 1 m capsule plus a turnaround, and composes `preview_sheet.png` cards; `--hero` renders the acorn helmet close-up. |
| 5 | `build_all.py` | Writes `assets/props/manifest.json` and `assets/credits/weapons_props.json` from the reports, so manifest and credits always match what was built. |
| 4b | `blender/fit_helmet.py` | Puts the exported `acorn_helmet.glb` on the real `assets/characters/bun/bun.glb` exactly like the game (origin at bun model space (0, 0.875, -0.010), upright, scale 1), densely samples the bun's skull and ears, reports any sample inside the helmet solid (`acorn_helmet_fit.json`, also copied into the manifest) and renders front / side / 3/4 views for the close-up sheet. |
| 6 | `godot_check.py`, `godot/check_glbs.gd` | Copies the glbs into a throwaway project at `/tmp/bbd-propcheck`, imports them headless and prints AABBs, triangle counts, marker positions and material flags. Never touches the real project. |

## Code map

```
blender/bbd/util.py       scene helpers, paths, Blender -> Godot axis conversion
blender/bbd/geo.py        lathe, sweep (parallel-transport tubes), extruded outlines,
                          chaikin curves, carrots, carrot greens, pinnate leaves
blender/bbd/mats.py       bake-source materials: wood, metal, chipped paint (+stencil),
                          twine, leather, bark, burlap, fabric with seams, wicker weave,
                          carrot skin/flesh, acorn shell/cap/scales, clover, alpha cards
blender/bbd/parts.py      gunsmith parts: twine sleeves & knots, bands, rivets, screws,
                          sights, triggers, guards, carrot sections, leafy sprigs
blender/bbd/plants.py     dandelion pappus parachutes, achene seeds, clovers, flowers
blender/bbd/textures.py   code-generated textures (crate stencil, pappus bristle)
blender/bbd/bake.py       atlas UVs, channel bakes, final material, glTF export, report
blender/assets/*.py       one builder per asset + the ASSETS registry (id, folder,
                          atlas size, intended use)
```

## Conventions (see `docs/ASSET_PIPELINE.md`)

Builders work in Blender space: **+Y forward, +Z up, metres**, which exports to
Godot as forward **-Z**, up **+Y**.

* Weapons: origin at the trigger grip, barrel along -Z. Empties `Muzzle`,
  `SupportGrip`, `Sight` (eye point on the sight line), `Eject`. The rocket
  launcher's loaded rocket is a separate `Rocket` node (hide after firing).
* Projectiles: origin at the centre, tip toward -Z; `Trail` marks the rear.
* Props: origin at the bottom centre, front toward +Z. `loot_crate` and
  `supply_drop` have a `Lid` node pivoting on the back hinge (open with a
  negative X rotation); `supply_drop` has a `Chute` node.
* `acorn_helmet`: fitted to `bun` - the game puts its origin at bun model
  space (0, 0.875, -0.010), upright (opening -Y, front +Z), scale 1. The bowl
  hugs bun's measured cranium sphere (+1.5 cm), is tipped back 15 deg so the
  brim clears the eyes and the forehead tuft peeks out, and the ear slots
  follow the `DEF_Ear_1 -> DEF_Ear_2` bone lines; `EarHole_L/R` mark their
  centres. Fit constants live at the top of `blender/assets/helmet.py`.
* `dandelion_glider`: origin at the hand grip, `Hand_L/R` IK targets.
* `dropship_balloon`: origin at the basket floor centre, flies toward -Z,
  `Burner` (flame VFX) and `Exit` (jump point) markers.
* `treasure_chest`, `treasure_chest_golden`: origin at the bottom centre, front
  +Z, `Lid` node on the back hinge (X towards -110 deg opens) and a
  `LootSpawn` marker just above the open box.
* `glider_*` (dandelion plume, oak leaf, maple leaf, tulip, daisy, mushroom):
  1.7-2.4 m canopies, origin at the hand grip with `Hand_L/R`; thin canopies
  use two-sided alpha-scissor materials made from the scans (not baked).

Budgets: guns <= 8k triangles, bolt/pellet <= 600, rocket <= 2k; 1024 px atlases
for weapons/props, 512 px for small pickups and projectiles, 2048 px for the
14 m balloon. Baked materials are single-sided; thin leaves are modelled
two-sided; only the pappus uses an alpha-scissor texture.

## Adding an asset

Write a `build_<id>()` in `blender/assets/` that returns
`{"objects": [...], "markers": {...}, "pivots": {...}, "report": {"notes": ...}}`
(parts may set `bbd_node`, `bbd_uv="src"`, `bbd_bake=False`, `bbd_texel`), add it
to that module's `ASSETS` dict, and list it in `WEAPON_SHEET` / `PROP_SHEET` in
`build_all.py`. Any new third-party input goes into `sources.json` first.
