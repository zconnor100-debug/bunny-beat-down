class_name Building
extends StaticBody3D
## The big walk-in buildings, one style per biome, built in code from textured
## boxes, logs and gable prisms: a log WOODCUTTER'S LODGE in the forest, a BIG
## RED BARN on the grasslands and a STILT SHACK out over the swamp water.
##
## Every piece that you can see is also solid (one collision box per wall
## run, so the doorways are real gaps the navmesh and the critters can get
## through). Doors are 4.6 m+ wide and 5 m+ tall: a 2.9 m frog fits.
## `loot_spots` (local, on the floor inside) are where crates, floor loot and
## a treasure chest go. Faces +Z; the front door is on that side.
##
## What you see is a model when there is one (assets/maps/island/<style>.glb,
## made in Blender by tools/maps/island.py from these same pieces: separate
## boards, stacked stones, layered thatch, framed windows), drawn with the
## materials below; the pieces here still make every collider.

enum Style { LODGE, BARN, SHACK }

const TEXTURES := "res://assets/textures/%s/%s"
const SOFT_SHADER := preload("res://src/world/shaders/soft_pbr.gdshader")
const DOOR_W := 4.8
const DOOR_H := 5.4
const MODEL := "res://assets/maps/island/%s.glb"
const END_GRAIN_SHADER := preload("res://src/world/shaders/end_grain.gdshader")

var style := Style.LODGE
## Floor points inside, in local space: where crates and loot go.
var loot_spots: Array[Vector3] = []
## Where a treasure chest sits (local), or Vector3.INF for none.
var chest_spot := Vector3.INF
## Radius that keeps trees and rocks away (and the POI flat).
var footprint := 12.0
## Height of the floor inside above the building's origin.
var floor_y := 0.0

## Building for tools/maps/island.py (tests/export_kits.gd): every piece and
## wall run is kept in `parts` and `walls`, as plain data, and no model is
## used, so the model is built to the same pieces as the colliders.
static var recording := false
var parts: Array = []
var walls: Array = []

static var _materials: Dictionary = {}
var _surfaces: Dictionary = {}      # material key -> SurfaceTool
var _rng: RandomNumberGenerator
var _wall := -1                     # (recording) the wall run being built


static func make(style_: Style, rng: RandomNumberGenerator) -> Building:
	var b := Building.new()
	b.style = style_
	b._rng = rng
	b.collision_layer = Layers.WORLD
	b.set_meta(&"surface", &"wood")
	match style_:
		Style.LODGE:
			b.name = "Lodge"
			b._build_lodge()
		Style.BARN:
			b.name = "Barn"
			b._build_barn()
		Style.SHACK:
			b.name = "Shack"
			b._build_shack()
	b._commit()
	return b


## World-space loot spots once the building is placed in the tree.
func world_loot_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in loot_spots:
		out.append(global_transform * p)
	return out


# ---- the three styles --------------------------------------------------------------------------

## Woodcutter's Lodge: stacked bark logs with notched corners, a thatched
## gable roof, a stone chimney, doors front and back and a porch.
func _build_lodge() -> void:
	var w := 18.0
	var d := 13.0
	var wall_h := 6.6
	var log_r := 0.36
	footprint = 15.0
	floor_y = 0.12
	# stone plinth sunk into the ground, plank floor on top
	_box(&"rock", Vector3(0, floor_y - 1.1, 0), Vector3(w + 0.8, 2.0, d + 0.8))
	_box(&"floorboards", Vector3(0, floor_y - 0.06, 0), Vector3(w - 0.4, 0.12, d - 0.4))
	var windows := [[-4.5, 3.0, 2.0, 4.2], [4.5, 3.0, 2.0, 4.2]]
	# front and back: a door in the middle of each, windows either side
	for zs in [1.0, -1.0]:
		var openings := [[0.0, DOOR_W, 0.0, DOOR_H]] + windows
		_log_wall(Vector3(-w * 0.5, floor_y, zs * d * 0.5), Vector3(w * 0.5, floor_y, zs * d * 0.5), wall_h, log_r, openings, 0.0)
	for xs in [1.0, -1.0]:
		_log_wall(Vector3(xs * w * 0.5, floor_y, -d * 0.5), Vector3(xs * w * 0.5, floor_y, d * 0.5), wall_h, log_r, [[0.0, 3.2, 2.0, 4.2]], log_r)
	# thatched gable roof along X, overhanging the walls
	var ridge := wall_h + 4.6
	_gable_roof(&"thatch", w + 2.4, d + 2.8, floor_y + wall_h, floor_y + ridge, 0.55)
	for xs in [1.0, -1.0]:
		_gable_end(&"planks", d - 0.2, floor_y + wall_h, floor_y + ridge - 0.3, xs * (w * 0.5 - 0.05), 0.3)
	# chimney up the east end
	_box(&"rock", Vector3(w * 0.5 + 0.6, floor_y + (ridge + 1.6) * 0.5, -2.5), Vector3(2.2, ridge + 1.6, 2.4))
	# porch: deck, two posts and a little roof
	_box(&"floorboards", Vector3(0, floor_y - 0.18, d * 0.5 + 2.4), Vector3(9.0, 0.36, 4.4))
	for xs in [-1.0, 1.0]:
		_log(&"bark", Vector3(xs * 4.2, floor_y, d * 0.5 + 4.2), Vector3(xs * 4.2, floor_y + wall_h - 0.4, d * 0.5 + 4.2), 0.28)
	_slab(&"thatch", Vector3(0, floor_y + wall_h - 0.2, d * 0.5 + 2.6), Vector3(10.0, 0.35, 5.2), Basis(Vector3.RIGHT, 0.22))
	# inside: a plank table and a stack of firewood (cover)
	_box(&"planks", Vector3(-3.5, floor_y + 1.0, -2.5), Vector3(3.6, 0.18, 1.8))
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_box(&"planks", Vector3(-3.5 + xs * 1.5, floor_y + 0.5, -2.5 + zs * 0.7), Vector3(0.2, 1.0, 0.2), Basis(), false)
	for i in 4:
		_log(&"bark", Vector3(5.0, floor_y + 0.32 + i * 0.5, -4.6 + (i % 2) * 0.25), Vector3(8.0, floor_y + 0.32 + i * 0.5, -4.6 + (i % 2) * 0.25), 0.25)
	loot_spots = [Vector3(-5.5, floor_y, 3.0), Vector3(5.5, floor_y, 3.0), Vector3(0.0, floor_y, -1.0),
		Vector3(-6.5, floor_y, -4.0), Vector3(3.0, floor_y, 1.5)]
	chest_spot = Vector3(1.5, floor_y, -4.7)


## Big Red Barn: red plank walls with white trim, a gambrel slate roof, huge
## doors at both ends (swung open), hay bales and stalls inside, and a carrot
## weathervane on the ridge.
func _build_barn() -> void:
	var w := 16.0
	var d := 23.0
	var wall_h := 7.0
	var t := 0.4
	footprint = 17.0
	floor_y = 0.12
	var door_w := 7.0
	var door_h := 6.6
	_box(&"rock", Vector3(0, floor_y - 1.1, 0), Vector3(w + 0.6, 2.0, d + 0.6))
	_box(&"floorboards", Vector3(0, floor_y - 0.06, 0), Vector3(w - 0.6, 0.12, d - 0.6))
	for zs in [1.0, -1.0]:
		_plank_wall(&"barn_red", Vector3(-w * 0.5, floor_y, zs * d * 0.5), Vector3(w * 0.5, floor_y, zs * d * 0.5), wall_h, t, [[0.0, door_w, 0.0, door_h]])
	for xs in [1.0, -1.0]:
		_plank_wall(&"barn_red", Vector3(xs * w * 0.5, floor_y, -d * 0.5), Vector3(xs * w * 0.5, floor_y, d * 0.5), wall_h, t,
			[[-6.0, 3.0, 3.0, 5.0], [6.0, 3.0, 3.0, 5.0]])
	# white trim: corner boards and door frames
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_box(&"barn_white", Vector3(xs * (w * 0.5 + 0.05), floor_y + wall_h * 0.5, zs * (d * 0.5 + 0.05)), Vector3(0.6, wall_h, 0.6), Basis(), false)
		for zs in [-1.0, 1.0]:
			_box(&"barn_white", Vector3(xs * (door_w * 0.5 + 0.2), floor_y + door_h * 0.5, zs * (d * 0.5 + 0.12)), Vector3(0.4, door_h, 0.3), Basis(), false)
	for zs in [-1.0, 1.0]:
		_box(&"barn_white", Vector3(0, floor_y + door_h + 0.2, zs * (d * 0.5 + 0.12)), Vector3(door_w + 0.8, 0.4, 0.3), Basis(), false)
		# the big doors, swung open flat against the wall, with white X braces
		for xs in [-1.0, 1.0]:
			var c := Vector3(xs * (door_w * 0.5 + 0.4 + door_w * 0.25), floor_y + door_h * 0.5, zs * (d * 0.5 + 0.45))
			_box(&"barn_red", c, Vector3(door_w * 0.5, door_h, 0.25))
			var diag := atan2(door_h, door_w * 0.5)
			for s in [-1.0, 1.0]:
				_box(&"barn_white", c + Vector3(0, 0, zs * 0.16), Vector3(sqrt(door_h * door_h + door_w * door_w * 0.25) - 0.4, 0.3, 0.06), Basis(Vector3.BACK, s * diag), false)
	# gambrel roof: steep lower slopes, shallow upper ones
	var eave := floor_y + wall_h
	var knee := Vector2(w * 0.5 - 2.6, eave + 3.4)
	var top := Vector2(0.0, eave + 5.6)
	for xs in [-1.0, 1.0]:
		_roof_strip(&"slate_roof", Vector2(xs * (w * 0.5 + 0.6), eave - 0.5), Vector2(xs * knee.x, knee.y), d + 1.6, 0.35)
		_roof_strip(&"slate_roof", Vector2(xs * knee.x, knee.y), Vector2(0.0, top.y), d + 1.6, 0.35)
	for zs in [1.0, -1.0]:
		_prism(&"barn_red", [Vector2(-w * 0.5, eave), Vector2(-knee.x, knee.y), Vector2(0.0, top.y - 0.25), Vector2(knee.x, knee.y), Vector2(w * 0.5, eave)],
			zs * (d * 0.5 - 0.05), t)
		# the hayloft door
		_box(&"barn_white", Vector3(0, eave + 2.0, zs * (d * 0.5 + 0.12)), Vector3(3.0, 2.6, 0.2), Basis(), false)
		_box(&"planks", Vector3(0, eave + 2.0, zs * (d * 0.5 + 0.2)), Vector3(2.4, 2.0, 0.12), Basis(), false)
	# carrot weathervane
	_log(&"tin_roof", Vector3(0, top.y, 4.0), Vector3(0, top.y + 2.6, 4.0), 0.06)
	_cone(&"carrot", Vector3(0, top.y + 2.4, 4.0), Vector3(0, top.y + 2.4, 2.2), 0.28)
	_cone(&"leaf", Vector3(0, top.y + 2.4, 4.0), Vector3(0, top.y + 2.9, 4.7), 0.18)
	# stalls down one side (low plank walls: cover), hay bales on the other
	for i in 3:
		var z := -7.0 + i * 5.0
		_box(&"planks", Vector3(w * 0.5 - 2.4, floor_y + 0.75, z), Vector3(4.4, 1.5, 0.25))
	loot_spots = [Vector3(5.6, floor_y, -4.5), Vector3(5.6, floor_y, 0.5), Vector3(-4.0, floor_y, 6.0),
		Vector3(-1.0, floor_y, -6.0), Vector3(2.0, floor_y, 3.0), Vector3(5.6, floor_y, 5.5)]
	chest_spot = Vector3(-5.5, floor_y, -9.0)


## Stilt Shack: a plank shack on log stilts over the swamp water, with a tin
## roof, a porch and a ramp down to the mud. `floor_y` is the deck height.
func _build_shack() -> void:
	var w := 14.0
	var d := 10.0
	var wall_h := 5.8
	var t := 0.3
	footprint = 13.0
	floor_y = 2.4
	_box(&"floorboards", Vector3(0, floor_y - 0.2, 0), Vector3(w + 0.4, 0.4, d + 0.4))
	for xs in [-1.0, 0.0, 1.0]:
		for zs in [-1.0, 1.0]:
			_log(&"bark", Vector3(xs * (w * 0.5 - 0.2), -2.0, zs * (d * 0.5 - 0.2)), Vector3(xs * (w * 0.5 - 0.2), floor_y - 0.3, zs * (d * 0.5 - 0.2)), 0.32, true)
	_plank_wall(&"planks", Vector3(-w * 0.5, floor_y, d * 0.5), Vector3(w * 0.5, floor_y, d * 0.5), wall_h, t, [[0.0, DOOR_W, 0.0, DOOR_H], [-4.6, 2.2, 2.0, 3.8]])
	# (the back and side walls stop under the lean-to roof's low edge: they
	# used to stand up through the tin at the back)
	_plank_wall(&"planks", Vector3(-w * 0.5, floor_y, -d * 0.5), Vector3(w * 0.5, floor_y, -d * 0.5), wall_h - 1.8, t, [[3.0, DOOR_W, 0.0, DOOR_H - 1.6]])
	for xs in [1.0, -1.0]:
		_plank_wall(&"planks", Vector3(xs * w * 0.5, floor_y, -d * 0.5), Vector3(xs * w * 0.5, floor_y, d * 0.5), wall_h - 1.8, t, [[0.0, 2.6, 2.0, 3.8]])
	# lean-to tin roof, sloping from the front down to the back
	var front_h := floor_y + wall_h + 0.4
	var back_h := floor_y + wall_h - 1.6
	_roof_strip(&"tin_roof", Vector2(d * 0.5 + 1.2, front_h + 0.3), Vector2(-d * 0.5 - 1.2, back_h - 0.3), w + 1.6, 0.2, true)
	for xs in [1.0, -1.0]:
		_prism(&"planks", [Vector2(d * 0.5, floor_y + wall_h - 1.8), Vector2(d * 0.5, front_h), Vector2(-d * 0.5, back_h), Vector2(-d * 0.5, floor_y + wall_h - 1.8)],
			xs * (w * 0.5 - 0.05), t, true)
	# porch and ramp
	_box(&"floorboards", Vector3(0, floor_y - 0.2, d * 0.5 + 1.7), Vector3(7.0, 0.4, 3.4))
	var ramp_len := 8.5
	var drop := floor_y + 0.4
	var ang := atan2(drop, ramp_len)
	var ramp_c := Vector3(0, floor_y * 0.5 - 0.35, d * 0.5 + 3.4 + ramp_len * 0.5 * cos(ang))
	var ramp_basis := Basis(Vector3.RIGHT, ang)
	var ramp_long := sqrt(ramp_len * ramp_len + drop * drop)
	_box(&"floorboards", ramp_c, Vector3(4.6, 0.3, ramp_long), ramp_basis)
	# hand rails: the ramp's sides are a ledge you can't step up, so the only
	# way on is the bottom end (the navmesh would otherwise join them up)
	for xs in [-1.0, 1.0]:
		_box(&"planks", ramp_c + ramp_basis * Vector3(xs * 2.22, 0.75, 0.0), Vector3(0.16, 1.2, ramp_long), ramp_basis)
	# a hanging lantern by the door
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.75, 0.4)
	lantern.light_energy = 1.6
	lantern.omni_range = 7.0
	lantern.position = Vector3(3.2, floor_y + 4.0, d * 0.5 + 0.8)
	add_child(lantern)
	_box(&"lantern", lantern.position, Vector3(0.35, 0.5, 0.35), Basis(), false)
	loot_spots = [Vector3(-4.5, floor_y, -2.5), Vector3(4.5, floor_y, -2.5), Vector3(-4.5, floor_y, 2.0), Vector3(1.5, floor_y, 1.0)]
	chest_spot = Vector3(-1.5, floor_y, -3.6)


# ---- walls ------------------------------------------------------------------------------------

## A wall run from a to b (on the floor) with rectangular openings
## [centre along the wall from its middle, width, bottom, top] (all metres).
## Calls `piece(from_along, to_along, bottom, top)` for every solid rectangle.
func _wall_pieces(length: float, height: float, openings: Array) -> Array:
	var cuts := [-length * 0.5]
	for o in openings:
		cuts.append(float(o[0]) - float(o[1]) * 0.5)
		cuts.append(float(o[0]) + float(o[1]) * 0.5)
	cuts.append(length * 0.5)
	cuts.sort()
	var pieces := []
	for i in cuts.size() - 1:
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 0.01:
			continue
		var mid := (a + b) * 0.5
		# vertical solid spans in this column: the full height minus any openings over it
		var spans := [[0.0, height]]
		for o in openings:
			if absf(mid - float(o[0])) < float(o[1]) * 0.5:
				var next := []
				for s in spans:
					if float(o[2]) > s[0]:
						next.append([s[0], minf(float(o[2]), s[1])])
					if float(o[3]) < s[1]:
						next.append([maxf(float(o[3]), s[0]), s[1]])
				spans = next
		for s in spans:
			if s[1] - s[0] > 0.01:
				pieces.append([a, b, s[0], s[1]])
	return pieces


func _plank_wall(mat: StringName, a: Vector3, b: Vector3, height: float, thick: float, openings: Array) -> void:
	_begin_wall("plank", mat, a, b, height, thick, openings)
	var along := (b - a)
	var length := along.length()
	var dir := along / length
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var mid := (a + b) * 0.5
	for p in _wall_pieces(length, height, openings):
		var c: Vector3 = mid + dir * (p[0] + p[1]) * 0.5 + Vector3.UP * (p[2] + p[3]) * 0.5
		_box(mat, c, Vector3(p[1] - p[0], p[3] - p[2], thick), basis)
	_wall = -1


## A wall of stacked logs: one collision box per solid piece, logs cut at the
## openings and running past the corners (`offset` staggers the courses of
## adjacent walls by half a log, like notched corners).
func _log_wall(a: Vector3, b: Vector3, height: float, r: float, openings: Array, offset: float) -> void:
	_begin_wall("log", &"bark", a, b, height, r * 2.0, openings)
	var along := (b - a)
	var length := along.length()
	var dir := along / length
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var mid := (a + b) * 0.5
	for p in _wall_pieces(length, height, openings):
		var c: Vector3 = mid + dir * (p[0] + p[1]) * 0.5 + Vector3.UP * (p[2] + p[3]) * 0.5
		_collide(c, Vector3(p[1] - p[0], p[3] - p[2], r * 2.0), basis)
	var rows := int(height / (r * 2.0))
	for i in rows:
		var y := r + i * r * 2.0 + offset
		if y + r > height + 0.01:
			break
		# the open spans of this course
		var spans := [[-length * 0.5 - 0.6, length * 0.5 + 0.6]]
		for o in openings:
			if y + r > float(o[2]) and y - r < float(o[3]):
				var next := []
				for s in spans:
					var lo := float(o[0]) - float(o[1]) * 0.5
					var hi := float(o[0]) + float(o[1]) * 0.5
					if lo > s[0]:
						next.append([s[0], minf(lo, s[1])])
					if hi < s[1]:
						next.append([maxf(hi, s[0]), s[1]])
				spans = next
		for s in spans:
			if s[1] - s[0] > 0.2:
				_log(&"bark", mid + dir * s[0] + Vector3.UP * y, mid + dir * s[1] + Vector3.UP * y, r * (0.92 + _rng.randf() * 0.12), false)
	_wall = -1


## (recording) A wall run starts: its pieces are tagged with it.
func _begin_wall(kind: String, mat: StringName, a: Vector3, b: Vector3, height: float, thick: float, openings: Array) -> void:
	if recording:
		_wall = walls.size()
		walls.append({"kind": kind, "mat": String(mat), "a": _v(a), "b": _v(b), "height": height, "thick": thick, "openings": openings.duplicate(true)})


## A sloped roof strip between two (across, height) points of the profile,
## `length` long along the building. The profile is across X (the strip runs
## along Z), or across Z with `along_x` (the strip runs along X).
func _roof_strip(mat: StringName, p0: Vector2, p1: Vector2, length: float, thick: float, along_x := false) -> void:
	var span := p1 - p0
	var ang := atan2(span.y, span.x)
	var mid := (p0 + p1) * 0.5
	if along_x:
		# profile across Z: rotate about X
		_slab(mat, Vector3(0, mid.y, mid.x), Vector3(length, thick, span.length() + 0.1), Basis(Vector3.RIGHT, -ang))
	else:
		# profile across X: rotate about Z (the strip runs along Z)
		var c := Vector3(mid.x, mid.y, 0)
		_slab(mat, c, Vector3(span.length() + 0.1, thick, length), Basis(Vector3.BACK, ang))


## A two-sided gable roof (ridge along X).
func _gable_roof(mat: StringName, length: float, depth: float, eave_y: float, ridge_y: float, thick: float) -> void:
	for zs in [1.0, -1.0]:
		var p0 := Vector2(zs * depth * 0.5, eave_y - 0.3)
		var p1 := Vector2(0.0, ridge_y)
		var span := p1 - p0
		var ang := atan2(span.y, span.x)
		var mid := (p0 + p1) * 0.5
		_slab(mat, Vector3(0, mid.y, mid.x), Vector3(length, thick, span.length() + 0.4), Basis(Vector3.RIGHT, -ang))


## The triangle under a gable roof whose ridge runs along X: in the Z-Y plane
## at x, `width` across Z.
func _gable_end(mat: StringName, width: float, base_y: float, top_y: float, x: float, thick: float) -> void:
	_prism(mat, [Vector2(-width * 0.5, base_y), Vector2(0.0, top_y), Vector2(width * 0.5, base_y)], x, thick, true)


# ---- geometry --------------------------------------------------------------------------------

## A box that is drawn and (by default) solid.
func _box(mat: StringName, c: Vector3, size: Vector3, basis := Basis(), solid := true) -> void:
	if recording:
		_record({"kind": "box", "mat": String(mat), "c": _v(c), "size": _v(size), "basis": [_v(basis.x), _v(basis.y), _v(basis.z)], "solid": solid})
	var h := size * 0.5
	var axes := [basis.x, basis.y, basis.z]
	var st := _st(mat)
	for f in 6:
		var n_axis: int = f / 2
		var sgn := 1.0 if f % 2 == 0 else -1.0
		var n: Vector3 = axes[n_axis] * sgn
		var u_axis := (n_axis + 1) % 3
		var v_axis := (n_axis + 2) % 3
		# UVs run along the face's longer side horizontally, in metres
		var u: Vector3 = axes[u_axis]
		var v: Vector3 = axes[v_axis]
		var hu: float = h[u_axis]
		var hv: float = h[v_axis]
		if absf(v.dot(Vector3.UP)) < absf(u.dot(Vector3.UP)):
			var tmp := u
			u = v
			v = tmp
			var th := hu
			hu = hv
			hv = th
		var centre: Vector3 = c + n * h[n_axis]
		var corners := [centre - u * hu - v * hv, centre + u * hu - v * hv, centre + u * hu + v * hv, centre - u * hu + v * hv]
		var uvs := [Vector2(-hu, hv), Vector2(hu, hv), Vector2(hu, -hv), Vector2(-hu, -hv)]
		var tri := [0, 1, 2, 0, 2, 3] if u.cross(v).dot(n) < 0.0 else [0, 2, 1, 0, 3, 2]
		var off := Vector2(c.dot(u), -c.dot(v))   # keep the texture continuous between boxes
		for k in tri:
			st.set_normal(n)
			st.set_uv((uvs[k] + off))
			st.add_vertex(corners[k])
	if solid:
		_collide(c, size, basis)


## A box that is drawn, solid, and looks like a thick board or roof slab.
func _slab(mat: StringName, c: Vector3, size: Vector3, basis: Basis) -> void:
	_box(mat, c, size, basis, true)


func _collide(c: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = Transform3D(basis, c)
	add_child(cs)


## A round log from a to b.
func _log(mat: StringName, a: Vector3, b: Vector3, r: float, solid := true) -> void:
	if recording:
		_record({"kind": "log", "mat": String(mat), "a": _v(a), "b": _v(b), "r": r, "solid": solid})
	var axis := b - a
	var length := axis.length()
	var dir := axis / length
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir)
	var seg := _segments(10)
	var st := _st(mat)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		var quad := [[a + n0 * r, n0, Vector2(a0 * r, 0.0)], [b + n0 * r, n0, Vector2(a0 * r, length)],
			[b + n1 * r, n1, Vector2(a1 * r, length)], [a + n1 * r, n1, Vector2(a1 * r, 0.0)]]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])
	# end caps (cut log faces)
	for end in [[a, -dir], [b, dir]]:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0: Vector3 = end[0] + (side * cos(a0) + up * sin(a0)) * r
			var p1: Vector3 = end[0] + (side * cos(a1) + up * sin(a1)) * r
			var tri := [end[0], p0, p1] if end[1] == dir else [end[0], p1, p0]
			for p in tri:
				st.set_normal(end[1])
				st.set_uv(Vector2((p - end[0]).dot(side), (p - end[0]).dot(up)))
				st.add_vertex(p)
	if solid:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = length
		cs.shape = cyl
		cs.transform = Transform3D(Basis(side, dir, side.cross(dir)), (a + b) * 0.5)   # cylinder axis = Y
		add_child(cs)


## A cone (carrot!) from base a to tip b.
func _cone(mat: StringName, a: Vector3, b: Vector3, r: float) -> void:
	if recording:
		_record({"kind": "cone", "mat": String(mat), "a": _v(a), "b": _v(b), "r": r})
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir)
	var st := _st(mat)
	var seg := _segments(10)
	for i in seg:
		var a0 := TAU * (i + 0.5) / seg
		var p0 := a + (side * cos(TAU * i / seg) + up * sin(TAU * i / seg)) * r
		var p1 := a + (side * cos(TAU * (i + 1) / seg) + up * sin(TAU * (i + 1) / seg)) * r
		var out := (side * cos(a0) + up * sin(a0)).normalized()
		_tri(st, [p0, p1, b], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], (out + dir * 0.3).normalized())


## A flat prism: polygon `pts` (x, y) extruded `thick` along Z, centred on z.
## Solid via a convex shape.
func _prism(mat: StringName, pts: Array, z: float, thick: float, along_z_profile := false) -> void:
	if recording:
		_record({"kind": "prism", "mat": String(mat), "pts": pts.map(func(p: Vector2): return [p.x, p.y]), "z": z, "thick": thick, "along_z": along_z_profile})
	var st := _st(mat)
	var verts3 := []
	for half in [thick * 0.5, -thick * 0.5]:
		for p in pts:
			verts3.append(_prism_point(p, z + half, along_z_profile))
	var n := pts.size()
	var front := _prism_normal(along_z_profile)
	var centre := Vector3.ZERO
	for v in verts3:
		centre += v
	centre /= verts3.size()
	# the two faces (fans)
	for side in [0, 1]:
		var nrm: Vector3 = front * (1.0 if side == 0 else -1.0)
		for i in range(1, n - 1):
			var tri: Array = [verts3[side * n], verts3[side * n + i], verts3[side * n + i + 1]]
			var uv := tri.map(func(p: Vector3): return Vector2(p.x + p.z, -p.y))
			_tri(st, tri, uv, nrm)
	# the rim
	for i in n:
		var j := (i + 1) % n
		var q := [verts3[i], verts3[j], verts3[n + j], verts3[n + i]]
		var e: Vector3 = q[1] - q[0]
		var nrm := e.cross(front).normalized()
		if nrm.dot((q[0] + q[1]) * 0.5 - centre) < 0.0:
			nrm = -nrm
		var len_e := e.length()
		var uvs := [Vector2(0, 0), Vector2(len_e, 0), Vector2(len_e, thick), Vector2(0, thick)]
		_tri(st, [q[0], q[1], q[2]], [uvs[0], uvs[1], uvs[2]], nrm)
		_tri(st, [q[0], q[2], q[3]], [uvs[0], uvs[2], uvs[3]], nrm)
	var cs := CollisionShape3D.new()
	var cvx := ConvexPolygonShape3D.new()
	cvx.points = PackedVector3Array(verts3)
	cs.shape = cvx
	add_child(cs)


## One triangle facing `nrm` (Godot draws clockwise-wound faces).
func _tri(st: SurfaceTool, p: Array, uv: Array, nrm: Vector3) -> void:
	var order := [0, 1, 2] if (p[1] - p[0]).cross(p[2] - p[0]).dot(nrm) < 0.0 else [0, 2, 1]
	for k in order:
		st.set_normal(nrm)
		st.set_uv(uv[k])
		st.add_vertex(p[k])


func _prism_point(p: Vector2, depth: float, along_z_profile: bool) -> Vector3:
	# profile in X-Y (extruded along Z), or in Z-Y (extruded along X)
	return Vector3(depth, p.y, p.x) if along_z_profile else Vector3(p.x, p.y, depth)


func _prism_normal(along_z_profile: bool) -> Vector3:
	return Vector3.RIGHT if along_z_profile else Vector3.BACK


# ---- materials & mesh -----------------------------------------------------------------------------

## How many sides a round piece gets (CageKit doubles them for its models).
func _segments(n: int) -> int:
	return n


func _st(mat: StringName) -> SurfaceTool:
	if not _surfaces.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[mat] = st
	return _surfaces[mat]


func _commit() -> void:
	var m := island_model(MODEL % String(Style.keys()[style]).to_lower()) if not recording else null
	if m:
		_surfaces.clear()
		add_child(m)
		return
	var mesh := ArrayMesh.new()
	for key in _surfaces:
		var st: SurfaceTool = _surfaces[key]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	add_child(mi)
	_surfaces.clear()


## A building's model (or null without one), its "bld:<key>" materials drawn
## with Building's own.
static func island_model(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var root := ModelUtil.instantiate(path)
	if root == null:
		return null
	root.name = "Model"
	for mi in ModelUtil.find_all(root, "MeshInstance3D"):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			var n := sm.resource_name if sm else ""
			if n.begins_with("bld:"):
				(mi as MeshInstance3D).set_surface_override_material(i, material(StringName(n.trim_prefix("bld:"))))
	return root


## (recording) One piece, as plain data.
func _record(part: Dictionary) -> void:
	part["wall"] = _wall
	parts.append(part)


static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Shared materials (texture tiles are in metres: UVs are in metres). The
## textured ones use the soft PBR shader (photo detail toned down).
static func material(key: StringName) -> Material:
	if _materials.has(key):
		return _materials[key]
	# [texture folder, metres per repeat, tint, use the colour texture]
	var spec: Array = {
		&"planks": ["planks", 2.4, Color(1, 1, 1), true],
		&"barn_red": ["planks", 2.4, Color(1.35, 0.36, 0.28), true],
		&"barn_white": ["planks", 2.4, Color(0.9, 0.88, 0.82), false],
		&"floorboards": ["floorboards", 2.2, Color(1, 1, 1), true],
		&"thatch": ["thatch", 4.5, Color(0.9, 0.82, 0.66), true],
		&"slate_roof": ["slate_roof", 2.6, Color(1, 1, 1), true],
		&"tin_roof": ["tin_roof", 2.2, Color(1, 1, 1), true],
		&"bark": ["bark", 2.4, Color(1, 1, 1), true],
		&"rock": ["rock", 3.0, Color(1, 1, 1), true],
		# the models' extra detail: single stones, mortar, a rug
		&"stone": ["rock", 1.6, Color(1.1, 1.05, 1.0), true],
		&"stone_warm": ["rock", 1.6, Color(1.25, 1.08, 0.9), true],
		&"stone_cool": ["rock", 1.6, Color(0.95, 1.0, 1.08), true],
		&"mortar": ["rock", 3.0, Color(0.62, 0.6, 0.56), false],
		&"plaid": ["plaid", 1.6, Color(1.0, 0.66, 0.56), true],
	}.get(key, [])
	if not spec.is_empty():
		var sm := ShaderMaterial.new()
		sm.shader = SOFT_SHADER
		var dir: String = spec[0]
		var alb := _tex(TEXTURES % [dir, "albedo.jpg"]) if spec[3] else null
		var nrm := _tex(TEXTURES % [dir, "normal.png"])
		var rgh := _tex(TEXTURES % [dir, "roughness.jpg"])
		sm.set_shader_parameter(&"albedo_tex", alb)
		sm.set_shader_parameter(&"use_albedo", alb != null)
		sm.set_shader_parameter(&"normal_tex", nrm)
		sm.set_shader_parameter(&"use_normal", nrm != null)
		sm.set_shader_parameter(&"rough_tex", rgh)
		sm.set_shader_parameter(&"use_rough", rgh != null)
		sm.set_shader_parameter(&"tint", spec[2])
		sm.set_shader_parameter(&"metres_per_repeat", float(spec[1]))
		_materials[key] = sm
		return sm
	if key == &"end_grain":
		var eg := ShaderMaterial.new()
		eg.shader = END_GRAIN_SHADER
		_materials[key] = eg
		return eg
	var m := StandardMaterial3D.new()
	match key:
		&"chinking":
			m.albedo_color = Color(0.62, 0.58, 0.5)
		&"iron":
			m.albedo_color = Color(0.17, 0.17, 0.19)
			m.metallic = 0.6
		&"soot":
			m.albedo_color = Color(0.07, 0.06, 0.06)
		&"soil":
			m.albedo_color = Color(0.25, 0.17, 0.11)
		&"petal_red":
			m.albedo_color = Color(0.95, 0.27, 0.32)
		&"petal_yellow":
			m.albedo_color = Color(1.0, 0.83, 0.22)
		&"petal_white":
			m.albedo_color = Color(0.97, 0.95, 0.92)
		&"petal_purple":
			m.albedo_color = Color(0.64, 0.42, 0.92)
		&"carrot":
			m.albedo_color = Color(0.95, 0.45, 0.1)
		&"leaf":
			m.albedo_color = Color(0.3, 0.6, 0.15)
		&"lantern":
			m.albedo_color = Color(1.0, 0.8, 0.45)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.7, 0.35)
			m.emission_energy_multiplier = 3.0
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[key] = m
	return m


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null
