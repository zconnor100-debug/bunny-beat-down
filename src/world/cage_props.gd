class_name CageProps
extends RefCounted
## Builders for the hamster cage's props, all original procedural geometry
## (see CageKit for the primitives and materials). Each returns a CageKit
## (a StaticBody3D with one merged mesh) standing on its origin, its front
## (doorways, the wheel's open side) toward +Z.
##
## Sizes are at critter scale (a Bun stands ~2.6 m): tunnels are 5 m across,
## the wheel 26 m high, a sunflower seed is a knee-high obstacle.

const TUBE_R := 2.5            ## inner radius of a Habitrail tube
const TUBE_WALL := 0.35
const POD_R := 9.0
const POD_H := 7.5


## The giant exercise wheel: a ridged teal tread you can run into from the
## open front, yellow rims, spokes and a hub on the closed back, and an
## A-frame stand.
static func wheel(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Wheel", rng, &"wood")
	var r := 16.0
	var w := 10.0
	var axle := r + 0.02        # the tread's inside bottom sits right on the floor
	var c := Vector3(0, axle, 0)
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)   # axis along Z
	k._ring(&"plastic_teal", c, basis, r, w, 0.6, 44)
	for zs in [-1.0, 1.0]:
		k._ring(&"plastic_yellow", c + Vector3(0, 0, zs * (w * 0.5 + 0.3)), basis, r - 0.4, 0.6, 1.8, 44, [], false)
	# ridges across the tread (visual: little rungs to grip)
	for i in 44:
		var a := TAU * (i + 0.5) / 44.0
		var out := Vector3(cos(a), -sin(a), 0)
		k._box(&"plastic_white", c + out * (r - 0.08), Vector3(0.25, 0.16, w - 0.4), Basis(Vector3.BACK, -a), false)
	# the closed back: spokes and hub, then the stand behind
	var back := -w * 0.5 - 0.6
	for i in 8:
		var a := TAU * i / 8.0
		k._rod(&"plastic_yellow", c + Vector3(0, 0, back), c + Vector3(cos(a) * (r + 0.4), sin(a) * (r + 0.4), back), 0.45)
	k._rod(&"plastic_yellow", c + Vector3(0, 0, back - 0.8), c + Vector3(0, 0, back + 0.6), 1.8)
	k._rod(&"metal", c + Vector3(0, 0, back - 3.2), c + Vector3(0, 0, back), 0.45)
	var hub := c + Vector3(0, 0, back - 3.2)
	for xs in [-1.0, 1.0]:
		k._rod(&"plastic_purple", Vector3(xs * 10.0, -0.3, back - 4.5), hub, 0.9)
	k._box(&"plastic_purple", Vector3(0, 0.3, back - 4.5), Vector3(23.0, 0.8, 4.0))
	k.footprint = 19.0
	return k.finish()


## A round Habitrail pod: a ring of plastic panels with doorways at the given
## angles (radians, 0 = +X toward +Z), a white domed roof and a rim band.
static func pod(rng: RandomNumberGenerator, colour: StringName, doors: Array) -> CageKit:
	var k := CageKit.blank("Pod", rng, &"wood")
	var gaps := []
	for a in doors:
		gaps.append([a, (TUBE_R + TUBE_WALL) * 2.4 / POD_R])
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	k._ring(StringName("plastic_" + String(colour)), Vector3(0, POD_H * 0.5 - 0.2, 0), basis, POD_R, POD_H + 0.4, 0.45, 28, gaps)
	k._lathe(&"plastic_white", [Vector2(POD_R + 0.9, POD_H - 0.1), Vector2(POD_R + 0.9, POD_H + 0.6), Vector2(POD_R * 0.75, POD_H + 2.6),
		Vector2(POD_R * 0.35, POD_H + 3.4), Vector2(0.0, POD_H + 3.6)], 28, Vector3.ZERO, true)
	k._lathe(&"plastic_white", [Vector2(0.0, POD_H - 0.1), Vector2(POD_R + 0.9, POD_H - 0.1)], 28, Vector3.ZERO, false)   # the ceiling
	# a round vent on the dome and a little flag
	k._lathe(StringName("plastic_" + String(colour)), [Vector2(1.8, POD_H + 3.55), Vector2(1.8, POD_H + 4.2), Vector2(0.0, POD_H + 4.3)], 16, Vector3.ZERO, false)
	k.footprint = POD_R + 1.5
	k.floor_y = 0.05
	return k.finish()


## A straight Habitrail tube along local Z, `length` long, centred on the
## origin, its flat bottom panel level with the ground: walk straight through.
static func tube(rng: RandomNumberGenerator, colour: StringName, length: float) -> CageKit:
	var k := CageKit.blank("Tube", rng, &"wood")
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var c := Vector3(0, TUBE_R + 0.05, 0)
	k._ring(StringName("plastic_" + String(colour)), c, basis, TUBE_R, length, TUBE_WALL, 12)
	# connector collars every few metres
	var n := maxi(2, int(length / 9.0))
	for i in n + 1:
		var z := -length * 0.5 + length * i / n
		k._ring(&"plastic_white", c + Vector3(0, 0, z), basis, TUBE_R + TUBE_WALL, 0.8, 0.3, 12, [], false)
	return k.finish()


## A cardboard roll lying on its side (a toilet-paper tube is a tunnel to a
## critter): rough tan outside, darker inside, open at both ends.
static func roll(rng: RandomNumberGenerator, length: float, radius := 2.7) -> CageKit:
	var k := CageKit.blank("Roll", rng, &"wood")
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var c := Vector3(0, radius + 0.02, 0)
	k._ring(&"cardboard", c, basis, radius, length, 0.3, 16, [], true, PI / 16.0 * 0.0)
	k._ring(&"cardboard_in", c, basis, radius - 0.04, length - 0.05, 0.04, 16, [], false)
	# the spiral seam
	for i in int(length / 2.0):
		var a := float(i) * 0.9
		var out := Vector3(cos(a), -sin(a), 0)
		k._box(&"cardboard_in", c + out * (radius + 0.31) + Vector3(0, 0, -length * 0.5 + i * 2.0 + 1.0), Vector3(0.12, 0.05, 2.2),
			Basis(Vector3.BACK, -a) * Basis(Vector3.UP, 0.35), false)
	return k.finish()


## A ceramic pet bowl: flared outside in `colour`, a white glazed rim and
## inside, `rim` high, `r` across the rim. Water (if any) is added by the cage.
static func bowl(rng: RandomNumberGenerator, colour: StringName, r: float, rim: float) -> CageKit:
	var k := CageKit.blank("Bowl", rng, &"rock")
	var lip := 1.4
	var base_r := r * 0.82
	var floor_y := 0.6
	var outer := StringName("ceramic_" + String(colour))
	k._lathe(outer, [Vector2(base_r, -0.5), Vector2(r * 0.97, rim - 0.6), Vector2(r, rim)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(r, rim), Vector2(r - lip, rim)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(r - lip, rim), Vector2(r - lip - 0.6, rim - 1.2), Vector2(base_r - lip * 0.8, floor_y + 0.4),
		Vector2(base_r - lip * 1.3, floor_y)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(base_r - lip * 1.3, floor_y), Vector2(0.0, floor_y)], 40, Vector3.ZERO)
	# a painted band round the outside
	k._lathe(&"plastic_white", [Vector2(r * 0.9 + 0.06, rim * 0.45), Vector2(r * 0.93 + 0.06, rim * 0.62)], 40, Vector3.ZERO, false)
	k.footprint = r + 1.0
	k.floor_y = floor_y
	return k.finish()


## Radius of a bowl's inside at height y above its base (for the water disc).
static func bowl_inner_radius(r: float, rim: float, y: float) -> float:
	var lip := 1.4
	var base_r := r * 0.82
	var top := r - lip
	var bottom := base_r - lip * 0.8
	return lerpf(bottom, top, clampf((y - 1.0) / maxf(rim - 1.0, 0.1), 0.0, 1.0))


## A food bowl heaped with seed mix: a walkable mound of seeds inside the rim.
static func seed_bowl(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("SeedBowl", rng, &"wood")
	var r := 13.0
	var rim := 2.2
	k._lathe(&"ceramic_lemon", [Vector2(r * 0.85, -0.5), Vector2(r * 0.98, rim - 0.4), Vector2(r, rim)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(r, rim), Vector2(r - 1.2, rim)], 40, Vector3.ZERO)
	# the heap: a low dome of seed mix from just under the rim
	k._lathe(&"pellet", [Vector2(r - 1.2, rim - 0.1), Vector2(r * 0.6, rim + 1.2), Vector2(r * 0.25, rim + 2.0), Vector2(0.0, rim + 2.2)], 32, Vector3.ZERO)
	for i in 34:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (r - 2.0)
		var h := rim - 0.1 + (2.3 * (1.0 - pow(d / r, 2.0)))
		var at := Vector3(cos(a) * d, h, sin(a) * d)
		match i % 3:
			0:
				k._ellipsoid(&"seed_shell", at, Vector3(0.38, 0.75, 0.2), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 - 0.3), false, 6, 10)
			1:
				k._ellipsoid(&"corn", at, Vector3(0.35, 0.28, 0.32), Basis(Vector3.UP, rng.randf() * TAU), false, 5, 8)
			_:
				k._rod(&"pellet", at, at + Vector3(rng.randf_range(-0.6, 0.6), 0.1, rng.randf_range(-0.6, 0.6)), 0.3, false)
	k.footprint = r + 1.0
	return k.finish()


## A shallow tray of bathing sand (the sand itself is the floor, painted by
## the terrain): just a low plastic rim you can step over.
static func sand_tray(rng: RandomNumberGenerator, r: float) -> CageKit:
	var k := CageKit.blank("SandTray", rng, &"wood")
	k._lathe(&"plastic_blue", [Vector2(r, -0.6), Vector2(r, 0.12), Vector2(r - 0.8, 0.12), Vector2(r - 0.8, -0.6)], 40, Vector3.ZERO, false)
	return k.finish()


## A cage shelf: a plastic platform on legs, railings on three sides and a
## slatted wooden ramp up to it.
static func platform(rng: RandomNumberGenerator, height: float) -> CageKit:
	var k := CageKit.blank("Platform", rng, &"wood")
	var w := 18.0
	var d := 12.0
	k._box(&"plastic_lime", Vector3(0, height - 0.3, 0), Vector3(w, 0.6, d))
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			k._rod(&"plastic_white", Vector3(xs * (w * 0.5 - 1.0), -0.2, zs * (d * 0.5 - 1.0)), Vector3(xs * (w * 0.5 - 1.0), height - 0.6, zs * (d * 0.5 - 1.0)), 0.7)
	# railings (low walls: crouch behind them), open where the ramp arrives
	k._box(&"plastic_white", Vector3(0, height + 0.7, -d * 0.5 + 0.2), Vector3(w, 1.4, 0.3))
	k._box(&"plastic_white", Vector3(-w * 0.5 + 0.2, height + 0.7, 0), Vector3(0.3, 1.4, d))
	k._box(&"plastic_white", Vector3(w * 0.5 - 0.2, height + 0.7, -d * 0.25), Vector3(0.3, 1.4, d * 0.5))
	var length := height / tan(deg_to_rad(24.0))
	k._ramp(&"wood_light", Vector3(w * 0.5 + length - 0.2, -0.15, d * 0.25), Vector3(w * 0.5 - 0.4, height, d * 0.25), 4.6, &"paint_yellow")
	k.footprint = w * 0.5 + length * 0.5 + 2.0
	k.floor_y = height
	k.loot_spots = [Vector3(-4.0, height, 0.0), Vector3(3.0, height, -2.0)]
	return k.finish()


## The water bottle clipped to the inside of the glass: a tilted tank of
## blue water, a red cap and a steel spout with its ball, on a wire holder.
## Decoration only (it hangs well above the bedding). Faces +Z (into the cage).
static func water_bottle(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("WaterBottle", rng, &"wood")
	var top := Vector3(0, 70.0, -3.0)
	var bottom := Vector3(0, 30.0, 1.0)
	k._rod(&"bottle_glass", bottom, top, 6.5, false)
	k._rod(&"bottle_water", bottom + (top - bottom) * 0.02, bottom + (top - bottom) * 0.62, 6.1, false)
	k._rod(&"plastic_red", bottom + (bottom - top).normalized() * 3.0, bottom, 4.2, false)
	var tip := bottom + (bottom - top).normalized() * 3.0
	var spout_end := tip + Vector3(0, -12.0, 5.0)
	k._rod(&"metal", tip, spout_end, 1.0, false)
	k._ellipsoid(&"metal", spout_end, Vector3.ONE * 1.25, Basis(), false)
	for y in [38.0, 58.0]:
		k._lathe(&"metal", [Vector2(7.2, y), Vector2(7.2, y + 0.8)], 24, Vector3(0, 0, -1.0), false)
		k._rod(&"metal", Vector3(-7.0, y + 0.4, -1.0), Vector3(-7.0, y + 0.4, -10.4), 0.35, false)
		k._rod(&"metal", Vector3(7.0, y + 0.4, -1.0), Vector3(7.0, y + 0.4, -10.4), 0.35, false)
	k.set_meta(&"drip_from", spout_end + Vector3.DOWN * 1.3)
	return k.finish()


# ---- food & cover ---------------------------------------------------------------------------

static func sunflower_seed(rng: RandomNumberGenerator, length := 2.2) -> CageKit:
	var k := CageKit.blank("Seed", rng, &"wood")
	# long axis along the ellipsoid's own Y (so the stripes run tip to tip), laid flat
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.15, 0.15))
	k._ellipsoid(&"seed_shell", Vector3(0, length * 0.2, 0), Vector3(length * 0.32, length * 0.5, length * 0.2), basis)
	return k.finish()


static func pellet(rng: RandomNumberGenerator, length := 2.4) -> CageKit:
	var k := CageKit.blank("Pellet", rng, &"wood")
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)).normalized()
	var r := length * 0.28
	k._rod(&"pellet", Vector3.UP * r - dir * length * 0.5, Vector3.UP * r + dir * length * 0.5, r)
	return k.finish()


## A broccoli floret as tall as a small tree: a pale stalk under a bumpy
## crown of green buds. Good cover.
static func broccoli(rng: RandomNumberGenerator, size := 1.0) -> CageKit:
	var k := CageKit.blank("Broccoli", rng, &"wood")
	var h := 5.0 * size
	k._rod(&"broccoli_stem", Vector3.ZERO, Vector3(0, h * 0.6, 0), 0.9 * size)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		k._rod(&"broccoli_stem", Vector3(0, h * 0.45, 0), Vector3(cos(a) * 1.6 * size, h * 0.75, sin(a) * 1.6 * size), 0.5 * size, false)
	k._ellipsoid(&"broccoli", Vector3(0, h * 0.85, 0), Vector3(2.6, 1.7, 2.6) * size)
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf() * 0.4
		var at := Vector3(cos(a) * 2.0 * size, h * 0.8 + rng.randf_range(-0.2, 0.6) * size, sin(a) * 2.0 * size)
		k._ellipsoid(&"broccoli", at, Vector3.ONE * rng.randf_range(1.0, 1.4) * size, Basis(), false, 6, 10)
	return k.finish()


static func carrot_stick(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Carrot", rng, &"wood")
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)).normalized()
	var r := 0.9
	k._rod(&"carrot", Vector3.UP * r - dir * 3.0, Vector3.UP * r + dir * 2.0, r)
	k._cone(&"carrot", Vector3.UP * r + dir * 2.0, Vector3.UP * r * 0.8 + dir * 4.2, r)
	return k.finish()


static func corn_cob(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Corn", rng, &"wood")
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	k._ellipsoid(&"corn", Vector3(0, 1.3, 0), Vector3(1.4, 1.3, 4.5), basis)
	for i in 3:
		var a := -0.6 + i * 0.6
		k._ellipsoid(&"broccoli_stem", basis * Vector3(sin(a) * 1.0, 1.0, -4.2), Vector3(0.6, 0.3, 2.2), basis * Basis(Vector3.UP, a), false, 5, 8)
	return k.finish()


static func apple_slice(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Apple", rng, &"wood")
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	k._ellipsoid(&"apple_flesh", Vector3(0, 1.1, 0), Vector3(3.0, 1.1, 1.2), b)
	k._ellipsoid(&"apple_skin", b * Vector3(0, 1.1, -0.35), Vector3(3.05, 1.12, 0.9), b, false)
	return k.finish()


## A chew block: a wooden cube, plain or brightly painted, with holes to chew.
static func block(rng: RandomNumberGenerator, size: float) -> CageKit:
	var k := CageKit.blank("Block", rng, &"wood")
	var mats := [&"wood_light", &"paint_red", &"paint_blue", &"paint_yellow", &"paint_lime", &"paint_purple"]
	var m: StringName = mats[rng.randi() % mats.size()]
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	k._box(m, Vector3(0, size * 0.5, 0), Vector3.ONE * size, b)
	for f in 4:
		var n := b * (Basis(Vector3.UP, f * PI * 0.5) * Vector3.BACK)
		k._ellipsoid(&"cardboard_in", Vector3(0, size * 0.5, 0) + n * size * 0.5, Vector3(size * 0.18, size * 0.18, 0.05),
			Basis(n.cross(Vector3.UP).normalized(), Vector3.UP, n), false, 4, 10)
	return k.finish()


## A clear plastic exercise ball, lid band and air slots, lying in the bedding.
static func hamster_ball(rng: RandomNumberGenerator, r := 6.0) -> CageKit:
	var k := CageKit.blank("Ball", rng, &"wood")
	var c := Vector3(0, r - 0.3, 0)
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	k._ellipsoid(&"ball_plastic", c, Vector3.ONE * r, b, true, 12, 20)
	k._lathe(&"plastic_purple", [Vector2(r * 0.55, r * 0.82), Vector2(r * 0.55, r * 0.92), Vector2(0.0, r * 0.98)], 20, c, false)
	for i in 10:
		var a := TAU * i / 10.0
		var n := b * Vector3(cos(a), 0, sin(a))
		k._box(&"plastic_purple", c + n * (r + 0.02), Vector3(0.25, r * 0.6, 0.06), Basis(n.cross(b.y).normalized(), b.y, n), false)
	return k.finish()


## A frozen pea the size of a boulder, frosted white on top.
static func pea(rng: RandomNumberGenerator, r := 1.6) -> CageKit:
	var k := CageKit.blank("Pea", rng, &"rock")
	k._ellipsoid(&"pea", Vector3(0, r * 0.9, 0), Vector3(r, r * 0.95, r))
	for i in 3:
		var a := rng.randf() * TAU
		k._ellipsoid(&"frost", Vector3(cos(a) * r * 0.4, r * 1.55, sin(a) * r * 0.4), Vector3(r * 0.45, r * 0.18, r * 0.4), Basis(), false, 4, 8)
	return k.finish()


## A giant ice cube (or a stack of two), glassy blue-white.
static func ice_cube(rng: RandomNumberGenerator, size: float) -> CageKit:
	var k := CageKit.blank("IceCube", rng, &"rock")
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
	k._box(&"ice", Vector3(0, size * 0.48, 0), Vector3.ONE * size, b)
	k._box(&"frost", Vector3(0, size * 0.97, 0), Vector3(size * 0.96, 0.08, size * 0.96), b, false)
	return k.finish()


## A popsicle stuck stick-up in the snow (or lying on its side).
static func popsicle(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Popsicle", rng, &"rock")
	var colours := [&"plastic_red", &"plastic_orange", &"plastic_purple", &"plastic_lime", &"plastic_pink"]
	var m: StringName = colours[rng.randi() % colours.size()]
	var lying := rng.randf() < 0.35
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if lying:
		b = b * Basis(Vector3.RIGHT, PI * 0.5)
	else:
		b = b * Basis(Vector3.FORWARD, rng.randf_range(-0.35, 0.35))   # stuck in the snow at a slant
	var h := rng.randf_range(7.0, 10.0)
	var origin := Vector3(0, 1.1, 0) if lying else Vector3(0, 2.4, 0)
	k._box(m, origin + b * Vector3(0, h * 0.5, 0), Vector3(h * 0.45, h, h * 0.2), b)
	k._box(&"popsicle_stick", origin + b * Vector3(0, -1.2, 0), Vector3(1.0, 4.0, 0.3), b)
	k._box(&"frost", origin + b * Vector3(0, h * 0.75, h * 0.1 + 0.02), Vector3(h * 0.38, h * 0.3, 0.05), b, false)
	return k.finish()


## A scallop seashell (aquarium decoration), resting on its back.
static func shell(rng: RandomNumberGenerator, size := 4.0) -> CageKit:
	var k := CageKit.blank("Shell", rng, &"rock")
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -0.25)
	k._ellipsoid(&"shell", Vector3(0, size * 0.32, 0), Vector3(size, size * 0.38, size * 0.85), b, true, 6, 16)
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		var dir := b * Vector3(sin(a), 0.0, cos(a))
		k._box(&"plastic_pink", Vector3(0, size * 0.62, 0) + dir * size * 0.42 + b.y * 0.02, Vector3(0.18, 0.16, size * 0.8),
			Basis(dir.cross(b.y).normalized(), b.y, dir), false)
	return k.finish()


## The toy airplane that flies everyone into the cage (see Dropship): a red
## fuselage, yellow wings with blue star roundels, a wind-up key and a
## spinning propeller (child "Propeller").
static func toy_plane(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "ToyPlane"
	var k := CageKit.blank("Body", rng, &"wood")
	k.collision_layer = 0
	# fuselage along -Z (forward)
	k._ellipsoid(&"plastic_red", Vector3(0, 0, 0), Vector3(4.2, 4.0, 15.0), Basis(), false, 10, 20)
	k._ellipsoid(&"bottle_glass", Vector3(0, 2.6, -4.0), Vector3(2.6, 2.0, 4.0), Basis(), false, 8, 14)
	k._box(&"plastic_yellow", Vector3(0, -0.8, -1.5), Vector3(36.0, 0.9, 7.0))
	k._box(&"plastic_yellow", Vector3(0, 3.6, 12.0), Vector3(14.0, 0.6, 4.0))
	k._box(&"plastic_blue", Vector3(0, 6.0, 12.2), Vector3(0.6, 7.0, 4.6))
	for xs in [-1.0, 1.0]:
		k._lathe(&"plastic_blue", [Vector2(2.2, 0.0), Vector2(2.2, 0.1), Vector2(0.0, 0.1)], 16, Vector3(xs * 12.0, -0.3, -1.5), false)
		k._lathe(&"plastic_white", [Vector2(1.0, 0.11), Vector2(1.0, 0.16), Vector2(0.0, 0.16)], 5, Vector3(xs * 12.0, -0.3, -1.5), false)
		k._rod(&"plastic_white", Vector3(xs * 2.5, -3.0, -5.0), Vector3(xs * 3.2, -6.0, -5.0), 0.35, false)
		k._rod(&"plastic_black", Vector3(xs * 3.6, -6.4, -5.0), Vector3(xs * 2.6, -6.4, -5.0), 1.4, false)
	k._rod(&"plastic_yellow", Vector3(0, 0, -15.2), Vector3(0, 0, -16.6), 1.6, false)
	# the wind-up key on top
	k._rod(&"metal", Vector3(0, 3.8, 6.0), Vector3(0, 6.5, 6.0), 0.4, false)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"metal", Vector3(xs * 1.6, 7.2, 6.0), Vector3(1.6, 1.3, 0.3), Basis(), false, 6, 10)
	root.add_child(k.finish())
	var prop := CageKit.blank("Propeller", rng, &"wood")
	prop.collision_layer = 0
	for s in [-1.0, 1.0]:
		prop._box(&"plastic_blue", Vector3(0, s * 4.0, 0), Vector3(1.4, 8.0, 0.3), Basis(Vector3.UP, s * 0.25), false)
	prop._ellipsoid(&"plastic_yellow", Vector3.ZERO, Vector3(1.0, 1.0, 1.2), Basis(), false, 6, 10)
	prop.position = Vector3(0, 0, -16.8)
	root.add_child(prop.finish())
	return root


# ---- batched ground cover (MultiMesh via Scatter) ---------------------------------------------------

static var _meshes: Dictionary = {}


## A scatter entry (like SwampPlants.entry) for batched cage ground cover:
## "fluff" (paper bedding tufts: they hide you like bushes), "seeds" (loose
## seeds and pellets, decoration), "plant" (plastic aquarium plants, like
## reeds), "snowball" (snow clumps in the winter corner, cover).
static func entry(kind: String) -> Dictionary:
	match kind:
		"fluff":
			return {"id": "cage_fluff", "category": "bush", "height_m": 2.2, "footprint_radius_m": 1.8, "scale_range": [0.7, 1.4], "_mesh": _mesh("fluff")}
		"seeds":
			return {"id": "cage_seeds", "category": "lily", "height_m": 0.4, "footprint_radius_m": 1.2, "scale_range": [0.8, 1.3], "_mesh": _mesh("seeds")}
		"plant":
			return {"id": "cage_plant", "category": "reed", "height_m": 6.0, "footprint_radius_m": 1.5, "scale_range": [0.7, 1.3], "_mesh": _mesh("plant")}
		_:
			return {"id": "cage_snowball", "category": "bush", "height_m": 1.8, "footprint_radius_m": 1.6, "scale_range": [0.7, 1.5], "_mesh": _mesh("snowball")}


static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var k := CageKit.blank("tmp", rng)
	match kind:
		"fluff":
			for i in 6:
				var a := TAU * i / 6.0 + rng.randf()
				var d := rng.randf_range(0.2, 1.2)
				k._ellipsoid(&"paper_fluff", Vector3(cos(a) * d, rng.randf_range(0.4, 1.0), sin(a) * d),
					Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.5, 0.9), rng.randf_range(0.8, 1.3)), Basis(Vector3.UP, rng.randf() * TAU), false, 5, 9)
		"seeds":
			for i in 7:
				var at := Vector3(rng.randf_range(-1.2, 1.2), 0.12, rng.randf_range(-1.2, 1.2))
				if i % 2 == 0:
					k._ellipsoid(&"seed_shell", at, Vector3(0.22, 0.45, 0.12), Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), false, 5, 8)
				else:
					k._rod(&"pellet", at, at + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5)), 0.17, false)
		"plant":
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf()
				var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.8)
				var h := rng.randf_range(3.5, 6.5)
				var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.3, 1.4)
				var m: StringName = &"plastic_lime" if i % 3 != 0 else (&"plastic_pink" if i % 2 == 0 else &"plastic_teal")
				for s in 4:
					var t0 := float(s) / 4.0
					var t1 := float(s + 1) / 4.0
					var p0 := base + Vector3.UP * h * t0 + lean * t0 * t0 + Vector3(sin(t0 * 6.0 + a), 0, cos(t0 * 6.0 + a)) * 0.25
					var p1 := base + Vector3.UP * h * t1 + lean * t1 * t1 + Vector3(sin(t1 * 6.0 + a), 0, cos(t1 * 6.0 + a)) * 0.25
					k._box(m, (p0 + p1) * 0.5, Vector3(0.7 * (1.0 - t0 * 0.6), (p1 - p0).length() + 0.05, 0.08),
						Basis(IKMath.from_to(Vector3.UP, (p1 - p0).normalized())) * Basis(Vector3.UP, a), false)
		_:
			for i in 4:
				var a := TAU * i / 4.0 + rng.randf()
				var d := rng.randf_range(0.0, 0.9)
				k._ellipsoid(&"snow", Vector3(cos(a) * d, rng.randf_range(0.3, 0.7), sin(a) * d),
					Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.5, 0.8), rng.randf_range(0.8, 1.2)), Basis(), false, 5, 9)
	k._commit()
	var mesh: ArrayMesh = (k.get_node("Mesh") as MeshInstance3D).mesh
	k.free()
	_meshes[kind] = mesh
	return mesh
