extends "res://tests/workshop_stage.gd"
## Stage for tests/capture_roguelike.gd: every species wearing scars (an eye
## patch, a bandaged arm, a splinted leg), close-ups, an acorn shrine, a boon
## draft and the Trail (the test profile).


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.002
	add_child(FX.new())
	add_child(Projectiles.new())
	_ground()
	for i in IDS.size():
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % IDS[i])
		c.display_name = IDS[i]
		add_child(c)
		c.place_at(Vector3((i - (IDS.size() - 1) * 0.5) * 3.4, 0.05, 0), 0.0)
		c.visual.add_scars(["eye_patch", "arm_l", "leg_r"])
		critters.append(c)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 2.4, -17.0)
	cam.look_at(Vector3(0, 1.7, 0), Vector3.UP)
	await _wait(1.0)
	await _snap("90_scars")
	for k in [3, 7, 5]:
		var c := critters[k]
		var head := c.visual.bone_world_position(&"head")
		cam.fov = 30
		cam.global_position = head + Vector3(0.6, 0.15, -2.2) * c.visual.rig.world_scale
		cam.look_at(head + Vector3.DOWN * 0.35 * c.visual.rig.world_scale, Vector3.UP)
		await _wait(0.3)
		await _snap("91_scar_close_%s" % IDS[k])
	var sh := AcornShrine.new()
	add_child(sh)
	sh.global_position = Vector3(0, 0, -6)
	cam.fov = 40
	cam.global_position = Vector3(1.0, 1.1, -8.8)
	cam.look_at(Vector3(0, 0.75, -6), Vector3.UP)
	await _wait(0.6)
	await _snap("92_shrine")
	Boons.reset({"cruel_thorns": 1, "thick_skin": 2, "splitting": 1})
	var layer := CanvasLayer.new()
	add_child(layer)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var d := DraftPanel.new()
	d.heading = "The acorn shrine offers a boon"
	d.choices = ["thorny", "splitting", "bark_skin"]
	cc.add_child(d)
	await _wait(0.5)
	await _snap("93_draft")
	d.queue_free()
	PlayerProfile.reset_for_tests()
	Run.start(77)
	Run.choose(0)
	Run.finish_match(4, 24, 2, false, [], 2, {"thorny": 1, "sugar_rush": 2})
	Run.take_pending("bouncy")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	layer.move_child(dim, 0)
	var tp := TrailPanel.new()
	cc.add_child(tp)
	await _wait(0.5)
	await _snap("94_trail")
	get_tree().quit()
