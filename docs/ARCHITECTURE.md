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
  world/      Island · Terrain · Scatter · WorldLighting · Pickup · LootCrate · shaders/
  match/      MatchManager · Storm (the Briar) · Dropship (the picnic balloon)
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
from the rest pose:

1. A gait clock advances from the critter's *real* velocity (bunnies, the
   hop gait; everyone else, a run cycle), so feet never skate when speed changes.
2. The hips bob, lean into speed, squash on landing and flinch when hit
   (a damped spring).
3. Aim pitch/yaw is spread across spine → chest → neck → head.
4. The held gun is placed in front of the shoulder (with recoil kick and a
   reload tilt), and **analytic two-bone IK** (`IKMath.solve_two_bone`, unit
   tested) puts both paws on the gun's real `Muzzle`/`SupportGrip` markers.
5. Legs solve two-bone IK to the gait's foot targets.

Ears and tails run through Godot's `SpringBoneSimulator3D` after the poser, so
they flop with every hop, landing and hit.

> Engine detail worth knowing: `Skeleton3D` restores the *un-modified* pose
> after skinning, so `get_bone_global_pose()` outside the modifier stack
> returns the rest pose. Code that needs the rendered pose reads it from
> `BoneAttachment3D` nodes or ragdoll bodies (`CritterVisual.current_bone_global`).

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
   collapsed, so only the real skinned limb remains, wearing the pose it had
   when it came off. It flies as a `RigidBody3D`.
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

Rockets are real nodes with smoke trails; `Explosion` applies falloff damage
with a cover check, shoves every ragdoll, gib and prop in range, and blows
limbs off nearby corpses.

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
5. **Navigation**: the navmesh is baked as 4×4 tiles in parallel
   (`bake_from_source_geometry_data_async`). Each tile's bake area is grown by
   its border so neighbouring tiles stitch exactly.

## Battle-royale loop

`MatchManager` spawns 1 player plus N bots (species weighted from
`data/critters/`), scatters loot and crates, and boards everyone onto the
**picnic balloon** (`Dropship`). Bots pick a landing spot, often a POI, and
jump when the balloon is closest. Everyone free-falls and then pops a
dandelion glider.

The **Briar** (`Storm`) runs staged wait/shrink cycles. Each new safe circle
is placed inside the old one and nudged onto land. The bots' `FLEE_STORM` mode
queries the same API the HUD uses. The last critter standing wins.

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
* a **full headless match** with 8 bots that must loot, fight and finish.

`tests/check_scripts.gd` compiles every script. CI
(`.github/workflows/tests.yml`) runs all of it on each push.
