class_name PatchOutro
extends MissionCinematic
## How Act I ends (PatchMission), once Brutus is down and has fallen. The
## camera leaves you. A gold-green light swells in his chest and he shrinks,
## smaller and smaller in his own dust, until what's lying there is a little
## grey bunny: Little Bru, the runt of the Carrot Patch warren who ate the
## glowing carrots (BossLore, docs/LORE.md). Over him hangs what was inside
## him: the first Starfall Kernel, glowing and humming (StarfallKernel). The
## rangers have gathered round: "It's... it's just a bunny." "Little Bru? Is
## that you?" Bru looks up at it, the way he used to look at the stars, and one
## of them says what it is, and another that it's humming, like it's calling
## something across the lake. Then the card: ACT I COMPLETE.

const GLOW_AT := 0.6
const SHRINK_AT := 1.7
const SHRINK := 4.0            ## seconds he takes to shrink
const FACES_AT := 7.4
const BRU_AT := 12.4
const CARD_AT := 18.2
const LENGTH := 22.5
const SMALL := 0.045           ## of his size, at the end of it (about a bunny's)
const KERNEL_OVER := 0.85      ## metres over Bru's head it hangs
const RING := 9.5              ## metres from his feet the rangers stand

var bru: Critter
var kernel: StarfallKernel
var _boss: Boss
var _feet := Vector3.ZERO      ## where he stood (what he shrinks toward: Bru is there after)
var _lie := Vector3.FORWARD    ## the way he fell (his body lies along it from his feet)
var _out := Vector3.BACK       ## from his feet toward where the rangers stand (behind them)
var _side := Vector3.RIGHT     ## the side the camera sees him from
var _from_scale := Vector3.ONE
var _glow: OmniLight3D
var _crowd: Array[Critter] = []


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	super._init(d, r, h, pc)
	name = "PatchOutro"
	length = LENGTH


func _start() -> void:
	_boss = director.match_manager.boss
	var p := director.match_manager.player
	if _boss and is_instance_valid(_boss):
		_feet = director._ground_at(_boss.global_position)
		var f := MissionDirector._flat(_boss.forward())
		_lie = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
		_from_scale = _boss.scale
	else:
		_feet = director._ground_at(p.global_position if p else director.bluff_pos)
	_out = -_lie
	# the camera on whichever side of him the view's clearest
	_side = _lie.cross(Vector3.UP)
	var middle := _feet + _lie * Boss.HEIGHT * 0.38 + Vector3.UP * 3.0
	if _blocked(middle + _side * 40.0 + Vector3.UP * 9.0, middle) > _blocked(middle - _side * 40.0 + Vector3.UP * 9.0, middle):
		_side = -_side
	_glow = OmniLight3D.new()
	_glow.light_color = StarfallKernel.GLOW
	_glow.light_energy = 0.0
	_glow.omni_range = 18.0
	_glow.shadow_enabled = false
	add_child(_glow)
	_gather()


## How much is in the way from `from` to `to` (rays round the line of sight).
func _blocked(from: Vector3, to: Vector3) -> int:
	var world := get_viewport().find_world_3d()
	if world == null:
		return 0
	var n := 0
	for off: Vector3 in [Vector3.ZERO, Vector3.UP * 2.0, Vector3.DOWN * 2.0, _lie * 6.0, -_lie * 6.0]:
		if world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from + off, to + off, Layers.WORLD)):
			n += 1
	return n


## Everyone on your side still standing, in an arc behind his feet, looking
## at him (the Barn Rangers in front, the Warren behind).
func _gather() -> void:
	var front: Array[Critter] = []
	var back: Array[Critter] = []
	for c in director.match_manager.alive_critters():
		if c.team != 1 or c.is_player:
			continue
		(front if director.rangers.has(c) else back).append(c)
	_crowd = front + back
	for row in [[front, RING, 0.3], [back, RING + 4.5, 0.24]]:
		var who: Array = row[0]
		for i in who.size():
			var c: Critter = who[i]
			var a := (i - (who.size() - 1) * 0.5) * float(row[2])
			var at := director._ground_at(_feet + _out.rotated(Vector3.UP, a) * float(row[1]))
			var face := MissionDirector._flat(_feet - at)
			c.place_at(at, atan2(-face.x, -face.z))
			var brain := c.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.escort = null
				brain.hold_low = false
				brain.forget()
				brain.hold(at, _feet + Vector3.UP * 1.0, 60.0)


func _play(delta: float) -> void:
	if _beat("glow", GLOW_AT):
		_shake = 0.25
		FX.burst(_chest() + Vector3.UP * 1.0, Vector3.UP, {"amount": 40, "lifetime": 2.2, "speed": Vector2(1.0, 4.0), "spread": 160.0,
			"gravity": -0.4, "size": 0.35, "scale": Vector2(0.6, 1.4), "color": Color(StarfallKernel.GLOW, 0.9), "fade": true,
			"additive": true, "damping": 1.6, "aabb": 16.0})
		create_tween().tween_property(_glow, "light_energy", 9.0, SHRINK_AT + SHRINK - GLOW_AT)
		var groan := Audio.play_at(&"boss_roar", _chest() + Vector3.UP * 2.0, 0.0, 0.0, {"max_distance": 400.0, "unit_size": 30.0})
		if groan:
			groan.pitch_scale = 0.55   # (a long, low groan: going out of him)
	if _beat("shrink", SHRINK_AT) and _boss and is_instance_valid(_boss):
		create_tween().tween_property(_boss, "scale", _from_scale * SMALL, SHRINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if t > SHRINK_AT and t < SHRINK_AT + SHRINK and fmod(t - SHRINK_AT, 0.6) < delta:
		var k := _size()
		BossFX.dust(_chest(), 3.0 + 14.0 * k)
		_shake = 0.18 + 0.2 * k
	if _beat("bru", SHRINK_AT + SHRINK - 0.15):
		_become_bru()
	if _glow:
		_glow.global_position = _chest() + Vector3.UP * 0.5
	if bru:
		# his eyes on his paws, then (once it's over him) up at the Kernel, the way he used to look at the stars
		bru.aim_point = kernel.global_position if kernel and t >= BRU_AT else bru.global_position + MissionDirector._flat(-_out) * 1.2
		bru.want_crouch = t < BRU_AT
	if _beat("bunny", FACES_AT + 0.4):
		director._shout("pb", 0, _nearest(_feet + _out * RING))
	if _beat("bru?", FACES_AT + 3.0):
		var first := _nearest(_feet + _out * RING)
		director._shout("pb", 1, _keeper(first))
	if _beat("kernel", BRU_AT + 1.0):
		director._shout("pk", 0, _nearest(_feet + _out * RING))
		if kernel:
			kernel.pulse(0.6)
	if _beat("across", BRU_AT + 3.8):
		var first := _nearest(_feet + _out * RING)
		director._shout("pk", 1, _nearest(_feet + _out * RING, first))
		if kernel:
			kernel.pulse(1.0)
	if _beat("photo", CARD_AT - 0.7):
		_take_photo("Little Bru, and what was inside him.")
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  ACT I COMPLETE", "THE FIRST KERNEL",
			"To be continued in Act II: %s." % String(KernelHunt.act("clockwork_decree").get("title", "The Clockwork Decree")))


## How big he still is (1 as he fell, SMALL at the end).
func _size() -> float:
	if _boss == null or not is_instance_valid(_boss) or not _boss.visible:
		return SMALL
	return clampf(_boss.scale.x / maxf(_from_scale.x, 0.001), SMALL, 1.0)


## His chest as he lies there (where the light swells), as big as he is now.
func _chest() -> Vector3:
	if _boss and is_instance_valid(_boss) and _boss.visible:
		return _boss.get_chest_position()
	return _feet + Vector3.UP * 0.6


## The giant's gone: a flash, and there's Little Bru, with the Kernel over him.
func _become_bru() -> void:
	if bru:
		return
	if _boss and is_instance_valid(_boss):
		_boss.visible = false
	FX.muzzle(_feet + Vector3.UP * 0.8, Vector3.UP, true, Color(1.0, 0.97, 0.85, 1.0))
	BossFX.dust(_feet, 4.0)
	var def: CritterDef = (load("res://data/critters/bun.tres") as CritterDef).duplicate()
	def.body_scale *= 0.8   # (the runt)
	def.wears_acorn_helmet = false
	bru = director.match_manager._spawn_critter(def, "Little Bru")
	bru.team = 1
	bru.max_health = 100000.0
	bru.health = bru.max_health
	bru.visual.apply_skin("midnight")   # (grey, like the giant he was)
	if bru.visual.name_tag:
		bru.visual.name_tag.visible = false
	bru.place_at(_feet, atan2(-_out.x, -_out.z))
	var head := bru.visual.rig.world_head_top if bru.visual.rig else 1.0
	kernel = StarfallKernel.new()
	director.match_manager.world_root.add_child(kernel)
	kernel.global_position = _feet + Vector3.UP * 0.9
	create_tween().tween_property(kernel, "global_position", _feet + Vector3.UP * (head + KERNEL_OVER), 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _glow:
		create_tween().tween_property(_glow, "light_energy", 0.0, 1.2)


## The shots: the whole of him from the side, pushing in as he shrinks; the
## rangers' faces; then low by Bru, looking up past him at the Kernel.
func _aim() -> void:
	var shake := _jolt()
	if t < FACES_AT:
		var k := _size()
		var look := _chest()
		var far := lerpf(8.5, 46.0, k)
		_cam.fov = 46.0
		_cam.global_position = look + _side * far - _lie * far * 0.3 + Vector3.UP * lerpf(1.6, 12.0, k) + shake * (1.0 + 4.0 * k)
		_cam.look_at(look + shake * 3.0, Vector3.UP)
	elif t < BRU_AT:
		var k := clampf((t - FACES_AT) / (BRU_AT - FACES_AT), 0.0, 1.0)
		_cam.fov = 44.0
		_cam.global_position = _feet + _out * lerpf(3.6, 3.2, k) + Vector3.UP * 1.45 + shake * 0.3
		_cam.look_at(_feet + _out * RING + Vector3.UP * 1.1, Vector3.UP)
	else:
		var k := clampf((t - BRU_AT) / (LENGTH - BRU_AT), 0.0, 1.0)
		var bp := bru.global_position if bru else _feet
		var head := bru.visual.rig.world_head_top if bru and bru.visual.rig else 1.0
		_cam.fov = 48.0
		_cam.global_position = bp + _out * lerpf(4.4, 3.8, k) + _side * 1.5 + Vector3.UP * 0.5 + shake * 0.3
		_cam.look_at(bp + Vector3.UP * (head * 0.75 + KERNEL_OVER * 0.5), Vector3.UP)


## Skipped (or over): he's Bru, whatever.
func _ending() -> void:
	_become_bru()


## Whoever's standing nearest `at` (not `but`).
func _nearest(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.global_position.distance_to(at) < best_d:
			best_d = c.global_position.distance_to(at)
			best = c
	return best if best else director.ranger_near(at, but)


## Buck Toothington (he keeps the tally: he knew Bru), unless he's `but` or down.
func _keeper(but: Critter = null) -> Critter:
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.display_name == KernelHunt.RANGERS[0]:
			return c
	return _nearest(_feet + _out * RING, but)
