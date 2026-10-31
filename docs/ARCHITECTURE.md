# Architecture

A tour of how Bunny Beat Down works, aimed at someone reviewing the code.
Everything runs on stock **Godot 4.6** (GDScript, Jolt physics, Forward+).

```
src/
  autoload/   Settings · Events (signal bus) · GameInput (bindings in code) · Audio
  core/       DamageInfo · IKMath · Layers · ModelUtil · Despawner · GameSession
  critters/   Critter · CritterVisual · CritterPoser · RigInfo · Gore · LimbHider · Inventory
  player/     PlayerController · CameraRig
  ai/         AIBrain
  weapons/    WeaponData (.tres) · WeaponInstance · Rarity · Projectiles · Rocket · Explosion
  world/      Island · Terrain · Scatter · Building · WorldLighting · Pickup · LootCrate · shaders/
              HamsterCage · CageFloor · CageKit · CageProps · CageRoom (the second map)
              ToyBox · ToyFloor · ToyProps · ToyRoom · ToyTrain · Spinner (the third map)
  match/      MatchManager · Storm (the Briar) · Dropship (the picnic balloon / the toy plane)
  fx/         FX · FXTextures
  ui/         HUD · Minimap · MainMenu · SettingsPanel · CreditsPanel · UITheme
tests/        headless test runner + suites, screenshot capture scripts
tools/        asset pipelines (Blender/Python), credits generator
```

Scenes are built in code rather than hand-edited `.tscn` trees; that keeps the
whole game reviewable as text and diff-friendly.

## One body, two brains

`Critter` (a `CharacterBody3D`) knows nothing about who controls it. It exposes
*intent* fields — `move_input`, `look_yaw/pitch`, `aim_point`, `want_fire`,
`want_jump`, ... — and every physics tick turns them into movement, spread,
recoil, reloads and damage. `PlayerController` fills those fields from the
mouse/gamepad; `AIBrain` fills them from its own decisions. The bots therefore
obey exactly the same rules as the player: no hitscan, no free aim, no
infinite ammo. Skill only changes *how well* they drive the controls
(reaction time, aim-error decay, turn rate, bravery).

## Procedural animation (no keyframes)

The roster comes from different artists with different rigs, so animation is
driven by **roles**, not bone names. Each model ships with a `rig.json`
(`tools/characters/` builds it) that maps roles such as `hips`, `l_upper_arm`,
`r_hand` to that model's bones.

`CritterPoser` is a `SkeletonModifier3D` that rebuilds the pose every frame
(see below for the ones further off) from the rest pose:

1. A gait clock advances from the critter's *real* velocity (bunnies, the
   hop gait; everyone else, a run cycle), so feet never skate when speed changes.
2. The hips bob, lean into speed (hoppers pitch nose-down on each push-off),
   kick off for a jump, sink and bounce back on landing, and flinch when
   hit (a damped spring).
3. Aim pitch/yaw is spread across spine → chest → neck → head. The chest
   keeps most of a run's lean while the neck and head level the eyes, and
   bare-pawed runners swing their shoulders against their hips.
4. Idle life goes on top, on each critter's own clock (scaled time, a random
   start, so a crowd never moves in step): breathing that turns to panting
   after a sprint, a slow weight shift from paw to paw, glances off the aim,
   and **fidgets**: a table of each species' own (`FIDGETS`: thumps, a
   nibble on the jaw bone, tail swishes, knee bobs, stretches, ear scratches,
   a look over the gun). Fidgets start only while the critter stands calm and
   fade out the moment it moves or gets alert.
5. The held gun is placed in front of the shoulder (with recoil kick and a
   reload tilt) and moved clear of the head: the head's capsule is sampled
   in the gun's frame and the gun steps out to the cheek or down under the
   chin, whichever is less. That is the **raised** pose (`raised_holder`),
   and shots always leave from its muzzle. The gun you *see* is then carried:
   up on the aim when shooting, aiming, reloading or just hit, tipped down
   about its butt when things go quiet, swung across the body at a sprint,
   with a little lag behind fast turns.
6. **Analytic two-bone IK** (`IKMath.solve_two_bone`, unit tested) puts both
   paws on the gun's real `Muzzle`/`SupportGrip` markers, or pumps, swings,
   raises and stretches them when they're empty. The paws really close on the
   handles: `PawGrip` measures each model's paw once from its skinned mesh
   (which way it runs, which side the palm is on, its depth and breadth, where
   the hole of a fist is) and the poser turns the hand to the handle, puts
   that hole on it, and curls the fingers round (each joint about one
   precomputed axis, so it costs a rotation per bone). A fist may turn round
   its handle, so of a few turns it takes the one that bends the wrist least;
   the support paw slides back along the fore-end until it can reach; guns
   sit as far out as each critter's own arms reach (a hamster's are half a
   fox's), move toward the middle when the other arm is too short to reach
   across, and come out in front of round tummies. Mitten paws with no finger
   bones (the frog, the raccoon, the beaver) are given knuckles at load time
   (`PawKnuckles`: two bones per paw and the fingers' skin reweighted onto
   them, built once per model). `test_anims` checks every critter with every
   gun, aiming level, up and down: both paws on their handles, no wrist bent
   past 85°.
7. Legs solve two-bone IK to the gait's foot targets: tucked on the way up
   a jump, reaching for the ground on the way down. Standing still, planted
   feet stay put in the world while the body turns over them and step round
   once it has turned far enough.

Ears and tails run through Godot's `SpringBoneSimulator3D` after the poser, so
they flop with every hop, landing and hit (stiff enough to keep their shape:
a long brush tail stays out of the legs at a bound).

Posing is the dearest thing a critter does each frame, so `CritterVisual`
advances its skeleton itself (`modifier_callback_mode_process` MANUAL,
`_advance_pose`): every frame within 30 m of the camera, every other frame
out to 70 m, every third beyond that (or behind the camera), with the time
that passed, and not at all while the critter is hidden (riding in the
balloon). The critters take turns. The KillCam's replay, which runs with the
match paused, sets its critters' skeletons back to advancing themselves every
frame (`pose_every_frame`).

> Engine detail worth knowing: `Skeleton3D` restores the *un-modified* pose
> after skinning, so `get_bone_global_pose()` outside the modifier stack
> returns the rest pose. Code that needs the rendered pose reads it from
> `BoneAttachment3D` nodes or ragdoll bodies (`CritterVisual.current_bone_global`).

## Outfits: one hat, eight heads

Every member of the Cast wears its own outfit (`Outfits.LOOKS`: a fur and a
few pieces). The pieces are ordinary models (built by `tools/env` like the
scenery, category "outfit") and know nothing about critters. Both sides are
measured, and each piece is fitted to each critter from the two:

* **The pieces** (`tools/outfits/measure_pieces.py`, run in Blender, writes
  `OutfitShapes`): rays cast up into every model on a grid find where the head
  goes: the hollow inside a cap's crown (not its visor), the empty middle of a
  crown or a sweatband, its centre, width each way and the height of its rim.
  A few that no ray can read are given by hand (a top hat's closed crown, a
  chin strap hanging below a shako's rim).
* **The critters** (`OutfitFit`, once per model from its skinned mesh in the
  rest pose): the skull and the body are *cut across* at 24 heights (the
  triangles, not the vertices, so a big low-poly beaver head reads as round
  as it looks), giving the skull's breadth, and the body's breadth, front and
  back, at every height; the crown (from the middle third only, so ears in
  the head mesh don't lift a hat); the eyes (`rig.json` "eyes", read off
  straight-on renders by `tests/capture_eyes.gd`, since a squirrel's sit deep
  in their sockets), the brow, the snout, the chin, the shoulders and where a
  big tail leaves the body.

A hat's rim goes down from the crown toward the brow (its `sink`: a party
hat perched on top, a beanie pulled right down), its hole made as wide as the
skull is there (but never out to a hamster's ears) and no deeper than the
head, and its crown squashed or stretched a little so the inside sits on the
skull (`hat_stretch` in `rig.json` for the beaver's tall egg of a head).
Glasses are scaled so their lenses land on the eyes; a bandana's loop is sized
to the snout, its front on the front of the face below the eyes (its back is
hidden in a big round head); a scarf goes round the neck under the chin. A
cape is **skinned to the spine**: its top rides the chest and its hem the hips,
draped at rest over the back as far as it bulges, so it lies on a hunched
squirrel or a running fox instead of swinging out like a board (the mesh is
built beside the critter's own, with the body's bind poses, once per model).
A headshot or a blast knocks the head's pieces off as debris, like the acorn
helmet. `test_outfits` checks every rogue's look exists and, on every
species, that a hat sits on the crown, centred and not oversized, glasses
span the eyes, a pack is on the back and a cape lies on it.
`tests/capture_outfits.gd -- DIR cast:<species>` renders every rogue of a
species (front, side, back and whole body) to check fits by eye, and `-- DIR
fit` prints every species' measurements.

## Hitboxes, ragdolls and gore

`RigInfo` turns the rest pose into body *segments* (start, end, radius). Each
segment becomes:

* a **hitbox**: an `Area3D` capsule on a `BoneAttachment3D`, so shots know
  exactly which body part they hit (head = headshot multiplier, limbs take less);
* a dormant **ragdoll body**: a `PhysicalBone3D` with cone-twist limits sized
  for that limb, under a `PhysicalBoneSimulator3D` (Jolt).

On death the poser is switched off, the ragdoll starts with the critter's
velocity, and the killing blow's impulse is applied at the bone that was hit.

**Dismemberment** works on any model without pre-cut meshes. To sever a limb:

1. The corpse's `LimbHider` modifier, last in the stack, collapses that bone
   subtree to zero scale, so the limb vanishes into the joint. Its ragdoll
   bodies and hitboxes are removed.
2. A **second copy of the same model** is spawned. Its skeleton is re-rooted
   at the severed bone (`set_bone_parent(bone, -1)`) and every other root is
   collapsed to zero scale *at the cut*, so only the real skinned limb
   remains, wearing the pose it had when it came off. (Collapsing them where
   they stood would drag skin that is weighted partly to the body, around the
   joint, off toward the hips in long spikes; collapsed into the cut, it
   pinches shut under the cap.) It flies as a `RigidBody3D`.
3. Both cut ends get a meaty cap with a bone nub and a spurting blood fountain.
   Decals land on the ground.

Gore has three settings: **Full**, **Plushie** (white stuffing instead of blood)
and **Off**. Particles are always billboarded soft blobs generated at runtime
(`FXTextures`), and so are the splat and scorch decal textures.

## Carrots in flight

`Projectiles` keeps bolts and pellets as plain data. Each physics tick it
ray-steps each one from its last position to the next (with gravity), so a
150 m/s carrot can't tunnel through a 5 cm paw. All of them are drawn through
one `MultiMesh` per kind, extrapolated between ticks for smooth motion. A
carrot that hits something **stays stuck in it**. It is parented to the hit
bone's attachment, so carrots ride along on a ragdoll.

Rockets are real nodes with smoke trails. `Explosion` gives a critter the
rocket hit square on the full blast damage (120), and everyone else falloff
damage by their distance from it (out to 10 m) with a cover check; it shoves
every ragdoll, gib and prop in range, and blows limbs off nearby corpses.

Weapons are `.tres` resources (`data/weapons/`). Balancing happens in the
inspector, and loot **rarity** (Baby → Garden → Prize → Heirloom → Golden)
scales damage, magazine size and reload speed.

## The island

`Island.generate(seed)` is deterministic and yields between steps for the
loading screen (~5 s):

1. **Terrain**: fBm heightfield with a noisy coastline (513² vertices,
   chunked meshes for culling, one `HeightMapShape3D` for physics).
2. **POIs** (Carrot Patch, Picnic Hill, Mushroom Ring, Duck Pond, ...) are
   placed with spacing, flattened into the terrain and dressed with their kit.
   Wandering dirt paths connect each POI to its nearest neighbours.
3. A **splat control map** (grass / dirt / rock / moss, plus sand by height)
   feeds `terrain.gdshader`. That shader has six PBR layers, anti-tiling,
   macro colour variation and tri-planar rock on cliffs.
4. **Scatter**: giant trees on a jittered grid gated by a forest-density noise,
   rocks, logs and mushrooms with cached collision shapes. Ground cover is
   batched into chunked `MultiMesh`es with visibility ranges and a wind
   shader that also bends grass away from the player.
5. **Navigation**: the navmesh is baked as 12×12 tiles of 128 m in parallel
   (`bake_from_source_geometry_data_async`). Each tile's bake area is grown by
   its border so neighbouring tiles stitch exactly. A path (`Island.find_path`)
   searches only the tiles round its two ends (the query's `included_regions`):
   Godot's query checks every polygon on the map to find where a path starts
   and ends, about 87,000 on the island. A path that stops short there, or a
   trip over more than `PATH_TILES_MAX` tiles, searches the whole map, and a
   spot the whole map can't reach either is left alone for 15 s
   (`_dead_ends`: bots kept asking for loot up on ledges, at ~15 ms a time).

## The Hamster Cage

The second map is the same machinery wearing a different costume, which is
why the rest of the game (AI, loot, the Briar, the HUD) needed only a few
hooks: `Island` gained `play_bounds()`, `map_color()`, `tune_lighting()`, a
`drop_vehicle` and a `music_slot`, and `HamsterCage` overrides them.

- **`CageFloor extends Terrain`**: a rectangle of bedding dunes heaped up
  against the glass, with a lagoon and a winter corner in the biome map's
  slots, gravel ramps up to the bowls' rims (`ramp()`), sand-bath and trail
  splats, and `cage_floor.gdshader`, which recolours a wood-shaving scan pale
  and blends in pebbles, snow and sand.
- **`CageKit extends Building`**: the toys reuse the buildings' merged-mesh
  boxes, logs, cones and prisms (each one its own collider) and add lathes
  with concave collision (bowls, tubs, domes), rings of panels (Habitrail
  tubes and pods, the wheel's tread: the bottom panel is the walkway) and
  ellipsoids with convex-hull collision (seeds, peas, broccoli). Huts, the
  aquarium castle, the ice cream tub, the pods and the shelf are walk-in
  "buildings", so the loot planner puts their loot indoors.
- **Water** is per-cell for the lagoon (like the island's swamp) plus a disc
  per bowl; `water_level_at()` answers both, so swimming just works.
- **`CageRoom`** is scenery: the glass (four solid panes with a frost shader
  near the fridge), the room around the tank, and the open fridge with its
  cold light, mist particles that roll over the wall and snowfall.
- The **toy plane** is a `Dropship` variant whose route is clipped to the
  tank's rectangle, under the rim of the glass.

## Toy Box Bash

The third map follows the cage's pattern (`ToyBox extends Island`,
`ToyFloor extends Terrain`, toys built on `CageKit`), with two new ideas:

- **A procedural texture as a landmark.** The play rug's town (roads with
  dashed lines, lawns, a river, printed houses) is drawn into an `Image` with
  `fill_rect` at load time and sampled by `toy_floor.gdshader` inside the rug
  rectangle; the minimap reads the same image.
- **A vehicle you can ride.** `ToyTrain` resamples a rounded-rectangle loop
  evenly, then each physics step places six `AnimatableBody3D` cars
  (`sync_to_physics`) along it, each car facing along the chord between its
  front and back bogies. A critter standing on a car is carried by the
  physics engine's moving-platform handling, with no special code. A bumper
  `Area3D` on the engine damages and shoves anyone standing on the line
  (the kill feed: "bonked by the toy train"). The train is added after the
  navmesh bake, so it never becomes part of the walkable floor.

## Characters, rivals and a director

- **`RivalBook`** (a `ConfigFile` in `user://`, a separate one for test runs)
  keeps the score between the player and each bot by name. Personalities are
  a fixed function of the name, so "Vex" is always the same character; each
  has its own taunt lines for spotting you, beating you and losing to you.
  A bot with two or more beat-downs on you (and more than yours on it) is a
  rival: `MatchManager` puts up to three rivals in every match, their
  `AIBrain` scores the player as a preferred target and skips the
  "attack slot" queue, and `Events.taunt` drives the HUD's speech bubbles.
- **Gangs** (`Gang`, made by `MatchManager.make_gang`): members share
  `Critter.gang` (no damage between them, ignored in `AIBrain._perceive`).
  `MatchManager._tend_gangs` runs once a second: it deals roles
  (`AIBrain.flank`: the longest reach pins, the rest flank at ±100° from
  where the enemy looks, steered with `_stick_toward` so the aim isn't
  disturbed), disbands a gang whose enemy bot is down, rolls betrayal
  (`betrayal_chance`: zero until `win_in_sight`, then `Gang.DISLOYAL` x
  `BETRAY_RATE`, more with a grudge or a weak mate) and every few seconds
  tries a mid-match truce (`Gang.JOIN`, never between two with a betrayal in
  `RivalBook`). A sighting goes through `gang_spotted` to the mates'
  `share_sighting`; `AIBrain._rushing` reads the enemy's reload and
  `Events.clover_eaten`.
- **The Doppelbunny** (docs/plans/doppelbunny.md).
  `DoppelRecorder`, a child of the player's critter in a match, notes every
  0.2 s of a fight the situation (`DoppelSense.features`: 24 numbers, all
  relative to the critter) and the decision taken through it
  (`DoppelSense.label`: the move against the nearest enemy, read off the
  stick, and eight flags such as sprint, prone or grenade), not the raw
  controls. `DoppelData` keeps the newest 30,000 moments in `user://` and,
  after a match, trains a `DoppelNet` (24 → 64 → 64 → 13, ReLU, softmax for
  the move, a sigmoid per flag, SGD) on a `WorkerThreadPool` task. A tenth
  is held back to measure likeness honestly against always guessing the
  most common move. Plain GDScript, every weight in one flat
  `PackedFloat32Array` written in place, trains about 3,000 moments a
  second on the dev machine. **`DoppelBrain`** extends `AIBrain`: it runs
  the base `_fight` (paths, aim, trigger), then every 0.2 s in sight of its
  target asks the network for the odds, samples a move and flags, and
  overwrites the stick and buttons with them (holding fire when you would,
  grenades through `_lob`). `Run.generate(seed, mirror)` turns one middle
  match stop into a Mirror Match with its own RNG, so a seed's Trail is
  otherwise unchanged; `MatchManager._spawn_doppel` dresses your critter
  (`Outfits.dress_player`) under `mirror.gdshader`, and the doppel is kept
  out of `RivalBook`, gangs and `_say`.
- **Your arsenal** (`Arsenal`, docs/plans/player-arsenal.md). Its guns are
  `WeaponData` in `data/arsenal`, which `WeaponDB.all()` (loot) never lists
  and `WeaponDB.arsenal()` / `get_weapon` do. Bots are kept off them in one
  place, `Pickup.anyone_may_take` (`AIBrain._find_loot` and
  `Pickup.try_collect` ask it), plus `LootCrate.player_only`; a corpse doesn't
  drop them, a rogue can't steal one, a keepsake can't be one, and
  `PlayerProfile.favourite_gun` (your Doppelbunny's loadout) skips them. Their
  mechanics are fields any gun could use: `spin_up` / `spin_spread`
  (`Critter.spin`, gating the trigger, slowing you, a `rumbler_spin` loop
  pitched by it), `pierce` and `pierce_cover` (`Projectiles._through_cover`
  finds the far side of a hit with a ray back from beyond it, never through
  the ground's `HeightMapShape3D`), `stand_spread_deg`, and
  `ProjectileKind.LOB` + `fuse` (`Grenade` with the gun's blast). Unlocks
  are kept with the profile; `Run.finish_match` offers one after a Grudge or
  Mirror Match goal. `MatchManager.call_in` drops a fast `SupplyDrop` whose
  `LootCrate.contents` are every gun won (`"one_of"`: take one and the rest
  go back) and their carrots (`"yours"`). The Cunning boons act where they
  apply: Gang Buster (`AIBrain.panic`) in `_gang_member_down`, Pack Sense
  (`CritterVisual.reveal`, `xray.gdshader`, depth test off) in
  `gang_spotted`, Cardboard You (`Decoy`, which `AIBrain._fight` aims at
  while it stands), Habit Breaker (`DoppelRecorder.fooled` when a move is
  under 15% of your kept moments; `DoppelBrain` then moves at random).
- **`WarrenSim`** plays the rogues' off-screen matches: one per three hours
  of real time since its clock last moved (kept in its own `ConfigFile`,
  capped at twelve), caught up when the main menu opens. They're
  statistical, not physical: a lobby meets two at a time, the one who
  starts it picked by temper, the one it meets by grudge, the winner by a
  logistic of each rogue's `power` (personality, its smoothed tracked
  accuracy, wins, scars). Results go through the same `RivalBook` calls as
  real matches (`note_bot_beat`, `note_win`) plus `add_scar_from` and
  `set_mood`, so the next real match picks them up with no new code; the
  seed is the clock, so the same absence makes the same news. `edition_of`
  turns the matches into weighted stories for `GazettePanel`. Big news
  doesn't wait: `print_extra` prints a special edition at once (a boss
  beaten: `boss_news` from `MatchManager._on_boss_died`; the Barn held:
  `mission_news`), over whatever of the last edition you hadn't read, and
  `catch_up` keeps an unread one on the front page. `keep_photo` saves the
  game's screenshot of the moment (the HUD hidden for two frames, or the
  outro's letterbox cropped off) and pins it to the edition it's news for,
  whichever comes first; the panel prints it through `halftone.gdshader`
  (a 45-degree dot screen sized by each cell's darkness).
- **Voices.** Every line a bot says is picked as `Cast.say` (text, a key
  naming the template, the fields that fill it), shown, and spoken by
  **`RogueVoice`** from the bot's head. `tests/export_lines.gd` writes every
  template to `tools/voices/lines.json`; `tools/voices/build_voices_maya.py`
  (Maya1 on the GPU, ~25 minutes a rogue) speaks each rogue in a voice
  designed from a written description (`tools/voices/maya_voices.json`: its
  accent spelled out by `dialects.py`, its pitch and tempo), held steady by
  two anchor sentences in that voice (`tools/voices/anchors/`, some first
  made with a real speaker of the accent in front), the best of several
  takes per line kept by Whisper and a voice encoder. (Before Maya1 every
  rogue spoke with `tools/voices/build_voices.py`'s Kokoro-82M voices: two
  voice packs blended, pitched for its species, paced for its personality,
  `tools/voices/cast_voices.json`. It still provides the shared parts of
  the pipeline.) Every line is rendered as parts: words, your name ("Bun!" with the
  punctuation it ends on), other rogues' names, numbers 0–60 for scores; a
  line's plan stitches them back together at run time. Each rogue's clips
  are one Ogg file (16 kHz, ~0.8 MB) with an index in
  `assets/voices/voices.json`; `test_voices` checks every rogue can say
  every line with every name. A new line renumbers the word clips (an id is
  its words' place in the list of every line's words), so lines added later
  don't rebuild everyone: `build_voices_maya.py --new-lines` matches each
  rogue's clips to the new ids by their words (the bank keeps the list,
  `segs`) and speaks only what's missing into a second file,
  `<rogue>_2.ogg`. Such a clip names its file, so nothing already made is
  re-encoded, and a line whose words a rogue hasn't been given yet is only
  shown, never half-said.
- **`PlayerProfile`** remembers the player's landings and beat-downs by
  weapon. `MatchManager` acts as a small director: some bots drop at your
  favourite landmark, `AIBrain.player_style` shifts the bots' preferred
  range against your favourite guns, camping (25 s within 14 m) sends the
  three nearest armed bots to `hunt()` your spot, and two quick beat-downs
  give the bots an extra attack slot and a skill bump for a minute.
- **`Storm.VARIANTS`**: the Briar's moods are small switches in the same
  state machine: the next centre (hungry), the per-tick effect on critters
  outside (sticky sets `Critter.slow_factor`, bouncy sets `velocity.y`),
  the wait time and damage (sleepy), a creep during waits (wandering), and a
  nap timer fed by `Events.clover_eaten` (bribable).

- **`Burrow`** (in the profile file) holds acorns, unlocked and equipped
  perks and run modifiers. `MatchManager._apply_perks` gives the player its
  perks at spawn (armor, clovers, a gun, `Critter.reload_scale`,
  `jump_scale`, `second_wind`); modifiers flip match-wide switches
  (`Critter.glass_cannon`, gravity, loot tier, `Storm.rush`). The end screen
  pays out `Burrow.reward()`.
- **`TimeKeeper`** (a child of `MatchManager`) snapshots every standing
  critter (transform, velocity, look, health, armor, guns, ammo, clovers),
  the set of pickups and the Briar's state every 0.25 s, and keeps about
  11 s of them. `Pickup` reports what each critter takes (`note_taken`). A
  rewind restores the critters that are still alive, re-spawns what *they*
  took since, removes the guns they swapped out since, clears
  `Projectiles` (`clear_in_flight`), winds back the `Storm`, and makes each
  bot's `AIBrain.forget()` what it learned. Dead critters stay dead, so a
  rewind never has to un-ragdoll anything. When a blow would kill the
  player, `Critter.take_damage` asks `hold_killing_blow`: if the game is
  listening to `offered`, the tree pauses at 1 HP until `resolve()` either
  rewinds or lets the blow land. A rewind plays out first: the tree pauses
  and, for `PLAYBACK` seconds (wall-clock time, since the paused engine's
  frame delta isn't reliable), the TimeKeeper (`PROCESS_MODE_ALWAYS`) moves
  every critter that will be restored back through the snapshots, newest to
  oldest, and the camera rig keeps following. The HUD shows a tape-rewind
  shader for the duration (`rewinding` → `rewound`).
- **`KillCam`** (also a child of `MatchManager`) records the final fight once
  `RECORD_WHEN_ALIVE` critters are left. Each tracked critter gets a
  **`ReplayPose`**, a `SkeletonModifier3D` added last in its skeleton's stack.
  It sees the final pose after the poser, the ragdoll and the limb hider, and
  records the body transform, the model and gun-holder transforms, every bone
  pose and the chest position each frame. During a replay it writes a
  recorded frame back instead. Everything else reports in through cheap
  hooks guarded by `KillCam.recording`:
  - `Projectiles` sends shot start and end (shots are re-derived
    ballistically and drawn with `draw_shots`);
  - rockets, gibs, helmets, spilled loot and stuck carrots are tracked as
    nodes (a rocket that went off leaves a ghost model);
  - `FX._burst`, decals and the explosion flash, and `Audio.play[_at]`,
    are logged as timed events.

  `MatchManager` calls `note_final()` *before* it announces the winner, so
  `game.gd` can hold the end screen. `play_final()` slows time (physics
  ticks raised to match), then pauses the tree, sets the tracked skeletons
  and `FX` to `PROCESS_MODE_ALWAYS`, and plays three camera angles. At the
  end, `_show(INF)` puts every node back to its live state.

## Battle-royale loop

`MatchManager` spawns 1 player plus N bots (species weighted from
`data/critters/`), scatters loot and crates, and boards everyone onto the
**picnic balloon** (`Dropship`). Bots pick a landing spot, often a POI, and
jump when the balloon is closest. Everyone free-falls and then pops a
dandelion glider.

The **Briar** (`Storm`) runs staged wait/shrink cycles. Each new safe circle
is placed inside the old one and nudged onto land. The bots' `FLEE_STORM` mode
queries the same API the HUD uses. The last critter standing wins.

## Team Battles and Boss Battles

`MatchManager.mode` (Settings "mode", or `-- --mode teams|boss`) picks the
kind of match; a run's stops are always battle royales.

- **Teams** are `Critter.team` (0 in a battle royale). `take_damage` drops a
  team mate's carrot, blast or club before anything else happens;
  `AIBrain._perceive` skips team mates, fights the other team as far as it
  can see (`AIBrain.teams_on`) and roams toward it; the aim assist, the
  minimap's red blips and a flare's crate leave your team alone.
  `MatchManager._pick_teams` puts the bots you've made radical (and your
  rivals) on the other side, and `CritterVisual.set_ally_tag` gives yours a
  blue rim and a see-through-walls tag. A Team Battle flies two
  `Dropship`s (`setup(lane, heading)`: the same way, either side of the
  middle) and lands each team along its own route (`_team_spot`); the
  match ends in `_check_teams` when one side is gone.
- **Bosses** (`src/bosses/`) are not critters: a `Boss` is a Node3D with
  the model (`assets/bosses/<id>/`, scaled so its skull is `Boss.HEIGHT`
  up), Area3D hitboxes on anchors that follow its bones (they carry the
  `critter` meta, so `Projectiles` calls its `receive_shot` like a
  critter's; `Explosion.detonate` calls `receive_blast`; a club lands via
  `receive_melee`), and AnimatableBody3D capsules on the CRITTERS layer
  that push critters out of its body. It walks the critters' navmesh
  (cutting the corners: it stomps through props), its feet on
  `terrain.height_at`. `BossPoser` poses its skeleton from per-role
  rotations in model space (parents first, so one pose works on any of the
  three rigs); a move is a `BossAction` (keyframed poses eased between,
  events at set times, a per-frame `tick`). Every blow is announced by
  `Boss.warn` (a `BossFX` decal ring filling up, and a `danger` zone that
  `AIBrain._dodge` gets out of after a reaction time that depends on the
  bot's skill) and lands through `hurt_ring` / `hurt`, which spare anyone in
  the air. `BruteBoss`, `RobotBoss` and `HamsterBoss` choose between their
  moves in `_choose`; `Boss.snapshot`/`restore` let the TimeKeeper rewind it.
  Bots' carrots count for `Boss.BOT_DAMAGE` of yours.
- The models come from `tools/characters/boss_build.py` (recipes in
  `bosses.json`): decimate, orient and scale a download; build a skeleton
  from joints read off `grid` renders, or keep the download's own (rested in
  its bind pose); skin by bone heat on a voxel-remeshed copy with its stray
  islands removed (bone heat finds no solution on a decimated sculpt) and
  copy the weights across; paint into the texture by where each texel sits
  on the body (`paint`: Nibbles's blood and foam); export the GLB and a
  `<id>.boss.json` (bones per role, tips, hitbox radii, eyes, mouth).
- **Its arrival** is `MatchManager.release_boss` (landing it facing you,
  then `boss_arriving`), which the game answers with a `BossIntro` when
  Settings "boss_intro" is on: a Camera3D of its own driven off the boss's
  clock (`Boss.fight_time` against `land_time`: a low shot up at it falling,
  or at the ground where `from_below` Nibbles is coming up; then its face),
  a moment of slow motion as it lands, letterbox bars and its name card on a
  CanvasLayer, and `Boss.show_off` (its roar for the camera: `hurt_ring`
  does nothing while `_quiet_until` lasts). It holds the boss still
  (`thinking` off), the HUD hidden and your controls off until it's over or
  skipped, then gives the camera back turned to face it and calls
  `boss_intro_done` (which says your arsenal's ready).
- **The rogues' shouts** are `MatchManager._boss_banter`, every frame of a
  Boss Battle: it watches the boss for new `danger` zones (RUN!, from the
  rogue nearest you if it's on you, or one in it near you), stun and
  wind-down (`vulnerable()`), enrage, and the arrival and the fall (queued
  against its landing); `_boss_shout` picks the rogue (`_shouter`: the
  nearest within `BANTER_NEAR` for warnings, anyone for its name and the
  cheer) and keeps them apart (`BANTER_GAP`, `BANTER_EVERY` per kind). The
  lines are `Cast.BOSS_LINES`, spoken by `RogueVoice` from each rogue's bank
  (`<rogue>_6.ogg`, added with `build_voices_maya.py --new-lines`).
- **Lore and records.** `BossLore` holds the story (the myth, each boss's
  four chapters, its arrival line, the loading screen's rumours) and opens a
  chapter by your record: `StatBook.boss(id)` (fought, beaten, standing,
  last blows, hard, damage, best time), kept by `release_boss`,
  `Boss.take_damage` and `_on_boss_died`. `Mastery` reads it (stats
  `boss_wins[:<id>]`, `bosses_beaten`, `boss_standing`, `boss_hard`,
  `boss_last_blows`, `boss_damage`); milestones and ladders marked `boss`
  show on the Trophy Room's Bosses page instead of the Milestones and
  Ladders pages. The rewards: coat pattern 6 (`coat_rakes` in
  `coat_lib.gdshaderinc`), gun skin pattern 6, the "froth" beat-down burst
  and the "kernel" colour. The full story, and the quest line it leads to,
  is `docs/LORE.md`.

## The Kernel Hunt (player against environment)

`KernelHunt` is the quest line's data and your record in it (the acts, the
prologue's island seed, its rangers and waves; `note_result`, `done`,
`best`, kept in the PlayerProfile). The menu's `QuestPanel` sets
`KernelHunt.playing`, and the game reads it like `Run.in_match`: mode
"kernel", the act's map, its fixed seed.

- **MatchManager mode "kernel"** brings no lobby (`opponents` 0) and no
  balloon: `setup` makes a `MissionDirector`, which spawns the rangers
  (cast members, dressed and voiced as themselves, team 1, their own
  favourite guns, `AIBrain.hold` at a post round the Barn watching outward),
  and `begin_drop` hands over to `MissionDirector.begin`, which puts everyone
  on their feet at the Barn and starts PLAYING. Beat-downs go to
  `_mission_down` (your trackers and arsenal count; nothing goes in the
  `RivalBook`, since the Touched aren't the cast) and on to the director.
- **The director** finds the Big Red Barn, the Carrot Patch and Boulder
  Bluff among the island's POIs and runs a small stage machine (BRIEFING,
  WAVE, BREATHER, OUTRO, OVER). A wave spawns all its Touched at once, at the
  Patch or out to the sides (`_wave_spot`), each with `AIBrain.hold` on a spot
  in the Barn's yard: they march on it and fight anyone they see (teams are on,
  so on sight), standing where they hold (`hold_low` off). The Barn's meter
  is worn by every Touched in the yard each second. A Touched is any
  species, wearing coat pattern 7 (veins from Voronoi edges, the glow
  crawling up them by height) as its overlay, which also gives it its
  gold-green rim; the giant is a beaver `CritterDef` duplicated with
  `body_scale` and `max_health` raised. Between waves the director patches
  the Barn, restocks the rangers and drops a `SupplyDrop` behind it.
- **The ending** is `MissionOutro`, played when the last wave's held (via
  `MatchManager.mission_outro`, which the game answers with its rig, HUD and
  controller, like a boss's arrival): its own Camera3D, the letterbox and
  title card shared with `BossIntro` (`BossIntro.letterbox`, `title_card`),
  name tags and loot (their beams) put away while it plays. The rangers
  still standing are put in a line on the Barn's Bluff side (whichever side
  gives the clearest view out, by raycasts: `_blocked`), standing and
  `hold`ing a look at the Bluff; a long lens over their heads watches
  `BossFX.dust_column` (a slow world-space emitter, its particles turned to
  start upward) climb over the trees while Brutus's roar plays from it; then
  their faces for the `kr` lines; then a cut to the `TallySign` on the Barn's
  door (Label3Ds and chalk-mark boxes on a slate; `wipe_to` squashes them
  flat under `chalk_smudge.gdshader`'s streaks and chalks the new count). Then
  `MissionDirector.end`: `KernelHunt.note_result`, the Gazette's special
  edition, `MatchManager.end_mission`.
- **A boss's glowing eyes** are balls on its head bone at the boss.json's
  `eyes`, unless it has an `eye_mask`: then its own eyes glow, in its skin
  (`Boss._glow_eyes_in_skin`: the mask as the material's emission texture,
  multiplied, so they deform with the face). `boss_build.py` makes the mask
  (recipe paint `eyes`): the download's dark texels round each eye it's
  given, painted red, their real middles written back as the `eyes`.
- **Path queries are budgeted** (`AIBrain._set_dest`): a moving destination is
  re-pathed early only once it's moved 15% of the way off (at least 2 m), the
  re-path timers are jittered, a bot chasing a boss asks every 2 to 3 seconds,
  and all bots share `PATHS_PER_TICK` (1) queries a physics tick, the rest
  keeping their current path a tick. A boss turning up used to send 24 bots'
  queries (each up to 20 ms on the island's navmesh) into the same few frames.
  `tests/perf_boss.gd` measures a Boss Battle's frames through the arrival and
  the fight (Godot's physics-time monitor is the worst tick of each second);
  `tests/perf_match.gd` a Battle Royale's or a Team Battle's (the balloon, the
  landings, the fighting), each frame split into the game's code, what was
  deferred after it (the skeletons), the physics engine and the rendering, and
  the frames over 50 ms noted with when they came.
- **The rangers' lines** are `Cast.KERNEL_LINES` (`kt`, `kw`, `ks`, `ky`, `kb`,
  `kg`, `kc`, `kd`, `kr`; Act I's `pt`, `pc`, `pp`, `pf`, `pl`, `pd`, `pw`,
  `pb`, `pk`), voiced for every rogue like every other line, said by the
  ranger nearest you and kept apart per kind.

### Act I, The Carrot Patch

`MissionDirector.make(id)` gives an act its own director: `PatchMission`
extends the prologue's, keeping the rangers, the Touched, the tally (at 0
now: `tally_days`) and the talk, and overriding `begin`, `_process`, the bar
on the HUD (`bar_title`, `bar_fill`, `bar_status`, `bar_warn`, `bar_good`,
`bar_shown`: `MissionBar` only draws what the director says) and the ending.
It runs three parts (`step`), the rangers sticking by you (`AIBrain.escort`,
as your squad does in a Team Battle; `AIBrain.release` ends a hold):

- **TRACK**: five `GlowCarrot`s on a wandering trail from the Barn to the
  Patch (`TRAIL`, on clear ground: `Island.clear_loot_spot`). A GlowCarrot is
  a `LootCrate` like the acorn shrine: held interact pulls it (only yours,
  only the lit one; `channel_verb` names it on the HUD), with
  `kernel_glow.gdshader` over the carrot (an additive rim, veins crawling in
  world space, a pulse) and a beam while it's lit. Each lights in turn, and
  the Touched come up out of the dirt round it (`_spawn_touched` now takes a
  post of their own to hold).
- **BURN**: three `BurnSpot`s, on the Patch's two rows (`Island` keeps the
  carrot_patch POI's `rows` now) and the bed square to them. A spot fills
  while any of your side stands in its ring and none of the Touched does
  (faster with more of you), stops with one of theirs in it, dies back with
  nobody; full, it lights a `Fire`. The rangers `hold` posts inside the rings
  still to go; the Touched rush them from the Bluff side every `RUSH_EVERY`.
  All three alight, the whole Patch burns (a bigger `Fire`) and the ground
  drums (`Events.explosion` shakes the camera).
- **WAKE**: Boulder Bluff (a marker). Within `WAKE_AT` (or after
  `WAKE_ANYWAY`), `MatchManager.release_boss` brings Brutus down onto open
  ground between it and you, made at setup and parked like a Boss Battle's
  (`_make_boss`, at `BOSS_HEALTH` of his health: there are fewer of you),
  and the game plays `BossIntro` for him (`wants_boss`). The HUD's `BossBar`
  (`hide_waiting`) takes over from the mission's; the rogues shout about him
  (`_boss_banter` runs in a mission too). The Warren answers
  (`KernelHunt.ANSWER`): eight rogues spawned in the air round you, gliding
  down (`begin_freefall`, `AIBrain.drop_spot`).
- **His end**: `MatchManager._on_boss_died` routes a mission's boss to
  `MissionDirector.boss_down` (StatBook still counts him beaten) instead of
  ending the match; after his fall, `PatchOutro`. Both endings are
  `MissionCinematic`s (the camera, the HUD and name tags put away, the
  letterbox, the beats on a clock, skipping, putting it all back): PatchOutro
  shrinks him (his scale, around his feet) in his own dust while a light
  swells in his chest (`get_chest_position` follows the bones as he lies and
  shrinks), then puts Little Bru there (a `bun`, the runt: `body_scale` x0.8,
  no helmet, his gaze steered with `aim_point`) under the `StarfallKernel`
  (the acorn model, emissive, haloed, humming: `kernel_hum`), with the shots
  framed by the way he fell (`forward`).

Objectives (the lit carrot, rings still to go, the Bluff) are nodes in the
group `objectives`: the minimap draws a gold-green diamond for each, and the
HUD one on screen with its distance (pinned to the edge, pointing, when it's
off screen). `Fire` is GPU particles on a disc of evenly spread emission
points (a sunflower spiral), with procedural textures (`FXTextures.flame`,
`smoke_puff`): flames all over and a taller core, an additive glow, smoke
that climbs, embers, a flickering light and `fire_loop`. Its layers fade out
within 3.5 m of the camera, so standing in it doesn't fill the screen.

### Act II, The Clockwork Decree

`ClockworkMission` is the first act off the island: `KernelHunt` gives an
act its own `map` (here `toybox`, Toy Box Bash, at the same seed), and the
director overrides `setup` too (no Barn, no tally: the toy room's landmarks
from `island.pois`, the rangers, the Wound rogues, the stations, and the Tin
Tyrant made and parked as in Act I). `facing` says where the camera starts
looking. Three parts again:

- **FREE**: four rogues from `KernelHunt.WOUND`, on the enemy side, dressed
  as themselves under the Touched coat, a `WindKey` in their backs (brass, on
  the chest bone's attachment, placed from `OutfitFit`'s measure of the back
  like a pack), each holding a landmark with a few generic Wound
  (`_spawn_touched` takes what to call them now). A Wound rogue has
  `Critter.hold_on`: the blow that would beat it down leaves it on 1 HP and
  emits `held_on`, and the director winds it down: `spared` (nothing hurts
  it, `AIBrain` ignores it, `HoldRing` doesn't count it), its brain stopped,
  kneeling, its key slowing, and a `KeyPull` on it (a `LootCrate`, like the
  glowing carrot: held interact, only you). Pulled, it's freed: team 1, an
  ally tag, its own brain and escort; left `WIND_BACK` seconds, it winds
  itself back up.
- **BREAK**: three `WindingStation`s (a `StaticBody3D` of primitives in the
  toy paints, `CageKit.mat`: a riveted base, a banded drum, gears from
  `_gear_mesh`, the big key, a chute, a bulb). Area3D hitboxes with the
  `critter` meta take carrots like a boss's (`receive_shot`; its tin and its
  drum count differently), and `Explosion` hands blasts to anything in the
  group `blast_targets` (`receive_blast`). While active and you're near, each
  winds a Wound out of its chute every `WIND_EVERY` (`wound_out`). Broken,
  its drum, gears and key come off as `RigidBody3D` scrap.
- **STORM**: a `HoldRing` in Block Castle's courtyard (`BurnSpot` is a
  HoldRing now too: the ring, the counting and the filling are shared, the
  smoke and the fire are its own). Taken, a `WarrenFlag` goes up
  (`warren_flag.gdshader` flaps the cloth and draws the acorn), the
  `TyrantWatch` on the bookshelf (two red eyes and a sweeping `SpotLight3D`,
  all act long) glares at the castle, and he jumps: `Boss.entrance_from`
  makes `RobotBoss._entrance` an arc from there instead of a drop from the
  sky, and `BossIntro` follows him down.
- **His end**: `ClockworkOutro` (a `MissionCinematic`). He stays the boss,
  posed by hand (`poser`, from his fall's last key to standing, his own
  `walk_pose` for three steps, his key's turn), shrunk to `SMALL` round his
  feet; the second `StarfallKernel` rises from his key (`bone_point`), the
  first comes out of Buck Toothington's paws, and the two orbit each other
  and drift toward the room's door.

## Tests

`godot --headless --path . -s tests/run_tests.gd` runs:

* **IK and spread maths** (pure functions);
* **critter tests**: rig binding, paws on the grip, raycasts hitting
  hitboxes, a carrot kill, a ragdoll that lands on the floor, dismemberment;
* **island tests**: determinism, POIs on land, and a navmesh path across tiles;
* **player tests**, driven through real input events: [E] to pick up a gun,
  open a crate, auto-collect ammo, heal with a clover;
* **rules tests**: weapon balance sanity, rarity scaling and drop odds, the
  Briar's geometry, armor soak, gore-off, and swimming;
* **credits test**: every shipped asset file must have a license-checked
  credit, and every credited file must exist;
* a **full headless match** with 8 bots that must loot, fight and finish;
* **Kernel Hunt tests**: the quest line and its records, and the prologue,
  Act I and Act II played through headless (waves held; carrots pulled, rings
  lit, Brutus woken and beaten; Wound rogues unwound, stations broken, the
  castle taken, the Tin Tyrant beaten; the endings), and the ways each is
  lost. `run_tests.gd -- kernel::act_two` runs just the tests whose names
  match, in the files that do.

`tests/check_scripts.gd` compiles every script. CI
(`.github/workflows/tests.yml`) runs all of it on each push.
