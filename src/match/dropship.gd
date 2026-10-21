class_name Dropship
extends Node3D
## The battle bus: a hot-air balloon with a picnic-basket gondola that drifts
## across the island while everyone picks their moment to jump.

const MODEL := "res://assets/props/dropship_balloon.glb"
const ALTITUDE := 115.0
const DURATION := 38.0

var duration := DURATION
var start := Vector3.ZERO
var finish := Vector3.ZERO
var progress := 0.0
var flying := false
var passengers: Array[Critter] = []
var _wind: Node


func setup(island_radius: float, rng: RandomNumberGenerator) -> void:
	duration = DURATION * sqrt(island_radius / 215.0)
	var a := rng.randf() * TAU
	# the route stays inside the boundary wall (island_radius + 45) so anyone
	# who jumps at the very start or end still lands in reach of the shore
	var dir := Vector2(cos(a), sin(a))
	var offset := dir.orthogonal() * rng.randf_range(-0.25, 0.25) * island_radius
	var s := -dir * (island_radius + 10.0) + offset
	var f := dir * (island_radius + 10.0) + offset
	start = Vector3(s.x, ALTITUDE, s.y)
	finish = Vector3(f.x, ALTITUDE, f.y)
	global_position = start
	look_at(finish, Vector3.UP)
	var model := ModelUtil.instantiate(MODEL)
	if model == null:
		model = _fallback_balloon()
	add_child(model)


func _fallback_balloon() -> Node3D:
	# Fallback only — used until assets/props/dropship_balloon.glb exists.
	var root := Node3D.new()
	var env := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 6.0
	sph.height = 14.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.55, 0.2)
	sph.material = m
	env.mesh = sph
	env.position.y = 12.0
	root.add_child(env)
	var basket := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4, 1.6, 4)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.6, 0.42, 0.22)
	box.material = bm
	basket.mesh = box
	basket.position.y = 0.8
	root.add_child(basket)
	return root


func board(c: Critter) -> void:
	passengers.append(c)
	c.board_dropship()


func launch() -> void:
	flying = true
	_wind = Audio.make_loop(&"wind_loop", self, false)
	if _wind:
		_wind.volume_db = -10.0
		_wind.play()


## Throws a passenger out of the basket.
func eject(c: Critter) -> void:
	if not passengers.has(c):
		return
	passengers.erase(c)
	var fwd := (finish - start).normalized()
	var side := fwd.cross(Vector3.UP).normalized() * randf_range(-1.5, 1.5)
	c.begin_freefall(global_position + Vector3.DOWN * 2.0 + side, fwd * 12.0)


func _process(delta: float) -> void:
	if not flying:
		return
	progress = minf(1.0, progress + delta / duration)
	global_position = start.lerp(finish, progress)
	if progress >= 1.0:
		for c in passengers.duplicate():
			eject(c)
		flying = false
		if _wind:
			_wind.queue_free()
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + (finish - start).normalized() * 200.0 + Vector3.UP * 60.0, 20.0)
		tw.tween_callback(queue_free)


## Route progress (0..1) closest to a ground point — when to jump for it.
func progress_nearest(p: Vector3) -> float:
	var ab := finish - start
	ab.y = 0.0
	var ap := p - start
	ap.y = 0.0
	return clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
