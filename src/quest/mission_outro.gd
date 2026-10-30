class_name MissionOutro
extends MissionCinematic
## How the Kernel Hunt's prologue ends (MissionDirector), once the last wave
## is beaten. The camera leaves you. The rangers have gathered on the Barn's
## Boulder Bluff side, and the first shot looks out past them: the ground
## shakes, a column of dust goes up over the trees at the Bluff, and
## something roars. Then their faces, as one asks what that was and another
## says where it came from. Then the tally on the Barn's door, rubbed out and
## chalked back to zero, and the card: DAYS SINCE BRUTUS: 0. Brutus is
## heard, not seen (BossLore, docs/LORE.md). Jump, fire or accept skips it
## (MissionCinematic: the camera, the bars, putting everything back).

const REACT_AT := 4.0          ## the cut to the rangers' faces
const TALLY_AT := 9.0          ## the cut to the Barn's door
const CARD_AT := 12.6
const LENGTH := 17.0
const PLUME_FARTHEST := 125.0  ## metres off the dust column goes up (the Bluff, or toward it: seen through the haze)

var _to_bluff := Vector3.FORWARD
var _side := Vector3.RIGHT
var _line := Vector3.ZERO      ## where the rangers stand, looking at the Bluff
var _plume := Vector3.ZERO     ## where the dust goes up
var _crowd: Array[Critter] = []


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	super._init(d, r, h, pc)
	name = "MissionOutro"
	length = LENGTH


func _start() -> void:
	_to_bluff = MissionDirector._flat(director.bluff_pos - director.barn_pos).normalized()
	_side = _to_bluff.cross(Vector3.UP)
	var far := minf(MissionDirector._flat(director.bluff_pos - director.barn_pos).length(), PLUME_FARTHEST)
	_plume = director._ground_at(director.barn_pos + _to_bluff * far)
	_gather()


## The rangers still standing, in a loose line on the Barn's Bluff side,
## standing (not crouched) and looking out at it. (The camera's just cut
## away: they're simply there.)
func _gather() -> void:
	# on whichever side of the Barn the view out to the Bluff is clearest
	var best := INF
	for shift: float in [0.0, -7.0, 7.0, -14.0, 14.0]:
		var at := director.barn_pos + _to_bluff * 22.0 + _side * shift
		var blocked := _blocked(at - _to_bluff * 9.5 + Vector3.UP * 2.6, _plume + Vector3.UP * 22.0) + absf(shift) * 0.01
		if blocked < best:
			best = blocked
			_line = director._ground_at(at)
	for r in director.rangers:
		if is_instance_valid(r) and r.alive:
			_crowd.append(r)
	var n := _crowd.size()
	for i in n:
		var r := _crowd[i]
		var at := _line + _side * ((i - (n - 1) * 0.5) * 2.4) + _to_bluff * (0.6 if i % 2 == 0 else -0.5)
		at = director._ground_at(at)
		r.place_at(at, atan2(-_to_bluff.x, -_to_bluff.z))
		var brain := r.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.hold_low = false
			brain.forget()
			brain.hold(at, _plume + Vector3.UP * 20.0, 60.0)


## How much stands between `from` and `to` in the first 70 m: rays a little
## above and below the line of sight, and how many of them hit something.
func _blocked(from: Vector3, to: Vector3) -> float:
	var world := get_viewport().find_world_3d()
	if world == null:
		return 0.0
	var space := world.direct_space_state
	var dir := (to - from).normalized()
	var n := 0.0
	for up: float in [-1.4, -0.6, 0.0, 0.8, 1.6]:
		for across: float in [-1.5, 1.5]:
			var a := from + Vector3.UP * up + _side * across
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 70.0, Layers.WORLD)
			if space.intersect_ray(q):
				n += 1.0
	return n


func _play(_delta: float) -> void:
	if _beat("rumble", 0.5):
		_shake = 0.45
		Audio.play_at(&"boss_stomp", _plume, 10.0, 0.0, {"max_distance": 3000.0, "unit_size": 120.0})
	if _beat("dust", 1.0):
		BossFX.dust_column(_plume, 3.5)
		BossFX.dust(_plume + Vector3.UP * 2.0, 40.0)
	if _beat("roar", 1.6):
		_shake = 1.0
		Audio.play_at(&"boss_roar", _plume + Vector3.UP * 10.0, 16.0, 0.0, {"max_distance": 3000.0, "unit_size": 150.0})
	if _beat("what", REACT_AT + 0.5):
		director._shout("kr", 0, _nearest(_line + _to_bluff * 4.0))
	if _beat("where", REACT_AT + 2.9):   # ("What... was THAT?" takes its time)
		var first := _nearest(_line + _to_bluff * 4.0)
		director._shout("kr", 1, _nearest(_line + _to_bluff * 4.0, first))
	if _beat("wipe", TALLY_AT + 0.8) and director.tally:
		director.tally.wipe_to(0)
	if _beat("zero", TALLY_AT + 2.4):
		var keeper: Critter = null
		for r in _crowd:
			if r.display_name == KernelHunt.RANGERS[0] and r.alive:
				keeper = r   # (the tally's his)
		director._shout("kr", 2, keeper if keeper else _nearest(_line))
	if _beat("photo", TALLY_AT + 3.25):
		_take_photo("The tally on the Big Red Barn's door, back at zero.")
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  PROLOGUE COMPLETE", "DAYS SINCE BRUTUS: 0",
			"To be continued in Act I: %s." % String(KernelHunt.act("carrot_patch").get("title", "The Carrot Patch")))


## The ranger standing nearest `at` (not `but`).
func _nearest(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for r in _crowd:
		if r.alive and r != but and r.global_position.distance_to(at) < best_d:
			best_d = r.global_position.distance_to(at)
			best = r
	return best if best else director.ranger_near(at, but)


## The three shots: out past the rangers to the Bluff (pushing in slowly),
## their faces, then the tally on the Barn's door.
func _aim() -> void:
	var shake := _jolt()
	if t < REACT_AT:
		var k := clampf(t / REACT_AT, 0.0, 1.0)
		var pos := _line - _to_bluff * lerpf(11.0, 9.5, k) + _side * 1.6 + Vector3.UP * 2.3
		_cam.fov = 40.0   # (long: the Bluff close, the rangers' heads along the bottom under it)
		_cam.global_position = pos + shake
		_cam.look_at(_plume + Vector3.UP * 15.0 + shake * 8.0, Vector3.UP)
	elif t < TALLY_AT:
		var k := clampf((t - REACT_AT) / (TALLY_AT - REACT_AT), 0.0, 1.0)
		_cam.fov = 44.0
		_cam.global_position = _line + _to_bluff * lerpf(6.4, 5.8, k) + Vector3.UP * 1.7 + shake * 0.3   # (over the grass)
		_cam.look_at(_line + Vector3.UP * 1.05, Vector3.UP)
	else:
		var sign_at := director.tally.global_position if director.tally else director.barn_pos + Vector3.UP * 2.8
		var facing := director.tally.global_transform.basis.z.normalized() if director.tally else Vector3.BACK
		var k := clampf((t - TALLY_AT) / (LENGTH - TALLY_AT), 0.0, 1.0)
		_cam.fov = 40.0
		_cam.global_position = sign_at + facing * lerpf(3.6, 3.0, k) + Vector3.UP * 0.15 + shake * 0.3
		_cam.look_at(sign_at, Vector3.UP)


## Over (or skipped): the tally's at zero whatever.
func _ending() -> void:
	if director.tally and director.tally.count != 0:
		director.tally.wipe_to(0, 0.2)
