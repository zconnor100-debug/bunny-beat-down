class_name Layers
## Physics layer bits — keep in sync with [layer_names] in project.godot.

const WORLD := 1 << 0      # terrain, trees, rocks, crates (static)
const CRITTERS := 1 << 1   # CharacterBody3D movement capsules
const HITBOXES := 1 << 2   # per-bone Area3D hit volumes of living critters
const RAGDOLL := 1 << 3    # PhysicalBone3D bodies of dead critters
const PICKUPS := 1 << 4    # loot on the ground
const DEBRIS := 1 << 5     # gibs, dropped helmets, physics props
const WATER := 1 << 6

## What a carrot projectile can hit.
const SHOT_MASK := WORLD | HITBOXES | RAGDOLL | DEBRIS
## What blocks line of sight (AI vision, explosion occlusion).
const SIGHT_MASK := WORLD
