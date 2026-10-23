extends Node3D
## Stage for tests/capture_island.gd (loaded at runtime so autoloads exist).

var out_dir := "user://island"
var seed_value := 1234
var cam: Camera3D
var island: Island


func _ready() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _look(from: Vector3, at: Vector3, fov := 55.0) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at, Vector3.UP if absf((at - from).normalized().y) < 0.99 else Vector3.FORWARD)
	island.set_player_position(from)


func _ground(p: Vector2) -> float:
	return island.terrain.height_at(p.x, p.y)


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	add_child(FX.new())
	add_child(Projectiles.new())
	cam = Camera3D.new()
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	island = Island.new()
	add_child(island)
	var t0 := Time.get_ticks_msec()
	await island.generate(seed_value, 2, false)
	print("island in %d ms: %d POIs, %d buildings, %d loot spots" % [Time.get_ticks_msec() - t0, island.pois.size(), island.buildings.size(), island.loot_points.size()])
	for p in island.pois:
		print("  %-20s biome %d at %s" % [p.name, p.biome, p.center])
	# overhead
	_look(Vector3(0, 1250, 1), Vector3.ZERO, 60.0)
	await _wait(1.5)
	await _snap("40_overhead")
	_look(Vector3(0, 420, 820), Vector3(0, 0, 60), 60.0)
	await _wait(1.0)
	await _snap("41_oblique")
	# each biome at critter height: the POI of that biome nearest the middle
	for biome in [Terrain.Biome.FOREST, Terrain.Biome.GRASS, Terrain.Biome.SWAMP]:
		var best: Dictionary = {}
		for p in island.pois:
			if p.biome == biome and (best.is_empty() or p.center.length() < best.center.length()):
				best = p
		if best.is_empty():
			continue
		var c: Vector2 = best.center
		var out := c + (c.normalized() if c.length() > 1.0 else Vector2.RIGHT) * 60.0
		_look(Vector3(out.x, _ground(out) + 4.0, out.y), Vector3(c.x, _ground(c) + 3.0, c.y), 60.0)
		await _wait(1.2)
		await _snap("42_biome_%s" % ["forest", "swamp", "grass"][biome])
	# every building: outside, then inside through the front door
	var i := 0
	for b in island.buildings:
		var front := b.global_transform.basis.z.normalized()
		var side := b.global_transform.basis.x.normalized()
		var base := b.global_position
		var eye := base + front * (b.footprint + 10.0) + side * 9.0
		eye.y = maxf(_ground(Vector2(eye.x, eye.z)), base.y) + 5.0
		_look(eye, base + Vector3.UP * 5.0, 60.0)
		await _wait(0.8)
		await _snap("43_building_%d_%s_out" % [i, b.name])
		var inside := base + Vector3.UP * (b.floor_y + 2.6) + front * 2.0
		_look(inside, inside - front * 10.0 - Vector3.UP * 1.0, 75.0)
		await _wait(0.6)
		await _snap("44_building_%d_%s_in" % [i, b.name])
		i += 1
	get_tree().quit()
