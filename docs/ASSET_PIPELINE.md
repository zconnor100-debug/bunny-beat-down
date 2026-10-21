# Asset pipeline & contracts

Bunny Beat Down mixes third-party models (Sketchfab CC-BY / CC0, Poly Haven CC0),
custom Blender-scripted models, and procedural code. Every file that ships in
`assets/` must be **license-clean and credited**. This document is the contract
between the asset tools (`tools/`) and the game code (`src/`).

## Art direction

*"Grounded meets Saturday-morning cartoon."* Stylized, expressive woodland
critters (~1 m tall in game units) fight in a lush, believably-lit forest seen
from critter height: grass clumps up to your shoulders, mushrooms you can hide
under, fallen logs like walls, trees whose trunks are as wide as a house.

* World unit = 1 metre **at critter scale**. A critter's head-top is ~0.85–1.2 m.
* Real-world nature assets are therefore scaled up ~4–8× (a 20 m tree → 80–150 m).
* Lighting is PBR with real shadows; particles are billboarded soft blobs, never
  flat quads.
* Gore is cartoon-anatomical: red blood, fluff/fur tufts, limbs that pop off.
  It is always behind the in-game *Gore* setting (Full / Fluff-only / Off).

## Licensing rules (hard requirements)

1. Allowed licenses: **CC0**, **CC-BY 3.0/4.0**. Nothing else (no CC-BY-NC,
   no CC-BY-SA, no "free for personal use", no Mixamo, no ripped game assets).
2. **No third-party IP characters** (Sonic, Disney, Nintendo, Five Nights at
   Freddy's, Marvel, etc.) even if uploaded under CC-BY — the uploader does not
   own those rights.
3. Every asset — including CC0 ones — gets a credits entry (see below). CC-BY
   requires title, author, source link, license link and a description of the
   changes we made; we record all of that.

## Credits entries

Each asset area writes its own JSON file in `assets/credits/` (e.g.
`characters.json`, `environment.json`, `weapons_props.json`, `audio.json`).
`tools/gen_credits.py` renders them into `CREDITS.md`, and the in-game
**Credits** screen (main menu → Credits) reads the same JSON at runtime, so the
two can never disagree.

```json
[
  {
    "asset": "Bunny Guard Ranger",
    "author": "Arcnay",
    "author_url": "https://sketchfab.com/Arcnay",
    "source_url": "https://sketchfab.com/3d-models/<slug>-<uid>",
    "license": "CC BY 4.0",
    "license_url": "https://creativecommons.org/licenses/by/4.0/",
    "changes": "Rescaled, re-oriented, added ear/tail bones, textures resized to 2K",
    "used_for": "Player character",
    "files": ["assets/characters/bun/bun.glb"]
  }
]
```

`license` is one of `"CC0 1.0"`, `"CC BY 4.0"`, `"CC BY 3.0"`. Original work
made for this project (Blender-scripted models, synthesized audio) is listed with
`"author": "Bunny Beat Down project"`, `"license": "MIT (project)"` so the credits
page shows it too.

## Characters — `assets/characters/<id>/`

| file | purpose |
|---|---|
| `<id>.glb` | normalized, skinned model |
| `<id>.rig.json` | bone-role map + ragdoll sizes |
| `preview.png` | front + side render used to verify orientation/scale |

Normalization (done in Blender by `tools/characters/`):

* glTF/Godot axes: +Y up, **character faces +Z** (Blender −Y), metres.
* Soles of the feet at y = 0, centred in x/z between the feet.
* Armature object transform applied (location 0, rotation 0, scale 1); mesh
  transforms applied; one Armature, as few skinned meshes as possible, no stray
  cameras/lights/empties.
* Scaled so the **top of the skull** (not ears, not hats) is at the species'
  `head_top` height: bun 0.95, bandit bunny 0.95, squirrel 0.9, fox 1.15,
  raccoon 1.05, frog 0.85, badger 1.1, others ~1.0.
* ≤ 20 k triangles, textures ≤ 2048 px (JPEG for colour, PNG for normal/alpha).
* Ears / tail: if the source rig has no bones for prominent ears or a tail, add a
  2–4 bone chain each (root at the head/hips, tip at the end) and weight those
  vertices to it — the game drives them with spring-bone physics.

`<id>.rig.json`:

```json
{
  "id": "bun",
  "display_name": "Bun",
  "species": "rabbit",
  "head_top": 0.95,
  "eye_height": 0.82,
  "rest_pose": "T",            // "T" or "A"
  "bones": {                    // role -> bone name in the glb (null if absent)
    "hips": "...", "spine": "...", "chest": "...", "neck": "...", "head": "...",
    "jaw": null,
    "l_upper_arm": "...", "l_lower_arm": "...", "l_hand": "...",
    "r_upper_arm": "...", "r_lower_arm": "...", "r_hand": "...",
    "l_upper_leg": "...", "l_lower_leg": "...", "l_foot": "...",
    "r_upper_leg": "...", "r_lower_leg": "...", "r_foot": "..."
  },
  "chains": { "ear_l": ["..."], "ear_r": ["..."], "tail": ["..."] },
  "radii": { "hips": 0.14, "chest": 0.15, "head": 0.16, "l_upper_arm": 0.05, "...": 0.0 },
  "animations": ["Idle", "Walk"],   // baked clips kept in the glb, may be empty
  "notes": "free text"
}
```

`radii` = typical distance (m) from the bone axis to the vertices weighted to that
role — used to size ragdoll capsules and hit boxes.

## Weapons — `assets/weapons/<id>.glb`

Custom carrot-themed guns. Origin at the **main (trigger) grip**, barrel along
**−Z**, +Y up, metres, sized for a ~1 m critter: pistol ≈ 0.28 m long, shotgun ≈
0.75 m, LMG ≈ 0.9 m, rocket launcher ≈ 1.0 m. Named empties (exported as nodes):
`Muzzle`, `SupportGrip` (off-hand), `Sight` (eye point for ADS), `Eject`
(optional). Projectiles: `carrot_bolt.glb` (tip along −Z), `carrot_rocket.glb`.

## Props & pickups — `assets/props/<id>.glb`

Acorn helmet (origin = where it sits on the skull, opening facing −Y), pickups
(health, armor, ammo bundles), loot crate, supply drop, dandelion glider.
`assets/props/manifest.json` lists sizes and node markers.

## Environment — `assets/env/<id>/<id>.glb`, `assets/textures/`, `assets/sky/`

Each model is pre-scaled to its in-game size (see art direction) with its base at
y = 0. `assets/env/manifest.json`:

```json
[{ "id": "fern_a", "file": "assets/env/fern_a/fern_a.glb", "category": "bush",
   "height_m": 2.5, "footprint_radius_m": 1.4, "collision": "none",
   "collision_radius_m": 0.0, "scale_range": [0.8, 1.3], "density_weight": 1.0 }]
```

`category` ∈ tree, bush, grass, flower, mushroom, rock, log, stump, prop,
landmark. `collision` ∈ none, cylinder, convex, trimesh.

Terrain layers live in `assets/textures/<layer>/` as `albedo.jpg`,
`normal.png` (OpenGL convention, +Y), `roughness.jpg`.

## Audio — `assets/audio/`

`sfx/*.ogg`, `music/*.ogg`, mapped by `assets/audio/manifest.json`
(`{"pistol_fire": ["sfx/pistol_fire_1.ogg", ...], ...}`).

## Process rules

* Tools that touch the network or Blender live in `tools/`; generated assets are
  committed, raw downloads are **not** (they stay in `/tmp` or `tools/_cache/`,
  which is git-ignored).
* Never print or commit API tokens.
