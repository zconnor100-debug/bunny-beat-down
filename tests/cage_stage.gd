extends "res://tests/island_stage.gd"
## Stage for tests/capture_cage.gd: a tour of the Hamster Cage map. Overhead,
## an oblique view, every landmark at critter height, the fridge through the
## glass, and the toy plane. `only` limits the tour to landmarks whose name
## contains it (quick looks while iterating).

var only := ""


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	add_child(FX.new())
	add_child(Projectiles.new())
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	island = HamsterCage.new()
	add_child(island)
	var t0 := Time.get_ticks_msec()
	await island.generate(seed_value, 2, false)
	island.tune_lighting(light)
	print("cage in %d ms: %d POIs, %d buildings, %d loot spots, %d bowls" % [Time.get_ticks_msec() - t0, island.pois.size(),
		island.buildings.size(), island.loot_points.size(), (island as HamsterCage).bowls.size()])
	for p in island.pois:
		print("  %-20s %s at %s h=%.1f" % [p.name, p.kit, p.center, p.height])
	if only == "":
		_look(Vector3(0, 1300, 1), Vector3.ZERO, 60.0)
		await _wait(1.5)
		await _snap("50_overhead")
		_look(Vector3(-300, 360, 760), Vector3(60, 0, -60), 60.0)
		await _wait(1.0)
		await _snap("51_oblique")
		# the winter corner, looking at the fridge through the north glass
		_look(Vector3(300, 30, -200), Vector3(440, 120, -500), 70.0)
		await _wait(1.0)
		await _snap("52_fridge_from_inside")
		_look(Vector3(-200, 60, 300), Vector3(-450, 20, -200), 65.0)
		await _wait(0.8)
		await _snap("53_lagoon_wide")
		# the toy plane
		var plane := CageProps.toy_plane(island.rng)
		add_child(plane)
		plane.global_position = Vector3(0, 112, 0)
		_look(Vector3(28, 118, 26), Vector3(0, 112, 0), 55.0)
		await _wait(0.6)
		await _snap("54_toy_plane")
		plane.queue_free()
	var i := 0
	for p in island.pois:
		if only != "" and not String(p.name).to_lower().contains(only):
			continue
		var c: Vector2 = p.center
		var out: Vector2 = c.normalized() if c.length() > 1.0 else Vector2.RIGHT
		var eye2: Vector2 = c + out * (p.radius + 26.0) + out.orthogonal() * 12.0
		eye2 = eye2.clamp(Vector2(-CageFloor.HX + 15.0, -CageFloor.HZ + 15.0), Vector2(CageFloor.HX - 15.0, CageFloor.HZ - 15.0))
		var eye := Vector3(eye2.x, maxf(_ground(eye2), island.water_level_at(Vector3(eye2.x, 0, eye2.y))) + 7.0, eye2.y)
		_look(eye, Vector3(c.x, _ground(c) + 4.0, c.y), 62.0)
		await _wait(0.8)
		await _snap("55_poi_%02d_%s" % [i, String(p.name).to_snake_case()])
		i += 1
	if only == "" or only == "inside":
		var j := 0
		for b in island.buildings:
			var front := b.global_transform.basis.z.normalized()
			var inside := b.global_position + Vector3.UP * (b.floor_y + 2.6) + front * 2.0
			_look(inside, inside - front * 10.0 - Vector3.UP * 1.0, 75.0)
			await _wait(0.5)
			await _snap("56_inside_%02d_%s" % [j, b.name])
			j += 1
	get_tree().quit()
