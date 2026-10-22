extends TestCase
## Character picker: the preview faces the camera, and click-drag spins it
## a full 360° in either direction.


func _drag(picker: CharacterSelect, dx: float) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	picker._on_preview_input(down)
	# drag in small steps like a real mouse
	var steps := 12
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.relative = Vector2(dx / steps, 0)
		picker._on_preview_input(m)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	picker._on_preview_input(up)


func _facing(picker: CharacterSelect) -> Vector3:
	return -picker._preview.global_basis.z   # critters face their −Z


func test_preview_faces_camera_and_spins_both_ways() -> void:
	var picker := CharacterSelect.new()
	add_child(picker)
	await wait_frames(6)
	var cam := picker._viewport.get_camera_3d()
	var to_cam := (cam.global_position - picker._preview.global_position) * Vector3(1, 0, 1)
	check(_facing(picker).dot(to_cam.normalized()) > 0.95, "starts facing the camera (dot %.2f)" % _facing(picker).dot(to_cam.normalized()))
	# a quarter-width drag right → quarter turn
	_drag(picker, 105.0)
	await wait_frames(2)
	check_near(absf(_facing(picker).dot(to_cam.normalized())), 0.0, 0.05, "quarter turn shows the side")
	# another quarter: now we see its back (half a turn in total)
	_drag(picker, 105.0)
	await wait_frames(2)
	check(_facing(picker).dot(to_cam.normalized()) < -0.95, "can spin round to the back")
	# and all the way back the other way, past the start (360° in either direction)
	_drag(picker, -210.0 - 420.0)
	await wait_frames(2)
	check(_facing(picker).dot(to_cam.normalized()) > 0.95, "dragging left spins a full turn the other way")
	# motion without a held button does nothing
	var before := picker._spin
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(200, 0)
	picker._on_preview_input(m)
	check_near(picker._spin, before, 1e-6, "hover without a click doesn't spin")
	# picking another critter starts it facing forward again
	_drag(picker, 140.0)
	picker._cycle(1)
	await wait_frames(4)
	check(_facing(picker).dot(to_cam.normalized()) > 0.95, "next critter starts facing the camera")
	picker.queue_free()


func test_real_mouse_drag_reaches_the_preview() -> void:
	# Deliver events the way the OS does (through the viewport's GUI input),
	# not by calling the handler, to prove a real click-and-drag spins it.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var picker := CharacterSelect.new()
	layer.add_child(picker)
	await wait_frames(6)
	var svc := picker.find_children("*", "SubViewportContainer", true, false)[0] as SubViewportContainer
	var start := svc.get_global_rect().get_center()
	var vp := get_viewport()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	down.global_position = start
	vp.push_input(down, true)
	var pos := start
	for i in 10:
		var m := InputEventMouseMotion.new()
		m.relative = Vector2(21, 0)
		pos += m.relative
		m.position = pos
		m.global_position = pos
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(m, true)
		await wait_frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	vp.push_input(up, true)
	await wait_frames(2)
	check_near(absf(picker._spin), PI, 0.15, "a real 210 px drag (half the preview width) spins the critter half a turn (spin %.2f)" % picker._spin)
	layer.queue_free()
