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
	if only == "clutter":
		# each big toy on the floor (its hills and cover): from a critter's
		# height nearby, and from a little above
		var n := 0
		for kit in tb.clutter:
			var r: float = kit.footprint if kit is Building else float(kit.get_meta(&"footprint", 20.0))
			var c := kit.global_position
			var dir := Vector2.from_angle(n * 2.1 + 0.6)
			var eye2 := Vector2(c.x, c.z) + dir * (r + 14.0)
			_look(Vector3(eye2.x, _ground(eye2) + 4.0, eye2.y), c + Vector3.UP * 4.0, 70.0)
			await _wait(0.5)
			await _snap("72_clutter_%02d_%s" % [n, String(kit.name).get_slice("@", 0)])
			_look(c + Vector3(-dir.x, 0, -dir.y) * (r + 22.0) + Vector3.UP * (r * 0.9 + 8.0), c + Vector3.UP * 2.0, 60.0)
			await _wait(0.4)
			await _snap("73_clutter_%02d_above" % n)
			n += 1
		# crayon scribbled on the floor by a few loose crayons, and the rug's fringe
		var crayons := island.get_children().filter(func(c): return c.has_meta(&"crayon"))
		for i in mini(4, crayons.size()):
			var c: Vector3 = crayons[i * 3 % crayons.size()].global_position
			_look(c + Vector3(16, 14, 16), c + Vector3(-4, 0, -4), 65.0)
			await _wait(0.3)
			await _snap("74_scribbles_%d" % i)
		var edge := Vector2(150.0, ToyFloor.RUG.position.y)
		_look(Vector3(edge.x - 8.0, ToyFloor.FLOOR + 3.0, edge.y - 9.0), Vector3(edge.x + 6.0, ToyFloor.FLOOR, edge.y), 65.0)
		await _wait(0.3)
		await _snap("75_fringe")
		get_tree().quit()
		return
	if only == "floor":
		# the open floor between the toys, from above and at critter height
		_look(Vector3(520, 140, 380), Vector3(-100, 0, -120), 65.0)
		await _wait(1.5)
		await _snap("70_floor_oblique")
		var k := 0
		for at: Vector2 in [Vector2(-60, 60), Vector2(380, -60), Vector2(-380, 0), Vector2(220, -300), Vector2(-60, 300), Vector2(-420, -120)]:
			var to := at + Vector2(70, -50).rotated(k * 1.1)
			_look(Vector3(at.x, _ground(at) + 6.0, at.y), Vector3(to.x, _ground(to) + 3.0, to.y), 70.0)
			await _wait(0.6)
			await _snap("71_floor_%d" % k)
			k += 1
		get_tree().quit()
		return
	if only == "" or only == "room":
		# the bedroom's furniture: the bed (and its teddy), the dresser and the desk
		_look(Vector3(330, 190, -120), Vector3(742, 60, -255), 60.0)
		await _wait(1.0)
		await _snap("69a_bed")
		_look(Vector3(160, 140, 230), Vector3(260, 70, 470), 62.0)
		await _wait(0.6)
		await _snap("69b_dresser_desk")
		if only == "room":
			get_tree().quit()
			return
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
