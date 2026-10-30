class_name MissionOutro
extends Node
## How the Kernel Hunt's prologue ends (MissionDirector), once the last wave
## is beaten. The camera leaves you. The rangers have gathered on the Barn's
## Boulder Bluff side, and the first shot looks out past them: the ground
## shakes, a column of dust goes up over the trees at the Bluff, and
## something roars. Then their faces, as one asks what that was and another
## says where it came from. Then the tally on the Barn's door, rubbed out and
## chalked back to zero, and the card: DAYS SINCE BRUTUS: 0. Brutus is
## heard, not seen (BossLore, docs/LORE.md). Jump, fire or accept skips it.

signal finished

const REACT_AT := 4.0          ## the cut to the rangers' faces
const TALLY_AT := 9.0          ## the cut to the Barn's door
const CARD_AT := 12.6
const LENGTH := 17.0
const PLUME_FARTHEST := 125.0  ## metres off the dust column goes up (the Bluff, or toward it: seen through the haze)

var director: MissionDirector
var rig: CameraRig
var hud: CanvasLayer
var controller: PlayerController
var playing := false
var t := 0.0
var _cam: Camera3D
var _prev_cam: Camera3D
var _ui: CanvasLayer
var _bars: Array[ColorRect] = []
var _card: Control
var _beats := {}               # what's happened already (by name)
var _shake := 0.0
var _hud_was := true
var _controls_were := true
var _tags := {}                # name tag -> whether it was showing
var _loot := {}                # pickup -> whether it was showing (put away for the cinematic: their beams)
var _to_bluff := Vector3.FORWARD
var _side := Vector3.RIGHT
var _line := Vector3.ZERO      ## where the rangers stand, looking at the Bluff
var _plume := Vector3.ZERO     ## where the dust goes up
var _crowd: Array[Critter] = []


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	director = d
	rig = r
	hud = h
	controller = pc
	name = "MissionOutro"


func _ready() -> void:
	playing = true
	_to_bluff = MissionDirector._flat(director.bluff_pos - director.barn_pos).normalized()
	_side = _to_bluff.cross(Vector3.UP)
	var far := minf(MissionDirector._flat(director.bluff_pos - director.barn_pos).length(), PLUME_FARTHEST)
	_plume = director._ground_at(director.barn_pos + _to_bluff * far)
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.far = 3000.0
	add_child(_cam)
	_cam.make_current()
	if controller:
		_controls_were = controller.enabled
		controller.enabled = false
	if hud:
		_hud_was = hud.visible
		hud.visible = false
	for c in director.match_manager.critters:
		if is_instance_valid(c) and c.visual and c.visual.name_tag:
			_tags[c.visual.name_tag] = c.visual.name_tag.visible
			c.visual.name_tag.visible = false
	for p in get_tree().get_nodes_in_group(&"pickups"):
		_loot[p] = (p as Node3D).visible
		(p as Node3D).visible = false
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	_bars = BossIntro.letterbox(_ui)
	_gather()
	_aim()


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


func _exit_tree() -> void:
	if playing:
		_restore()


func _process(delta: float) -> void:
	if not playing:
		return
	t += delta
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
		_take_photo()
	if _beat("card", CARD_AT):
		_card = BossIntro.title_card(_ui, "THE KERNEL HUNT  ·  PROLOGUE COMPLETE", "DAYS SINCE BRUTUS: 0",
			"To be continued in Act I: %s." % String(KernelHunt.act("carrot_patch").get("title", "The Carrot Patch")))
	if t >= LENGTH:
		end()
		return
	_shake = maxf(0.0, _shake - delta * 0.6)
	_aim()


## True the first time `t` passes `at` for the beat called `what`.
func _beat(what: String, at: float) -> bool:
	if t < at or _beats.has(what):
		return false
	_beats[what] = true
	return true


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
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12
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


## The tally, back at zero, for the Gazette's special edition (WarrenSim.keep_photo): the bars cropped off.
func _take_photo() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var bar := roundi(img.get_height() * BossIntro.BAR) + 2
	WarrenSim.keep_photo(img.get_region(Rect2i(0, bar, img.get_width(), img.get_height() - bar * 2)),
		"The tally on the Big Red Barn's door, back at zero.")


func _unhandled_input(event: InputEvent) -> void:
	if playing and BossIntro.skippable and (event.is_action_pressed(&"jump") or event.is_action_pressed(&"fire") or event.is_action_pressed(&"ui_accept")):
		get_viewport().set_input_as_handled()
		end()


## Over (or skipped): the tally's at zero whatever, and your camera's back.
func end() -> void:
	if not playing:
		return
	if director.tally and director.tally.count != 0:
		director.tally.wipe_to(0, 0.2)
	_restore()
	finished.emit()
	var tw := create_tween().set_ignore_time_scale(true)
	var view := get_viewport().get_visible_rect().size
	for b in _bars:
		tw.parallel().tween_property(b, "size:y", 0.0, 0.35)
		if b.position.y > 1.0:
			tw.parallel().tween_property(b, "position:y", view.y, 0.35)
	if _card:
		tw.parallel().tween_property(_card, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func _restore() -> void:
	playing = false
	if controller and is_instance_valid(controller):
		controller.enabled = _controls_were
	if hud and is_instance_valid(hud):
		hud.visible = _hud_was
	for tag in _tags:
		if is_instance_valid(tag):
			(tag as Label3D).visible = _tags[tag]
	for p in _loot:
		if is_instance_valid(p):
			(p as Node3D).visible = _loot[p]
	if _cam:
		_cam.clear_current(false)
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif rig and rig.camera:
		rig.camera.make_current()
