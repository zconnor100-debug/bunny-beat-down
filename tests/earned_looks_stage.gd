extends "res://tests/workshop_stage.gd"
## Stage for tests/capture_workshop.gd with "earned": the looks only the
## Mastery ladders give. Each earned gun skin on the gun whose ladder gives
## it (held by a Bun, in two rows), close-ups, then the two earned beat-down
## bursts and the earned flash and tracer colours.


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.002
	add_child(FX.new())
	add_child(Projectiles.new())
	_ground()
	# [skin, the gun whose ladder gives it] for each earned skin
	var pairs := []
	for l in Mastery.LADDERS:
		var look: String = l.tiers[-1][1].get("look", "")
		if look.begins_with("skin:"):
			var gun := String(l.stat).get_slice(":", 1)
			pairs.append([look.get_slice(":", 1), gun if WeaponDB.get_weapon(StringName(gun)) and gun != "melee" else "carrot_rifle"])
	for i in pairs.size():
		var c := Critter.new()
		c.def = load("res://data/critters/bun.tres")
		c.display_name = pairs[i][0]
		add_child(c)
		var row := i / 6
		c.place_at(Vector3((i % 6 - 2.5) * 2.6, 0.05, row * 3.2), 0.0)
		c.visual.kit = {"skin": pairs[i][0]}
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(StringName(pairs[i][1])), Rarity.Tier.GARDEN))
		critters.append(c)
	var cam := Camera3D.new()
	cam.fov = 38
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 3.6, -15.0)
	cam.look_at(Vector3(0, 1.4, 1.6), Vector3.UP)
	await _wait(1.0)
	await _snap("86_earned_skins")
	for k in critters.size():
		var at := critters[k].visual.weapon_model.global_position
		cam.fov = 24
		cam.global_position = at + Vector3(1.3, 0.5, -1.5)
		cam.look_at(at, Vector3.UP)
		await _wait(0.2)
		await _snap("87_skin_%s" % critters[k].display_name)
	for c in critters:
		c.visible = false
	# the earned bursts, and the earned flash colour
	cam.fov = 40
	cam.global_position = Vector3(0, 2.0, -9.0)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	FX.beat_down(Vector3(-1.6, 1.6, 0), "fireworks")
	FX.beat_down(Vector3(1.6, 1.6, 0), "gold_rush")
	await _wait(0.35)
	await _snap("88_earned_bursts")
	for j in 3:
		FX.muzzle(Vector3(0, 1.5, 0), Vector3(0, 0.2, -1), true, Color(Workshop.color("gold"), 0.9), "none")
	await _wait(0.09)
	await _snap("89_gold_flash")
	get_tree().quit()
