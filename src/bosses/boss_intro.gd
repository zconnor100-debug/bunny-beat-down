class_name BossIntro
extends Node
## A boss's arrival as a cinematic (Boss Battles; Settings "boss_intro"). As it
## turns up, the camera leaves you for a few seconds of its own, bars top and
## bottom and the HUD put away: from the ground, looking up as it drops out of
## the sky (or at the bedding heaving where Nibbles is about to burst out), a
## jolt and a moment of slow motion as it lands, then up close on its face as
## its name comes up with its billing and the line the Warren knows it by
## (BossLore.epigraph), and its roar for the camera (Boss.show_off). Then the
## camera's yours again, turned to face it. Jump, fire or accept skips it.
## The match goes on underneath: everyone on the map is on your side, and it
## never lands near you (MatchManager.release_boss).

signal finished

const BAR := 0.12            ## each letterbox bar, a share of the screen's height
const AFTER_ROAR := 2.2      ## seconds of its roar on camera before the end
const SLOW := 0.35           ## time's speed for a moment as it lands...
const SLOW_FOR := 0.3        ## ...for this long (in the boss's seconds)
const MAX_SECONDS := 14.0    ## at most this long into its arrival, whatever happens (its clock: a
                             ## recording renders slower than real time)

## Off, it can't be skipped and doesn't say how (the trailer's).
static var skippable := true

var boss: Boss
var match_manager: MatchManager
var rig: CameraRig
var hud: CanvasLayer
var controller: PlayerController
var playing := false
var _cam: Camera3D
var _prev_cam: Camera3D
var _ui: CanvasLayer
var _bars: Array[ColorRect] = []
var _card: Control
var _card_shown := false
var _shake := 0.0
var _roared_at := -1.0       # (the boss's fight_time when it roared for us)
var _time_was := 1.0         # (Engine.time_scale before the slow motion)
var _slowed := false
var _landed := false
var _dir := Vector3.FORWARD  # (flat: from where it lands toward you)
var _spot := Vector3.ZERO
var _hud_was := true
var _controls_were := true
var _thinking_was := true


func _init(b: Boss, mm: MatchManager, r: CameraRig = null, h: CanvasLayer = null, pc: PlayerController = null) -> void:
	boss = b
	match_manager = mm
	rig = r
	hud = h
	controller = pc
	name = "BossIntro"


func _ready() -> void:
	playing = true
	_spot = boss.global_position
	var you: Vector3 = _spot + boss.forward() * 60.0
	if match_manager and is_instance_valid(match_manager.player) and match_manager.player.alive:
		you = match_manager.player.global_position
	_dir = Vector3(you.x - _spot.x, 0.0, you.z - _spot.z)
	_dir = _dir.normalized() if _dir.length() > 1.0 else boss.forward()
	_pick_side()
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.far = 3000.0
	add_child(_cam)
	_cam.make_current()
	_thinking_was = boss.thinking
	boss.thinking = false
	if controller:
		_controls_were = controller.enabled
		controller.enabled = false
	if hud:
		_hud_was = hud.visible
		hud.visible = false
	_build_ui()
	_aim(0.0, true)


func _exit_tree() -> void:
	_restore_time()


func _process(delta: float) -> void:
	if not playing:
		return
	if boss == null or not is_instance_valid(boss) or not boss.alive or boss.fight_time() > MAX_SECONDS \
			or (match_manager and match_manager.phase == MatchManager.Phase.ENDED):
		end()
		return
	var t := boss.fight_time()
	if not _landed and t >= boss.land_time:
		_landed = true
		_shake = 1.0
		if not _slowed and Engine.time_scale > 0.0:
			_slowed = true
			_time_was = Engine.time_scale
			Engine.time_scale = _time_was * SLOW
	if _slowed and Engine.time_scale < _time_was and t >= boss.land_time + SLOW_FOR:
		_restore_time()
	if not _card_shown and t >= boss.land_time + 0.45:
		_show_card()
	if _roared_at < 0.0 and boss.state == Boss.State.FIGHTING:
		_roared_at = t
		if boss.show_off() or (boss.action and boss.action.name in [&"roar", &"screech", &"overdrive"]):
			_shake = maxf(_shake, 0.6)
	if _roared_at >= 0.0 and t - _roared_at >= AFTER_ROAR:
		end()
		return
	_shake = maxf(0.0, _shake - delta / maxf(Engine.time_scale, 0.05) * 1.4)
	_aim(t, false)


func _unhandled_input(event: InputEvent) -> void:
	if playing and skippable and (event.is_action_pressed(&"jump") or event.is_action_pressed(&"fire") or event.is_action_pressed(&"ui_accept")):
		get_viewport().set_input_as_handled()
		end()


## Over (or skipped): your camera back, turned to face it.
func end() -> void:
	if not playing:
		return
	playing = false
	_restore_time()
	if boss and is_instance_valid(boss):
		boss.thinking = _thinking_was
	if controller and is_instance_valid(controller):
		controller.enabled = _controls_were
	if hud and is_instance_valid(hud):
		hud.visible = _hud_was
	var p: Critter = match_manager.player if match_manager and is_instance_valid(match_manager.player) else null
	if rig and p and p.alive and boss and is_instance_valid(boss):
		var to := boss.get_chest_position() - p.global_position
		rig.yaw = atan2(-to.x, -to.z)
		rig.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()) * 0.6, 0.0, deg_to_rad(30.0))
	_cam.clear_current(false)
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	elif rig and rig.camera:
		rig.camera.make_current()
	if match_manager:
		match_manager.boss_intro_done()
	finished.emit()
	# the bars slide away, then it's gone
	var tw := create_tween().set_ignore_time_scale(true)
	var view := get_viewport().get_visible_rect().size
	for b in _bars:
		tw.parallel().tween_property(b, "size:y", 0.0, 0.35)
		if b.position.y > 1.0:
			tw.parallel().tween_property(b, "position:y", view.y, 0.35)
	for c in _ui.get_children():
		if c is Label or c == _card:
			tw.parallel().tween_property(c, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func _restore_time() -> void:
	if _slowed and Engine.time_scale < _time_was:
		Engine.time_scale = _time_was
	_slowed = false


# ---- the camera ---------------------------------------------------------------------------------

## The way round it the camera shoots from: in front of it (it lands facing
## you), turned as far as it takes (up to 72 degrees either way) to find a
## view with no tree in it, of where it lands from afar and of its face up
## close. (A tree's crown isn't solid, so _clear_view can't see it: the
## map's Scatter knows where every trunk stands.)
func _pick_side() -> void:
	var island: Node = match_manager.island if match_manager else null
	var scatter: Scatter = island.get("scatter") if island else null
	if scatter == null:
		return
	var front := Vector3(boss.forward().x, 0.0, boss.forward().z).normalized()
	var best := front
	var best_trees := 1 << 20
	for k in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		var d := front.rotated(Vector3.UP, deg_to_rad(18.0 * k))
		var side := d.cross(Vector3.UP)
		var trees := _trees_on_view(scatter, _spot + d * 62.0 + side * 12.0)
		for dist in [24.0, 29.0, 34.0]:   # (the face shot pushes in from 34 m to 24)
			trees += _trees_on_view(scatter, _spot + d * dist + side * 7.0) * 2
		if trees < best_trees:
			best_trees = trees
			best = d
		if trees == 0:
			break
	_dir = best


## Trees on the way from `cam` to where it lands (a crown spreads far past
## its trunk's footprint), and over the camera.
func _trees_on_view(scatter: Scatter, cam: Vector3) -> int:
	var n := 2 if scatter.blocked(Vector2(cam.x, cam.z), 8.0, false) else 0
	for i in 12:
		var p := cam.lerp(_spot, 0.075 * (i + 1))
		if scatter.blocked(Vector2(p.x, p.z), 6.0, false):
			n += 1
	return n


## Where the camera is `t` seconds into its arrival: on the ground in front of
## where it lands, looking up at it coming down; once it's down, low in front
## of its face, pushing in.
func _aim(t: float, snap: bool) -> void:
	var side := _dir.cross(Vector3.UP).normalized()
	var pos: Vector3
	var look: Vector3
	var fov := 52.0
	if t < boss.land_time:
		if boss.from_below:   # (the ground heaving where it's about to come up)
			pos = _spot + _dir * 36.0 + side * 8.0
			pos.y = boss.ground_y(pos) + 2.6
			look = _spot + Vector3.UP * 4.0
			_shake = maxf(_shake, 0.2 + 0.45 * t / boss.land_time)
		else:   # (looking up at it dropping out of the sky)
			pos = _spot + _dir * 62.0 + side * 12.0
			pos.y = boss.ground_y(pos) + 2.0
			look = boss.get_chest_position()
			fov = 62.0
	else:
		var fwd := _dir   # (in front of it: it lands facing you, and the side picked has a clear view)
		var fside := fwd.cross(Vector3.UP).normalized()
		var face := _face()
		var k := smoothstep(0.0, 1.0, clampf((t - boss.land_time) / 3.5, 0.0, 1.0))
		var dist := lerpf(34.0, 24.0, k)
		pos = face + fwd * dist + fside * lerpf(9.0, 5.0, k)
		pos.y = maxf(face.y - lerpf(6.0, 3.5, k), boss.ground_y(pos) + 2.0)   # (a little below its eyes: looking up at it)
		look = face.lerp(boss.get_chest_position(), 0.12)
		fov = 50.0
		if not _landed:
			snap = true
	pos = _clear_view(look, pos)
	var view := get_viewport().get_visible_rect().size
	if view.x < view.y:
		fov = minf(fov * 1.45, 95.0)   # (a tall window needs a wider lens)
	var want := Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
	if snap or t < 0.05:
		_cam.global_transform = want
	else:
		var d := get_process_delta_time() / maxf(Engine.time_scale, 0.05)
		_cam.global_transform = _cam.global_transform.interpolate_with(want, clampf(d * 4.0, 0.0, 1.0))
	_cam.fov = fov
	if _shake > 0.0:
		var s := _shake * _shake
		_cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s * 0.9
		_cam.rotate_object_local(Vector3.FORWARD, randf_range(-1, 1) * s * 0.04)


## The middle of its face: between its eyes (its boss.json's), or its head's.
func _face() -> Vector3:
	var eyes := boss.eye_positions()
	if eyes.is_empty():
		return boss.get_eye_position()
	var m := Vector3.ZERO
	for e in eyes:
		m += e / eyes.size()
	return m


## Kept on this side of anything solid between it and what it's looking at.
func _clear_view(look: Vector3, pos: Vector3) -> Vector3:
	var space := _cam.get_world_3d().direct_space_state if _cam.is_inside_tree() else null
	if space == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(look, pos, Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return hit.position + (look - pos).normalized() * 1.5


# ---- on screen ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	_bars = letterbox(_ui)
	if skippable:
		var view := get_viewport().get_visible_rect().size
		var skip := UITheme.label("Skip: %s" % GameInput.prompt(&"jump"), 18, Color(UITheme.CREAM, 0.55))
		skip.position = Vector2(view.x - 230.0, view.y - view.y * BAR * 0.5 - 13.0)
		_ui.add_child(skip)


## Its name, its billing and the Warren's line for it, low on the left.
func _show_card() -> void:
	_card_shown = true
	_card = title_card(_ui, boss.title.to_upper(), boss.display_name.to_upper(), BossLore.epigraph(boss.id))


## A cinematic's black bars, top and bottom, sliding in on `layer` (each
## BAR of the screen's height). Shared with MissionOutro.
static func letterbox(layer: CanvasLayer) -> Array[ColorRect]:
	var view := layer.get_viewport().get_visible_rect().size
	var h := view.y * BAR
	var bars: Array[ColorRect] = []
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size = Vector2(view.x, 0.0)
		b.position = Vector2(0.0, 0.0 if top else view.y)
		layer.add_child(b)
		bars.append(b)
		var tw := b.create_tween().set_ignore_time_scale(true)
		tw.tween_property(b, "size:y", h, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if not top:
			tw.parallel().tween_property(b, "position:y", view.y - h, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return bars


## A cinematic's title card, low on the left over the bottom bar: a kicker
## (a boss's billing), a big title (its name), a red rule drawn out under it,
## and a line. It slides in (whatever time's speed). Shared with MissionOutro.
static func title_card(layer: CanvasLayer, kicker: String, title: String, line_text: String) -> Control:
	var view := layer.get_viewport().get_visible_rect().size
	var tall := view.x < view.y
	var card := VBoxContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_constant_override("separation", 2)
	layer.add_child(card)
	var billing := UITheme.label(kicker, 30 if not tall else 24, UITheme.CARROT_LIGHT, true)
	card.add_child(billing)
	var who := UITheme.label(title, 112 if not tall else 76, UITheme.CREAM, true)
	card.add_child(who)
	var rule := ColorRect.new()
	rule.color = Color(0.86, 0.12, 0.08)
	rule.custom_minimum_size = Vector2(0.0, 5.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_child(rule)
	var line := UITheme.label(line_text, 26 if not tall else 21, Color(UITheme.CREAM, 0.9))
	line.modulate.a = 0.0
	card.add_child(line)
	var left := view.x * (0.06 if not tall else 0.05)
	card.position = Vector2(left - 60.0, view.y * (1.0 - BAR) - (210.0 if not tall else 160.0))
	card.modulate.a = 0.0
	var tw := card.create_tween().set_ignore_time_scale(true)   # (the slow motion doesn't slow the titles)
	tw.tween_property(card, "modulate:a", 1.0, 0.45)
	tw.parallel().tween_property(card, "position:x", left, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rule, "custom_minimum_size:x", minf(view.x * 0.42, 620.0), 0.7).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(line, "modulate:a", 1.0, 0.4)
	return card
