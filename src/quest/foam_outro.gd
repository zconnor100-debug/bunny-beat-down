class_name FoamOutro
extends MissionCinematic
## How Act III ends (FoamMission), once Nibbles is down in the bedding by
## his dammed falls. A gold-green light swells in his cheeks and he shrinks,
## smaller and smaller in a froth of foam, until what's sitting there is a
## little golden hamster, cheeks full: the children's Nibbles, a good boy
## (BossLore, docs/LORE.md). He gives a squeak and spits out what was in
## them: the third Starfall Kernel, no bigger than a seed, humming. "He's...
## tiny." "Nibbles? Good boy. Who's a good boy?" Buck Toothington brings out
## the other two, and the three find each other in the air and turn round
## each other, brighter and brighter. Then the ground shakes, and the Briar
## comes up through the bedding all round them: "All three of them. Together."
## "The Briar... it's coming up through the floor!" Then the card.

const GLOW_AT := 0.6
const SHRINK_AT := 1.6
const SHRINK := 3.6            ## seconds he takes to shrink
const SPIT_AT := 6.6           ## the third Kernel, out of his cheeks
const FACES_AT := 7.8
const KERNELS_AT := 12.8       ## the other two join it
const BRIAR_AT := 17.4         ## and the Briar comes for them
const CARD_AT := 22.6
const LENGTH := 27.0
const SMALL := 0.05            ## of his size, at the end of it (about a hamster's)
const RING := 10.0             ## metres from him the rangers stand
const KERNEL_UP := 2.2

var little: Critter
var kernel: StarfallKernel
var others: Array[StarfallKernel] = []
var briar: BriarBurst
var _boss: Boss
var _feet := Vector3.ZERO
var _lie := Vector3.FORWARD    ## (flat) the way he fell
var _out := Vector3.BACK       ## (flat) from him toward where the rangers stand
var _side := Vector3.RIGHT
var _from_scale := Vector3.ONE
var _glow: OmniLight3D
var _crowd: Array[Critter] = []
var _pair := Vector3.ZERO      # (where the three meet)


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	super._init(d, r, h, pc)
	name = "FoamOutro"
	length = LENGTH


func _start() -> void:
	_boss = director.match_manager.boss
	var p := director.match_manager.player
	if _boss and is_instance_valid(_boss):
		_feet = director._ground_at(_boss.global_position)
		_from_scale = _boss.scale
		_lie = MissionDirector._flat(_boss.forward()).normalized()
	else:
		_feet = director._ground_at(p.global_position if p else director.barn_pos)
	_out = -_lie
	_side = _out.cross(Vector3.UP)
	_pair = _feet + _out * (RING * 0.4) + Vector3.UP * 3.0
	_glow = OmniLight3D.new()
	_glow.light_color = StarfallKernel.GLOW
	_glow.light_energy = 0.0
	_glow.omni_range = 16.0
	_glow.shadow_enabled = false
	add_child(_glow)
	_gather()


## Everyone on your side still standing, in an arc behind him, looking at him.
func _gather() -> void:
	var front: Array[Critter] = []
	var back: Array[Critter] = []
	for c in director.match_manager.alive_critters():
		if c.team != 1 or c.is_player:
			continue
		(front if director.rangers.has(c) else back).append(c)
	_crowd = front + back
	for row in [[front, RING], [back, RING + 4.5]]:
		var who: Array = row[0]
		for i in who.size():
			var c: Critter = who[i]
			var a := (i - (who.size() - 1) * 0.5) * (0.24 if row[1] == RING else 0.18)
			var at := director._ground_at(_feet + _out.rotated(Vector3.UP, a) * float(row[1]))
			var face := MissionDirector._flat(_feet - at)
			c.place_at(at, atan2(-face.x, -face.z))
			var brain := c.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.escort = null
				brain.hold_low = false
				brain.forget()
				brain.hold(at, _feet + Vector3.UP * 0.6, 60.0)


func _play(delta: float) -> void:
	if _beat("glow", GLOW_AT):
		var at := _chest()
		FX.burst(at, Vector3.UP, {"amount": 36, "lifetime": 2.0, "speed": Vector2(1.0, 4.0), "spread": 140.0, "gravity": -0.4,
			"size": 0.35, "scale": Vector2(0.6, 1.4), "color": Color(StarfallKernel.GLOW, 0.9), "fade": true, "additive": true,
			"damping": 1.6, "aabb": 16.0})
		create_tween().tween_property(_glow, "light_energy", 8.0, SHRINK_AT + SHRINK - GLOW_AT)
	if _beat("shrink", SHRINK_AT) and _boss and is_instance_valid(_boss):
		var tw := create_tween()
		tw.tween_property(_boss, "scale", _from_scale * SMALL, SHRINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_boss, "global_position", _feet, SHRINK)
	if t > SHRINK_AT and t < SHRINK_AT + SHRINK and fmod(t - SHRINK_AT, 0.6) < delta:
		var k := 1.0 - (t - SHRINK_AT) / SHRINK
		BossFX.dust(_chest(), 2.0 + 6.0 * k, Color(0.94, 0.99, 0.88, 0.35))   # (a froth of foam)
		_shake = 0.15 + 0.2 * k
	if _beat("little", SHRINK_AT + SHRINK - 0.15):
		_become_little()
	if _glow:
		_glow.global_position = _chest() + Vector3.UP * 0.5
	if _beat("spit", SPIT_AT):
		_spit()
	if _beat("tiny", FACES_AT + 0.4):
		director._shout("nb", 0, _nearest(_feet + _out * RING))
	if _beat("good_boy", FACES_AT + 3.0):
		director._shout("nb", 1, _keeper(_nearest(_feet + _out * RING)))
	if _beat("kernels", KERNELS_AT):
		_bring_the_others()
	if t > KERNELS_AT + 0.4:
		_orbit(delta)
	if _beat("together", KERNELS_AT + 1.2):
		director._shout("nk", 0, _keeper())
	if _beat("briar", BRIAR_AT):
		briar = BriarBurst.new(RING * 1.5)
		director.match_manager.world_root.add_child(briar)
		briar.global_position = _feet + _out * (RING * 0.4)
		briar.burst()
		_shake = 0.8
		for k in [kernel] + others:
			if k:
				k.pulse(1.0)
	if _beat("floor", BRIAR_AT + 1.6):
		director._shout("nk", 1, _nearest(_feet + _out * RING, _keeper()))
	if _beat("photo", CARD_AT - 0.6):
		_take_photo("Nibbles, a good boy again, and the third Kernel.")
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  ACT III COMPLETE", "THE THIRD KERNEL",
			"To be continued in the Finale: %s." % String(KernelHunt.act("starfall").get("title", "The Starfall")))


func _chest() -> Vector3:
	if little:
		return little.get_chest_position()
	if _boss and is_instance_valid(_boss) and _boss.visible:
		return _boss.get_chest_position()
	return _feet + Vector3.UP * 0.6


## The giant's gone: a flash, and there's Nibbles, the size a hamster should be.
func _become_little() -> void:
	if little:
		return
	if _boss and is_instance_valid(_boss):
		_boss.visible = false
	FX.muzzle(_feet + Vector3.UP * 0.6, Vector3.UP, true, Color(1.0, 0.97, 0.85, 1.0))
	BossFX.dust(_feet, 3.0, Color(0.94, 0.99, 0.88, 0.5))
	var def: CritterDef = (load("res://data/critters/hamster.tres") as CritterDef).duplicate()
	def.body_scale *= 0.85
	def.wears_acorn_helmet = false
	little = director.match_manager._spawn_critter(def, "Nibbles")
	little.team = 1
	little.max_health = 100000.0
	little.health = little.max_health
	little.visual.apply_skin("default")
	if little.visual.name_tag:
		little.visual.name_tag.visible = false
	little.place_at(_feet, atan2(-_out.x, -_out.z))
	little.want_crouch = true
	if _glow:
		create_tween().tween_property(_glow, "light_energy", 0.0, 1.2)


## A squeak, and out of his cheeks comes the third Kernel, the size of a seed.
func _spit() -> void:
	_become_little()
	var at := little.get_eye_position() + MissionDirector._flat(_out) * 0.3 if little else _feet + Vector3.UP
	Audio.play_at(&"hurt_squeak", at, 2.0, 0.0).pitch_scale = 1.4
	kernel = StarfallKernel.new()
	director.match_manager.world_root.add_child(kernel)
	kernel.global_position = at
	kernel.scale = Vector3.ONE * 0.6   # (the seed-sized one)
	FX.muzzle(at, Vector3.UP, true, Color(StarfallKernel.GLOW, 0.9))
	create_tween().tween_property(kernel, "global_position", _feet + Vector3.UP * KERNEL_UP, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if little:
		little.want_crouch = false
		create_tween().tween_property(little, "look_pitch", 0.8, 1.2).set_trans(Tween.TRANS_SINE)


## Buck Toothington brings out the first two.
func _bring_the_others() -> void:
	var buck := _keeper()
	for i in 2:
		var k := StarfallKernel.new()
		director.match_manager.world_root.add_child(k)
		var at := (buck.get_chest_position() if buck else _feet + _out * RING + Vector3.UP * 1.2) + _side * (i - 0.5) * 0.8
		k.global_position = at
		FX.muzzle(at, Vector3.UP, true, Color(StarfallKernel.GLOW, 0.8))
		others.append(k)


## The three find each other in the air over him and turn round each other,
## closer and faster.
func _orbit(delta: float) -> void:
	var all: Array[StarfallKernel] = []
	if kernel:
		all.append(kernel)
	all.append_array(others)
	var k := clampf((t - KERNELS_AT - 0.4) / 3.0, 0.0, 1.0)
	var spin := (t - KERNELS_AT) * lerpf(1.2, 3.4, clampf((t - KERNELS_AT) / (BRIAR_AT - KERNELS_AT), 0.0, 1.0))
	var r := lerpf(2.4, 1.1, k)
	for i in all.size():
		var a := spin + TAU * i / all.size()
		var want := _pair + Vector3(cos(a), 0.25 * sin(a * 2.0), sin(a)) * r
		all[i].global_position = all[i].global_position.lerp(want, clampf(delta * 2.5 * k + 0.002, 0.0, 1.0))


## The shots: him from above as he shrinks (pushing in); low by little
## Nibbles as he spits it out; their faces; then wide and low, the three
## Kernels turning over him as the Briar comes up all round.
func _aim() -> void:
	var shake := _jolt()
	if t < SPIT_AT:
		var size := lerpf(1.0, SMALL, clampf((t - SHRINK_AT) / SHRINK, 0.0, 1.0))
		var c := _chest()
		var dir := (_out + _side * 0.6 + Vector3.UP * 0.7).normalized()
		_cam.fov = 46.0
		_cam.global_position = c + dir * (30.0 * size + 3.4) + shake
		_cam.look_at(c + shake * 6.0, Vector3.UP)
	elif t < FACES_AT:
		var bp := little.global_position if little else _feet
		_cam.fov = 44.0
		_cam.global_position = bp + _out * 3.0 + _side * 1.0 + Vector3.UP * 0.7 + shake * 0.3
		_cam.look_at(bp + Vector3.UP * lerpf(0.5, 1.5, clampf((t - SPIT_AT) / 1.2, 0.0, 1.0)), Vector3.UP)
	elif t < KERNELS_AT:
		var line := _feet + _out * RING
		_cam.fov = 50.0
		_cam.global_position = _feet + _out * 3.6 + Vector3.UP * 2.0 + shake * 0.3
		_cam.look_at(line + Vector3.UP * 1.7, Vector3.UP)
	else:
		var k := clampf((t - KERNELS_AT) / (LENGTH - KERNELS_AT), 0.0, 1.0)
		var pull := 1.0 if t > BRIAR_AT else 0.0
		_cam.fov = 54.0 + 6.0 * pull
		_cam.global_position = _feet + _side * lerpf(9.0, 12.0, k) + _out * lerpf(2.0, -2.0, k) + Vector3.UP * lerpf(1.6, 3.2, k) + shake
		_cam.look_at(_pair.lerp(_feet + Vector3.UP * 1.0, 0.35) + Vector3.UP * pull * 1.5, Vector3.UP)


## Skipped (or over): he's little Nibbles, and the third Kernel's out.
func _ending() -> void:
	_become_little()
	if kernel == null:
		_spit()


func _nearest(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.global_position.distance_to(at) < best_d:
			best_d = c.global_position.distance_to(at)
			best = c
	return best if best else director.ranger_near(at, but)


## Buck Toothington (he's carried the Kernels), unless he's `but` or down.
func _keeper(but: Critter = null) -> Critter:
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.display_name == KernelHunt.RANGERS[0]:
			return c
	return _nearest(_feet + _out * RING, but)
