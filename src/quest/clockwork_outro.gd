class_name ClockworkOutro
extends MissionCinematic
## How Act II ends (ClockworkMission), once the Tin Tyrant is down on his
## face in front of his castle. The key in his back slows and stops. A
## gold-green light comes out of the hole it turns in, and he shrinks, smaller
## and smaller in his own steam, until what's lying there is a tin toy robot
## no taller than a bunny: Model No. 7, from the toy room windowsill
## (BossLore, docs/LORE.md). Out of his back comes what was in his winding
## drum: the second Starfall Kernel (StarfallKernel). The rangers have
## gathered round: "He's... a toy. He's just a toy." "Model Number Seven. It
## says so on his foot." Then he gets up, turns to them, and does what he did
## for thirty years on the windowsill: three steps, a beep and sparks. Buck
## Toothington brings out the first Kernel, and the two pull at each other,
## and then both the same way: toward the hamster cage. ACT II COMPLETE.

const STILL_AT := 1.6          ## his key's stopped
const GLOW_AT := 1.0
const SHRINK_AT := 2.0
const SHRINK := 4.0            ## seconds he takes to shrink
const KERNEL_AT := 6.2
const FACES_AT := 8.2
const UP_AT := 13.2            ## he gets up...
const TURN_AT := 14.6          ## ...turns to them...
const WALK_AT := 15.6          ## ...three steps...
const BEEP_AT := 17.6          ## ...a beep and sparks
const KERNELS_AT := 18.6       ## the first Kernel joins the second
const PULL_AT := 22.2          ## and both pull, the same way
const CARD_AT := 26.0
const LENGTH := 30.2
const SMALL := 0.09            ## of his size, at the end of it (about a bunny's)
const KERNEL_UP := 2.4         ## metres over him the Kernel hangs
const RING := 11.0             ## metres from his feet the rangers stand
## The way to the hamster cage from the toy room (the door in its west wall: ToyRoom).
const DOOR := Vector3(-ToyFloor.HX, ToyFloor.FLOOR, 190.0)

var kernel: StarfallKernel
var first: StarfallKernel
var _boss: Boss
var _feet := Vector3.ZERO
var _fwd := Vector3.FORWARD    ## (flat) the way he fell: his head's that way
var _out := Vector3.BACK       ## (flat) from his feet toward where the rangers stand
var _side := Vector3.RIGHT
var _from_scale := Vector3.ONE
var _lying := {}               # his pose, fallen
var _key_turn := 0.0           # degrees
var _key_speed := 120.0
var _glow: OmniLight3D
var _crowd: Array[Critter] = []
var _walked := 0.0             # how far his three steps have taken him
var _yaw0 := 0.0
var _pair := Vector3.ZERO      # where the two Kernels meet


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	super._init(d, r, h, pc)
	name = "ClockworkOutro"
	length = LENGTH


func _start() -> void:
	_boss = director.match_manager.boss
	var p := director.match_manager.player
	if _boss and is_instance_valid(_boss):
		_feet = director._ground_at(_boss.global_position)
		_from_scale = _boss.scale
		_fwd = MissionDirector._flat(_boss.forward()).normalized()
		_yaw0 = _boss.rotation.y
		var fall: BossAction = _boss._death_action()
		_lying = fall.keys.back()[1] if not fall.keys.is_empty() else {}
	else:
		_feet = director._ground_at(p.global_position if p else director.castle_pos)
	_out = -_fwd
	_side = _out.cross(Vector3.UP)
	_glow = OmniLight3D.new()
	_glow.light_color = StarfallKernel.GLOW
	_glow.light_energy = 0.0
	_glow.omni_range = 16.0
	_glow.shadow_enabled = false
	add_child(_glow)
	_pair = _feet + _out * (RING * 0.45) + Vector3.UP * 3.2
	_gather()


## Everyone on your side still standing, in an arc behind his feet, looking
## at him (the rangers and the rogues you freed in front, the rest behind).
func _gather() -> void:
	var front: Array[Critter] = []
	var back: Array[Critter] = []
	var m := director as ClockworkMission
	for c in director.match_manager.alive_critters():
		if c.team != 1 or c.is_player:
			continue
		(front if director.rangers.has(c) or (m and m.freed.has(c)) else back).append(c)
	_crowd = front + back
	for row in [[front, RING], [back, RING + 4.5]]:
		var who: Array = row[0]
		for i in who.size():
			var c: Critter = who[i]
			var a := (i - (who.size() - 1) * 0.5) * (0.22 if row[1] == RING else 0.18)
			var at := director._ground_at(_feet + _out.rotated(Vector3.UP, a) * float(row[1]))
			var face := MissionDirector._flat(_feet - at)
			c.place_at(at, atan2(-face.x, -face.z))
			var brain := c.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.escort = null
				brain.hold_low = false
				brain.forget()
				brain.hold(at, _feet + Vector3.UP * 0.8, 60.0)


func _play(delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	# his key: slowing to a stop; then, as he gets up, wound once more
	if t < STILL_AT:
		_key_speed = lerpf(120.0, 0.0, t / STILL_AT)
	elif t > UP_AT and t < BEEP_AT + 0.4:
		_key_speed = 260.0   # (his last winding: what gets him up for his three steps)
	else:
		_key_speed = maxf(0.0, _key_speed - delta * 400.0)
	_key_turn = fmod(_key_turn + _key_speed * delta, 360.0)
	if _beat("glow", GLOW_AT):
		var at := _key_point()
		FX.burst(at, Vector3.UP, {"amount": 36, "lifetime": 2.0, "speed": Vector2(1.0, 4.0), "spread": 120.0,
			"gravity": -0.4, "size": 0.35, "scale": Vector2(0.6, 1.4), "color": Color(StarfallKernel.GLOW, 0.9), "fade": true,
			"additive": true, "damping": 1.6, "aabb": 16.0})
		create_tween().tween_property(_glow, "light_energy", 8.0, SHRINK_AT + SHRINK - GLOW_AT)
		var s := Audio.play_at(&"wind_key", at, 2.0, 0.0, {"max_distance": 400.0, "unit_size": 30.0})
		if s:
			s.pitch_scale = 0.45
	if _beat("shrink", SHRINK_AT):
		var tw := create_tween()
		tw.tween_property(_boss, "scale", _from_scale * SMALL, SHRINK).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_boss, "global_position", _feet, SHRINK)
	if t > SHRINK_AT and t < SHRINK_AT + SHRINK and fmod(t - SHRINK_AT, 0.7) < delta:
		var k := 1.0 - (t - SHRINK_AT) / SHRINK
		BossFX.dust(_key_point(), 2.0 + 7.0 * k, Color(0.92, 0.92, 0.9, 0.3))   # (a puff of steam: thin, he's still there to see)
		BossFX.sparks(_key_point(), Vector3.UP, 0.6 + k)
		_shake = 0.15 + 0.2 * k
	if _beat("kernel", KERNEL_AT):
		_kernel_out()
	_pose(t)
	if _glow:
		_glow.global_position = _key_point() + Vector3.UP * 0.6
	if _beat("toy", FACES_AT + 0.4):
		director._shout("ob", 0, _nearest(_feet + _out * RING))
	if _beat("seven", FACES_AT + 3.0):
		director._shout("ob", 1, _keeper(_nearest(_feet + _out * RING)))
	if _beat("turn", TURN_AT):
		var tw := create_tween()
		tw.tween_property(_boss, "rotation:y", _yaw0 + PI, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Audio.play_at(&"wind_key", _boss.global_position + Vector3.UP, -2.0, 0.0).pitch_scale = 1.6
	if t >= WALK_AT and t < WALK_AT + 1.8:
		var step_len := Boss.HEIGHT * SMALL * 0.2
		var was := _walked
		_walked = minf(3.0 * step_len, _walked + delta * 3.0 * step_len / 1.8)
		_boss.global_position = director._ground(Vector2(_feet.x, _feet.z) + Vector2(_out.x, _out.z) * _walked)
		if floori(was / step_len) != floori(_walked / step_len) or (was == 0.0 and _walked > 0.0):
			Audio.play_at(&"boss_clank", _boss.global_position, -10.0, 0.05).pitch_scale = 2.4
	if _beat("beep", BEEP_AT):
		Audio.play_at(&"toy_beep", _boss.get_eye_position(), 2.0, 0.0, {"max_distance": 120.0, "unit_size": 8.0})
		BossFX.sparks(_boss.get_eye_position() + Vector3.UP * 0.2, Vector3.UP, 0.8)
		_eyes(14.0)
		var tw := create_tween()
		tw.tween_method(_eyes, 14.0, 0.4, 0.9)
	if _beat("kernels", KERNELS_AT):
		_first_out()
	if _beat("pulling", KERNELS_AT + 0.6):
		director._shout("ok", 0, _keeper())
	if t > KERNELS_AT + 0.5 and kernel and first:
		_orbit(delta)
	if _beat("cage", PULL_AT + 0.4):
		director._shout("ok", 1, _nearest(_feet + _out * RING, _keeper()))
		if kernel:
			kernel.pulse(1.0)
		if first:
			first.pulse(1.0)
	if _beat("photo", CARD_AT - 0.6):
		_take_photo("Model No. 7, and what was in his winding drum.")
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  ACT II COMPLETE", "THE SECOND KERNEL",
			"To be continued in Act III: %s." % String(KernelHunt.act("foam_at_the_falls").get("title", "Foam at the Falls")))


## Him, posed as he is at `time`: lying where he fell (his key turning, then
## still), getting up, standing; his three stiff steps.
func _pose(time: float) -> void:
	var up := clampf((time - UP_AT) / 1.2, 0.0, 1.0)
	up = up * up * (3.0 - 2.0 * up)
	_boss.poser.clear()
	_boss.poser.add_pose(_lying, 1.0 - up)
	if time >= WALK_AT and time < WALK_AT + 1.8:
		var phase := (time - WALK_AT) / 1.8 * 3.0 * PI
		_boss.poser.add_pose(_boss.walk_pose(phase, 1.0), 1.0)
	_boss.poser.add_pose({&"key": Vector3(_key_turn, 0, 0)}, 1.0)
	_boss.poser.apply()


## His eyes' glow (dim once the Kernel's out of him; a flash with his beep).
func _eyes(energy: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	if _boss._eye_mat:
		_boss._eye_mat.emission_energy_multiplier = energy
	for m in _boss._eye_skin:
		m.emission_energy_multiplier = energy


## Where his key goes into his back (where the light comes out, and the Kernel).
func _key_point() -> Vector3:
	if _boss and is_instance_valid(_boss) and _boss.poser.has(&"key"):
		return _boss.bone_point(&"key", 0.0)
	return _feet + Vector3.UP * 0.5


## The second Kernel, up out of his back.
func _kernel_out() -> void:
	if kernel:
		return
	var at := _key_point()
	kernel = StarfallKernel.new()
	director.match_manager.world_root.add_child(kernel)
	kernel.global_position = at
	FX.muzzle(at, Vector3.UP, true, Color(StarfallKernel.GLOW, 0.9))
	create_tween().tween_property(kernel, "global_position", _feet + Vector3.UP * KERNEL_UP, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _glow:
		create_tween().tween_property(_glow, "light_energy", 0.0, 1.2)
	create_tween().tween_method(_eyes, 2.5, 0.4, 1.2)   # (what lit them is out of him)


## The first Kernel, out of Buck Toothington's paws (he's carried it since the Carrot Patch).
func _first_out() -> void:
	if first:
		return
	var buck := _keeper()
	var at := buck.get_chest_position() + MissionDirector._flat(_feet - buck.global_position).normalized() * 0.6 if buck \
		else _feet + _out * RING + Vector3.UP * 1.2
	first = StarfallKernel.new()
	director.match_manager.world_root.add_child(first)
	first.global_position = at
	FX.muzzle(at, Vector3.UP, true, Color(StarfallKernel.GLOW, 0.8))


## The two, drawn together: they meet over him and turn round each other;
## then they both pull the same way, toward the door (and the hamster cage
## beyond it).
func _orbit(delta: float) -> void:
	var k := clampf((t - KERNELS_AT - 0.5) / 2.5, 0.0, 1.0)
	var pull := clampf((t - PULL_AT) / 3.0, 0.0, 1.0)
	var toward := MissionDirector._flat(DOOR - _pair).normalized()
	var mid := _pair + toward * 2.2 * pull
	var a := (t - KERNELS_AT) * (1.4 + pull * 2.0)
	var r := lerpf(2.6, 1.5, k)
	var round_ := Vector3(cos(a), 0.0, sin(a)) * r
	kernel.global_position = kernel.global_position.lerp(mid + round_, clampf(delta * 2.5 * k + 0.002, 0.0, 1.0))
	first.global_position = first.global_position.lerp(mid - round_, clampf(delta * 2.5 * k + 0.002, 0.0, 1.0))


## The shots: him from above and behind as he stops and shrinks (pushing in);
## their faces; low in front of him as he gets up and comes; then wide, low,
## the two Kernels over him pulling toward the door.
func _aim() -> void:
	var shake := _jolt()
	if t < FACES_AT:
		# from behind and above his back, as far off as he's big (pushing in as he shrinks)
		var size := lerpf(1.0, SMALL, clampf((t - SHRINK_AT) / SHRINK, 0.0, 1.0))
		var kp := _key_point()
		var look := kp + Vector3.UP * size * 2.0
		if kernel:
			look = look.lerp(kernel.global_position, clampf((t - KERNEL_AT) / 0.8, 0.0, 1.0) * 0.55)
		var dir := (_out + _side * 0.55 + Vector3.UP * 0.8).normalized()
		_cam.fov = 46.0
		_cam.global_position = kp + dir * (lerpf(36.0, 30.0, clampf(t / SHRINK_AT, 0.0, 1.0)) * size + 3.4) + shake
		_cam.look_at(look + shake * 6.0, Vector3.UP)
	elif t < UP_AT:
		var k := clampf((t - FACES_AT) / (UP_AT - FACES_AT), 0.0, 1.0)
		var line := _feet + _out * RING
		_cam.fov = 50.0
		_cam.global_position = _feet + _out * lerpf(3.8, 3.3, k) + Vector3.UP * 2.0 + shake * 0.3
		_cam.look_at(line + Vector3.UP * 1.7, Vector3.UP)
	elif t < KERNELS_AT:
		var k := clampf((t - UP_AT) / (KERNELS_AT - UP_AT), 0.0, 1.0)
		var bp := _boss.global_position if _boss else _feet
		_cam.fov = 44.0
		_cam.global_position = _feet + _out * lerpf(6.6, 6.2, k) + _side * 1.6 + Vector3.UP * 1.1 + shake * 0.3
		_cam.look_at(bp + Vector3.UP * 1.25, Vector3.UP)
	else:
		var k := clampf((t - KERNELS_AT) / (LENGTH - KERNELS_AT), 0.0, 1.0)
		var bp := _boss.global_position if _boss else _feet
		var toward := MissionDirector._flat(DOOR - _pair).normalized()
		var across := toward.cross(Vector3.UP)
		if across.dot(_out) < 0.0:
			across = -across
		_cam.fov = 52.0
		_cam.global_position = bp + across * lerpf(7.5, 6.5, k) - toward * 2.0 + Vector3.UP * 1.0 + shake * 0.3
		_cam.look_at(_pair.lerp(bp + Vector3.UP * 1.0, 0.45) + toward * 1.2 * k, Vector3.UP)


## Skipped (or over): he's Model No. 7, standing, and the Kernel's out.
func _ending() -> void:
	if _boss and is_instance_valid(_boss):
		_boss.scale = _from_scale * SMALL
		_pose(maxf(t, UP_AT + 1.2))
	_kernel_out()


## Whoever's standing nearest `at` (not `but`).
func _nearest(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.global_position.distance_to(at) < best_d:
			best_d = c.global_position.distance_to(at)
			best = c
	return best if best else director.ranger_near(at, but)


## Buck Toothington (he's carried the first Kernel), unless he's `but` or down.
func _keeper(but: Critter = null) -> Critter:
	for c in _crowd:
		if is_instance_valid(c) and c.alive and c != but and c.display_name == KernelHunt.RANGERS[0]:
			return c
	return _nearest(_feet + _out * RING, but)
