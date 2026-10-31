class_name StarfallOutro
extends MissionCinematic
## How the Kernel Hunt ends (StarfallMission), once the Briar Heart is down,
## grey in the husk on Boulder Bluff. The light goes out of the Touched, and
## they blink and sit down, just critters again. The three Kernels it took
## come down off the night sky together, turning round each other closer and
## faster; the pieces of the husk lift off the Bluff and close round them,
## and in a flash there it is, whole for the first time since it fell: the
## Starfall Acorn, gold and humming, as big as the Big Red Barn. "They're
## putting themselves back together. It's the ACORN." It rises off the Bluff,
## slowly and then faster, up and up into the stars, while the Briar's wall
## withers away; at the front of the crowd watching it go are the three it
## made into giants, small again: Little Bru, Model No. 7 and Nibbles. "It's
## going home." It's a point of light, and then a star, a new one over
## Boulder Bluff. "Look. Up there. It's a star again." Little Bru, counting.
## Then the card: the Kernel Hunt, complete.

const DRAIN_AT := 0.4          ## the light goes out of the Touched
const GATHER_AT := 1.0         ## the three Kernels come down together over the husk
const HUSK_AT := 5.2           ## the husk's pieces lift off the Bluff, round them
const WHOLE_AT := 8.6          ## closed: a flash, and the Acorn, whole
const SAY_WHOLE := 9.4
const RISE_AT := 12.6          ## it goes up
const STAR_AT := 21.0          ## it's a star
const BRU_AT := 23.4           ## Little Bru, counting
const CARD_AT := 25.6
const LENGTH := 31.0
const RING := 30.0             ## metres from the Heart the crowd stands
const UP := 18.0               ## metres over the Heart's foot the Acorn comes together
const ACORN := 18.0            ## a Kernel's size times this: the whole Acorn (as big as the Barn)
const SKY := 1000.0            ## how far up it goes (a star)

var acorn: StarfallKernel
var star: Sprite3D
var bru: Critter
var nibbles: Critter
var seven: Boss
var kernels: Array[StarfallKernel] = []
var _heart: BriarHeart
var _feet := Vector3.ZERO      ## the Heart's foot
var _out := Vector3.BACK       ## (flat) from it toward the crowd
var _side := Vector3.RIGHT
var _crowd: Array[Critter] = []
var _husk: Array[Node3D] = []
var _husk_from: Array[Transform3D] = []
var _light: OmniLight3D
var _rise_from := Vector3.ZERO
var _sky_at := Vector3.ZERO


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	super._init(d, r, h, pc)
	name = "StarfallOutro"
	length = LENGTH


func _start() -> void:
	var mm := director.match_manager
	_heart = mm.boss as BriarHeart
	var p := mm.player
	var at: Vector3 = (director as StarfallMission).heart_pos if director is StarfallMission else (p.global_position if p else Vector3.ZERO)
	_feet = director._ground(Vector2(at.x, at.z))
	var toward := MissionDirector._flat((p.global_position if p and p.alive else _feet + Vector3.BACK) - _feet)
	_out = toward.normalized() if toward.length() > 1.0 else Vector3.BACK
	_side = _out.cross(Vector3.UP)
	_sky_at = _feet - _out * SKY + Vector3.UP * SKY   # (up, and away beyond the Bluff: over the trees, and in the shot)
	_light = OmniLight3D.new()
	_light.light_color = StarfallKernel.GLOW
	_light.light_energy = 0.0
	_light.omni_range = 70.0
	_light.shadow_enabled = false
	add_child(_light)
	if _heart:
		for k in _heart.kernels:
			if is_instance_valid(k):
				kernels.append(k)
		_husk = _heart.husk()
		for h in _husk:
			_husk_from.append(h.global_transform)
	# (whatever it didn't let go of comes out of it now)
	while kernels.size() < 3:
		var k := StarfallKernel.new()
		mm.world_root.add_child(k)
		k.global_position = _feet + Vector3.UP * (BriarHeart.H + 13.0) + _side * (kernels.size() - 1) * 4.0
		k.scale = Vector3.ONE * 2.2
		kernels.append(k)
	_gather()
	_little_ones()


## Everyone on your side still standing, in an arc in front of the Heart,
## looking at it; the Touched, where they are.
func _gather() -> void:
	var front: Array[Critter] = []
	var back: Array[Critter] = []
	for c in director.match_manager.alive_critters():
		if c.team != 1 or c.is_player:
			continue
		(front if director.rangers.has(c) else back).append(c)
	_crowd = front + back
	for row in [[front, RING], [back, RING + 5.0]]:
		var who: Array = row[0]
		for i in who.size():
			var c: Critter = who[i]
			var a := (i - (who.size() - 1) * 0.5) * (0.13 if row[1] == RING else 0.1)
			var at := director._ground_at(_feet + _out.rotated(Vector3.UP, a) * float(row[1]))
			_hold(c, at, _feet + Vector3.UP * UP)


func _hold(c: Critter, at: Vector3, look: Vector3) -> void:
	var face := MissionDirector._flat(look - at)
	c.place_at(at, atan2(-face.x, -face.z))
	var brain := c.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.escort = null
		brain.hold_low = false
		brain.forget()
		brain.hold(at, look, 60.0)


## The three it made into giants, small again, at the front: Little Bru,
## Model No. 7 and Nibbles (they could hear it, too).
func _little_ones() -> void:
	var mm := director.match_manager
	var at := _feet + _out * (RING - 6.0)
	var def: CritterDef = (load("res://data/critters/bun.tres") as CritterDef).duplicate()
	def.body_scale *= 0.8   # (the runt)
	def.wears_acorn_helmet = false
	bru = mm._spawn_critter(def, "Little Bru")
	bru.visual.apply_skin("midnight")   # (grey, like the giant he was)
	var hdef: CritterDef = (load("res://data/critters/hamster.tres") as CritterDef).duplicate()
	hdef.body_scale *= 0.85
	hdef.wears_acorn_helmet = false
	nibbles = mm._spawn_critter(hdef, "Nibbles")
	nibbles.visual.apply_skin("default")
	for c in [bru, nibbles]:
		c.team = 1
		c.max_health = 100000.0
		c.health = c.max_health
		if c.visual.name_tag:
			c.visual.name_tag.visible = false
	var look := _feet + Vector3.UP * UP
	_stand(bru, director._ground_at(at - _side * 2.2), look)
	_stand(nibbles, director._ground_at(at + _side * 2.2), look)
	# Model No. 7: the Tin Tyrant's tin, no taller than a bunny, standing stiff
	seven = RobotBoss.new()
	seven.setup(mm, 1)
	mm.world_root.add_child(seven)
	seven.thinking = false
	seven.alive = false
	seven.remove_from_group(&"bosses")
	seven.set_physics_process(false)
	seven._set_hittable(false)
	seven.scale = Vector3.ONE * 0.09
	var spot := director._ground_at(at)
	seven.global_position = spot
	var face := MissionDirector._flat(look - spot)
	seven.rotation.y = atan2(-face.x, -face.z)
	seven.visible = true
	seven.poser.clear()
	seven.poser.add_pose(seven.idle_pose(0.0), 1.0)
	seven.poser.apply()


func _stand(c: Critter, at: Vector3, look: Vector3) -> void:
	var face := MissionDirector._flat(look - at)
	c.place_at(at, atan2(-face.x, -face.z))
	c.look_pitch = 0.5


func _play(delta: float) -> void:
	if _beat("drain", DRAIN_AT):
		_free_the_touched()
	if t > GATHER_AT and t < WHOLE_AT:
		_orbit(delta)
	if _beat("husk", HUSK_AT):
		for i in _husk.size():
			var h := _husk[i]
			if is_instance_valid(h):
				h.reparent(director.match_manager.world_root, true)
	if t > HUSK_AT and t < WHOLE_AT:
		_close_husk()
	if _beat("whole", WHOLE_AT):
		_make_whole()
	if _beat("say_whole", SAY_WHOLE):
		director._shout("sa", 0, _keeper())
	if _beat("rise", RISE_AT):
		_rise_from = acorn.global_position if acorn else _feet + Vector3.UP * UP
		if _heart and is_instance_valid(_heart):
			_heart.crumble(6.0)
		Audio.play_at(&"starfall_chime", _rise_from, 6.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
	if t > RISE_AT and acorn:
		var u := clampf((t - RISE_AT) / (STAR_AT - RISE_AT), 0.0, 1.0)
		acorn.global_position = _rise_from.lerp(_sky_at, u * u * u)
		acorn.scale = Vector3.ONE * ACORN * lerpf(1.0, 0.6, u)
		_light.global_position = acorn.global_position
		_light.light_energy = lerpf(3.5, 0.0, clampf(u * 2.0, 0.0, 1.0))
	if _beat("going", RISE_AT + 1.8):
		director._shout("sg", 0, _nearest(_feet + _out * RING))
	if _beat("star", STAR_AT):
		_become_star()
	if star:
		var tw := 0.75 + 0.25 * sin(t * 5.3) * sin(t * 2.1)
		star.modulate = Color(Color(1.0, 0.98, 0.85).lerp(StarfallKernel.GLOW, 0.25), clampf(tw, 0.0, 1.0))
	if _beat("again", STAR_AT + 1.2):
		director._shout("sg", 1, _keeper(_nearest(_feet + _out * RING)))
	if _beat("seven", STAR_AT + 0.4) and seven:
		Audio.play_at(&"toy_beep", seven.get_eye_position(), 2.0, 0.0, {"max_distance": 120.0, "unit_size": 8.0})
		BossFX.sparks(seven.get_eye_position() + Vector3.UP * 0.2, Vector3.UP, 0.8)
	if _beat("squeak", STAR_AT + 2.6) and nibbles:
		var s := Audio.play_at(&"hurt_squeak", nibbles.get_eye_position(), 0.0, 0.0)
		if s:
			s.pitch_scale = 1.5
	if _beat("bru", BRU_AT) and bru:
		Events.taunt.emit(bru, "...a hundred and twelve. A hundred and thirteen.")
	if _beat("photo", RISE_AT + 2.6):
		_take_photo("The Starfall Acorn, going home.")
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  COMPLETE", "THE STARFALL", "The Acorn's gone home, and the Briar's just a briar.")


## The light goes out of the Touched: they blink, and sit down, critters again.
func _free_the_touched() -> void:
	for c in director.match_manager.alive_critters():
		if c.team != 2:
			continue
		c.team = 1
		for m in c.visual.meshes:
			m.material_overlay = null
		if c.visual.name_tag:
			c.visual.name_tag.visible = false
		_tags.erase(c.visual.name_tag)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.forget()
			brain.hold(c.global_position, _feet + Vector3.UP * UP, 60.0)
		c.want_crouch = true
		FX.burst(c.get_chest_position(), Vector3.UP, {"amount": 10, "lifetime": 1.6, "speed": Vector2(0.6, 2.0), "spread": 60.0,
			"gravity": -0.4, "size": 0.18, "scale": Vector2(0.6, 1.3), "color": Color(StarfallKernel.GLOW, 0.7), "fade": true,
			"additive": true, "damping": 1.5})


## The three Kernels come down over the husk and turn round each other,
## closer and faster.
func _orbit(delta: float) -> void:
	var at := _feet + Vector3.UP * UP
	var k := clampf((t - GATHER_AT) / 3.0, 0.0, 1.0)
	var spin := (t - GATHER_AT) * lerpf(0.8, 4.0, clampf((t - GATHER_AT) / (WHOLE_AT - GATHER_AT), 0.0, 1.0))
	var r := lerpf(6.0, 1.2, clampf((t - GATHER_AT) / (WHOLE_AT - GATHER_AT), 0.0, 1.0))
	for i in kernels.size():
		var kern := kernels[i]
		if not is_instance_valid(kern):
			continue
		var a := spin + TAU * i / kernels.size()
		var want := at + Vector3(cos(a), 0.3 * sin(a * 2.0), sin(a)) * r
		kern.global_position = kern.global_position.lerp(want, clampf(delta * 2.0 * k + 0.004, 0.0, 1.0))
	if _light:
		_light.global_position = at
		_light.light_energy = lerpf(0.0, 6.0, k)


## The husk's pieces, lifting off the Bluff and closing round the Kernels.
func _close_husk() -> void:
	var at := _feet + Vector3.UP * UP
	var u := clampf((t - HUSK_AT) / (WHOLE_AT - HUSK_AT), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	for i in _husk.size():
		var h := _husk[i]
		if not is_instance_valid(h) or i >= _husk_from.size():
			continue
		var from := _husk_from[i]
		var side := -1.0 if i == 0 else 1.0
		# the halves come face to face round where the Kernels are; the cap goes on top
		var want: Transform3D
		if i < 2:
			want = Transform3D(Basis(Vector3.FORWARD, side * PI * 0.5).scaled(Vector3(0.75, 0.75, 0.75)), at + _side * side * 0.2)
		else:
			want = Transform3D(Basis(Vector3.RIGHT, 0.0).scaled(Vector3(0.75, 0.75, 0.75)), at + Vector3.UP * 6.0)
		h.global_transform = from.interpolate_with(want, e)


## A flash, and it's whole: the Starfall Acorn, gold and humming.
func _make_whole() -> void:
	var at := _feet + Vector3.UP * UP
	for kern in kernels:
		if is_instance_valid(kern):
			kern.queue_free()
	for h in _husk:
		if is_instance_valid(h):
			h.queue_free()
	acorn = StarfallKernel.new()
	director.match_manager.world_root.add_child(acorn)
	acorn.global_position = at
	acorn.glow_k = 0.3   # (it's as big as the Barn: a Kernel's glow, that size, would be blinding)
	acorn.gild()
	acorn.scale = Vector3.ONE * ACORN * 0.6
	create_tween().tween_property(acorn, "scale", Vector3.ONE * ACORN, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	acorn.pulse(1.0)
	FX.burst(at, Vector3.UP, {"amount": 120, "lifetime": 2.6, "speed": Vector2(4.0, 18.0), "spread": 180.0, "gravity": -0.2,
		"size": 0.7, "scale": Vector2(0.6, 1.5), "color": Color(StarfallKernel.GLOW, 0.95), "fade": true, "additive": true,
		"damping": 1.1, "aabb": 60.0})
	FX.muzzle(at, Vector3.UP, true, Color(1.0, 0.97, 0.85, 1.0))
	Events.explosion.emit(at, 18.0)
	Audio.play_at(&"starfall_chime", at, 8.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
	_light.global_position = at
	_light.light_energy = 3.5
	_light.light_color = Color(1.0, 0.85, 0.5)   # (gold, now it's whole)
	_shake = 0.6


## It's so far up it's a point of light: a star, a new one over the Bluff.
func _become_star() -> void:
	var at := acorn.global_position if acorn else _sky_at
	if acorn:
		acorn.queue_free()
		acorn = null
	star = Sprite3D.new()
	star.texture = FXTextures.soft_blob()
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.fixed_size = true
	star.pixel_size = 0.0005
	star.shaded = false
	star.no_depth_test = true
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	director.match_manager.world_root.add_child(star)
	star.global_position = at
	for k in 2:   # (a glint: a long thin cross through it)
		var g := Sprite3D.new()
		g.texture = FXTextures.soft_blob()
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		g.fixed_size = true
		g.pixel_size = 0.0004
		g.shaded = false
		g.no_depth_test = true
		g.modulate = Color(1.0, 0.97, 0.82, 0.75)
		g.scale = Vector3(6.0, 0.14, 1.0) if k == 0 else Vector3(0.14, 6.0, 1.0)
		star.add_child(g)
	var flare := Sprite3D.new()
	flare.texture = FXTextures.soft_blob()
	flare.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flare.fixed_size = true
	flare.pixel_size = 0.0013
	flare.shaded = false
	flare.no_depth_test = true
	flare.modulate = Color(StarfallKernel.GLOW, 0.9)
	star.add_child(flare)
	var tw := flare.create_tween()
	tw.tween_property(flare, "modulate:a", 0.0, 1.6)
	tw.tween_callback(flare.queue_free)


## The shots: wide and low on the grey Heart, the Kernels coming down over
## it; in close as the husk closes round them and the Acorn's whole; the
## crowd's faces lit by it; then low behind the three little ones, tilting
## up after it into the stars, and holding on the new one.
func _aim() -> void:
	var shake := _jolt()
	var at := _feet + Vector3.UP * UP
	if t < HUSK_AT:
		_cam.fov = 56.0
		_cam.global_position = _feet + _out * (RING + 12.0) + _side * 10.0 + Vector3.UP * 6.0 + shake
		_cam.look_at(_feet + Vector3.UP * lerpf(16.0, 13.0, clampf((t - GATHER_AT) / 4.0, 0.0, 1.0)), Vector3.UP)
	elif t < WHOLE_AT + 1.6:
		var k := clampf((t - HUSK_AT) / (WHOLE_AT + 1.6 - HUSK_AT), 0.0, 1.0)
		_cam.fov = 50.0
		_cam.global_position = at + _out * lerpf(42.0, 34.0, k) + _side * lerpf(10.0, 4.0, k) + Vector3.UP * lerpf(-6.0, -3.0, k) + shake
		_cam.look_at(at + shake * 4.0, Vector3.UP)
	elif t < RISE_AT:
		var front := _feet + _out * (RING - 6.0)
		_cam.fov = 48.0
		_cam.global_position = front - _out * 7.0 + _side * 1.5 + Vector3.UP * 1.0 + shake * 0.3
		_cam.look_at(front + _out * 2.0 + Vector3.UP * 1.3, Vector3.UP)
	else:
		# low behind the three, in front of the crowd, looking up the way it goes
		# (up and away beyond the Bluff: it stays in the shot, getting smaller)
		var front := _feet + _out * (RING - 6.0)
		var k := clampf((t - RISE_AT) / (LENGTH - RISE_AT), 0.0, 1.0)
		_cam.fov = 66.0
		var pos := front + _out * lerpf(3.4, 2.6, k) + Vector3.UP * 1.0   # (in front of the crowd: their guns out of the shot)
		_cam.global_position = pos + shake * 0.4
		_cam.look_at(pos - _out * 100.0 + Vector3.UP * 58.0, Vector3.UP)   # (30 degrees up: the three at the foot of it)


## Skipped (or over): it's gone home, the Briar's gone, the Touched are free.
func _ending() -> void:
	if not _beats.has("drain"):
		_free_the_touched()
	for kern in kernels:
		if is_instance_valid(kern):
			kern.queue_free()
	for h in _husk:
		if is_instance_valid(h):
			h.queue_free()
	if acorn:
		acorn.queue_free()
		acorn = null
	if star == null:
		_become_star()
	if director.match_manager.storm.active:
		director.match_manager.storm.wither(1.0)


func _nearest(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.global_position.distance_to(at) < best_d:
			best_d = c.global_position.distance_to(at)
			best = c
	return best if best else director.ranger_near(at, but)


## Buck Toothington (he carried the Kernels), unless he's `but` or down.
func _keeper(but: Critter = null) -> Critter:
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.display_name == KernelHunt.RANGERS[0]:
			return c
	return _nearest(_feet + _out * RING, but)
