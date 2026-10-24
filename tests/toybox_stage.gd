extends "res://tests/island_stage.gd"
## Stage for tests/capture_toybox.gd: a tour of Toy Box Bash. Overhead, an
## oblique view, the toy train, the paper plane, every landmark at critter
## height and inside the walk-in ones. `only` limits the landmark shots.

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
	island = ToyBox.new()
	add_child(island)
	var t0 := Time.get_ticks_msec()
	await island.generate(seed_value, 2, false)
	island.tune_lighting(light)
	var tb := island as ToyBox
	print("toybox in %d ms: %d POIs, %d buildings, %d loot spots, track %.0f m" % [Time.get_ticks_msec() - t0, island.pois.size(),
		island.buildings.size(), island.loot_points.size(), tb.train.total])
	if only == "":
		_look(Vector3(-540, 360, 400), Vector3(120, 0, -160), 75.0)
		await _wait(1.5)
		await _snap("60_overhead")
		_look(Vector3(520, 140, 380), Vector3(-100, 0, -120), 65.0)
		await _wait(1.0)
		await _snap("61_oblique")
		# the train, from beside the track
		var car := tb.train.cars[0]
		var fwd := -car.global_basis.z
		var side := fwd.cross(Vector3.UP).normalized()
		_look(car.global_position + side * 20.0 - fwd * 6.0 + Vector3.UP * 6.0, car.global_position - fwd * 14.0 + Vector3.UP * 3.0, 60.0)
		await _snap("62_train")
		var plane := ToyProps.paper_plane(island.rng)
		add_child(plane)
		plane.global_position = Vector3(0, 115, 0)
		_look(Vector3(34, 124, 30), Vector3(0, 115, 0), 55.0)
		await _wait(0.4)
		await _snap("63_paper_plane")
		plane.queue_free()
	var i := 0
	for p in island.pois:
		if only != "" and not String(p.name).to_lower().contains(only):
			continue
		var c: Vector2 = p.center
		var out: Vector2 = c.normalized() if c.length() > 1.0 else Vector2.RIGHT
		var eye2: Vector2 = c - out * (p.radius + 24.0) + out.orthogonal() * 12.0
		eye2 = eye2.clamp(Vector2(-ToyFloor.HX + 12.0, -ToyFloor.HZ + 12.0), Vector2(ToyFloor.HX - 12.0, ToyFloor.HZ - 12.0))
		var eye := Vector3(eye2.x, _ground(eye2) + 7.0, eye2.y)
		_look(eye, Vector3(c.x, _ground(c) + 5.0, c.y), 62.0)
		await _wait(0.6)
		await _snap("64_poi_%02d_%s" % [i, String(p.name).to_snake_case()])
		i += 1
	if only == "spill" or only == "floor":
		# the spilled water, from above and wading in; the floorboards up close
		_look(Vector3(-350, 160, 420), Vector3(-350, 0, 225), 60.0)
		await _wait(0.8)
		await _snap("66_spill_above")
		var c := Vector2(-330, 230)
		_look(Vector3(c.x + 30, _ground(c) + 3.0, c.y + 30), Vector3(c.x, _ground(c), c.y), 70.0)
		await _wait(0.6)
		await _snap("67_spill_wading")
		_look(Vector3(250, ToyFloor.FLOOR + 2.0, 300), Vector3(220, ToyFloor.FLOOR, 260), 70.0)
		await _wait(0.6)
		await _snap("68_floorboards")
	if only == "" or only == "inside":
		var j := 0
		for b in island.buildings:
			var front := b.global_transform.basis.z.normalized()
			var inside := b.global_position + Vector3.UP * (b.floor_y + 2.6) + front * 2.0
			_look(inside, inside - front * 10.0 - Vector3.UP * 1.0, 75.0)
			await _wait(0.4)
			await _snap("65_inside_%02d_%s" % [j, b.name])
			j += 1
	get_tree().quit()
