extends "res://tests/workshop_stage.gd"
## Stage for tests/capture_workshop.gd with "earned": the looks only the
## Mastery ladders give. Each earned gun skin on the gun whose ladder gives
## it (held by a Bun, in two rows), close-ups, then the two earned beat-down
## bursts and the earned flash and tracer colours, then the Mended Mirror
## coat (beside a plain Bun and a Doppelbunny's silver mirror).


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
	# the Mended Mirror coat: a plain Bun, Bun in the coat (and in it with a
	# hat and a jetpack on), a fox in it, and a Doppelbunny
	var line := [["bun", [], "natural"], ["bun", [], "mended_mirror"], ["bun", ["wizard_hat", "jetpack"], "mended_mirror"],
		["fox", [], "mended_mirror"], ["bun", [], "doppel"]]
	var coats: Array[Critter] = []
	for i in line.size():
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % line[i][0])
		c.display_name = "coat %d" % i
		add_child(c)
		c.place_at(Vector3((i - 2.0) * 1.7, 0.05, 6.0), 0.0)
		c.visual.kit = {"skin": "stock"}
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN))
		Outfits.dress_player(c, line[i][1], "natural" if line[i][2] == "doppel" else line[i][2])
		if line[i][2] == "doppel":
			DoppelBrain.look(c)
		coats.append(c)
	cam.fov = 34
	cam.global_position = Vector3(0, 2.2, -1.5)
	cam.look_at(Vector3(0, 0.9, 6.0), Vector3.UP)
	await _wait(0.6)
	await _snap("90_mended_mirror")
	await _wait(0.5)
	await _snap("90_mended_mirror_b")
	for k in [1, 4]:
		var at := coats[k].global_position + Vector3.UP * 1.05
		cam.fov = 30
		cam.global_position = at + Vector3(0.8, 0.3, -3.4)
		cam.look_at(at, Vector3.UP)
		await _wait(0.3)
		await _snap("91_coat_close_%d" % k)
	get_tree().quit()
