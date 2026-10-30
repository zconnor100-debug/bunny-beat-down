class_name MissionCinematic
extends Node
## A Kernel Hunt mission's ending, played like a short film (MissionOutro,
## the prologue's; PatchOutro, Act I's). The camera leaves you; the HUD, the
## critters' name tags and the loot's beams go; black bars come in; and the
## film's beats play on its clock (`t`, `_beat`) while its camera moves
## (`_aim`). Jump, fire or accept skips it. `finished` when it's over (or
## skipped), with your camera, HUD and controls back as they were.

signal finished

var director: MissionDirector
var rig: CameraRig
var hud: CanvasLayer
var controller: PlayerController
var playing := false
var t := 0.0
var length := 17.0
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
var _loot := {}                # pickup -> whether it was showing (put away for the film: their beams)


func _init(d: MissionDirector, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	director = d
	rig = r
	hud = h
	controller = pc


func _ready() -> void:
	playing = true
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
	_start()
	_aim()


## Set the scene (the film's own).
func _start() -> void:
	pass


## The beats at `t` (the film's own).
func _play(_delta: float) -> void:
	pass


## Where the camera is at `t` (the film's own).
func _aim() -> void:
	pass


## The film's over, played or skipped: whatever it leaves behind is so (the film's own).
func _ending() -> void:
	pass


func _exit_tree() -> void:
	if playing:
		_restore()


func _process(delta: float) -> void:
	if not playing:
		return
	t += delta
	_play(delta)
	if not playing:
		return
	if t >= length:
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


## A little random shake, by `_shake`.
func _jolt() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.12


## The picture now, for the Gazette's special edition (WarrenSim.keep_photo): the bars cropped off.
func _take_photo(caption: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	var bar := roundi(img.get_height() * BossIntro.BAR) + 2
	WarrenSim.keep_photo(img.get_region(Rect2i(0, bar, img.get_width(), img.get_height() - bar * 2)), caption)


func _unhandled_input(event: InputEvent) -> void:
	if playing and BossIntro.skippable and (event.is_action_pressed(&"jump") or event.is_action_pressed(&"fire") or event.is_action_pressed(&"ui_accept")):
		get_viewport().set_input_as_handled()
		end()


## Over (or skipped): your camera's back.
func end() -> void:
	if not playing:
		return
	_ending()
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
