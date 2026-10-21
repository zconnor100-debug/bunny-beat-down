# tools/env — forest-island environment kit pipeline

Builds everything under `assets/env/`, `assets/textures/`, `assets/sky/` and
`assets/credits/environment.json` from CC0 / CC-BY sources, following
`docs/ASSET_PIPELINE.md`. Every step is a re-runnable script; raw downloads go
to `tools/_cache/env/` (git-ignored, one folder per source asset).

## Pipeline

```bash
# 1. download sources (idempotent, md5-checked where the API provides it)
python3 -I tools/env/polyhaven_fetch.py model fern_02 boulder_01 ...      # glTF @2k + alpha masks
python3 -I tools/env/polyhaven_fetch.py texture forest_leaves_02 ...      # terrain / bark textures
python3 -I tools/env/polyhaven_fetch.py hdri kloofendal_48d_partly_cloudy_puresky ...
python3 -I tools/env/ambientcg_fetch.py Grass004 Moss002
python3 -I tools/env/sketchfab_api.py download <uid> tools/_cache/env/sf_<uid>

# 2. models -> assets/env/<id>/<id>.glb + assets/env/manifest.json
blender --background --factory-startup --python tools/env/process_models.py -- [ids...]

# 3. terrain layers, water normal map, sky HDRIs
python3 -I tools/env/build_textures.py

# 4. credits -> assets/credits/environment.json
python3 -I tools/env/build_credits.py

# 5. verification
blender --background --factory-startup --python tools/env/render_previews.py -- [ids...]
python3 -I tools/env/make_preview_sheet.py          # -> assets/env/preview_sheet.png
python3 -I tools/env/glb_info.py assets/env/*/*.glb  # what the exporter really wrote
tools/env/godot_check.sh                             # throwaway Godot project import + AABB check
# critter's-eye screenshots rendered by Godot itself (needs a display; throwaway project only)
cp tools/env/godot_eyelevel.gd /tmp/bbd-envcheck/ && \
  godot4 --path /tmp/bbd-envcheck --resolution 960x540 -s res://godot_eyelevel.gd -- stump_a boulder_big tree_oak_a@top
```

## Files

| file | what it does |
|---|---|
| `env_recipes.json` | **The recipe book.** One line per game asset: source (`ph:<polyhaven id>`, `sf:<sketchfab uid>`, `gen:<generator>`), which sub-objects to keep, in-game size (`height_m` or `scale`), ground handling, triangle budget, texture cap, alpha mode and the manifest fields. `"enabled": false` keeps a vetted alternative without shipping it. |
| `process_models.py` | Blender: import → flatten hierarchy → select → join/duplicate → scale/ground/centre → decimate → rebuild textures → alpha-clip → export GLB; updates the manifest and a build record per asset. |
| `hollow_log.py` | Blender generator for the walk-through hollow log (procedural mesh, Poly Haven CC0 textures). |
| `texconv.py` | Pillow texture jobs: resize (Lanczos), 16→8 bit, alpha-mask merge, alpha bleeding (push-pull) for cut-out foliage, ORM packing. |
| `build_textures.py` | Terrain layers (`albedo.jpg`, `normal.png` OpenGL/+Y, `roughness.jpg`, `ao.jpg`, `height.jpg`), procedural tileable water normal map, HDRI copies. |
| `build_credits.py` | Credits JSON from recipes + build records + download metadata; refuses non-allowed licenses and missing files. |
| `render_previews.py`, `make_preview_sheet.py` | Cycles scale-check renders next to a 1 m capsule critter, assembled into `assets/env/preview_sheet.png`. |
| `godot_eyelevel.gd` | Godot-rendered close-ups: camera 1 m high, 4 m away, sun + sky (`id@top` = overview) → `/tmp/bbd-eyelevel/`. |
| `godot_check.sh`, `godot_check.gd` | Copies assets into `/tmp/bbd-envcheck`, imports headless, loads every GLB/texture/HDRI and compares AABBs with the manifest. |
| `polyhaven_fetch.py`, `ambientcg_fetch.py`, `sketchfab_api.py` | Source downloaders (the Sketchfab one only ever returns CC0 / CC-BY models; the token is read from `~/.config/sketchfab/token` and never printed). `thumbs` sub-commands make contact sheets for choosing assets by eye. |
| `inspect_source.py`, `glb_info.py` | Inspection helpers (source sub-objects/materials; exported GLB contents). |

## Scan quality notes (from the eye-level QA pass)

* **Decimation** welds glTF's split UV-seam vertices *before* collapsing. Collapsing an un-welded
  scan treats every UV seam as a border and opens cracks you can see the sky through.
* **Normal re-bake**: when a scan keeps < 60 % of its triangles (or `"bake_normals": true`), the
  full-detail source is baked onto the decimated mesh (Cycles, selected-to-active, tangent space)
  and the GLB is exported with tangents. The source normal map no longer matches the coarser mesh.
* **Hero scans** use Poly Haven's 4K/8K glTF (`"ph_res"`) with ~40k-triangle budgets, so the textures
  are downsampled from more detail. Rock sets share one atlas, so `"uv_crop": true` crops it to the
  region the kept rock uses (2048² colour instead of ~700² effective).
* **Tree bark**: `"retexture"` swaps the packs' soft 512×1024 bark for Poly Haven photo bark
  (jolcham_oak_bark_01, pine_bark, bark_willow_02), resampled to the original 1:2 UV aspect.
* All textures are resampled to power-of-two sides for GPU block compression.
* **Trees** (`"prune"`): stylised root claws and branches starting below 6.5 m are removed, and
  foliage cards below 7.5 m are removed (≥ 6 m even at the 0.8 minimum instance scale). Cards
  whose nearest branch was removed go too. The tree is then re-centred on its trunk axis, so the
  origin-centred collision cylinder matches the trunk, and re-grounded at `sink_m`.

## Conventions (see docs/ASSET_PIPELINE.md)

* Critter-world metres: a critter is ~1 m tall; nature is scaled ~4–8× (giant trees 60–115 m).
* GLB: +Y up, transforms applied, one mesh node named after the asset, base at y = 0 and
  footprint centred on the origin. Where a model is meant to sit *in* the ground (scanned
  rocks, stumps, trees with a flat trunk end) its buried part goes below y = 0 and the depth is
  recorded as `sink_m` in the manifest, so the game can place the origin on the terrain surface.
* Textures ≤ 2048 px: JPEG colour and ORM, PNG normal maps, RGBA PNG for cut-out foliage.
  Foliage uses glTF `alphaMode: MASK` (Godot imports it as alpha scissor) and is double-sided.
* Extra manifest fields beyond the contract: `sink_m`, `tris`. Extra categories requested by the
  lead dev: `cottage` (critter homes used as cover) and `cover` (low crouch-height cover props).
* `"level": true` rotates a scan so its captured ground patch is horizontal (sloped scans otherwise
  float on one side once grounded at their lowest vertex).

## Godot import note

Godot 4.6's default glTF import setting (`gltf/embedded_image_handling = Extract Textures`)
writes a copy of every texture embedded in a GLB next to it (`assets/env/<id>/<id>_<id>_albedo0.jpg`
etc., roughly doubling `assets/env/` on disk). Those copies are regenerated on every import, so
either git-ignore `assets/env/*/*.png` and `assets/env/*/*.jpg` (only GLBs live in the per-asset
folders) or switch the scene importer default to embedded images.
