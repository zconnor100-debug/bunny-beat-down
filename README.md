# 🥕 Bunny Beat Down

[![tests](https://github.com/zconnor100-debug/bunny-beat-down/actions/workflows/tests.yml/badge.svg)](https://github.com/zconnor100-debug/bunny-beat-down/actions/workflows/tests.yml)
![Godot 4.6](https://img.shields.io/badge/Godot-4.6-478cbf?logo=godotengine&logoColor=white)
![License: MIT](https://img.shields.io/badge/code-MIT-green)

**A whimsical third-person battle royale.** One bunny, one acorn helmet, 23
woodland critters, and a lot of carrots. Drop from a picnic-basket hot-air
balloon onto a procedurally generated forest island (or from a wind-up toy
plane into a giant hamster cage, or a paper airplane over a kid's bedroom
floor) and loot carrot guns. Then outlast the
closing Briar and be the last critter standing. Ragdolls, real limb-popping
gore, and floppy physics ears are included.

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
  | The Long Carrot | bolt-action sniper with a real scope view; 800 m/s, so little leading |
  | Carrot Rocket Launcher | one very large, very angry carrot: 120 on a direct hit, less the further from the blast (out to 10 m) |

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
- **Pick your critter** on the loading screen while the island grows:
  - all eight species (bunnies, squirrel, fox, raccoon, frog, beaver, hamster),
    each with several skins;
  - a live 3D preview showing the species' jump trick.

  ![Choosing a critter on the loading screen](docs/screenshots/picker.jpg)
  ![All 40 critter skins](docs/screenshots/skins.jpg)
- **Battle royale for 1 player and up to 49 bots** on three maps (pick one
  under *New match*): Wildwood Island, the Hamster Cage and Toy Box Bash:
  - a balloon (or toy-plane, or paper-airplane) drop, freefall, and a giant
    leaf, flower or dandelion umbrella to glide down on;
  - floor loot, garden crates and **treasure chests**: hold E for up to 5 s,
    out in the open, for the best gear;
  - big glowing pickups: green **lucky clover** bottles to heal and orange
    **acorn shields** for armor;
  - critter cottages, stumps, log piles and stone walls for cover;
  - the shrinking **Briar**, in a different mood every match (see below),
    and supply drops;
  - short matches: the Briar's whole run takes about eight minutes, and a
    **Rematch (same seed)** button replays the exact same map and drop;
  - a kill feed, a minimap and full map, spectating, and *Winner Winner Carrot
    Dinner*.
- **Moving like a critter**: long, bounding strides at an unhurried step
  rate (a short flight in every stride, so short legs don't patter); sprint
  while aiming; crouch → lie down and army-crawl → stand, all on one button.
  The crawl plants each paw and drags the body past it while the opposite
  knee draws up and pushes, so nothing slides; a gun rides along in the
  right paw. Under the glider both paws grip the handle (short arms stretch,
  cartoon-style, to reach it), the legs dangle, and critter and canopy lean
  together into the steer.
- **Small-critter physics**:
  - Jolt ragdolls with per-limb joint limits.
  - Spring-bone ears and tails.
  - Hit flinches and landing squash.
  - Explosion knockback, with corpses and gibs that react to blasts.
- **A club for every species**, three quarters of the critter's height. It
  comes out with empty paws, or any time on F / R3 (a gun in the paws is
  stowed for the swing and comes straight back). Each swing winds up over the
  shoulder and whips down across the body, connecting the moment the club
  passes chest height, and hits whoever is in front of you. Bots brawl with bare paws and bash point-blank with a gun out.

  | Critter | Club |
  |---|---|
  | Bun | Barbed-Wire Carrot |
  | Bandit Bunny | Shadow Carrot (violet veins, black thorns) |
  | Frog | Fly Swatter, with the fly still in it |
  | Fox | Bunny Spine, head still attached |
  | Squirrel | Acorn Knocker: a stick with a bloody acorn dangling off it |
  | Hamster | Mousetrap Mallet: a pencil with a sprung trap (and someone's tail) |
  | Raccoon | Rusty-Nail Corncob |
  | Beaver | Trout on a Stick |

  ![The melee clubs](assets/weapons/preview_sheet_melee.png)
- **Gore**:
  - Any limb or head can come off any critter, as a real skinned body part
    with a clean, capped stump.
  - Blood fountains, splat decals, fur tufts and acorn helmets that fly off.
  - Three settings: **Full**, **Plushie** (stuffing instead of blood) and **Off**.
- **Situational awareness**:
  - Enemies have a warm rim light and a name tag within 45 m, which cover still hides.
  - Red minimap blips show anyone firing, anywhere on the island, and anyone
    moving within 20 m of you.
  - Enemy footsteps are directional: loud, strongly panned, and muffled when
    they're behind you. The audio listener sits at your critter's head, so you
    can hear where someone is and turn to take the shot.
  - Every carrot leaves a glowing tracer, so you can see shots fly and where
    they came from.
  - When you're hit, the shooter's name tag lights up at any range and an
    arrow points their way. Blood splats land on that side of the screen
    (stuffing with Plushie gore).
- **AI opponents** drive the same controls as you:
  - They loot, choose guns by range, strafe and jump in fights, lead targets,
    hear gunshots and react to being hit.
  - They have to *spot* you first. Each critter in view fills an awareness
    meter, quickly if it's close, moving or firing, and slowly if it's far,
    still or crouched. Bushes, ferns and tall grass hide you from bots just as
    they hide bots from you. Getting shot turns a bot toward the noise, but it
    still has to find you.
  - Only one to three bots (by difficulty) shoot at you at once, in bursts,
    and their hits on you are softened by difficulty.
  - They heal, flee the Briar, and path across a navmesh baked from tiles.
- **Bots are characters, not targets.** The 63 bots each have a name and a
  personality for life (Hothead, Sneak, Show-off, Grudge-holder,
  Scaredy-cat, Prankster), and the game remembers the score between each of
  them and you, across runs. A bot that has beaten you down twice becomes
  your **rival**: it is always in your next matches (with a purple
  "⚔ RIVAL" name tag), it hunts you, and it taunts you in its own voice,
  in speech bubbles and the kill feed ("Didn't see me, did you? 3–1.").
  Beat it and the game calls it **revenge**.
- **The bots learn you.** They remember where you like to land (and more of
  them head there), and which guns you win with (they fight you at the
  range those guns are worst at). Sit still too long and the nearest bots
  come to flush you out; go on a hot streak and they sharpen up for a while.
- **A Briar with moods.** Every match rolls one, announced as you drop:
  the *Hungry* Briar closes each circle in on you, the *Sticky* one slows
  you in its thorns, the *Bribable* one naps for 15 s if you munch a lucky
  clover in its thorns, the *Wandering* circle never stops drifting, the
  *Sleepy* one waits longer but bites twice as hard, and the *Bouncy* one
  bounces you sky-high. (A quarter of matches get the classic Briar.)
- **Procedural island** from a seed, 1.3 km across, in three biomes:
  - a hilly **forest** with ridges and valleys, giant oaks and ferns;
  - open **grasslands** of rolling meadow, flat-topped mesas and wildflowers;
  - a **swamp** of knee-deep still water (wading slows you down) with
    cattail reeds you can hide in, lily pads and bare dead trees.
  - Big walk-in buildings in each biome, with their crates, loot and
    usually a treasure chest inside: the log **Woodcutter's Lodge** (thatched
    roof, stone chimney, porch), the **Big Red Barn** (gambrel roof, swung-open
    doors, stalls and hay bales, a carrot weathervane) and **stilt shacks**
    with tin roofs and ramps out over the swamp water.
  - Seventeen named landmarks in all, among them Carrot Patch, Picnic Hill,
    Mushroom Ring, Duck Pond, Gnome Garden, Hollow Stump, Boulder Bluff,
    Log Jam, Bayou Shacks and Haystack Barn.
  - Paths, ground cover that bends in the wind, PBR terrain and water. The
    textures are mipmapped and toned toward their average colour, with gentle
    bumps, SMAA on top of MSAA and alpha-to-coverage leaves, for a smooth,
    cartoony look instead of photo grain.

  ![The barn, the lodge, the swamp and the stilt shacks](docs/screenshots/biomes.jpg)
- **The Hamster Cage**, a second map: a 1.1 km glass tank full of
  wood-shaving bedding, standing in a human's living room, with its own
  toy-box chiptune soundtrack. Everyone flies in on a wind-up toy plane.
  - **Bedding**: a giant exercise wheel, *Tube Town* (Habitrail pods joined
    by tunnels you can run through), hamster huts, a food bowl heaped with
    seeds, a sand bath, a shelf with a ramp, the water bottle on the glass,
    cardboard rolls, chew blocks, and giant seeds, pellets, broccoli and
    carrots lying everywhere as cover (paper-bedding tufts hide you like bushes).
  - A **lagoon** of spilled water over aquarium gravel round five brimming
    water bowls (swim in, climb out over the rim), an aquarium castle, shells
    and plastic plants.
  - A **winter corner** next to a giant fridge the owner left open behind
    the glass: cold light and mist pour over the wall, and there are snow
    drifts, icicles, frost on the panes, ice cubes, frozen peas, popsicles
    and an upturned ice cream tub to hide in.

  ![The Hamster Cage: the tank, Tube Town, the aquarium castle and the fridge](docs/screenshots/hamster_cage.jpg)
- **Toy Box Bash**, the third map: a kid's bedroom floor, hemmed in by the
  bed, a cubby shelf, a bookshelf, a dresser and a desk, under a ceiling of
  glow-in-the-dark stars and a planet mobile, to a toy marching-band soundtrack.
  - **The toy train** loops the whole room on a wooden track. Hop on an open
    car and ride it (moving cover with a view), but don't stand on the track:
    the engine bonks you for real damage and knocks you flying.
  - **Dollhouse Manor**: three storeys, open at the back, with stairs up
    through every floor and loot on each one.
  - Oak floorboards with a printed town **play rug** (roads, lawns and a
    river) under **Brick City** (plastic-brick houses and towers) and the
    **Loop-de-Loop** race track; an alphabet-**Block Castle**, **Crayon
    Canyon** with a coloring-book tent, a **Domino Run**, a tea party, the
    toy chest, a piggy bank and a toy rocket.
  - A corner of **pillow hills** under a patchwork quilt with a blanket fort
    and a giant teddy, and a **fishbowl** with goldfish: climb the slide,
    jump in and swim.

  ![Toy Box Bash: the bedroom, the toy train, Dollhouse Manor and the pillow fort](docs/screenshots/toy_box_bash.jpg)
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
  corpse, a final modifier collapses the missing subtree into the stump; on
  the gib, the rest of the body collapses *into the cut*, so skin shared
  across the joint pinches shut instead of stretching off in spikes. This
  works on every model in the roster.
- **One body, two brains.** Players and bots write the same intent struct, so
  bots get no aim or movement cheats.
- **Deterministic island generation**: fBm, ridged and mesa terrain blended
  by a noise-warped biome map, a splat-map shader (with a swamp-mud layer),
  biome-aware POI placement and flattening, a scatter system with cached
  collision, a spatial hash for spacing and MultiMesh ground cover, buildings
  assembled in code from textured boxes and logs (every wall run is a
  collider, so doorways are real gaps for the navmesh), and a tiled async
  navmesh bake. The Hamster Cage reuses all of it: `HamsterCage` extends
  `Island` (bowl water, a rectangular play area, its own ground colours and
  light), `CageFloor` extends `Terrain`, and its toys are built by a
  `CageKit` that adds lathes, panel rings and ellipsoids to the buildings'
  boxes and logs. Toy Box Bash does the same (`ToyBox`, `ToyFloor`,
  `ToyProps`, `ToyRoom`), plus `ToyTrain`: `AnimatableBody3D` cars
  following a resampled loop, so riders are carried by the physics engine,
  and a bumper `Area3D` that bonks critters on the line.
- **Tests that play the game.** A headless suite of 82 tests covers:
  - the IK maths, hitboxes, ragdolls and dismemberment;
  - island navigation, the three biomes and the big buildings (a Bun walks
    in through the barn doors; every indoor loot spot is reachable on the
    navmesh), the Hamster Cage (bots can walk into every pod, hut, castle and
    tub; the glass holds; the bowls are swimmable), Toy Box Bash (every floor
    of the dollhouse is reachable; the train runs, carries a rider and bonks
    whoever is on the track; the fishbowl is swimmable) and the game rules;
  - rivals (made, remembered across runs, back in the next match, hunting
    and taunting, revenge), the bots learning you (landings, fighting style,
    camping, hot streaks) and every Briar mood;
  - the player's input loop through real keyboard and gamepad events (menus,
    crouch → crawl, the L3 + R3 chord, aim assist, one gun in first person)
    and licensing;
  - **a complete 8-bot match on each map** that must loot, fight and finish.

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
godot --headless --path . -s tests/run_tests.gd         # all tests (~3 min)
godot --headless --path . -s tests/run_tests.gd -- ik   # one suite
godot --headless --path . -s tests/check_scripts.gd     # compile every script
```

### Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | Left / right stick |
| Fire / aim (scope) | LMB / RMB | RT / LT |
| Jump (with species trick) · glide · leave the balloon | Space | A |
| Sprint (works while aiming) | Shift (hold) | L3 (click: on until you stop) |
| Crouch → crawl → stand (each press) | Ctrl or C | B (with a gun out) |
| Reload / pick up | R / E | X / A (with a gun or crate in front of you) or Y |
| Club swing (any time) | F, or LMB with empty paws | R3, or B / RT with empty paws |
| Switch weapon / drop it | 1-3, mouse wheel / G | LB / RB / D-pad ← |
| Heal (lucky clover) | H | D-pad ↓ |
| First / third person | V | Back, or L3 + R3 together |
| Swap shoulder | Q | D-pad → |
| Map | M (hold) | D-pad ↑ |
| Pause | Esc | Start |
| Menus: move / select / back | Arrows / Enter / Esc | D-pad / A / B |
| Character picker: critter / skin / spin | ← → / ↑ ↓ / drag | D-pad ← → / D-pad ↑ ↓ / right stick |

On-screen prompts follow whichever you used last (“[Y] Pick up” vs “[E] Pick up”).
On a gamepad a light aim assist helps: when the crosshair passes within 2 m of
an opponent you can see, the stick slows a little and the aim drifts onto them.
Pads with back buttons (an 8BitDo Ultimate's L4 / R4): map them to L3 / R3 and
squeeze both for first person.

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

Two small local web tools (standard-library Python, loopback only) close the
loop with a human reviewer:

- **Audio Review** (`tools/audio/review.py`): play every sound, mark it Good,
  Tweak or Replace, flag bad takes and leave notes. Sounds rebuilt since a
  verdict are marked for a second listen.
- **Game Notes** (`tools/notes/notes.py`): write down changes you want, one per
  note. Once nothing has been added for 10 minutes, Claude claims the new notes,
  makes the changes, and answers each note on the page (done, or a question).

## License

Code © 2026 Zachary Connor, [MIT](LICENSE). Third-party assets keep their own licenses. See
[CREDITS.md](CREDITS.md).
