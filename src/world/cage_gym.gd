class_name CageGym
## The Hamster Cage's high ground and climbing toys: the Hamster Gym (perches
## on stilts joined by see-through Habitrail tubes in every colour, with a
## slide tube back down), free-standing lookout perches, bendy wooden bridges,
## coconut hideouts, chew-stick bundles and egg-carton cover.
##
## See-through tubes are coloured clear plastic (CageKit "tube_<colour>"):
## you can see who's inside, but carrots bounce off them like any plastic.

const DECK_T := 0.6          ## perch deck thickness
const RAIL_H := 1.3          ## railing height (crouch behind it)
const GAP := 6.4             ## railing gap where a tube joins a deck
## The refined models' sizes (tools/maps): lookouts come in these heights,
## and bridges, coconuts and chew sticks are scaled from these.
const LOOKOUT_HEIGHTS := [9, 11, 13, 15]
const BRIDGE_SPAN := 18.0
const BRIDGE_RISE := 4.5
const COCONUT_R := 5.5
const STICKS_LENGTH := 11.0


## The Hamster Gym, centred on its kit origin (ground level): three perches
## climbing 7, 14 and 21 m, joined by sloping clear tubes, a skybridge tube
## out to a fourth perch, and two slide tubes back down. A ramp gets you
## onto the first perch. Faces +X (the ramp is at -X).
static func gym(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("HamsterGym", rng, &"wood")
	var colours := [&"pink", &"teal", &"orange", &"purple", &"lime", &"blue", &"yellow"]
	var deck := func(i: int) -> StringName: return k.accent("accent%d" % i, StringName("plastic_" + String(colours[(i + rng.randi()) % colours.size()])))
	# perches: [centre, height, size, sides with tubes]
	var a := Vector3(-28, 0, 0)
	var b := Vector3(8, 0, 0)
	var c := Vector3(8, 0, -36)
	var d := Vector3(42, 0, 0)
	perch(k, a, 7.0, 14.0, deck.call(0), [&"+x", &"-x"])
	perch(k, b, 14.0, 14.0, deck.call(1), [&"-x", &"-z", &"+x"])
	perch(k, c, 21.0, 12.0, deck.call(2), [&"+z", &"-x"], true)
	perch(k, d, 14.0, 11.0, deck.call(3), [&"-x", &"+z"])
	# the ramp up onto the first perch, from the west
	var run := 7.0 / tan(deg_to_rad(24.0))
	k._ramp(&"wood_light", Vector3(a.x - 7.0 - run, -0.15, 0.0), Vector3(a.x - 7.0 + 0.3, 7.0, 0.0), 5.0, &"paint_yellow")
	# tubes: up from A to B, up from B to C, across from B to D
	tube_between(k, &"pink", Vector3(a.x + 7.0, 7.0, 0), Vector3(b.x - 7.0, 14.0, 0))
	tube_between(k, &"teal", Vector3(b.x, 14.0, b.z - 7.0), Vector3(c.x, 21.0, c.z + 6.0))
	tube_between(k, &"yellow", Vector3(b.x + 7.0, 14.0, 0), Vector3(d.x - 5.5, 14.0, 0))
	# and the slides back down: off the top perch to the west, off D to the south
	var drop := 21.0 / tan(deg_to_rad(27.0))
	tube_between(k, &"purple", Vector3(c.x - 6.0, 21.0, c.z), Vector3(c.x - 6.0 - drop, 0.05, c.z))
	var drop_d := 14.0 / tan(deg_to_rad(26.0))
	tube_between(k, &"lime", Vector3(d.x, 14.0, d.z + 5.5), Vector3(d.x, 0.05, d.z + 5.5 + drop_d))
	# a hammock slung under the skybridge, and a water dish at the foot
	hammock(k, Vector3(b.x + 10.0, 0, -6.0), Vector3(d.x - 8.0, 0, -6.0), 6.0)
	k.footprint = 56.0
	k.floor_y = 7.0
	k.loot_spots = [Vector3(a.x - 3.0, 7.0, 2.0), Vector3(b.x + 2.0, 14.0, -2.0), Vector3(c.x + 1.0, 21.0, c.z + 1.0), Vector3(d.x, 14.0, d.z - 2.0)]
	k.chest_spot = Vector3(c.x - 2.0, 21.0, c.z - 2.0)
	return k.made_as("cage/gym").finish()


## A free-standing lookout perch: a deck on stilts with a railing and a
## ramp, `height` up. Faces +X (the ramp comes up from +X).
static func lookout(rng: RandomNumberGenerator, height: float, colour: StringName) -> CageKit:
	var k := CageKit.blank("Lookout", rng, &"wood")
	var size := 12.0
	var canopy := rng.randf() < 0.5
	perch(k, Vector3.ZERO, height, size, k.accent("accent", StringName("plastic_" + String(colour))), [&"+x"], canopy)
	var run := height / tan(deg_to_rad(25.0))
	k._ramp(&"wood_light", Vector3(size * 0.5 + run, -0.15, 0.0), Vector3(size * 0.5 - 0.3, height, 0.0), 5.0, &"paint_yellow")
	k.footprint = size * 0.5 + run * 0.5 + 3.0
	k.floor_y = height
	k.loot_spots = [Vector3(-2.0, height, 1.5)]
	if is_equal_approx(height, roundf(height)) and int(height) in LOOKOUT_HEIGHTS:
		k.made_as("cage/lookout_%d%s" % [int(height), "_canopy" if canopy else ""])
	return k.finish()


## One perch: a square deck `size` across at `height` on four stilts (with
## cross braces), a white rim, grip ridges, and a railing round the sides
## that aren't in `open` (those get a gap in the middle, for a tube or a
## ramp). With `canopy`, a striped sunshade on a pole over it.
static func perch(k: CageKit, centre: Vector3, height: float, size: float, mat: StringName, open: Array, canopy := false) -> void:
	var h := size * 0.5
	var top := centre + Vector3.UP * height
	k._box(mat, top - Vector3.UP * DECK_T * 0.5, Vector3(size, DECK_T, size))
	# rim and grip ridges (looks)
	for s in [-1.0, 1.0]:
		k._box(&"plastic_white", top + Vector3(s * h, -DECK_T * 0.5, 0), Vector3(0.25, DECK_T + 0.1, size + 0.25), Basis(), false)
		k._box(&"plastic_white", top + Vector3(0, -DECK_T * 0.5, s * h), Vector3(size + 0.25, DECK_T + 0.1, 0.25), Basis(), false)
	for i in int(size / 2.0):
		var z := -h + 1.0 + i * 2.0
		k._box(&"plastic_white", top + Vector3(0, 0.03, z), Vector3(size - 2.0, 0.06, 0.18), Basis(), false)
	# stilts, sunk a little into the bedding, and braces between them
	var legs := [Vector3(-h + 0.8, 0, -h + 0.8), Vector3(h - 0.8, 0, -h + 0.8), Vector3(h - 0.8, 0, h - 0.8), Vector3(-h + 0.8, 0, h - 0.8)]
	for i in 4:
		var p: Vector3 = centre + legs[i]
		k._rod(&"plastic_white", p - Vector3.UP * 2.0, p + Vector3.UP * (height - DECK_T), 0.55)
		var q: Vector3 = centre + legs[(i + 1) % 4]
		k._rod(&"plastic_white", p + Vector3.UP * height * 0.18, q + Vector3.UP * height * 0.62, 0.22, false)
	# railings: each side whole, or split round a gap in the middle
	var sides := {&"+x": [Vector3(h - 0.15, 0, 0), Vector3(0, 0, 1)], &"-x": [Vector3(-h + 0.15, 0, 0), Vector3(0, 0, 1)],
		&"+z": [Vector3(0, 0, h - 0.15), Vector3(1, 0, 0)], &"-z": [Vector3(0, 0, -h + 0.15), Vector3(1, 0, 0)]}
	for key in sides:
		var mid: Vector3 = top + (sides[key][0] as Vector3) + Vector3.UP * RAIL_H * 0.5
		var along: Vector3 = sides[key][1]
		var thick := Vector3(0.3, RAIL_H, 0.3) + along * (size - 0.3)
		if not open.has(key):
			k._box(&"plastic_white", mid, thick)
			continue
		var piece := (size - GAP) * 0.5
		for s in [-1.0, 1.0]:
			var c: Vector3 = mid + along * s * (GAP * 0.5 + piece * 0.5)
			k._box(&"plastic_white", c, Vector3(0.3, RAIL_H, 0.3) + along * (piece - 0.3))
	if canopy:
		k._rod(&"plastic_white", top + Vector3(h - 1.2, 0, -h + 1.2), top + Vector3(0, 7.5, 0), 0.25, false)
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			var st := k._st(&"plastic_red" if i % 2 == 0 else &"plastic_white")
			var apex := top + Vector3(0, 8.4, 0)
			var e0 := top + Vector3(cos(a0) * h * 0.9, 6.6, sin(a0) * h * 0.9)
			var e1 := top + Vector3(cos(a1) * h * 0.9, 6.6, sin(a1) * h * 0.9)
			var n := (e0 - apex).cross(e1 - apex).normalized()
			if n.y < 0.0:
				n = -n
			k._face(st, [apex, e0, e1], [Vector2(0.5, 0), Vector2(0, 1), Vector2(1, 1)], n, false)
			k._face(st, [apex, e0, e1], [Vector2(0.5, 0), Vector2(0, 1), Vector2(1, 1)], -n, false)


## A see-through Habitrail tube whose inside floor runs straight from `a` to
## `b` (kit space): walk up it, down it, or across. White collars at the
## ends and along it.
static func tube_between(k: CageKit, colour: StringName, a: Vector3, b: Vector3) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	var up := side.cross(axis).normalized()
	if up.y < 0.0:
		up = -up
	var r := CageProps.TUBE_R
	var length := a.distance_to(b)
	# basis.y along the tube, basis.z pointing down: panel 3 of 12 is the floor
	var basis := Basis(side, axis, -up)
	var mid := (a + b) * 0.5 + up * (r + 0.02)
	k._ring(StringName("tube_" + String(colour)), mid, basis, r, length, CageProps.TUBE_WALL, 12)
	var n := maxi(2, int(length / 8.0))
	for i in n + 1:
		var t := -length * 0.5 + length * i / n
		k._ring(&"plastic_white", mid + axis * clampf(t, -length * 0.5 + 0.4, length * 0.5 - 0.4), basis, r + CageProps.TUBE_WALL, 0.8, 0.3, 12, [], false)


## A fabric hammock slung between two pairs of posts (decoration).
static func hammock(k: CageKit, a: Vector3, b: Vector3, height: float) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	for p in [a, b]:
		for s in [-1.0, 1.0]:
			k._rod(&"plastic_white", p + side * s * 2.0 - Vector3.UP, p + side * s * 2.0 + Vector3.UP * height, 0.25, false)
	var segs := 10
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var sag0 := sin(t0 * PI) * 2.2
		var sag1 := sin(t1 * PI) * 2.2
		var p0 := a.lerp(b, t0) + Vector3.UP * (height - sag0)
		var p1 := a.lerp(b, t1) + Vector3.UP * (height - sag1)
		var mat := &"pillow_pink" if i % 2 == 0 else &"pillow_yellow"
		k._box(mat, (p0 + p1) * 0.5, Vector3(4.0, 0.12, p0.distance_to(p1) + 0.05), Basis(side, (p1 - p0).normalized().cross(side), -(p1 - p0).normalized()), false)


## A bendy wooden bridge: slats on an arch `span` long and `rise` high,
## along local X. Walk over it (a little high ground) or crouch under it.
static func bendy_bridge(rng: RandomNumberGenerator, span := 18.0, rise := 4.5) -> CageKit:
	var k := CageKit.blank("BendyBridge", rng, &"wood")
	var n := int(span / 1.1)
	var width := 6.0
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var p0 := Vector3(-span * 0.5 + span * t0, sin(t0 * PI) * rise, 0)
		var p1 := Vector3(-span * 0.5 + span * t1, sin(t1 * PI) * rise, 0)
		var f := (p1 - p0).normalized()
		var basis := Basis(f, Vector3.BACK.cross(f), Vector3.BACK)
		var mat: StringName = &"wood_honey" if i % 3 != 1 else &"wood_light"
		k._box(mat, (p0 + p1) * 0.5 + basis.y * 0.25, Vector3(p0.distance_to(p1) - 0.12, 0.5, width), basis)
	# the wire binding the slats together, along both edges
	for s in [-1.0, 1.0]:
		for i in n:
			var t0 := float(i) / n
			var t1 := float(i + 1) / n
			k._rod(&"metal", Vector3(-span * 0.5 + span * t0, sin(t0 * PI) * rise + 0.3, s * (width * 0.5 - 0.4)),
				Vector3(-span * 0.5 + span * t1, sin(t1 * PI) * rise + 0.3, s * (width * 0.5 - 0.4)), 0.08, false)
	k.footprint = span * 0.5 + 1.0
	return k.made_as("cage/bridge", Transform3D(Basis.from_scale(Vector3(span / BRIDGE_SPAN, rise / BRIDGE_RISE, 1.0)), Vector3.ZERO)).finish()


## Half a coconut shell turned over, a doorway cut in its side: a tiny
## hideout (walk in, or crouch behind it).
static func coconut(rng: RandomNumberGenerator, r := 5.5) -> CageKit:
	var k := CageKit.blank("Coconut", rng, &"wood")
	rng.randf()   # (the door: it faces +X now, and the scatter turns the shell anyway)
	var door := 0.0
	# the shell wall (with a doorway), then the dome over it
	k._ring(&"coconut", Vector3(0, r * 0.3, 0), Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), r, r * 0.6, 0.5, 20, [[door, 0.75]])
	var prof := []
	for i in 7:
		var a := PI * 0.5 * i / 6.0
		prof.append(Vector2(cos(a) * (r + 0.5), r * 0.6 + sin(a) * r * 0.75))
	k._lathe(&"coconut", prof, 20, Vector3.ZERO, true, 0.4)
	k._lathe(&"coconut_in", [Vector2(0.0, r * 0.6 - 0.05), Vector2(r, r * 0.6 - 0.05)], 20, Vector3.ZERO, false)
	# the three "eyes" on top
	for i in 3:
		var a := TAU * i / 3.0
		k._ellipsoid(&"coconut_in", Vector3(cos(a) * 0.9, r * 0.6 + r * 0.73, sin(a) * 0.9), Vector3(0.45, 0.2, 0.45), Basis(), false, 4, 8)
	k.footprint = r + 1.5
	return k.made_as("cage/coconut", Transform3D(Basis.from_scale(Vector3.ONE * r / COCONUT_R), Vector3.ZERO)).finish()


## A bundle of chew sticks: willow twigs tied with a ribbon, lying about.
static func chew_sticks(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("ChewSticks", rng, &"wood")
	var length := rng.randf_range(9.0, 13.0)
	if CageKit.exporting:
		length = STICKS_LENGTH
	for i in 7:
		var off := Vector3(0, 0.55 + floorf(i / 3.0) * 0.75, (i % 3 - 1) * 0.95 + rng.randf_range(-0.15, 0.15))
		var tilt := rng.randf_range(-0.06, 0.06)
		k._rod(&"wood_honey" if i % 2 == 0 else &"wood_light", off + Vector3(-length * 0.5, 0, tilt * length), off + Vector3(length * 0.5, 0, -tilt * length), 0.42, i < 3)
	for x in [-length * 0.2, length * 0.2]:
		k._ring(&"plastic_red", Vector3(x, 1.2, 0), Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP), 1.9, 0.7, 0.12, 14, [], false)
	k._collide(Vector3(0, 1.2, 0), Vector3(length, 2.4, 3.2))
	k.footprint = length * 0.5
	return k.made_as("cage/chew_sticks", Transform3D(Basis.from_scale(Vector3(length / STICKS_LENGTH, 1.0, 1.0)), Vector3.ZERO)).finish()


## An egg carton's bottom half: cardboard cups in two rows (cover, and a
## little maze to hop through).
static func egg_carton(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("EggCarton", rng, &"wood")
	var cell := 4.2
	for row in 2:
		for col in 6:
			var c := Vector3((col - 2.5) * cell, 0, (row - 0.5) * cell)
			k._lathe(&"cardboard", [Vector2(cell * 0.38, 0.0), Vector2(cell * 0.5, 2.6), Vector2(cell * 0.47, 2.9)], 10, c, false, 0.5)
			if col < 5 and (row + col) % 2 == 0:
				# the cones that hold the lid shut, between the cups
				k._lathe(&"cardboard_in", [Vector2(0.9, 2.9), Vector2(0.4, 3.6), Vector2(0.0, 3.7)], 8, c + Vector3(cell * 0.5, 0, 0), false)
	k._box(&"cardboard", Vector3(0, 2.8, 0), Vector3(cell * 6.0 + 0.4, 0.15, cell * 2.0 + 0.4), Basis(), false)
	k._collide(Vector3(0, 1.45, 0), Vector3(cell * 6.0, 2.9, cell * 2.0))
	k.footprint = cell * 3.0 + 0.5
	return k.made_as("cage/egg_carton").finish()
