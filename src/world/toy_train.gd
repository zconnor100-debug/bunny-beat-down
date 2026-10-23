class_name ToyTrain
extends Node3D
## The wooden toy train that loops round Toy Box Bash on its own track: a
## locomotive, a tender, three open cars and a caboose. Every car is an
## AnimatableBody3D that moves with the physics step, so a critter standing
## on one rides along (moving cover with a view). The engine's bumper BONKS
## anyone standing on the line: real damage, and a shove off the track.

const SPEED := 15.0              ## metres per second
const CAR_GAP := 13.0            ## coupling length between car centres
const DECK := 2.6                ## floor height of the open cars
const TRACK_WIDTH := 5.4
const BONK_DAMAGE := 35.0
const BONK_COOLDOWN_MS := 1500

var track := PackedVector3Array()     ## closed loop, evenly spaced
var cumulative := PackedFloat32Array()
var total := 0.0
var distance := 0.0
var cars: Array[AnimatableBody3D] = []
var running := true
var _bonk: Area3D
var _bonked := {}                       # Critter -> msec of its last bonk


## A rounded-rectangle loop through `rect` (x, z), corners of `corner`
## radius, a point every `step` metres, at height y.
static func loop_points(rect: Rect2, corner: float, y: float, step := 2.0) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var r := minf(corner, minf(rect.size.x, rect.size.y) * 0.5)
	var c := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	var start := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var outline := []
	for i in 4:
		for k in 13:
			var a: float = start[i] + PI * 0.5 * k / 12.0
			outline.append(c[i] + Vector2(cos(a), sin(a)) * r)
	# resample evenly
	var acc := 0.0
	pts.append(Vector3(outline[0].x, y, outline[0].y))
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var seg := a.distance_to(b)
		var t := step - acc
		while t <= seg:
			var p := a.lerp(b, t / seg)
			pts.append(Vector3(p.x, y, p.y))
			t += step
		acc = seg - (t - step)
	return pts


func setup(points: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	track = points
	cumulative.resize(track.size() + 1)
	cumulative[0] = 0.0
	for i in track.size():
		cumulative[i + 1] = cumulative[i] + track[i].distance_to(track[(i + 1) % track.size()])
	total = cumulative[track.size()]
	_build_track(rng)
	var makers := [_locomotive, _tender, _open_car, _open_car, _open_car, _caboose]
	for i in makers.size():
		var car := AnimatableBody3D.new()
		car.name = "TrainCar%d" % i
		car.sync_to_physics = true
		car.collision_layer = Layers.WORLD
		car.set_meta(&"surface", &"wood")
		car.set_meta(&"train", true)
		add_child(car)
		_adopt((makers[i] as Callable).call(rng, i), car)
		cars.append(car)
	_bonk = Area3D.new()
	_bonk.name = "Bumper"
	_bonk.collision_layer = 0
	_bonk.collision_mask = Layers.CRITTERS
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TRACK_WIDTH + 1.5, 5.0, 7.0)
	cs.shape = box
	cs.position = Vector3(0, 2.5, -9.5)
	_bonk.add_child(cs)
	cars[0].add_child(_bonk)
	distance = rng.randf() * total
	_place_cars()


## Point and travel direction at distance s along the loop.
func frame_at(s: float) -> Transform3D:
	s = fposmod(s, total)
	var lo := 0
	var hi := track.size()
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cumulative[mid] <= s:
			lo = mid
		else:
			hi = mid
	var a := track[lo]
	var b := track[(lo + 1) % track.size()]
	var seg := cumulative[lo + 1] - cumulative[lo]
	var p := a.lerp(b, (s - cumulative[lo]) / maxf(seg, 0.001))
	var fwd := (b - a).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p)


func _physics_process(delta: float) -> void:
	if not running or cars.is_empty():
		return
	distance = fposmod(distance + SPEED * delta, total)
	_place_cars()
	_check_bonks()


func _place_cars() -> void:
	for i in cars.size():
		# each car follows the rails: its centre at its own distance, facing
		# along the chord between its two bogies
		var s := distance - i * CAR_GAP
		var front := frame_at(s + 4.0).origin
		var back := frame_at(s - 4.0).origin
		var dir := (front - back).normalized()
		cars[i].global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), (front + back) * 0.5)


func _check_bonks() -> void:
	var now := Time.get_ticks_msec()
	var fwd := -cars[0].global_basis.z
	for body in _bonk.get_overlapping_bodies():
		var c := body as Critter
		if c == null or not c.alive or c.state != Critter.State.GROUND:
			continue
		if now - int(_bonked.get(c, -100000)) < BONK_COOLDOWN_MS:
			continue
		_bonked[c] = now
		var info := DamageInfo.make(BONK_DAMAGE, DamageInfo.Kind.MELEE, null, &"toy_train")
		info.position = c.get_chest_position()
		info.direction = fwd
		info.impulse = 14.0
		c.take_damage(info)
		var side := fwd.cross(Vector3.UP).normalized()
		if side.dot(c.global_position - cars[0].global_position) < 0.0:
			side = -side
		c.velocity = fwd * SPEED * 0.8 + side * 9.0 + Vector3.UP * 7.0
		Audio.play_at(&"melee_hit", c.global_position, 2.0, 0.1)


## Move a built kit's meshes and colliders onto the moving body.
func _adopt(kit: CageKit, body: AnimatableBody3D) -> void:
	for child in kit.get_children():
		kit.remove_child(child)
		body.add_child(child)
	kit.free()


# ---- the cars (local: forward is -Z, the rails at y 0) ---------------------------------------------

func _wheels(k: CageKit, length: float) -> void:
	for zs in [-1.0, 1.0]:
		for xs in [-1.0, 1.0]:
			var at := Vector3(xs * 2.5, 1.2, zs * length * 0.32)
			k._rod(&"plastic_black", at - Vector3(0.45, 0, 0), at + Vector3(0.45, 0, 0), 1.15, false)
			k._rod(&"plastic_red", at + Vector3(xs * 0.45, 0, 0), at + Vector3(xs * 0.55, 0, 0), 0.5, false)


func _locomotive(rng: RandomNumberGenerator, _i: int) -> CageKit:
	var k := CageKit.blank("Locomotive", rng)
	k._box(&"plastic_black", Vector3(0, 1.8, 0), Vector3(4.8, 1.2, 11.0))
	k._rod(&"paint_red", Vector3(0, 4.3, 1.5), Vector3(0, 4.3, -5.0), 2.2)
	k._rod(&"plastic_yellow", Vector3(0, 4.3, -5.0), Vector3(0, 4.3, -5.4), 2.3, false)
	k._box(&"paint_blue", Vector3(0, 4.6, 3.6), Vector3(4.8, 4.4, 3.8))
	k._box(&"paint_red", Vector3(0, 7.0, 3.6), Vector3(5.4, 0.5, 4.6))
	k._rod(&"plastic_black", Vector3(0, 6.0, -3.6), Vector3(0, 8.4, -3.6), 0.8)
	k._cone(&"plastic_black", Vector3(0, 9.6, -3.6), Vector3(0, 8.2, -3.6), 1.4)
	k._rod(&"plastic_yellow", Vector3(0, 6.3, -1.0), Vector3(0, 7.0, -1.0), 0.9, false)
	k._prism(&"plastic_yellow", [Vector2(-2.4, 0.6), Vector2(2.4, 0.6), Vector2(0.0, 2.6)], -6.2, 1.6)
	k._ellipsoid(&"lamp", Vector3(0, 6.0, -5.5), Vector3(0.7, 0.7, 0.4), Basis(), false)
	_wheels(k, 11.0)
	return k.finish()


func _tender(rng: RandomNumberGenerator, _i: int) -> CageKit:
	var k := CageKit.blank("Tender", rng)
	k._box(&"plastic_black", Vector3(0, 1.8, 0), Vector3(4.8, 1.2, 8.0))
	k._box(&"paint_red", Vector3(0, 3.6, 0), Vector3(4.8, 2.4, 8.0))
	k._ellipsoid(&"plastic_black", Vector3(0, 4.9, 0), Vector3(2.0, 0.8, 3.4), Basis(), false)
	_wheels(k, 8.0)
	return k.finish()


func _open_car(rng: RandomNumberGenerator, i: int) -> CageKit:
	var k := CageKit.blank("OpenCar", rng)
	var paint: StringName = [&"paint_yellow", &"paint_lime", &"paint_purple"][i % 3]
	k._box(&"plastic_black", Vector3(0, 1.6, 0), Vector3(4.8, 0.8, 11.0))
	k._box(paint, Vector3(0, DECK - 0.3, 0), Vector3(5.2, 0.6, 11.0))
	for xs in [-1.0, 1.0]:
		k._box(paint, Vector3(xs * 2.45, DECK + 0.55, 0), Vector3(0.3, 1.1, 11.0))
	_wheels(k, 11.0)
	return k.finish()


func _caboose(rng: RandomNumberGenerator, _i: int) -> CageKit:
	var k := CageKit.blank("Caboose", rng)
	k._box(&"plastic_black", Vector3(0, 1.6, 0), Vector3(4.8, 0.8, 9.0))
	k._plank_wall(&"paint_red", Vector3(-2.4, DECK - 0.6, 3.5), Vector3(2.4, DECK - 0.6, 3.5), 4.4, 0.3, [[0.0, 2.2, 0.0, 3.2]])
	k._plank_wall(&"paint_red", Vector3(-2.4, DECK - 0.6, -3.5), Vector3(2.4, DECK - 0.6, -3.5), 4.4, 0.3, [[0.0, 2.2, 0.0, 3.2]])
	for xs in [-1.0, 1.0]:
		k._plank_wall(&"paint_red", Vector3(xs * 2.4, DECK - 0.6, -3.5), Vector3(xs * 2.4, DECK - 0.6, 3.5), 4.4, 0.3, [[0.0, 2.4, 1.6, 3.2]])
	k._box(&"paint_blue", Vector3(0, DECK - 0.3, 0), Vector3(5.0, 0.6, 9.0))
	k._box(&"paint_yellow", Vector3(0, DECK + 4.0, 0), Vector3(5.6, 0.5, 9.4))
	k._box(&"paint_red", Vector3(0, DECK + 5.0, 0), Vector3(3.0, 1.6, 3.0))
	_wheels(k, 9.0)
	return k.finish()


## The wooden track: a light wooden bed with two dark grooves, round the loop.
func _build_track(rng: RandomNumberGenerator) -> void:
	var k := CageKit.blank("Track", rng)
	k.collision_layer = 0
	var n := track.size()
	for i in n:
		var a := track[i]
		var b := track[(i + 1) % n]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var basis := Basis(side, Vector3.UP, -dir)
		var len := a.distance_to(b) + 0.05
		var mid := (a + b) * 0.5
		k._box(&"rail_wood", mid + Vector3.UP * 0.07, Vector3(TRACK_WIDTH, 0.14, len), basis, false)
		for s in [-1.0, 1.0]:
			k._box(&"rail_groove", mid + side * s * 1.6 + Vector3.UP * 0.145, Vector3(0.5, 0.02, len), basis, false)
	add_child(k.finish())
