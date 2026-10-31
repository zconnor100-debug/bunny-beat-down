class_name ToyProps
extends RefCounted
## Builders for Toy Box Bash's toys, all original procedural geometry on the
## CageKit primitives (one merged mesh per toy, every visible piece solid
## unless it says otherwise). Each stands on its origin, front toward +Z.
## Critter scale: a Bun is ~2.6 m, the dollhouse three storeys of 8.5 m.

const CREW := [&"red", &"blue", &"yellow", &"lime", &"purple", &"orange", &"teal", &"pink"]


## The crayon models' colours, by crew colour.
const CRAYON_MODEL := {&"red": "red", &"blue": "blue", &"yellow": "yellow", &"lime": "green", &"purple": "violet",
	&"orange": "orange", &"teal": "blue", &"pink": "red"}
const LETTER_VARIANTS := 6
## The letters on each loose block model (cells of the alphabet atlas).
const LETTER_CELLS := [[0, 1, 2, 3, 4, 5], [6, 7, 8, 9, 10, 11], [12, 13, 14, 15, 0, 7], [3, 9, 1, 12, 5, 14],
	[10, 2, 15, 6, 8, 4], [13, 11, 0, 5, 7, 2]]
const TOWER_S := 8.0               ## the brick tower models' width (scaled to each tower)


static func _c(rng: RandomNumberGenerator) -> StringName:
	return CREW[rng.randi() % CREW.size()]


static func env(id: String) -> String:
	return CageProps.env(id)


static func made(name: String) -> String:
	return CageProps.made(name)


## Dollhouse Manor: three storeys and an attic under a pink roof, open at the
## back like every dollhouse, with ramps (the stairs) up through holes in the
## floors, furniture in every room and loot on every floor.
static func dollhouse(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Dollhouse", rng, &"wood")
	var w := 34.0
	var d := 18.0
	var t := 0.5
	var storey := 8.5
	var f := [0.12, 0.12 + storey, 0.12 + storey * 2.0]
	var top: float = f[2] + storey
	k.footprint = 24.0
	k.floor_y = f[0]
	k._box(&"wood_light", Vector3(0, -0.5, 0), Vector3(w + 0.8, 1.24, d + 0.8))
	# outer walls: the front with windows and a door, the two ends; the back is open
	var front_holes := [[0.0, 5.2, 0.0, 6.0], [-11.0, 3.6, 2.4, 5.6], [11.0, 3.6, 2.4, 5.6],
		[-11.0, 3.6, storey + 2.2, storey + 5.6], [0.0, 3.6, storey + 2.2, storey + 5.6], [11.0, 3.6, storey + 2.2, storey + 5.6],
		[-6.0, 3.0, storey * 2.0 + 2.4, storey * 2.0 + 5.4], [6.0, 3.0, storey * 2.0 + 2.4, storey * 2.0 + 5.4]]
	k._plank_wall(&"paint_pink", Vector3(-w * 0.5, f[0], d * 0.5), Vector3(w * 0.5, f[0], d * 0.5), top - f[0], t, front_holes)
	for xs in [-1.0, 1.0]:
		k._plank_wall(&"paint_yellow", Vector3(xs * w * 0.5, f[0], -d * 0.5), Vector3(xs * w * 0.5, f[0], d * 0.5), top - f[0], t,
			[[0.0, 3.4, 2.6, 5.6], [0.0, 3.4, storey + 2.6, storey + 5.6], [0.0, 3.4, storey * 2.0 + 2.6, storey * 2.0 + 5.6]])
	# white trim: window frames and the door's awning
	for hole in front_holes:
		var c := Vector3(hole[0], f[0] + (float(hole[2]) + float(hole[3])) * 0.5, d * 0.5 + 0.32)
		k._box(&"plastic_white", c + Vector3(0, (float(hole[3]) - float(hole[2])) * 0.5 + 0.2, 0), Vector3(float(hole[1]) + 0.8, 0.4, 0.3), Basis(), false)
		k._box(&"plastic_white", c - Vector3(0, (float(hole[3]) - float(hole[2])) * 0.5 + 0.2, 0), Vector3(float(hole[1]) + 0.8, 0.4, 0.5), Basis(), false)
	k._box(&"paint_teal", Vector3(0, f[0] + 6.6, d * 0.5 + 1.6), Vector3(7.0, 0.35, 3.2), Basis(Vector3.RIGHT, -0.2), false)
	# floors 1 and 2, each with a stairwell hole where the ramp comes up
	_slab_with_hole(k, f[1], w, d, Rect2(-11.0, -8.2, 13.0, 4.4))
	_slab_with_hole(k, f[2], w, d, Rect2(-6.0, 2.8, 17.0, 4.4))
	# the stairs: ramp 1 (ground → first) along the back, ramp 2 (first → second) along the front
	k._ramp(&"wood_light", Vector3(5.0, f[0] - 0.15, -6.0), Vector3(-11.0, f[1], -6.0), 3.8, &"paint_white")
	k._ramp(&"wood_light", Vector3(-5.0, f[1] - 0.15, 5.0), Vector3(11.0, f[2], 5.0), 3.8, &"paint_white")
	# railings along the open back of the upper floors
	for y in [f[1], f[2]]:
		k._box(&"plastic_white", Vector3(0, y + 0.6, -d * 0.5 + 0.2), Vector3(w - 1.0, 1.2, 0.3))
	# roof: a pink gable over the attic, plank gable ends and a chimney
	var ridge := top + 7.5
	k._gable_roof(&"paint_pink", w + 2.6, d + 2.6, top, ridge, 0.5)
	for xs in [1.0, -1.0]:
		k._gable_end(&"paint_yellow", d - 0.2, top, ridge - 0.3, xs * (w * 0.5 - 0.05), t)
	k._box(&"paint_red", Vector3(9.0, ridge - 1.0, -2.0), Vector3(2.4, 5.0, 2.4))
	# furniture: a kitchen table, a bed and a dresser upstairs, a rocking horse in the attic
	k._box(&"paint_teal", Vector3(-9.0, f[0] + 1.6, 2.0), Vector3(6.0, 0.4, 4.0))
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			k._rod(&"plastic_white", Vector3(-9.0 + xs * 2.6, f[0], 2.0 + zs * 1.6), Vector3(-9.0 + xs * 2.6, f[0] + 1.4, 2.0 + zs * 1.6), 0.25, false)
	k._box(&"paint_purple", Vector3(12.0, f[0] + 2.0, -1.0), Vector3(4.0, 4.0, 3.0))
	k._box(&"paint_blue", Vector3(-10.0, f[1] + 1.0, 4.5), Vector3(7.0, 2.0, 4.0))
	k._ellipsoid(&"pillow_white", Vector3(-12.0, f[1] + 2.4, 4.5), Vector3(1.4, 0.6, 1.8), Basis(), false, 5, 10)
	k._box(&"paint_orange", Vector3(13.0, f[1] + 2.5, -3.0), Vector3(3.0, 5.0, 4.0))
	k._ellipsoid(&"paint_yellow", Vector3(-11.0, f[2] + 3.0, -2.0), Vector3(3.2, 1.6, 1.2))
	k._ellipsoid(&"paint_red", Vector3(-11.0, f[2] + 0.6, -2.0), Vector3(4.0, 0.5, 1.4), Basis(), false, 4, 12)
	k.loot_spots = [Vector3(-12.0, f[0], -3.0), Vector3(9.0, f[0], 5.0), Vector3(0.0, f[1], 2.0), Vector3(13.0, f[1], 3.0),
		Vector3(-13.0, f[2], 5.0), Vector3(8.0, f[2], -4.0)]
	k.chest_spot = Vector3(0.0, f[2], -5.0)
	return k.made_as("toy/dollhouse").finish()


## A floor slab w × d at height y with a rectangular hole (x, z, width, depth).
static func _slab_with_hole(k: CageKit, y: float, w: float, d: float, hole: Rect2) -> void:
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	var th := 0.5
	for piece in [Rect2(x0, z0, hole.position.x - x0, d), Rect2(hole.end.x, z0, x1 - hole.end.x, d),
			Rect2(hole.position.x, z0, hole.size.x, hole.position.y - z0), Rect2(hole.position.x, hole.end.y, hole.size.x, z1 - hole.end.y)]:
		var r: Rect2 = piece
		if r.size.x > 0.05 and r.size.y > 0.05:
			k._box(&"wood_light", Vector3(r.get_center().x, y - th * 0.5, r.get_center().y), Vector3(r.size.x, th, r.size.y))


## Block Castle: walls of alphabet blocks two high round a courtyard, every
## other block on top a crenel, towers of blocks four high at the corners and
## a gate two blocks wide.
static func block_castle(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("BlockCastle", rng, &"wood")
	var s := 4.0
	var n := 8                # blocks per side
	var half := (n - 1) * s * 0.5
	k.footprint = half + 6.0
	k.floor_y = 0.0
	var cells := func() -> Array: return [rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16]
	# every block a piece of its own (ToyBlock), so blasts can knock the walls
	# down (BlockPile); the random draws in the order they always were
	var pile := BlockPile.new()
	pile.reach = half * 1.5 + s
	var block := func(at: Vector3, basis: Basis, c: Array) -> void:
		var b := letter_piece(s, c)
		b.position = at
		b.basis = basis
		k.add_child(b)
		pile.blocks.append(b)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		# each wall stops one block short: the next wall's first block is the corner
		for i in n - 1:
			var along := -half + i * s
			var gate := side == 0 and absf(along) < s
			for layer in 2:
				if gate:
					continue
				block.call(b * Vector3(along, s * 0.5 + layer * s, half), b, cells.call())
			if i % 2 == 0 and i > 0 and not gate:
				block.call(b * Vector3(along, s * 2.5, half), b, cells.call())
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			for layer in [2, 3]:
				block.call(Vector3(xs * half, s * 0.5 + layer * s, zs * half), Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), cells.call())
	# a lintel over the gate, and a pile of blocks inside as cover
	var lintel := ToyBlock.new(Vector3(s * 3.0, 0.8, s))
	lintel.name = "Lintel"
	var plank := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = lintel.size
	plank.mesh = box
	plank.material_override = CageKit.mat(&"paint_blue")
	lintel.dress(plank)
	lintel.position = Vector3(0, s * 2.0 + 0.4, half)
	k.add_child(lintel)
	pile.blocks.append(lintel)
	for i in 3:
		block.call(Vector3(-6.5 + i * 5.2, s * 0.5, -6.0), Basis(Vector3.UP, rng.randf() * 0.4), cells.call())
	block.call(Vector3(-3.9, s * 1.5, -6.0), Basis(Vector3.UP, 0.3), cells.call())
	k.add_child(pile)
	k.loot_spots = [Vector3(6.0, 0.0, 4.0), Vector3(-7.0, 0.0, 6.0), Vector3(7.0, 0.0, -8.0), Vector3(0.0, 0.0, 1.0)]
	k.chest_spot = Vector3(-8.0, 0.0, 0.0)
	return k.finish()


## One lettered block `size` across as a piece of its own (ToyBlock), its
## middle at its origin, the lettered block model picked by its letters.
static func letter_piece(size: float, cells: Array) -> ToyBlock:
	var b := ToyBlock.new(Vector3.ONE * size)
	b.name = "LetterBlock"
	var v: int = (int(cells[0]) + int(cells[1]) + int(cells[2])) % LETTER_VARIANTS
	var m := CageKit.model(made("toy/letter_block_%d" % v))
	if m == null:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = b.size
		mi.mesh = box
		mi.material_override = CageKit.mat(StringName("plastic_" + String(CREW[v % CREW.size()])))
		m = mi
	else:
		m.transform = Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3.DOWN * size * 0.5)   # (the model stands on its own bottom)
	b.dress(m)
	return b


## A plastic-brick house: walls in courses of bricks (the grooves between the
## courses), a door and windows, studs on the flat roof.
static func brick_house(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("BrickHouse", rng, &"wood")
	var colour := k.accent("accent", StringName("plastic_" + String(_c(rng))))
	var w := 16.0
	var d := 12.0
	var h := 9.0
	k.footprint = 12.0
	k.floor_y = 0.05
	k._plank_wall(colour, Vector3(-w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, d * 0.5), h, 1.0, [[0.0, 5.0, 0.0, 6.0], [-5.0, 3.0, 2.5, 5.5], [5.0, 3.0, 2.5, 5.5]])
	k._plank_wall(colour, Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5), h, 1.0, [[3.0, 4.6, 0.0, 6.0]])
	for xs in [-1.0, 1.0]:
		k._plank_wall(colour, Vector3(xs * w * 0.5, 0, -d * 0.5), Vector3(xs * w * 0.5, 0, d * 0.5), h, 1.0, [[0.0, 3.0, 2.5, 5.5]])
	# the roof plate and its studs
	k._box(&"plastic_white", Vector3(0, h + 0.4, 0), Vector3(w + 0.4, 0.8, d + 0.4))
	for x in range(-3, 4):
		for z in range(-2, 3):
			k._lathe(&"plastic_white", [Vector2(0.75, 0.0), Vector2(0.75, 0.55), Vector2(0.0, 0.55)], 10, Vector3(x * 2.2, h + 0.8, z * 2.2), false)
	k.loot_spots = [Vector3(-4.0, 0.05, -2.0), Vector3(4.0, 0.05, 1.0)]
	return k.made_as("toy/brick_house").finish()


## Brick City's green baseplate (decoration: walk on the floor through it).
static func baseplate(rng: RandomNumberGenerator) -> CageKit:
	var plate := CageKit.blank("Baseplate", rng)
	plate.collision_layer = 0
	plate._box(&"plastic_lime", Vector3(0, 0.03, 0), Vector3(110.0, 0.06, 110.0), Basis(), false)
	return plate.made_as("toy/baseplate").finish()


## A tower of stacked plastic bricks, each course a different colour, studs on top.
static func brick_tower(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("BrickTower", rng, &"wood")
	var s := rng.randf_range(7.0, 9.0)
	var courses := rng.randi_range(4, 8)
	if CageKit.exporting:
		s = TOWER_S
	for i in courses:
		var b := Basis(Vector3.UP, rng.randf_range(-0.08, 0.08))
		k._box(k.accent("accent%d" % i, StringName("plastic_" + String(_c(rng)))), Vector3(0, i * 3.0 + 1.5, 0), Vector3(s, 3.0, s * 0.62), b)
	for x in range(-1, 2):
		for z in range(-1, 1):
			k._lathe(&"plastic_white", [Vector2(0.9, 0.0), Vector2(0.9, 0.6), Vector2(0.0, 0.6)], 10, Vector3(x * s * 0.33, courses * 3.0, (z + 0.5) * s * 0.3), false)
	k.footprint = s * 0.7
	return k.made_as("toy/brick_tower_%d" % courses, Transform3D(Basis.from_scale(Vector3(s / TOWER_S, 1.0, s / TOWER_S)), Vector3.ZERO)).finish()


## Pillow Fort: two chairs back to back with a gingham blanket draped over
## their backs into a tent, open at both ends, plaid pillows piled round it.
static func pillow_fort(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("PillowFort", rng, &"wood")
	var gap := 9.0
	k.footprint = 20.0
	k.floor_y = 0.05
	for xs in [-1.0, 1.0]:
		var bx: float = xs * gap
		# chair: four legs, a seat facing out, and the back on the inside
		for lz in [-4.0, 4.0]:
			for lx in [0.6, 8.4]:
				k._rod(&"wood_honey", Vector3(bx + xs * lx, -0.2, lz), Vector3(bx + xs * lx, 8.0, lz), 0.5)
		k._box(&"wood_honey", Vector3(bx + xs * 4.5, 8.3, 0), Vector3(9.5, 0.7, 9.5))
		k._box(&"wood_honey", Vector3(bx + xs * 0.5, 13.5, 0), Vector3(0.8, 11.0, 9.5))
	# the blanket: a sagging sheet over both chair backs, falling on to the seats
	var nx := 14
	var nz := 8
	var pts := []
	for iz in nz + 1:
		var row := []
		for ix in nx + 1:
			var x := lerpf(-gap - 7.0, gap + 7.0, float(ix) / nx)
			var z := lerpf(-7.5, 7.5, float(iz) / nz)
			var y: float
			if absf(x) <= gap + 0.5:
				y = 19.2 - 3.0 * (1.0 - pow(x / (gap + 0.5), 2.0))
			else:
				y = lerpf(19.2, 9.2, smoothstep(gap + 0.5, gap + 7.0, absf(x)))
			y -= 0.6 * pow(absf(z) / 7.5, 2.0)
			row.append(Vector3(x, y, z))
		pts.append(row)
	for iz in nz:
		for ix in nx:
			var a: Vector3 = pts[iz][ix]
			var b: Vector3 = pts[iz][ix + 1]
			var c: Vector3 = pts[iz + 1][ix + 1]
			var dd: Vector3 = pts[iz + 1][ix]
			var n := (b - a).cross(dd - a).normalized()
			if n.y < 0.0:
				n = -n
			var st := k._st(&"gingham")
			var uv := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z)
			for side in [n, -n]:
				k._face(st, [a, b, c], [uv.call(a), uv.call(b), uv.call(c)], side, side == n)
				k._face(st, [a, c, dd], [uv.call(a), uv.call(c), uv.call(dd)], side, side == n)
	# pillows heaped round the outside
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.2, 0.2)
		var at := Vector3(cos(a) * 22.0, 2.0, sin(a) * 16.0)
		if absf(sin(a)) > 0.85:
			continue   # (keep the tent's ends open)
		var key := StringName("pillow_" + String(_c(rng)))
		if CageKit.exporting:
			continue   # (the pillows are their own models, below)
		k._ellipsoid(key, at, Vector3(5.5, 2.2, 3.8), Basis(Vector3.UP, a), true, 6, 12)
		k.dress(made("toy/pillow"), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(5.5 / 6.0, 2.2 / 2.4, 3.8 / 4.1)), at + Vector3.DOWN * 2.2), {"accent": key})
	k.loot_spots = [Vector3(0.0, 0.05, 0.0), Vector3(-4.0, 0.05, 3.0)]
	k.chest_spot = Vector3(4.0, 0.05, -3.0)
	return k.made_as("toy/pillow_fort").finish()


## A big teddy bear sitting on the floor: cover, and a landmark.
static func teddy(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Teddy", rng, &"wood")
	k._ellipsoid(&"fur", Vector3(0, 8.0, 0), Vector3(7.0, 8.0, 6.0))
	k._ellipsoid(&"fur_light", Vector3(0, 7.0, 4.6), Vector3(4.6, 5.0, 2.0), Basis(), false)
	k._ellipsoid(&"fur", Vector3(0, 19.5, 0.5), Vector3(5.6, 5.0, 5.0))
	k._ellipsoid(&"fur_light", Vector3(0, 18.4, 4.6), Vector3(2.4, 1.8, 1.6), Basis(), false)
	k._ellipsoid(&"button_eye", Vector3(0, 19.2, 6.0), Vector3(0.8, 0.6, 0.5), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"fur", Vector3(xs * 4.2, 24.0, 0.0), Vector3(2.0, 2.0, 1.0), Basis(), false)
		k._ellipsoid(&"fur_light", Vector3(xs * 4.2, 24.0, 0.6), Vector3(1.2, 1.2, 0.6), Basis(), false)
		k._ellipsoid(&"button_eye", Vector3(xs * 2.0, 20.8, 4.6), Vector3(0.7, 0.7, 0.5), Basis(), false)
		k._ellipsoid(&"fur", Vector3(xs * 7.5, 10.0, 2.0), Vector3(2.2, 5.0, 2.2), Basis(Vector3.FORWARD, xs * 0.5))
		k._ellipsoid(&"fur", Vector3(xs * 4.0, 2.4, 6.0), Vector3(2.8, 2.4, 5.0))
		k._ellipsoid(&"fur_light", Vector3(xs * 4.0, 2.4, 10.6), Vector3(2.0, 2.0, 0.6), Basis(), false)
	k._prism(&"paint_red", [Vector2(-3.0, 15.6), Vector2(0.0, 14.6), Vector2(3.0, 15.6), Vector2(3.0, 13.2), Vector2(0.0, 14.2), Vector2(-3.0, 13.2)], 5.4, 0.8)
	k.footprint = 12.5   # (arms and feet reach out past the tummy)
	return k.dress(env("toy_teddy"), Transform3D(), {}, true).finish()


## A crayon lying on the floor (or standing in its box).
static func crayon(rng: RandomNumberGenerator, length := 16.0, standing := false) -> CageKit:
	var k := CageKit.blank("Crayon", rng, &"wood")
	var col := _c(rng)
	var r := 1.3
	# the model: upright, base at its origin, 16 m (scaled), 0.62 m thick at that size
	var s := length / 16.0
	var lie := Basis() if standing else Basis(Vector3.BACK, -PI * 0.5)
	var foot := Vector3.ZERO if standing else Vector3(-length * 0.5, 0.62 * s, 0)
	k.dress(env("toy_crayon_" + String(CRAYON_MODEL[col])), Transform3D(lie * Basis.from_scale(Vector3.ONE * s), foot))
	# lying: along local X, centred on the origin (so its spacing is known)
	var dir := Vector3.UP if standing else Vector3.RIGHT
	var base := Vector3.ZERO if standing else Vector3.UP * r - dir * length * 0.5
	k._rod(StringName("crayon_" + String(col)), base, base + dir * length * 0.8, r)
	k._rod(&"paper", base + dir * length * 0.15, base + dir * length * 0.65, r + 0.08, false)
	k._rod(StringName("crayon_" + String(col)), base + dir * length * 0.3, base + dir * length * 0.5, r + 0.12, false)
	k._cone(StringName("crayon_" + String(col)), base + dir * length * 0.8, base + dir * length, r)
	k.set_meta(&"crayon", col)
	return k.finish()


## The crayon box tipped on its side, crayons spilling out of the open end.
static func crayon_box(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("CrayonBox", rng, &"wood")
	var w := 22.0
	var h := 9.0
	var d := 14.0
	k._box(&"paint_yellow", Vector3(0, 0.2, 0), Vector3(w, 0.4, d))
	k._box(&"paint_yellow", Vector3(0, h, 0), Vector3(w, 0.4, d))
	k._box(&"paint_lime", Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.4))
	for xs in [-1.0, 1.0]:
		k._box(&"paint_yellow", Vector3(xs * w * 0.5, h * 0.5, 0), Vector3(0.4, h, d))
	k._box(&"paint_red", Vector3(0, h * 0.5, -d * 0.5 - 0.25), Vector3(w * 0.7, h * 0.5, 0.1), Basis(), false)
	k.footprint = 13.0
	k.floor_y = 0.4
	k.loot_spots = [Vector3(-5.0, 0.4, -2.0), Vector3(5.0, 0.4, 1.0)]
	return k.made_as("toy/crayon_box").finish()


## A coloring book standing open like a tent: walk through underneath.
static func coloring_book(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("ColoringBook", rng, &"wood")
	var length := 26.0
	var slant := 0.55              # each cover's lean from upright
	var board := 16.0
	for xs in [-1.0, 1.0]:
		var b := Basis(Vector3.BACK, xs * slant)
		var c := Vector3(xs * sin(slant) * board * 0.5, cos(slant) * board * 0.5, 0)
		k._box(k.accent("accent%d" % int(xs > 0.0), StringName("paint_" + String(_c(rng)))), c, Vector3(0.6, board, length), b)
		k._box(&"paper", c + b * Vector3(xs * 0.4, 0, 0), Vector3(0.3, board - 1.0, length - 1.2), b, false)
		for i in 4:
			k._box(StringName("crayon_" + String(_c(rng))), c + b * Vector3(xs * 0.56, rng.randf_range(-4, 4), rng.randf_range(-9, 9)),
				Vector3(0.05, rng.randf_range(1.0, 4.0), rng.randf_range(2.0, 6.0)), b * Basis(Vector3.RIGHT, rng.randf() * 3.0), false)
	k._rod(&"paint_red", Vector3(0, cos(slant) * board, -length * 0.5), Vector3(0, cos(slant) * board, length * 0.5), 0.6, false)
	k.footprint = 15.0
	return k.made_as("toy/coloring_book").finish()


## A tea party: a round table set with cups, saucers and a teapot.
static func tea_table(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("TeaTable", rng, &"wood")
	var top := 9.0
	k._lathe(&"ceramic_white", [Vector2(0.0, top - 0.8), Vector2(13.0, top - 0.8), Vector2(13.0, top), Vector2(0.0, top)], 32, Vector3.ZERO)
	k._rod(&"ceramic_white", Vector3.ZERO, Vector3(0, top, 0), 1.6)
	k._lathe(&"ceramic_white", [Vector2(0.0, 0.0), Vector2(6.0, 0.0), Vector2(6.0, 0.6), Vector2(0.0, 0.6)], 24, Vector3.ZERO)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var at := Vector3(cos(a) * 8.5, top, sin(a) * 8.5)
		k._lathe(&"ceramic_pink", [Vector2(2.6, 0.0), Vector2(2.6, 0.2), Vector2(0.0, 0.2)], 16, at, false)
		k._lathe(&"ceramic_pink", [Vector2(1.1, 0.2), Vector2(1.8, 2.4), Vector2(1.6, 2.4), Vector2(1.0, 0.5)], 16, at, false)
	k._ellipsoid(&"ceramic_sky", Vector3(0, top + 3.2, 0), Vector3(3.6, 3.0, 3.6), Basis(), false)
	k._rod(&"ceramic_sky", Vector3(3.0, top + 3.0, 0), Vector3(6.0, top + 5.5, 0), 0.6, false)
	k.footprint = 14.0
	return k.made_as("toy/tea_table").finish()


## A giant teacup on the floor (cover), with its saucer and handle.
static func teacup(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Teacup", rng, &"wood")
	var col := StringName("ceramic_" + String([&"pink", &"sky", &"mint", &"lilac"][rng.randi() % 4]))
	k._lathe(&"ceramic_white", [Vector2(8.0, 0.0), Vector2(8.0, 0.6), Vector2(0.0, 0.6)], 28, Vector3.ZERO)
	k._lathe(col, [Vector2(3.5, 0.6), Vector2(6.0, 4.0), Vector2(6.8, 7.0), Vector2(6.4, 7.0), Vector2(5.6, 4.2), Vector2(3.4, 1.2), Vector2(0.0, 1.2)], 28, Vector3.ZERO)
	for i in 5:
		var a0 := -0.5 + i * 0.25
		var a1 := a0 + 0.25
		k._rod(col, Vector3(6.5 + sin(a0 * PI) * 2.2, 4.0 + cos(a0 * PI) * 2.0, 0), Vector3(6.5 + sin(a1 * PI) * 2.2, 4.0 + cos(a1 * PI) * 2.0, 0), 0.5, false)
	k.footprint = 8.5
	return k.dress(env("toy_teacup"), Transform3D(), {}, true).finish()


## A domino standing on end (or toppled), black with white pips.
static func domino(rng: RandomNumberGenerator, toppled := false) -> CageKit:
	var k := CageKit.blank("Domino", rng, &"wood")
	var b := Basis(Vector3.RIGHT, PI * 0.5 - 0.05) if toppled else Basis()
	var c := Vector3(0, 0.7, 0) if toppled else Vector3(0, 4.0, 0)
	k._box(&"domino", c, Vector3(4.2, 8.0, 1.4), b)
	k._box(&"plastic_white", c + b * Vector3(0, 0, 0.71), Vector3(3.4, 0.15, 0.05), b, false)
	var pips := _domino_pips(rng)
	for half in 2:
		for at: Vector3 in pips[half][1]:
			k._ellipsoid(&"plastic_white", c + b * at, Vector3(0.38, 0.38, 0.06), b, false, 4, 8)
	# the model: pips laid out like a real domino's, the same counts (top, bottom)
	return k.dress(made("toy/domino_%d%d" % [pips[1][0], pips[0][0]]), Transform3D(b, c - b * Vector3(0, 4.0, 0))).finish()


## A domino standing on its end that a carrot can tip over, and that knocks
## the next one over as it goes (ToyBlock): its middle at its origin, 8 m tall.
static func standing_domino(rng: RandomNumberGenerator) -> ToyBlock:
	var d := ToyBlock.new(Vector3(4.2, 8.0, 1.4))
	d.name = "Domino"
	d.tips = true
	var pips := _domino_pips(rng)
	var m := CageKit.model(made("toy/domino_%d%d" % [pips[1][0], pips[0][0]]))
	if m == null:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = d.size
		mi.mesh = box
		mi.material_override = CageKit.mat(&"domino")
		m = mi
	else:
		m.position = Vector3.DOWN * 4.0
	d.dress(m)
	return d


## A domino's two halves (bottom, top): how many pips each, and where each
## sits on its face (the random draws in the order the dominoes always made them).
static func _domino_pips(rng: RandomNumberGenerator) -> Array:
	var out := []
	for half in [-1.0, 1.0]:
		var n := rng.randi_range(1, 4)
		var at := []
		for i in n:
			at.append(Vector3(rng.randf_range(-1.3, 1.3), half * rng.randf_range(1.0, 3.0), 0.72))
		out.append([n, at])
	return out


## The toy chest: a painted wooden box with its lid flung open.
static func toy_chest(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("ToyChest", rng, &"wood")
	var w := 30.0
	var d := 16.0
	var h := 14.0
	k._box(&"paint_blue", Vector3(0, 0.5, 0), Vector3(w, 1.0, d))
	k._box(&"paint_blue", Vector3(0, h * 0.5, d * 0.5), Vector3(w, h, 1.0))
	k._box(&"paint_blue", Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 1.0))
	for xs in [-1.0, 1.0]:
		k._box(&"paint_blue", Vector3(xs * w * 0.5, h * 0.5, 0), Vector3(1.0, h, d))
	for xs in [-1.0, 0.0, 1.0]:
		k._box(&"paint_yellow", Vector3(xs * 9.0, h * 0.5, d * 0.5 + 0.55), Vector3(7.0, h * 0.6, 0.15), Basis(), false)
	var lid := Basis(Vector3.RIGHT, -1.9)
	k._box(&"paint_red", Vector3(0, h, -d * 0.5) + lid * Vector3(0, 0.5, d * 0.5), Vector3(w + 1.0, 1.0, d), lid)
	# toys inside poking out
	k._ellipsoid(&"plastic_red", Vector3(-8.0, h - 1.0, 0), Vector3.ONE * 4.0)
	k._ellipsoid(&"plastic_yellow", Vector3(6.0, h - 2.0, 2.0), Vector3.ONE * 3.2)
	k._rod(&"paint_purple", Vector3(1.0, h - 3.0, -2.0), Vector3(2.0, h + 6.0, -1.0), 1.0, false)
	k.footprint = 18.0
	return k.made_as("toy/toy_chest").finish()


## A bouncy ball (cover).
static func ball(rng: RandomNumberGenerator, r := 3.5) -> CageKit:
	var k := CageKit.blank("Ball", rng, &"wood")
	var col := StringName("plastic_" + String(_c(rng)))
	var spin := Basis(Vector3.UP, rng.randf() * TAU)
	k._ellipsoid(col, Vector3(0, r * 0.95, 0), Vector3.ONE * r, spin, true, 10, 18)
	k._lathe(&"plastic_white", [Vector2(r + 0.02, r * 0.85), Vector2(r + 0.02, r * 1.05)], 24, Vector3.ZERO, false)
	return k.dress(made("toy/ball"), Transform3D(spin * Basis.from_scale(Vector3.ONE * r), Vector3.ZERO), {"accent": col}).finish()


## The piggy bank, with coins round it.
static func piggy_bank(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("PiggyBank", rng, &"wood")
	k._ellipsoid(&"ceramic_pink", Vector3(0, 9.0, 0), Vector3(8.0, 7.0, 11.0))
	k._rod(&"ceramic_pink", Vector3(0, 9.0, 10.0), Vector3(0, 9.0, 12.6), 3.0)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"button_eye", Vector3(xs * 1.0, 9.0, 12.65), Vector3(0.5, 0.8, 0.1), Basis(), false)
		k._ellipsoid(&"button_eye", Vector3(xs * 3.0, 12.0, 9.4), Vector3(0.7, 0.7, 0.4), Basis(), false)
		k._cone(&"ceramic_pink", Vector3(xs * 4.0, 14.5, 5.0), Vector3(xs * 5.0, 18.0, 5.5), 2.0)
		for zs in [-1.0, 1.0]:
			k._rod(&"ceramic_pink", Vector3(xs * 4.0, 0.0, zs * 6.0), Vector3(xs * 4.0, 4.0, zs * 6.0), 1.6)
	k._box(&"domino", Vector3(0, 15.9, -1.0), Vector3(0.6, 0.3, 4.0), Basis(), false)
	for i in 8:
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * rng.randf_range(12.0, 18.0)
		k._lathe(&"coin", [Vector2(0.0, 0.0), Vector2(2.2, 0.0), Vector2(2.2, 0.5), Vector2(0.0, 0.5)], 18, at, false)
	k.footprint = 12.0
	k.keep_surfaces([&"coin"])   # (the coins round it stay)
	return k.dress(env("toy_piggy"), Transform3D(), {}, true).finish()


## A toy rocket on its launch pad: the tallest toy in the room.
static func rocket(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Rocket", rng, &"wood")
	k._lathe(&"plastic_white", [Vector2(10.0, 0.0), Vector2(10.0, 1.0), Vector2(0.0, 1.0)], 24, Vector3.ZERO)
	k._rod(&"plastic_white", Vector3(0, 1.0, 0), Vector3(0, 30.0, 0), 4.5)
	k._rod(&"plastic_red", Vector3(0, 12.0, 0), Vector3(0, 15.0, 0), 4.6, false)
	k._cone(&"plastic_red", Vector3(0, 30.0, 0), Vector3(0, 41.0, 0), 4.5)
	k._ellipsoid(&"plastic_blue", Vector3(0, 22.0, 4.2), Vector3(1.8, 1.8, 0.6), Basis(), false)
	for i in 3:
		var a := TAU * i / 3.0
		var dir := Vector3(cos(a), 0, sin(a))
		k._box(&"plastic_red", dir * 6.0 + Vector3.UP * 4.5, Vector3(4.0, 7.0, 0.8), Basis(Vector3.UP, -a + PI * 0.5))
	k.footprint = 12.0
	k.dress(made("toy/launch_pad"), Transform3D(), {}, true)
	return k.dress(env("toy_rocket"), Transform3D(Basis(), Vector3.UP * 1.0), {}, true).finish()


## A toy race car (cover).
static func race_car(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("RaceCar", rng, &"wood")
	var col := StringName("plastic_" + String(_c(rng)))
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	k._box(col, b * Vector3(0, 1.8, 0), Vector3(4.6, 1.8, 9.0), b)
	k._box(&"bottle_glass", b * Vector3(0, 3.2, -0.6), Vector3(3.8, 1.2, 3.6), b)
	k._box(&"plastic_white", b * Vector3(0, 2.75, 2.5), Vector3(0.6, 0.05, 3.0), b, false)
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			var at := b * Vector3(xs * 2.5, 1.1, zs * 3.0)
			k._rod(&"plastic_black", at - b.x * 0.6, at + b.x * 0.6, 1.1)
	return k.dress(env("toy_racecar"), Transform3D(b, Vector3.ZERO), {}, true).finish()


## The orange race track: a long jump ramp and a loop-the-loop (decoration).
static func race_track(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("RaceTrack", rng, &"wood")
	k._ramp(&"track", Vector3(0, -0.1, 22.0), Vector3(0, 5.0, 4.0), 7.0)
	for i in 3:
		k._rod(&"plastic_white", Vector3(-2.8, 0, 6.0 + i * 5.0), Vector3(-2.8, 4.6 - i * 1.6, 6.0 + i * 5.0), 0.35, false)
		k._rod(&"plastic_white", Vector3(2.8, 0, 6.0 + i * 5.0), Vector3(2.8, 4.6 - i * 1.6, 6.0 + i * 5.0), 0.35, false)
	# the loop, standing on its own a little way off (just to look at)
	k._ring(&"track", Vector3(0, 10.5, -22.0), Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP), 10.0, 7.0, 0.4, 28, [], false)
	k._box(&"track", Vector3(0, 0.05, -2.0), Vector3(7.0, 0.1, 30.0), Basis(), false)
	k.footprint = 14.0
	return k.made_as("toy/race_track").finish()


## The fishbowl: a huge glass bowl of water on the floor, gravel and plants
## in the bottom and a slide up to its rim (swim in; climb out over the rim).
static func fishbowl(rng: RandomNumberGenerator, rim_y: float) -> CageKit:
	var k := CageKit.blank("Fishbowl", rng, &"rock")
	var prof := [Vector2(14.0, 0.0), Vector2(24.0, 4.0), Vector2(30.0, 12.0), Vector2(28.5, 20.0), Vector2(22.0, rim_y)]
	k._lathe(&"bowl_glass", prof, 40, Vector3.ZERO)
	var inner := []
	for i in range(prof.size() - 1, -1, -1):
		var p: Vector2 = prof[i]
		inner.append(Vector2(p.x - 0.8, p.y if i < prof.size() - 1 else rim_y))
	k._lathe(&"bowl_glass", inner + [Vector2(0.0, 0.8)], 40, Vector3.ZERO)
	k._lathe(&"plastic_white", [Vector2(22.0, rim_y), Vector2(22.0, rim_y + 0.5), Vector2(21.0, rim_y + 0.5), Vector2(21.0, rim_y)], 40, Vector3.ZERO)
	# gravel in the bottom
	k._lathe(&"pebble_mix", [Vector2(14.0, 0.8), Vector2(13.6, 1.3), Vector2(0.0, 1.6)], 32, Vector3.ZERO, false)
	# the slide: a ramp from the floor up to the rim, with rails
	var bottom := Vector3(0, -0.1, 22.0 + rim_y / tan(deg_to_rad(28.0)))
	var top := Vector3(0, rim_y, 21.3)
	k._ramp(&"plastic_yellow", bottom, top, 6.0)
	for xs in [-1.0, 1.0]:
		k._box(&"plastic_red", (bottom + top) * 0.5 + Vector3(xs * 3.3, 1.0, 0), Vector3(0.5, 1.6, bottom.distance_to(top)),
			Basis(Vector3.RIGHT, atan2(top.y - bottom.y, bottom.z - top.z)), false)
	k.footprint = 32.0
	if is_equal_approx(rim_y, ToyBox.BOWL_RIM):
		k.made_as("toy/fishbowl")
	return k.finish()


## The paper airplane that carries everyone in (see Dropship): a white folded
## dart with crayon doodles on its wings.
static func paper_plane(rng: RandomNumberGenerator) -> Node3D:
	var k := CageKit.blank("PaperPlane", rng, &"wood")
	k.collision_layer = 0
	var nose := Vector3(0, 0, -22.0)
	for xs in [-1.0, 1.0]:
		var st := k._st(&"paper")
		var tail_in := Vector3(0, 0.6, 18.0)
		var tail_out := Vector3(xs * 17.0, 2.4, 18.0)
		k._face(st, [nose, tail_out, tail_in], [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)], Vector3.UP, false)
		k._face(st, [nose, tail_out, tail_in], [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)], Vector3.DOWN, false)
		var keel := Vector3(0, -4.5, 16.0)
		k._face(st, [nose, keel, tail_in], [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)], Vector3(xs, 0, 0), false)
		for i in 3:
			var along := lerpf(-4.0, 14.0, i / 2.0)
			var col := StringName("crayon_" + String(_c(rng)))
			k._box(col, Vector3(xs * (4.0 + i * 2.5), 1.0 + i * 0.35, along), Vector3(2.5, 0.05, 0.8), Basis(Vector3.UP, xs * 0.4), false)
	return k.dress(env("toy_paper_plane"), Transform3D(Basis(), Vector3(0, -3.0, -2.0)), {"material_0": "paper"}).finish()


## One loose alphabet block (cover), sometimes with a second stacked on it.
static func letter_block(rng: RandomNumberGenerator, size := 4.0) -> CageKit:
	var k := CageKit.blank("LetterBlock", rng)
	var cells := func() -> Array: return [rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16, rng.randi() % 16]
	# each block is one of the lettered block models, picked by the letters drawn
	var block := func(at: Vector3, basis: Basis, c: Array) -> void:
		k._letter_box(at, size, basis, c)
		var v: int = (c[0] + c[1] + c[2]) % LETTER_VARIANTS
		k.dress(made("toy/letter_block_%d" % v), Transform3D(basis * Basis.from_scale(Vector3.ONE * size), at - Vector3.UP * size * 0.5))
	block.call(Vector3(0, size * 0.5, 0), Basis(Vector3.UP, rng.randf() * TAU), cells.call())
	if rng.randf() < 0.3:
		var at := Vector3(rng.randf_range(-0.6, 0.6), size * 1.5, rng.randf_range(-0.6, 0.6))
		block.call(at, Basis(Vector3.UP, rng.randf() * TAU), cells.call())
	return k.finish()


## A plump plaid pillow lying on the floor (cover in the pillow corner).
static func pillow(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Pillow", rng)
	var key := StringName("pillow_" + String(_c(rng)))
	var rx := rng.randf_range(5.0, 7.0)
	var rz := rng.randf_range(3.6, 4.6)
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	k._ellipsoid(key, Vector3(0, 2.3, 0), Vector3(rx, 2.4, rz), b, true, 6, 14)
	return k.dress(made("toy/pillow"), Transform3D(b * Basis.from_scale(Vector3(rx / 6.0, 1.0, rz / 4.1)), Vector3.DOWN * 0.1), {"accent": key}).finish()


# ---- the floor's hills and cover (the floor itself stays flat) ----------------------------------

const SOCK_COLOURS := [&"red", &"blue", &"yellow", &"lime", &"purple", &"orange", &"teal", &"pink", &"white", &"grey", &"navy", &"white"]
const PLUSH_KINDS := ["whale", "shark", "octopus", "elephant", "sheep", "seal"]
## The sock models a heap is made of (assets/env/<id>), how often each turns
## up, how often it's dyed (the white tube sock and the knitted one come in
## every bright colour, the striped one sometimes) and how much a dye lifts
## it (the knitted one is a dark wool underneath).
const SOCK_MODELS := ["toy_sock_striped", "toy_sock_dots", "toy_sock_knit", "toy_sock_tube"]
const SOCK_SHARE := [0.12, 0.06, 0.36, 0.46]
const SOCK_DYED := [0.35, 0.0, 1.0, 1.0]
const SOCK_LIFT := [1.0, 1.0, 2.1, 1.0]
const SOCK_DYES := [&"red", &"blue", &"yellow", &"lime", &"purple", &"orange", &"teal", &"pink", &"white", &"sky"]
const UNIT := 2.0                    ## a wooden unit block's thickness (its width 2x, its length 4x)


static func _sock_key(rng: RandomNumberGenerator) -> StringName:
	return StringName("sock_" + String(SOCK_COLOURS[rng.randi() % SOCK_COLOURS.size()]))


## A soft dome's profile for CageKit._lathe, rim to top: y = h (1 + cos(pi d/r)) / 2,
## never steeper than atan(h pi / 2r).
static func _dome_profile(r: float, h: float, steps := 12) -> Array:
	var prof := []
	for i in steps + 1:
		var t := float(i) / steps
		prof.append(Vector2(r * (1.0 - t), h * (0.5 - 0.5 * cos(PI * t))))
	return prof


## [the dome's surface point over (x, z), and a basis whose Y is its normal,
## turned `yaw` about it].
static func _on_dome(r: float, h: float, x: float, z: float, yaw: float) -> Array:
	var d := minf(Vector2(x, z).length(), r)
	var slope := -h * 0.5 * PI / r * sin(PI * d / r)
	var radial := Vector2(x, z).normalized() if d > 0.01 else Vector2.ZERO
	var n := Vector3(-slope * radial.x, 1.0, -slope * radial.y).normalized()
	return [Vector3(x, h * (0.5 + 0.5 * cos(PI * d / r)), z), Basis(IKMath.from_to(Vector3.UP, n)) * Basis(Vector3.UP, yaw)]


## A sock lying flat in `b`'s XZ plane (b.y up off what it lies on): the leg
## from the cuff to the heel at `at`, the foot turning off to the toe, a
## band at the cuff and sometimes stripes.
static func _sock(k: CageKit, at: Vector3, b: Basis, rng: RandomNumberGenerator) -> void:
	var cloth := _sock_key(rng)
	var trim := _sock_key(rng)
	var r := rng.randf_range(0.55, 0.7)
	var foot := Vector3(cos(1.25), 0, -sin(1.25)) if rng.randf() < 0.5 else Vector3(cos(1.25), 0, sin(1.25))
	var lift := b.y * r * 0.75
	var heel := at + lift
	var cuff := heel - b.x * rng.randf_range(3.4, 4.4)
	var toe := heel + b * foot * rng.randf_range(2.6, 3.3)
	k._rod(cloth, cuff, heel, r, false)
	k._rod(cloth, heel, toe, r, false)
	k._ellipsoid(cloth, heel, Vector3.ONE * r * 1.05, b, false, 4, 8)
	k._ellipsoid(trim if rng.randf() < 0.5 else cloth, toe, Vector3(r * 1.3, r, r), b * Basis(Vector3.UP, -atan2(foot.z, foot.x)), false, 4, 8)
	k._rod(trim, cuff, cuff + b.x * 0.5, r + 0.07, false)
	if rng.randf() < 0.5:
		for i in 2:
			var s := cuff.lerp(heel, 0.35 + i * 0.25)
			k._rod(trim, s, s + b.x * 0.3, r + 0.04, false)


## A heap of socks tipped out of the laundry basket: a soft hill to run up
## (its collider a smooth dome, never steeper than about 33 degrees, so the
## bots climb it too; all you see of it is socks), the sock models heaped two
## deep over it, odd socks round its foot. Its loot spot is on top.
static func sock_hill(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("SockHill", rng, &"cloth")
	var r := rng.randf_range(16.0, 20.0)
	var h := r * rng.randf_range(0.36, 0.4)
	k._lathe(&"", _dome_profile(r, h), 24, Vector3.ZERO, true)   # (the collider alone)
	var socks := {}   # model id -> [[Transform3D, Color], ...]
	# two layers spread evenly over the dome (sunflower spirals): the lower
	# sunk most of the way in, filling the upper's gaps
	for layer in 2:
		var n := int(r * r * (0.3 if layer == 0 else 0.42))
		for i in n:
			var d := r * 0.97 * sqrt((i + 0.5) / n)
			var a := i * 2.39996 + layer * 1.3 + rng.randf_range(-0.2, 0.2)
			var s: Array = _on_dome(r, h, cos(a) * d, sin(a) * d, rng.randf() * TAU)
			var b: Basis = (s[1] as Basis) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
			_heap_sock(socks, rng, b, s[0], 1.0 if layer == 0 else 0.55)
	# odd socks round its foot
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		_heap_sock(socks, rng, Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a), 0, sin(a)) * (r + rng.randf_range(0.5, 3.0)), 0.0)
	for id in socks:
		var mesh := _sock_mesh(id)
		var list: Array = socks[id]
		if mesh == null:
			for e in list:   # (no model: the code-built socks)
				_sock(k, (e[0] as Transform3D).origin, (e[0] as Transform3D).basis.orthonormalized(), rng)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Socks_" + id.trim_prefix("toy_sock_")
		mmi.multimesh = mm
		k.add_child(mmi)
	k.footprint = r + 2.5
	k.loot_spots = [Vector3(0, h, 0)]
	return k.finish()


## One more sock for a heap (see sock_hill): a sock model, lying in `b`'s XZ
## plane at `at`, sunk `sink` of its thickness in; dyed if it's a plain one.
static func _heap_sock(socks: Dictionary, rng: RandomNumberGenerator, b: Basis, at: Vector3, sink: float) -> void:
	var m := 0
	var pick := rng.randf()
	while m < SOCK_MODELS.size() - 1 and pick > SOCK_SHARE[m]:
		pick -= SOCK_SHARE[m]
		m += 1
	var id: String = SOCK_MODELS[m]
	var mesh := _sock_mesh(id)
	var thick := mesh.get_aabb().size.y if mesh else 1.2
	var sc := rng.randf_range(0.85, 1.15)
	var col := Color.WHITE.darkened(rng.randf() * 0.12)
	if rng.randf() < SOCK_DYED[m]:
		col = CageKit._cloth(String(SOCK_DYES[rng.randi() % SOCK_DYES.size()])).lerp(Color.WHITE, 0.08) * SOCK_LIFT[m]
		col.a = 1.0
	if not socks.has(id):
		socks[id] = []
	(socks[id] as Array).append([Transform3D(b * Basis.from_scale(Vector3.ONE * sc), at - b.y * thick * sc * sink), col])


static var _sock_meshes: Dictionary = {}


## A sock model's mesh, its materials taking each sock's colour from the
## MultiMesh (null without the model).
static func _sock_mesh(id: String) -> Mesh:
	if _sock_meshes.has(id):
		return _sock_meshes[id]
	var mesh: Mesh = null
	if ResourceLoader.exists(env(id)):
		var src := ModelUtil.first_mesh(env(id))
		if src:
			mesh = src.duplicate()
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				if m:
					m = m.duplicate() as BaseMaterial3D
					m.vertex_color_use_as_albedo = true
					mesh.surface_set_material(i, m)
	_sock_meshes[id] = mesh
	return mesh


## A wooden unit-block fort (the plain maple blocks every nursery has, a few
## painted): a platform two blocks high with ramp blocks up two sides, a
## tower on its back corner with another ramp and a parapet of cubes, pillar
## blocks, an arch gate in front, and tumbled blocks round about. Loot on
## the platform and the tower.
static func block_fort(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("BlockFort", rng, &"wood")
	var u := UNIT
	var paint := func() -> StringName: return StringName("paint_" + String([&"red", &"blue", &"yellow", &"lime"][rng.randi() % 4]))
	var half := u * 4.0           # the platform: 16 m square, 4 m high
	# two courses of long blocks, crossing
	for i in 4:
		var z := -half + u + i * u * 2.0
		k._box(&"maple", Vector3(0, u * 0.5, z), Vector3(half * 2.0, u, u * 2.0))
		var x := -half + u + i * u * 2.0
		k._box(&"maple", Vector3(x, u * 1.5, 0), Vector3(u * 2.0, u, half * 2.0))
	# ramp blocks: up the +X side and the +Z side
	var ramp_a: StringName = paint.call()
	k._prism(ramp_a, [Vector2(half, 0.0), Vector2(half + u * 4.0, 0.0), Vector2(half, u * 2.0)], u * 1.5, u * 2.0)
	k._prism(paint.call(), [Vector2(half, 0.0), Vector2(half + u * 4.0, 0.0), Vector2(half, u * 2.0)], -u * 1.5, u * 2.0, true)
	# the tower on the back corner (-X, -Z): two more courses, a ramp up from the platform
	var top := u * 4.0
	for i in 2:
		var z := -half + u + i * u * 2.0
		k._box(&"maple", Vector3(-half * 0.5, u * 2.5, z), Vector3(half, u, u * 2.0))
		var x := -half + u + i * u * 2.0
		k._box(&"maple", Vector3(x, u * 3.5, -half * 0.5), Vector3(u * 2.0, u, half))
	k._prism(paint.call(), [Vector2(u * 4.0, u * 2.0), Vector2(0.0, u * 2.0), Vector2(0.0, top)], -half + u, u * 2.0, true)
	# a parapet of cubes along the tower's outer edges, with gaps to shoot through
	for c in [Vector2(-half + u * 0.5, -half + u * 0.5), Vector2(-half + u * 0.5, -half + u * 2.5), Vector2(-half + u * 2.5, -half + u * 0.5)]:
		k._box(paint.call(), Vector3(c.x, top + u * 0.5, c.y), Vector3.ONE * u)
	# pillar blocks on the platform's +X corners, a long block across them
	for zs in [-1.0, 1.0]:
		var c := Vector3(half - u * 0.5, u * 2.0, zs * (half - u * 0.5))
		k._rod(&"maple", c, c + Vector3.UP * u * 4.0, u * 0.5)
	k._box(&"maple", Vector3(half - u * 0.5, u * 6.0 + u * 0.25, 0), Vector3(u, u * 0.5, half * 2.0 + u))
	# the arch gate out in front (-X): two legs and an arch block, a bunny's height under it
	var gate := Vector3(-half - u * 6.0, 0, half * 0.25)
	for zs in [-1.0, 1.0]:
		k._box(&"maple", gate + Vector3(0, u, zs * u * 1.5), Vector3(u * 2.0, u * 2.0, u))
	k._box(&"maple", gate + Vector3(0, u * 2.0 + u * 0.4, 0), Vector3(u * 2.0, u * 0.8, u * 4.0))
	for i in 6:
		var a0 := PI * i / 6.0
		var a1 := PI * (i + 1) / 6.0
		var rr := u * 1.0
		var p0 := gate + Vector3(0, u * 2.0 - 0.02 - rr * (1.0 - sin(a0)) * 0.6, cos(a0) * rr)
		var p1 := gate + Vector3(0, u * 2.0 - 0.02 - rr * (1.0 - sin(a1)) * 0.6, cos(a1) * rr)
		k._box(&"maple", (p0 + p1) * 0.5 + Vector3.DOWN * 0.15, Vector3(u * 2.0, 0.3, p0.distance_to(p1) + 0.1),
			Basis(Vector3.RIGHT, atan2(p1.y - p0.y, p1.z - p0.z)), false)
	# tumbled blocks lying round about
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var d := rng.randf_range(half + u * 5.0, half + u * 7.5)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		if at.distance_to(gate) < u * 5.0:
			continue
		var long := rng.randf() < 0.6
		var size := Vector3(u * (4.0 if long else 2.0), u, u * 2.0)
		var mat: StringName = &"maple" if rng.randf() < 0.65 else paint.call()
		if rng.randf() < 0.35:
			size = Vector3(size.x, size.z, size.y)   # (stood on its long edge)
		k._box(mat, at + Vector3.UP * size.y * 0.5, size, Basis(Vector3.UP, rng.randf() * TAU))
	k.footprint = half + u * 8.0
	k.floor_y = u * 2.0
	k.loot_spots = [Vector3(half * 0.5, u * 2.0, half * 0.4), Vector3(-half * 0.5, top, -half * 0.5)]
	return k.finish()


## A Lincoln Log cabin: notched redwood logs (each wall's courses half a
## log above or below the next wall's, so they cross at the corners), a
## doorway and windows, gable ends and a green slatted roof; a pile of
## spare logs and a few loose roof slats beside it. Walk in for its loot.
static func log_cabin(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("LogCabin", rng, &"wood")
	var w := rng.randf_range(13.0, 15.0)
	var d := rng.randf_range(10.0, 11.5)
	var r := 0.75
	var wall_h := r * 2.0 * 4.0 + r
	var door := [0.0, 3.6, 0.0, 4.6]
	var window := [0.0, 2.6, 2.0, 4.4]
	k._log_wall(Vector3(-w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, d * 0.5), wall_h, r, [door], 0.0, &"lincoln")
	k._log_wall(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5), wall_h, r, [window], 0.0, &"lincoln")
	for xs in [-1.0, 1.0]:
		k._log_wall(Vector3(xs * w * 0.5, 0, -d * 0.5), Vector3(xs * w * 0.5, 0, d * 0.5), wall_h, r, [window], r, &"lincoln")
	# gable ends of shorter and shorter logs, and the green slat roof (ridge along X)
	var eave := wall_h + r * 0.5
	var ridge := eave + d * 0.32
	for xs in [-1.0, 1.0]:
		k._gable_end(&"lincoln", d, eave - 0.2, ridge - 0.2, xs * w * 0.5, r * 1.6)
	for zs in [-1.0, 1.0]:
		for i in 5:
			var t0 := float(i) / 5.0
			var t1 := float(i + 1) / 5.0
			var p0 := Vector3(0, lerpf(eave - 0.4, ridge, t0), zs * lerpf(d * 0.5 + 1.2, 0.0, t0))
			var p1 := Vector3(0, lerpf(eave - 0.4, ridge, t1), zs * lerpf(d * 0.5 + 1.2, 0.0, t1))
			var ang := atan2(p1.y - p0.y, absf(p1.z - p0.z))
			k._box(&"lincoln_green", (p0 + p1) * 0.5 + Vector3.UP * 0.2, Vector3(w + 2.6, 0.32, p0.distance_to(p1) + 0.12),
				Basis(Vector3.RIGHT, zs * ang))
	# a pile of spare logs (three, two, one) and loose roof slats
	var pile := Vector3(w * 0.5 + 4.2, 0, rng.randf_range(-1.0, 1.0))
	var length := rng.randf_range(7.0, 9.0)
	for row in 3:
		for i in 3 - row:
			var x := (i - (2 - row) * 0.5) * r * 2.05
			var y := r + row * r * 1.75
			k._log(&"lincoln", pile + Vector3(x, y, -length * 0.5), pile + Vector3(x, y, length * 0.5), r)
	for i in rng.randi_range(2, 3):
		var at := Vector3(rng.randf_range(-w * 0.5, w * 0.5), 0.16, -d * 0.5 - rng.randf_range(3.0, 5.0))
		k._box(&"lincoln_green", at, Vector3(rng.randf_range(4.0, 6.0), 0.32, 1.4), Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), false)
	k.footprint = w * 0.5 + 7.0
	k.floor_y = 0.0
	k.loot_spots = [Vector3(-w * 0.25, 0, -d * 0.2), Vector3(w * 0.25, 0, 0.0)]
	return k.finish()


## A big, well-loved stuffed animal flopped on the floor (soft cover), one
## of the plush models (assets/env/toy_plush_<kind>): "whale", "shark",
## "octopus", "elephant", "sheep" or "seal". It collides as its model's
## convex hull (without the model, it's a plush lump its size).
static func plush(rng: RandomNumberGenerator, kind := "") -> CageKit:
	if kind == "":
		kind = PLUSH_KINDS[rng.randi() % PLUSH_KINDS.size()]
	var k := CageKit.blank("Plush" + kind.capitalize(), rng, &"cloth")
	var path := env("toy_plush_" + kind)
	if not _plush_boxes.has(path):
		var m := ModelUtil.instantiate(path) if ResourceLoader.exists(path) else null
		_plush_boxes[path] = ModelUtil.aabb_of(m) if m else AABB(Vector3(-5, 0, -5), Vector3(10, 9, 10))
		if m:
			m.free()
	var box: AABB = _plush_boxes[path]
	var fur := StringName("plush_" + String([&"pink", &"teal", &"purple", &"yellow", &"blue"][rng.randi() % 5]))
	k._ellipsoid(fur, box.get_center(), box.size * 0.5, Basis(), true, 10, 18)
	k.footprint = maxf(box.size.x, box.size.z) * 0.5 + 2.0
	return k.dress(path, Transform3D(), {}, true).finish()


static var _plush_boxes: Dictionary = {}


## A take-apart toy airplane in pieces, the screws out of it: the chunky
## plastic fuselage (open at both ends and down one side where its panel came
## off: walk through it), one wing leaning on it (a ramp up onto its back),
## the other lying flat, the nose cone, the propeller, the tail fin, the
## wheels, giant screws and the toy screwdriver. Forward is -X.
static func takeapart_plane(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("TakeApartPlane", rng, &"wood")
	var body: StringName = [&"plastic_blue", &"plastic_red", &"plastic_teal"][rng.randi() % 3]
	var wing: StringName = &"plastic_yellow"
	var r := 4.4
	var t := 0.5
	var length := 24.0
	var cy := r + t
	# the fuselage: a ring of panels along X, its +Z side panels gone
	k._ring(body, Vector3(0, cy, 0), Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD), r, length, t, 16, [[PI * 1.5, 1.3]])
	for xs in [-1.0, 1.0]:
		k._ring(&"plastic_white", Vector3(xs * (length * 0.5 - 0.4), cy, 0), Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD), r + t, 0.8, 0.25, 16,
			[[PI * 1.5, 1.3]], false)
	# screw holes: dark dots along its back and down its sides
	for i in 6:
		var x := -length * 0.5 + 2.0 + i * (length - 4.0) / 5.0
		for a in [0.0, PI * 0.5]:
			k._ellipsoid(&"plastic_black", Vector3(x, cy + cos(a) * (r + t + 0.02), -sin(a) * (r + t + 0.02)), Vector3(0.45, 0.45, 0.45), Basis(), false, 4, 8)
	# the wing leaning on its -Z side: a ramp from the floor up onto its back
	var foot := Vector3(-1.0, 0.0, -(r + t) - 15.0)
	var lean_top := Vector3(-1.0, cy * 2.0 - 0.05, -0.6)
	var span := lean_top - foot
	var ramp_b := Basis(Vector3.RIGHT, -atan2(span.y, span.z))
	k._box(wing, (foot + lean_top) * 0.5 + ramp_b.y * 0.35, Vector3(6.0, 0.7, span.length()), ramp_b)
	k._box(&"plastic_red", (foot + lean_top) * 0.5 + ramp_b.y * 0.72, Vector3(1.0, 0.06, span.length() * 0.7), ramp_b, false)
	# the other wing lying flat beyond the open side (low enough to step onto)
	var flat := Vector3(2.0, 0.32, r + t + 9.0)
	k._box(wing, flat, Vector3(6.0, 0.64, 17.0), Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)))
	k._ellipsoid(&"plastic_red", flat + Vector3(0, 0.62, 4.0), Vector3(1.6, 0.05, 1.6), Basis(), false, 3, 12)
	# the nose cone off in front, tipped on its side
	var nose := Vector3(-length * 0.5 - 6.5, 0, -1.0)
	k._ellipsoid(&"plastic_white", nose + Vector3(0, r * 0.85, 0), Vector3(3.0, r * 0.85, r * 0.85), Basis(), true, 8, 14)
	# the propeller lying flat by the nose: a hub and three blades
	var prop := nose + Vector3(-2.0, 0.3, 7.5)
	k._rod(&"plastic_red", prop, prop + Vector3.UP * 1.0, 1.2, false)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		k._box(&"plastic_red", prop + Vector3(cos(a) * 3.4, 0.0, sin(a) * 3.4), Vector3(5.6, 0.5, 1.5), Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, 0.25), false)
	# the tail fin stood on the floor behind, and the wheels
	var tail := Vector3(length * 0.5 + 6.0, 0, 3.0)
	k._prism(&"plastic_red", [Vector2(tail.x - 3.0, 0.0), Vector2(tail.x + 3.5, 0.0), Vector2(tail.x + 2.4, 5.6), Vector2(tail.x + 0.6, 5.6)], tail.z, 0.6)
	for i in 2:
		var at := tail + Vector3(rng.randf_range(-2.0, 4.0), 0, -7.0 - i * 5.5)
		k._rod(&"plastic_black", at + Vector3.UP * 0.0, at + Vector3.UP * 1.3, 2.1)
		k._rod(&"plastic_yellow", at + Vector3.UP * 1.3, at + Vector3.UP * 1.45, 1.0, false)
	# giant screws, and the screwdriver that took it apart
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var at := Vector3(cos(a) * rng.randf_range(15.0, 19.0), 0.0, sin(a) * rng.randf_range(10.0, 13.0))
		var dir := Vector3(cos(a + 1.7), 0, sin(a + 1.7))
		k._rod(&"metal", at + Vector3.UP * 0.4, at + Vector3.UP * 0.4 + dir * 2.4, 0.35, false)
		k._rod(&"plastic_orange", at + Vector3.UP * 0.6 - dir * 0.3, at + Vector3.UP * 0.6, 0.6, false)
	var sd := Vector3(-length * 0.5 - 2.0, 0.0, r + t + 6.0)
	k._rod(&"plastic_red", sd + Vector3(0, 0.7, 0), sd + Vector3(5.0, 0.7, 1.0), 0.7, false)
	k._rod(&"metal", sd + Vector3(5.0, 0.7, 1.0), sd + Vector3(9.5, 0.6, 1.9), 0.22, false)
	k._box(&"metal", sd + Vector3(9.8, 0.6, 1.95), Vector3(0.6, 0.12, 0.5), Basis(Vector3.UP, -0.2), false)
	k.footprint = 23.0
	k.loot_spots = [Vector3(2.0, 0.5, 0.0), Vector3(-4.0, cy * 2.0, 0.0)]
	return k.finish()


static var _meshes: Dictionary = {}


## Batched floor clutter (MultiMesh via Scatter): "bricks" (tiny plastic
## bricks — mind your feet), "marbles" (glass marbles) and "fringe" (the play
## rug's tassels, 4 m to a piece) are decoration;
## "stuffing" (pillow stuffing tufts in the pillow corner) hides you like bushes.
static func entry(kind: String) -> Dictionary:
	match kind:
		"bricks":
			return {"id": "toy_bricks", "category": "lily", "height_m": 0.6, "footprint_radius_m": 1.4, "scale_range": [0.8, 1.2], "_mesh": _mesh("bricks")}
		"marbles":
			return {"id": "toy_marbles", "category": "lily", "height_m": 0.8, "footprint_radius_m": 1.2, "scale_range": [0.8, 1.3], "_mesh": _mesh("marbles")}
		"fringe":
			return {"id": "toy_fringe", "category": "lily", "height_m": 0.3, "footprint_radius_m": 2.0, "scale_range": [1.0, 1.0], "_mesh": _mesh("fringe")}
		_:
			var e := CageProps.entry("fluff")
			e["id"] = "toy_stuffing"
			if ResourceLoader.exists(made("toy/stuffing")):
				e["_mesh"] = _mesh("stuffing")
			return e


static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var model := made("toy/" + kind)
	if ResourceLoader.exists(model):
		_meshes[kind] = CageKit.model_mesh(model)
		return _meshes[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var k := CageKit.blank("tmp", rng)
	if kind == "fringe":
		# a 4 m run of the rug's cotton tassels, knotted at the rug's edge (x 0)
		# and lying out along +X, each a little askew
		for i in 9:
			var z := -2.0 + (i + 0.5) * 4.0 / 9.0
			var length := rng.randf_range(2.2, 2.9)
			var a := rng.randf_range(-0.14, 0.14)
			var root := Vector3(0.12, 0.14, z)
			k._ellipsoid(&"fringe", root, Vector3(0.3, 0.16, 0.22), Basis(), false, 3, 6)
			k._box(&"fringe", root + Vector3(cos(a), 0, sin(a)) * length * 0.5 + Vector3.DOWN * 0.05, Vector3(length, 0.14, 0.22), Basis(Vector3.UP, -a), false)
	elif kind == "bricks":
		for i in 3:
			var at := Vector3(rng.randf_range(-1.2, 1.2), 0.3, rng.randf_range(-1.2, 1.2))
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			var col := StringName("plastic_" + String(_c(rng)))
			k._box(col, at, Vector3(1.6, 0.6, 0.8), b, false)
			for sx in [-0.4, 0.4]:
				k._rod(col, at + b * Vector3(sx, 0.3, 0), at + b * Vector3(sx, 0.48, 0), 0.24, false)
	else:
		for i in 4:
			var at := Vector3(rng.randf_range(-1.0, 1.0), 0.45, rng.randf_range(-1.0, 1.0))
			k._ellipsoid(&"bowl_glass" if i % 2 == 0 else StringName("plastic_" + String(_c(rng))), at, Vector3.ONE * 0.45, Basis(), false, 6, 10)
	k._commit()
	var mesh: ArrayMesh = (k.get_node("Mesh") as MeshInstance3D).mesh
	k.free()
	_meshes[kind] = mesh
	return mesh
