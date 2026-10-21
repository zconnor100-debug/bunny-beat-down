# Character pipeline (`tools/characters/`)

Turns third-party Sketchfab characters into game-ready critters that follow the
character contract in [`docs/ASSET_PIPELINE.md`](../../docs/ASSET_PIPELINE.md):
one skinned mesh + one armature per GLB, facing +Z, +Y up, metres, soles on
y = 0, top of the skull at the species' `head_top`, <= 20k triangles,
textures <= 2048 px (JPEG colour, PNG normal maps), Godot-safe bone names, and
a `<id>.rig.json` with bone roles, spring-bone chains, ragdoll radii and eye
height.

Everything is driven by **`roster.json`** (one recipe per character) and is
re-runnable from the raw downloads.

## Quick start

```bash
tools/characters/build_all.sh            # whole roster (or: build_all.sh fox frog)
tools/characters/godot_check.sh          # import + verify in a throwaway Godot project
```

Requirements: Blender 5.x (`/snap/bin/blender`, override with `BLENDER=`),
python3 (stdlib only for the non-Blender scripts), a Sketchfab API token in
`~/.config/sketchfab/token` for downloads. Raw downloads live in
`tools/_cache/characters/<id>/` (git-ignored).

## Scripts

| script | runs in | what it does |
|---|---|---|
| `sketchfab_fetch.py` | python3 | `search` (rigged + downloadable, CC-BY/CC0 only), `info`, `fetch <uid> <id>`: downloads the GLB and stores the API record (`meta.json`) used for credits. Refuses non-CC-BY/CC0 licenses. The token is only sent to `api.sketchfab.com`, never printed or written. |
| `inspect_model.py` | Blender | dumps objects, the bone tree (rest/pose heads), meshes, materials, clips and `--weights` (which bones actually deform vertices) - used to write a recipe. |
| `gltf_bind.py` | python3 / Blender | GLB reader/writer and `rewrite_rest_to_bind()`: rebuilds the rest pose from the skin's inverse bind matrices (see below). |
| `normalize.py` | Blender | the pipeline proper: `blender --background --python tools/characters/normalize.py -- <id>` |
| `render_preview.py` | Blender | front + side orthographic preview on a metre grid with head_top (green) and eye_height (blue) markers. `--head` close-up with a 1 cm grid, `--anim NAME --frame F` poses a baked clip, `--source --noguess` for raw downloads. |
| `render_lineup.py` | Blender | all characters side by side at true relative scale -> `assets/characters/lineup.png`. |
| `write_credits.py` | python3 | writes `assets/credits/characters.json` from the cached API metadata + the roster's `used_for` / `changes` text. |
| `godot_check.sh` / `godot_check.gd` | Godot 4 | copies the GLBs into `/tmp/bbd-charcheck`, imports them headless and checks every rig.json bone exists in the `Skeleton3D`. Never touches the real project's import cache. |
| `skin_maps.py` | Blender (numpy) | texture-space maps of a GLB: rasterizes every material's triangles into its albedo texture so each texel knows its triangle, UV island, dominant bone, 3D rest position and vertex colour; OKLab colour conversion. |
| `make_skins.py` | Blender | recoloured skin variants from `skins_recipe.json` -> `assets/characters/<id>/skins/*.jpg` + `skins.json`. `--debug DIR` writes region masks, `--only a,b` rebuilds some skins. |
| `render_skins.py` | Blender | every skin of every character (front and back three-quarter), swapping albedo textures by material name like the game -> `assets/characters/skins_lineup.png`. `--head` for close-ups. |
| `build_all.sh` | bash | fetch (if missing) -> normalize -> skins -> previews -> lineups -> credits. |

## What `normalize.py` does

1. **Import.** `rest_from: "node"` uses the file's node pose as the rest pose.
   `rest_from: "bind"` first rewrites the GLB so every joint sits in its *bind*
   pose (inverse of its inverse bind matrix) - Sketchfab re-exports often store
   an animation frame (walk cycle, hunched idle) as the node pose while the
   mesh was skinned in a clean T-pose. Joints whose bind matrices are
   degenerate (IK targets, poles, helpers) keep their file pose. The global
   frame of the bind pose is snapped to the nearest axis-aligned frame so file
   unit/axis conversions survive but the anchor joint's own pose does not.
2. **Record clips** listed in the recipe as world-space bone matrices while the
   file's node hierarchy is intact (a clip can animate the armature *and* its
   parent empties - one action slot per object).
3. **Clean up**: keep the armature and the meshes it deforms, skin rigid parts
   (e.g. separate eye meshes) 100 % to a bone, drop props and Sketchfab helper
   nodes, join into one mesh.
4. **Rig surgery**: `reparent` (e.g. IK-rig hands back under the forearms),
   `split` (one bone -> two, weights blended with a smoothstep along the bone,
   so every limb has upper/lower segments), prune bones that deform nothing and
   aren't referenced, rename to Godot-safe unique names (Sketchfab's `_NN`
   suffix dropped, `.` / `:` -> `_`).
5. **Orient and scale**: yaw from the shoulder + hip axis (right -> left must
   be +X, i.e. the character faces -Y in Blender = +Z in glTF), cross-checked
   against the toes; scale so the top of the skull (head-bone vertices, minus
   ear/hat bones, optionally a centre column to skip ear tufts or horns) is at
   `head_top`; soles on the ground, centred between the feet; transforms applied.
6. **Budget**: decimate above 20k triangles (none of the current roster needs
   it), 4 skin influences per vertex, textures <= 2048 px, colour maps
   re-encoded as JPEG (normal maps / alpha stay PNG), unused vertex colours dropped.
7. **Re-bake clips** from the recorded world matrices onto the cleaned rig
   (handles re-parented, split and removed bones) and export one glTF
   animation per clip.
8. **Measure and export**: per-role ragdoll radius (median distance from the
   bone segment to the vertices that belong to it), eye height, rest pose
   (T if the upper arm is < 25 deg below horizontal, else A), head size; write
   `<id>.glb` and `<id>.rig.json`.

## Skin variants

The player picks species + skin; AI critters get a random one. Each skin is a
recoloured copy of the albedo texture(s); geometry, UVs and the other maps are
shared. `assets/characters/<id>/skins.json`:

```json
[{"id": "default", "name": "Classic"},
 {"id": "snowshoe", "name": "Snowshoe", "albedo": {"Base": "skins/snowshoe_albedo.jpg"}}]
```

Keys of `albedo` are material names exactly as Godot imports them
(`StandardMaterial3D.resource_name`); paths are relative to the character
folder. Materials a skin doesn't list keep the GLB's texture. The game swaps
`albedo_texture` on a duplicated material (`godot_check.gd` does exactly that).

How `make_skins.py` recolours (recipe: `skins_recipe.json`):

* **Regions** pick texels by material, dominant bone (regex), 3D rest position,
  colour in OKLCh (lightness / chroma / hue ranges) and 3D procedural patterns
  (`noise` for warts, `blob` for a Dutch-rabbit blaze, `stripes` for plaid).
  Selectors are soft and regions are claimed in order, so `keep_*` regions
  (eyes, mouths, noses, pink paws) listed first are never recoloured.
* **Skins** move each region's mean OKLab colour to a target (absolute `L`/`C`/`h`
  or relative `dL`/`Cs`/`dh`) while every texel keeps its offset from that mean:
  lightness offsets scaled by the available headroom, colour offsets rotated
  with the hue. Painted shading, fur strands, folds and texture noise survive.
  Regions driven by the same key (`"fur*"`) share statistics, so they land on
  one tone without seams.
* UV-island bleed padding is refilled from the nearest recoloured texel, so
  mip-maps don't show the old colour at seams.
* The bandit bunny's material multiplies its vertex colours (baked AO) into
  the albedo; skins only change the texture, so that shading still applies.

To add a skin: add regions if needed (check them with `--debug`), add an entry
to the character's `skins` list, run `make_skins.py <id>`, look at
`render_skins.py` output, then `godot_check.sh`.

## Adding a character

1. `python3 tools/characters/sketchfab_fetch.py search "badger"` - pick a
   CC-BY/CC0, rigged, bipedal, original (no third-party IP, no ripped game
   assets: check the uploader's other models) model.
2. `python3 tools/characters/sketchfab_fetch.py fetch <uid> <id>`
3. Inspect: `blender -b -P tools/characters/inspect_model.py -- tools/_cache/characters/<id>/source.glb --noguess --weights --pose`
   and render `render_preview.py ... --source --noguess` to look at it.
4. Add a recipe to `roster.json` (roles, chains, skull, eye, animations,
   reparent/split if the rig needs it, used_for/changes for credits).
5. `tools/characters/build_all.sh <id>`, look at `preview.png` (and a
   `--head` close-up to read the eye height), then `godot_check.sh`.

## Conventions the game can rely on

* Character faces **+Z**, **+Y** up, **left = +X**; soles at y = 0.
* Bone local **+Y points along the bone towards its child** (Blender convention,
  verified in Godot by `godot_check.gd`).
* `rig.json` bone names are exactly the `Skeleton3D` bone names.
* `radii` are medians (typical surface distance), not maxima - size capsules
  a little larger for hit boxes.
