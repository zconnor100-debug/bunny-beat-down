extends "res://tests/clubs_stage.gd"
## Stage for tests/capture_workshop.gd (the Burrow book is the test one).

const SKINS := ["stock", "fern_camo", "candy", "midnight", "bubblegum", "frost", "gilded"]


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.002
	add_child(FX.new())
	add_child(Projectiles.new())
	_ground()
	# every skin, on a rifle with the sight and the laser, held by a Bun
	for i in SKINS.size():
		var c := Critter.new()
		c.def = load("res://data/critters/bun.tres")
		c.display_name = SKINS[i]
		add_child(c)
		c.place_at(Vector3((i - (SKINS.size() - 1) * 0.5) * 2.6, 0.05, 0), 0.0)
		c.visual.kit = {"sight": true, "laser": true, "skin": SKINS[i]}
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN))
		critters.append(c)
	var cam := Camera3D.new()
	cam.fov = 34
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 2.6, -14.0)
	cam.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	await _wait(1.0)
	await _snap("80_skins")
	for k in [1, 5]:
		var at := critters[k].visual.weapon_model.global_position
		cam.fov = 22
		cam.global_position = at + Vector3(1.4, 0.6, -1.6)
		cam.look_at(at, Vector3.UP)
		await _wait(0.3)
		await _snap("81_skin_close_%s" % SKINS[k])
	# through the red dot (the first-person aim: the camera on the sight line)
	for c in critters:
		c.visible = false
	var gun := ModelUtil.instantiate(WeaponDB.get_weapon(&"carrot_rifle").model_path)
	add_child(gun)
	gun.scale = Vector3.ONE * 1.15
	GunKit.dress(gun, {"sight": true, "laser": true, "skin": "fern_camo"}, 3.5)
	gun.global_position = Vector3(0, 1.6, 0)
	var sight := gun.find_child("Sight", true, false) as Node3D
	cam.fov = 75
	cam.global_position = gun.global_transform * (sight.position + Vector3(0, 0, 0.22 / 1.15))
	cam.look_at(cam.global_position + Vector3(0, 0, -1), Vector3.UP)
	await _wait(0.4)
	await _snap("82_red_dot_view")
	gun.queue_free()
	# muzzle flashes and smoke, then beat-down bursts
	cam.fov = 40
	cam.global_position = Vector3(0, 2.0, -9.0)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	var looks := ["carrot", "lime", "blueberry", "plum", "bubblegum", "rainbow"]
	var smokes := ["none", "puff", "matching", "spores", "puff", "matching"]
	for i in looks.size():
		var tint := FX.FLASH if looks[i] == "carrot" else Color(Workshop.color(looks[i], i / 6.0), 0.9)
		for j in 3:
			FX.muzzle(Vector3((i - 2.5) * 1.6, 1.5, 0), Vector3(0, 0.2, -1), true, tint, smokes[i])
	await _wait(0.09)
	await _snap("83_flashes")
	await _wait(0.5)
	await _snap("84_smoke")
	var bursts := ["confetti", "leaves", "carrots", "hearts"]
	for i in bursts.size():
		FX.beat_down(Vector3((i - 1.5) * 2.4, 1.6, 0), bursts[i])
	await _wait(0.45)
	await _snap("85_beat_down_bursts")
	# every reticle in every colour
	var layer := CanvasLayer.new()
	add_child(layer)
	var sheet := ReticleSheet.new()
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(sheet)
	await _wait(0.2)
	await _snap("86_reticles")
	sheet.queue_free()
	# the Burrow's Workshop (some bought, to show both states)
	PlayerProfile.reset_for_tests()
	Burrow.add_acorns(600)
	Workshop.buy("red_dot")
	Workshop.buy("reticle:carrot")
	Workshop.set_look("reticle", "carrot")
	Workshop.buy("skin:frost")
	Workshop.set_look("skin", "frost")
	var panel := BurrowPanel.new()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(panel)
	layer.add_child(center)
	await _wait(0.3)
	for b in panel.find_children("*", "Button", true, false):
		if b.text == "Wearing ✓":
			b.grab_focus()
			break
	await _wait(0.4)
	await _snap("87_burrow_workshop")
	get_tree().quit()


func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(16, 16, 16)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)


## Every reticle style (rows) in every colour (columns), on a mid-grey card.
class ReticleSheet:
	extends Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2(200, 160), Vector2(1520, 760)), Color(0.35, 0.4, 0.3))
		var styles: Array = Workshop.LOOKS.reticle.options
		var colors: Array = Workshop.LOOKS.reticle_color.options
		for r in styles.size():
			for k in colors.size():
				var c := Vector2(420 + k * 210, 220 + r * 100)
				Reticle.draw(self, c, 10.0, styles[r][0], Color(Workshop.color(colors[k][0]), 0.95))
			draw_string(UITheme.text_font(700), Vector2(230, 228 + r * 100), styles[r][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
