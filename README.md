# 🥕 Bunny Beat Down

[![tests](https://github.com/zconnor100-debug/bunny-beat-down/actions/workflows/tests.yml/badge.svg)](https://github.com/zconnor100-debug/bunny-beat-down/actions/workflows/tests.yml)
![Godot 4.6](https://img.shields.io/badge/Godot-4.6-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/code-MIT-green)

**A whimsical third-person battle royale.** One bunny, one acorn helmet, 23
woodland critters, and a lot of carrots. Drop from a picnic-basket hot-air
balloon onto a procedurally generated forest island and loot carrot guns. Then
outlast the closing Briar and be the last critter standing. Ragdolls, real
limb-popping gore, and floppy physics ears are included.

Built in **Godot 4.6** (GDScript, Jolt physics, Forward+).

![Gameplay: a golden carrot shotgun, a ragdolled fox, and a rocket carrot](docs/screenshots/gameplay.gif)

| | |
|---|---|
| ![Title screen: Bun with a golden carrot LMG](docs/screenshots/menu.jpg) | ![A rocket carrot meets the roster](docs/screenshots/gore.jpg) |
| ![The picnic-basket balloon over the island](docs/screenshots/drop.jpg) | ![The roster, posed by the procedural animator](docs/screenshots/roster.jpg) |

## Features

- **Third person with a first-person option** (press **V**): over-the-shoulder
  camera with a shoulder swap, aim-down-sights zoom, recoil kick and trauma
  shake; a first-person viewmodel with sway, bob and procedural reloads.
- **Seven carrot guns**, each with its own feel:

  | Gun | Role |
  |---|---|
  | Carrot Pistol | snappy sidearm, big headshot bonus |
  | Carrot SMG | 900 rpm stick-mag of baby carrots, great up close |
  | Carrot Shotgun | nine julienned pellets, pump action |
  | Carrot Assault Rifle | the all-rounder, banana-carrot magazine |
  | Carrot LMG | a pan of baby carrots and no off switch |
  | The Long Carrot | bolt-action sniper with a real scope view |
  | Carrot Rocket Launcher | one very large, very angry carrot |

  Five loot rarities run from Baby to **Golden**, and Golden guns shimmer.
  Projectiles are real carrots that fly with drop and **stay stuck** in
  whatever they hit.
- **Species jump tricks**: every critter jumps in character.
  - **Bunnies flip**: a front flip when running forward, a back flip when
    backing up, a side flip when strafing.
  - Squirrels spin, foxes do a head-first mousing pounce, and raccoons
    cannonball.
  - Frogs stretch out into a leap, beavers land with a tail slap, and
    hamsters barrel-roll.

  ![Jump tricks](docs/screenshots/jump_tricks.gif)
- **Battle royale for 1 player and up to 49 bots**: a balloon drop, freefall
  and dandelion glider, floor loot and garden crates, the shrinking **Briar**,
  a kill feed, a minimap and full map, spectating, and *Winner Winner Carrot
  Dinner*.
- **Small-critter physics**:
  - Jolt ragdolls with per-limb joint limits.
  - Spring-bone ears and tails.
  - Hit flinches and landing squash.
  - Explosion knockback, with corpses and gibs that react to blasts.
- **Gore**:
  - Any limb or head can come off any critter, as a real skinned body part.
  - Blood fountains, splat decals, fur tufts and acorn helmets that fly off.
  - Three settings: **Full**, **Plushie** (stuffing instead of blood) and **Off**.
- **AI opponents** drive the same controls as you:
  - They loot, choose guns by range, strafe and jump in fights, lead targets,
    hear gunshots and react to being hit.
  - They heal, flee the Briar, and path across a navmesh baked from tiles.
- **Procedural island** from a seed:
  - Eight named landmarks: Carrot Patch, Picnic Hill, Mushroom Ring,
    Duck Pond, Gnome Garden, Hollow Stump, Boulder Bluff and Log Jam.
  - Paths, a giant forest, ground cover that bends in the wind, PBR terrain
    and water.
- **Full UI**: menus, settings, pause, loading screen, gamepad support, and a
  [credits page](CREDITS.md) generated from the asset metadata.

## How it's built (the interesting parts)

The full write-up is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

- **Keyframe-free animation.** Characters come from different artists with
  different rigs, so animation is driven by bone *roles*. A custom
  `SkeletonModifier3D` runs every frame:
  - It computes a velocity-synced gait (bunnies hop).
  - It spreads aim across the spine and moves the hips.
  - It solves **analytic two-bone IK** so the paws hold each gun's real grip
    markers.
- **Dismemberment without pre-cut meshes.** A severed limb is a copy of the
  same skinned model with its skeleton *re-rooted* at the cut bone. On the
  corpse, a final modifier collapses the missing subtree into the stump.
  This works on every model in the roster.
- **One body, two brains.** Players and bots write the same intent struct, so
  bots get no aim or movement cheats.
- **Deterministic island generation**: fBm terrain with a splat-map shader,
  POI placement and flattening, a scatter system with cached collision and
  MultiMesh ground cover, and a tiled async navmesh bake.
- **Tests that play the game.** A headless suite of 24 tests covers:
  - the IK maths, hitboxes, ragdolls and dismemberment;
  - island navigation and the game rules;
  - the player's input loop and licensing;
  - **a complete 8-bot match** that must loot, fight and finish.

  CI runs it on every push.

## Running it

**Desktop app (Linux):** run `./tools/install_desktop.sh`. It adds *Bunny Beat
Down* to your applications menu and desktop, with Bun as the icon. If a
standalone build exists in `build/linux/`, it launches that; otherwise it runs
the project through Godot.

**From source:**

1. Install **[Godot 4.6.2](https://godotengine.org/download)** (standard build).
2. `git clone https://github.com/zconnor100-debug/bunny-beat-down.git` and open `project.godot` (the first import takes a minute). On Linux you can also run `./play.sh`.
3. Press **F5**.

```bash
# or from a terminal
godot --path .                                          # play
godot --headless --path . -s tests/run_tests.gd         # all tests (~1 min)
godot --headless --path . -s tests/run_tests.gd -- ik   # one suite
godot --headless --path . -s tests/check_scripts.gd     # compile every script
```

### Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | Left / right stick |
| Fire / aim (scope) | LMB / RMB | RT / LT |
| Jump (with species trick) · glide · leave the balloon | Space | A |
| Sprint / crouch | Shift / Ctrl | L3 / B |
| Reload / pick up | R / E | X / Y |
| Switch weapon | 1-3, mouse wheel | LB / RB |
| Heal (lucky clover) | H | D-pad ↓ |
| First / third person | V | Back |
| Swap shoulder | Q | R3 |
| Map | M (hold) | D-pad ↑ |

## Assets and credits

![The in-game credits page](docs/screenshots/credits.jpg)

Every model, texture, sound, track and font is **CC0, CC BY or SIL OFL**.
Each one is credited with its author, source link, license and the changes
made in [CREDITS.md](CREDITS.md), and on the in-game **Credits** screen. Both
are generated from the same `assets/credits/*.json`. A test fails the build if
any asset file lacks a credit. The pipelines that fetched, vetted and
normalised the assets (Sketchfab / Poly Haven / ambientCG / Kenney /
incompetech) live in `tools/`. The carrot guns, helmet and pickups were
modelled from code in Blender (`tools/weapons/`).

## Development notes

This project was built with an AI pair-programmer (Claude Code) as part of
exploring agentic software development. That covered the game code and tests,
plus parallel asset agents that sourced, license-vetted, normalised and
documented the art and audio pipelines.

## License

Code © 2026 Zachary Connor, [MIT](LICENSE). Third-party assets keep their own licenses. See
[CREDITS.md](CREDITS.md).
