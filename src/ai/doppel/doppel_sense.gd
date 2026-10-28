class_name DoppelSense
extends RefCounted
## What the Doppelbunny learns from: a critter's situation in a fight, as
## numbers (`features`: all relative to it, so they mean the same for you and
## for the Doppel playing as you), and what it did about it (`label`: the
## decisions a bot makes, read off the controls, not the controls themselves:
## copying a thumb makes a jittery bot, copying a choice makes one that plays
## like you).

const INPUTS := 24
## Which way it moved, against its nearest enemy (one of these)...
const MOVES := ["hold", "push", "back", "left", "right"]
## ...and what else it did (any of these).
const FLAGS := ["sprint", "crouch", "prone", "jump", "fire", "heal", "grenade", "melee"]
const OUTPUTS := 13                  ## MOVES then FLAGS (DoppelNet)
const LABELS := 9                    ## a label: the move's index, then each flag (0 or 1)
const SIGHT := 75.0                  ## an enemy further off than this isn't a fight
const NEAR := 30.0                   ## "how many are near"
## Guns by how they fight: [none, close, mid, far, blast].
const GUN_CLASS := {&"carrot_pistol": 1, &"carrot_smg": 1, &"carrot_shotgun": 1, &"carrot_rifle": 2, &"carrot_lmg": 2,
	&"carrot_sniper": 3, &"carrot_rocket_launcher": 4}


## Its nearest living enemy within SIGHT (gang mates aren't enemies), or null.
static func nearest_enemy(me: Critter) -> Critter:
	var best: Critter = null
	var best_d := SIGHT
	for n in me.get_tree().get_nodes_in_group(&"critters"):
		var o := n as Critter
		if o == null or o == me or not o.alive or (o.gang != "" and o.gang == me.gang):
			continue
		var d := o.global_position.distance_to(me.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best


## Its situation (INPUTS numbers, each about -1..1). `mm`: the match (for
## the Briar; null in a bare arena), `since_hit`: seconds since it was hurt.
static func features(me: Critter, enemy: Critter, mm: Node, since_hit: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(INPUTS)
	f[0] = me.health / maxf(me.max_health, 1.0)
	f[1] = me.armor / maxf(me.max_armor, 1.0)
	var w := me.current_weapon()
	if w:
		f[2] = float(w.ammo_in_mag) / maxf(float(w.magazine_size()), 1.0)
		f[3] = 1.0 if me.inventory.ammo[w.data.ammo_type] > 0 else 0.0
	f[4 + int(GUN_CLASS.get(w.data.id, 2) if w else 0)] = 1.0
	f[9] = minf(me.inventory.clovers / 3.0, 1.0)
	f[10] = minf(me.inventory.grenades / 4.0, 1.0)
	var yaw := me.look_yaw
	if enemy:
		var to := enemy.global_position - me.global_position
		f[11] = 1.0
		f[12] = minf(to.length() / SIGHT, 1.0)
		var bearing := wrapf(atan2(-to.x, -to.z) - yaw, -PI, PI)
		f[13] = sin(bearing)
		f[14] = cos(bearing)
		f[15] = enemy.health / maxf(enemy.max_health, 1.0)
		var back := -to
		back.y = 0.0
		var look := enemy.look_direction()
		look.y = 0.0
		f[16] = look.normalized().dot(back.normalized()) if back.length_squared() > 1e-4 and look.length_squared() > 1e-4 else 0.0
	else:
		f[12] = 1.0
	var near := 0
	for n in me.get_tree().get_nodes_in_group(&"critters"):
		var o := n as Critter
		if o and o != me and o.alive and (o.gang == "" or o.gang != me.gang) and o.global_position.distance_to(me.global_position) < NEAR:
			near += 1
	f[17] = minf(near / 4.0, 1.0)
	if mm and mm.has_method("storm_threat") and mm.has_method("safe_center"):
		f[18] = 1.0 if mm.storm_threat(me.global_position) > 0.0 else 0.0
		var c: Vector2 = mm.safe_center()
		var r: float = mm.safe_radius()
		var off := Vector2(me.global_position.x - c.x, me.global_position.z - c.y)
		f[19] = clampf((r - off.length()) / 100.0, -1.0, 1.0)
		if off.length_squared() > 1.0:
			var bearing := wrapf(atan2(off.x, off.y) - yaw, -PI, PI)   # (toward the centre: -off)
			f[20] = sin(bearing)
			f[21] = cos(bearing)
	f[22] = minf(since_hit / 5.0, 1.0)
	f[23] = 1.0 if me.is_reloading() else 0.0
	return f


## What it did in a moment of a fight: how it moved (`moved`: its average
## stick, in the world, flat) against its enemy at `to_enemy`, and its
## `flags` (FLAGS names that happened). LABELS numbers.
static func label(moved: Vector3, to_enemy: Vector3, flags: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LABELS)
	out[0] = move_of(moved, to_enemy)
	for i in FLAGS.size():
		out[1 + i] = 1.0 if flags.get(FLAGS[i], false) else 0.0
	return out


## The MOVES index for a stick (in the world) against an enemy that way.
static func move_of(moved: Vector3, to_enemy: Vector3) -> int:
	moved.y = 0.0
	to_enemy.y = 0.0
	if moved.length() < 0.3 or to_enemy.length_squared() < 1e-4:
		return 0
	var m := moved.normalized()
	var e := to_enemy.normalized()
	var along := m.dot(e)
	if along > 0.5:
		return 1
	if along < -0.5:
		return 2
	return 4 if m.dot(e.cross(Vector3.UP)) > 0.0 else 3
