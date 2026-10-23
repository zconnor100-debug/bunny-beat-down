class_name Dropship
extends Node3D
## The battle bus: a hot-air balloon with a picnic-basket gondola that drifts
## across the island while everyone picks their moment to jump — or, in the
## hamster cage, a wind-up toy airplane flying wall to wall under the rim of
## the glass.

const MODEL := "res://assets/props/dropship_balloon.glb"
const ALTITUDE := 115.0
const PLANE_ALTITUDE := 112.0
const DURATION := 38.0
const PLANE_SPEED := 21.0

var vehicle := &"balloon"
var duration := DURATION
var start := Vector3.ZERO
var finish := Vector3.ZERO
var progress := 0.0
var flying := false
var passengers: Array[Critter] = []
var _wind: Node


func setup(island_radius: float, rng: RandomNumberGenerator, vehicle_ := &"balloon", bounds := Rect2()) -> void:
	vehicle = vehicle_
	var a := rng.randf() * TAU
	var dir := Vector2(cos(a), sin(a))
	var s: Vector2
	var f: Vector2
	var altitude := ALTITUDE
	if vehicle in [&"plane", &"paper_plane"]:
		# straight across the tank (or the bedroom), wall to wall
		var inner := bounds.grow(-30.0)
		var mid := inner.get_center() + dir.orthogonal() * rng.randf_range(-0.25, 0.25) * minf(inner.size.x, inner.size.y)
		s = mid - dir * _to_edge(mid, -dir, inner)
		f = mid + dir * _to_edge(mid, dir, inner)
		duration = s.distance_to(f) / PLANE_SPEED
		altitude = PLANE_ALTITUDE
	else:
		duration = DURATION * sqrt(island_radius / 215.0)
		# the route stays inside the boundary wall (island_radius + 45) so anyone
		# who jumps at the very start or end still lands in reach of the shore
		var offset := dir.orthogonal() * rng.randf_range(-0.25, 0.25) * island_radius
		s = -dir * (island_radius + 10.0) + offset
		f = dir * (island_radius + 10.0) + offset
	start = Vector3(s.x, altitude, s.y)
	finish = Vector3(f.x, altitude, f.y)
	global_position = start
	look_at(finish, Vector3.UP)
	var model: Node3D
	if vehicle == &"plane":
		model = CageProps.toy_plane(rng)
		_propeller = model.get_node_or_null("Propeller")
	elif vehicle == &"paper_plane":
		model = ToyProps.paper_plane(rng)
	else:
		model = ModelUtil.instantiate(MODEL)
		if model == null:
			model = _fallback_balloon()
	add_child(model)


var _propeller: Node3D


## Distance from p along dir to the edge of rect r (p inside r).
static func _to_edge(p: Vector2, dir: Vector2, r: Rect2) -> float:
	var t := INF
	if dir.x > 1e-4:
		t = minf(t, (r.end.x - p.x) / dir.x)
	elif dir.x < -1e-4:
		t = minf(t, (r.position.x - p.x) / dir.x)
	if dir.y > 1e-4:
		t = minf(t, (r.end.y - p.y) / dir.y)
	elif dir.y < -1e-4:
		t = minf(t, (r.position.y - p.y) / dir.y)
	return t if t < INF else 0.0


## How far back the camera sits while you ride (it frames the whole thing).
func view_distance() -> float:
	return {&"plane": 52.0, &"paper_plane": 46.0}.get(vehicle, 7.0)


## Where the ride camera starts looking: planes side-on, looking in toward
## the middle of the map (so the map is behind them), the balloon from
## behind and a little to the side.
func view_yaw() -> float:
	var d := finish - start
	if vehicle == &"balloon":
		return atan2(-d.x, -d.z) + 0.6
	var side := d.cross(Vector3.UP).normalized()
	var mid := (start + finish) * 0.5
	var look := side if (Vector3.ZERO - mid).dot(side) >= 0.0 else -side
	return atan2(-look.x, -look.z)


## What to call the ride in messages ("the balloon won't wait").
func display_name() -> String:
	return {&"plane": "toy plane", &"paper_plane": "paper airplane"}.get(vehicle, "balloon")


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
	if passengers.has(c):
		return
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
	if not passengers.has(c) or c.state != Critter.State.IN_DROPSHIP:
		passengers.erase(c)
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
	if _propeller:
		_propeller.rotate_z(delta * 22.0)
	if progress >= 1.0:
		for c in passengers.duplicate():
			eject(c)
		flying = false
		if _wind:
			_wind.queue_free()
		var tw := create_tween()
		if vehicle != &"balloon":
			# loop up and away (over the rim of the glass)
			tw.tween_property(self, "global_position", global_position + Vector3.UP * 260.0 - (finish - start).normalized() * 120.0, 9.0)
		else:
			tw.tween_property(self, "global_position", global_position + (finish - start).normalized() * 200.0 + Vector3.UP * 60.0, 20.0)
		tw.tween_callback(queue_free)


## Route progress (0..1) closest to a ground point — when to jump for it.
func progress_nearest(p: Vector3) -> float:
	var ab := finish - start
	ab.y = 0.0
	var ap := p - start
	ap.y = 0.0
	return clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
