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
const BOWL_R := 12.0           ## the bowl model's size (scaled to each bowl)
const BOWL_RIM := 3.4
## Tube Town's pods, built facing out (+X): doors out and to both neighbours.
const TOWN_DOORS := [-PI * 0.75, PI * 0.75, 0.0]
const TOWN_TUBE := 27.0 * 1.41421356 - POD_R * 2.0 + 1.2   ## its tubes' length


## A downloaded model (tools/env, assets/env/<id>) or one made in Blender
## (tools/maps, assets/maps/<name>.glb), for CageKit.dress.
static func env(id: String) -> String:
	return "res://assets/env/%s/%s.glb" % [id, id]


static func made(name: String) -> String:
	return "res://assets/maps/%s.glb" % name


## Rotation and uniform scale (Basis.scaled scales in world space, so not that).
static func xf(basis: Basis, size := 1.0, at := Vector3.ZERO) -> Transform3D:
	return Transform3D(basis * Basis.from_scale(Vector3.ONE * size), at)


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
	return k.made_as("cage/wheel").finish()


## A round Habitrail pod: a ring of plastic panels with doorways at the given
## angles (radians, 0 = +X toward +Z), a white domed roof and a rim band.
static func pod(rng: RandomNumberGenerator, colour: StringName, doors: Array, made := "") -> CageKit:
	var k := CageKit.blank("Pod", rng, &"wood")
	var wall := k.accent("accent", StringName("plastic_" + String(colour)))
	var gaps := []
	for a in doors:
		gaps.append([a, (TUBE_R + TUBE_WALL) * 2.4 / POD_R])
	var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	k._ring(wall, Vector3(0, POD_H * 0.5 - 0.2, 0), basis, POD_R, POD_H + 0.4, 0.45, 28, gaps)
	k._lathe(&"plastic_white", [Vector2(POD_R + 0.9, POD_H - 0.1), Vector2(POD_R + 0.9, POD_H + 0.6), Vector2(POD_R * 0.75, POD_H + 2.6),
		Vector2(POD_R * 0.35, POD_H + 3.4), Vector2(0.0, POD_H + 3.6)], 28, Vector3.ZERO, true)
	k._lathe(&"plastic_white", [Vector2(0.0, POD_H - 0.1), Vector2(POD_R + 0.9, POD_H - 0.1)], 28, Vector3.ZERO, false)   # the ceiling
	# a round vent on the dome and a little flag
	k._lathe(wall, [Vector2(1.8, POD_H + 3.55), Vector2(1.8, POD_H + 4.2), Vector2(0.0, POD_H + 4.3)], 16, Vector3.ZERO, false)
	k.footprint = POD_R + 1.5
	k.floor_y = 0.05
	if made != "":
		k.made_as(made)   # (a model for this door layout: Tube Town's)
	return k.finish()


## A straight Habitrail tube along local Z, `length` long, centred on the
## origin, its flat bottom panel level with the ground: walk straight through.
static func tube(rng: RandomNumberGenerator, colour: StringName, length: float, made := "") -> CageKit:
	var k := CageKit.blank("Tube", rng, &"wood")
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var c := Vector3(0, TUBE_R + 0.05, 0)
	k._ring(k.accent("accent", StringName("plastic_" + String(colour))), c, basis, TUBE_R, length, TUBE_WALL, 12)
	# connector collars every few metres
	var n := maxi(2, int(length / 9.0))
	for i in n + 1:
		var z := -length * 0.5 + length * i / n
		k._ring(&"plastic_white", c + Vector3(0, 0, z), basis, TUBE_R + TUBE_WALL, 0.8, 0.3, 12, [], false)
	if made != "":
		k.made_as(made)   # (a model for this length: Tube Town's)
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
	if is_equal_approx(radius, 2.7) and (is_equal_approx(length, 9.0) or is_equal_approx(length, 24.0)):
		k.made_as("cage/roll_%d" % int(length))
	return k.finish()


## A ceramic pet bowl: flared outside in `colour`, a white glazed rim and
## inside, `rim` high, `r` across the rim. Water (if any) is added by the cage.
static func bowl(rng: RandomNumberGenerator, colour: StringName, r: float, rim: float) -> CageKit:
	var k := CageKit.blank("Bowl", rng, &"rock")
	var lip := 1.4
	var base_r := r * 0.82
	var floor_y := 0.6
	var outer := k.accent("accent", StringName("ceramic_" + String(colour)))
	k._lathe(outer, [Vector2(base_r, -0.5), Vector2(r * 0.97, rim - 0.6), Vector2(r, rim)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(r, rim), Vector2(r - lip, rim)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(r - lip, rim), Vector2(r - lip - 0.6, rim - 1.2), Vector2(base_r - lip * 0.8, floor_y + 0.4),
		Vector2(base_r - lip * 1.3, floor_y)], 40, Vector3.ZERO)
	k._lathe(&"ceramic_white", [Vector2(base_r - lip * 1.3, floor_y), Vector2(0.0, floor_y)], 40, Vector3.ZERO)
	# a painted band round the outside
	k._lathe(&"plastic_white", [Vector2(r * 0.9 + 0.06, rim * 0.45), Vector2(r * 0.93 + 0.06, rim * 0.62)], 40, Vector3.ZERO, false)
	k.footprint = r + 1.0
	k.floor_y = floor_y
	return k.made_as("cage/bowl", Transform3D(Basis.from_scale(Vector3(r / BOWL_R, rim / BOWL_RIM, r / BOWL_R)), Vector3.ZERO)).finish()


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
	return k.made_as("cage/seed_bowl").finish()


## A shallow tray of bathing sand (the sand itself is the floor, painted by
## the terrain): just a low plastic rim you can step over.
static func sand_tray(rng: RandomNumberGenerator, r: float) -> CageKit:
	var k := CageKit.blank("SandTray", rng, &"wood")
	k._lathe(&"plastic_blue", [Vector2(r, -0.6), Vector2(r, 0.12), Vector2(r - 0.8, 0.12), Vector2(r - 0.8, -0.6)], 40, Vector3.ZERO, false)
	if is_equal_approx(r, 16.6):
		k.made_as("cage/sand_tray")
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
	if is_equal_approx(height, 9.0):
		k.made_as("cage/platform")
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
	return k.made_as("cage/water_bottle").finish()


# ---- food & cover ---------------------------------------------------------------------------

static func sunflower_seed(rng: RandomNumberGenerator, length := 2.2) -> CageKit:
	var k := CageKit.blank("Seed", rng, &"wood")
	# long axis along the ellipsoid's own Y (so the stripes run tip to tip), laid flat
	var yaw := rng.randf() * TAU
	var tilt := rng.randf_range(-0.15, 0.15)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5 + tilt)
	k._ellipsoid(&"seed_shell", Vector3(0, length * 0.2, 0), Vector3(length * 0.32, length * 0.5, length * 0.2), basis)
	k.dress(env("cage_seed"), xf(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt * 0.3), length / 2.2))
	return k.finish()


static func pellet(rng: RandomNumberGenerator, length := 2.4) -> CageKit:
	var k := CageKit.blank("Pellet", rng, &"wood")
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)).normalized()
	var r := length * 0.28
	k._rod(&"pellet", Vector3.UP * r - dir * length * 0.5, Vector3.UP * r + dir * length * 0.5, r)
	k.dress(env("cage_peanut"), xf(Basis(Vector3.UP, atan2(dir.x, dir.z)), length / 2.4))   # (a peanut in its shell)
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
	var yaw := 0.0
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf() * 0.4
		yaw += a
		var at := Vector3(cos(a) * 2.0 * size, h * 0.8 + rng.randf_range(-0.2, 0.6) * size, sin(a) * 2.0 * size)
		k._ellipsoid(&"broccoli", at, Vector3.ONE * rng.randf_range(1.0, 1.4) * size, Basis(), false, 6, 10)
	k.dress(env("cage_broccoli"), xf(Basis(Vector3.UP, yaw), size))
	return k.finish()


static func carrot_stick(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Carrot", rng, &"wood")
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)).normalized()
	var r := 0.9
	k._rod(&"carrot", Vector3.UP * r - dir * 3.0, Vector3.UP * r + dir * 2.0, r)
	k._cone(&"carrot", Vector3.UP * r + dir * 2.0, Vector3.UP * r * 0.8 + dir * 4.2, r)
	k.dress(env("cage_carrot"), xf(Basis(Vector3.UP, atan2(-dir.z, dir.x)), 1.0, dir * 0.6))   # (tip toward dir)
	return k.finish()


static func corn_cob(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Corn", rng, &"wood")
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	k._ellipsoid(&"corn", Vector3(0, 1.3, 0), Vector3(1.4, 1.3, 4.5), basis)
	for i in 3:
		var a := -0.6 + i * 0.6
		k._ellipsoid(&"broccoli_stem", basis * Vector3(sin(a) * 1.0, 1.0, -4.2), Vector3(0.6, 0.3, 2.2), basis * Basis(Vector3.UP, a), false, 5, 8)
	k.dress(env("cage_corn"), xf(basis))
	return k.finish()


static func apple_slice(rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.blank("Apple", rng, &"wood")
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	k._ellipsoid(&"apple_flesh", Vector3(0, 1.1, 0), Vector3(3.0, 1.1, 1.2), b)
	k._ellipsoid(&"apple_skin", b * Vector3(0, 1.1, -0.35), Vector3(3.05, 1.12, 0.9), b, false)
	k.dress(env("cage_apple"), xf(b, 0.8))   # (an apple and its cut half)
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
	k.dress(made("cage/chew_block"), xf(b, size), {"accent": m})
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
	k.dress(made("cage/hamster_ball"), xf(b, r))
	return k.finish()


## A frozen pea the size of a boulder, frosted white on top.
static func pea(rng: RandomNumberGenerator, r := 1.6) -> CageKit:
	var k := CageKit.blank("Pea", rng, &"rock")
	k._ellipsoid(&"pea", Vector3(0, r * 0.9, 0), Vector3(r, r * 0.95, r))
	var yaw := 0.0
	for i in 3:
		var a := rng.randf() * TAU
		yaw = a
		k._ellipsoid(&"frost", Vector3(cos(a) * r * 0.4, r * 1.55, sin(a) * r * 0.4), Vector3(r * 0.45, r * 0.18, r * 0.4), Basis(), false, 4, 8)
	k.dress(env("cage_pea"), xf(Basis(Vector3.UP, yaw), r / 1.6))
	return k.finish()


## A giant ice cube (or a stack of two), glassy blue-white.
static func ice_cube(rng: RandomNumberGenerator, size: float) -> CageKit:
	var k := CageKit.blank("IceCube", rng, &"rock")
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08))
	k._box(&"ice", Vector3(0, size * 0.48, 0), Vector3.ONE * size, b)
	k._box(&"frost", Vector3(0, size * 0.97, 0), Vector3(size * 0.96, 0.08, size * 0.96), b, false)
	k.dress(made("cage/ice_cube"), xf(b, size))
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
	# lying flat it's centred on the origin (stick end to tip), like anything long
	var origin := Vector3(0, h * 0.1 + 0.02, 0) - b * Vector3(0, (h - 3.2) * 0.5, 0) if lying else Vector3(0, 2.4, 0)
	k._box(m, origin + b * Vector3(0, h * 0.5, 0), Vector3(h * 0.45, h, h * 0.2), b)
	k._box(&"popsicle_stick", origin + b * Vector3(0, -1.2, 0), Vector3(1.0, 4.0, 0.3), b)
	k._box(&"frost", origin + b * Vector3(0, h * 0.75, h * 0.1 + 0.02), Vector3(h * 0.38, h * 0.3, 0.05), b, false)
	# a blue ice lolly or a chocolate one (that model's flat side faces along X)
	var blue := colours.find(m) % 2 == 0
	var lolly := b if blue else b * Basis(Vector3.UP, PI * 0.5)
	k.dress(env("cage_popsicle_blue" if blue else "cage_popsicle_choc"), xf(lolly, (h + 3.2) / 11.0, origin + b * Vector3(0, -3.2, 0)))
	return k.finish()


## A scallop seashell (aquarium decoration), resting on its back.
static func shell(rng: RandomNumberGenerator, size := 4.0) -> CageKit:
	var k := CageKit.blank("Shell", rng, &"rock")
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.25)
	k._ellipsoid(&"shell", Vector3(0, size * 0.32, 0), Vector3(size, size * 0.38, size * 0.85), b, true, 6, 16)
	for i in 9:
		var a := lerpf(-1.2, 1.2, i / 8.0)
		var dir := b * Vector3(sin(a), 0.0, cos(a))
		k._box(&"plastic_pink", Vector3(0, size * 0.62, 0) + dir * size * 0.42 + b.y * 0.02, Vector3(0.18, 0.16, size * 0.8),
			Basis(dir.cross(b.y).normalized(), b.y, dir), false)
	k.dress(env("cage_shell"), xf(Basis(Vector3.UP, yaw), size / 4.0))
	return k.finish()


## The toy airplane that flies everyone into the cage (see Dropship): a red
## fuselage, yellow wings with blue star roundels, a wind-up key and a
## spinning propeller (child "Propeller").
static func toy_plane(rng: RandomNumberGenerator) -> Node3D:
	# A tin-toy biplane, about 35 m wing to wing at critter scale: a pressed-
	# tin fuselage with a white band and rivets, a radial engine behind a
	# yellow cowling, two stacked wings on struts with bracing wire and roundel
	# stickers, a goggled pilot in the open cockpit, spoked wheels, and the
	# wind-up key that makes it go. Forward is -Z.
	var root := Node3D.new()
	root.name = "ToyPlane"
	var k := CageKit.blank("Body", rng, &"wood")
	k.collision_layer = 0
	# fuselage: a tapered tin body, a white band, a darker belly seam
	var prof := [Vector2(0.0, -14.0), Vector2(2.6, -13.6), Vector2(3.9, -11.0), Vector2(4.2, -6.0), Vector2(3.9, 2.0),
		Vector2(2.9, 9.0), Vector2(1.6, 14.0), Vector2(0.6, 16.0), Vector2(0.0, 16.3)]
	_lathe_z(k, &"plastic_red", prof, 20, Vector3.ZERO)
	_lathe_z(k, &"plastic_white", [Vector2(4.25, -3.0), Vector2(4.3, -1.6), Vector2(4.25, -0.2)], 20, Vector3.ZERO)
	for i in 9:
		var z := -10.0 + i * 2.6
		for a in [0.6, PI - 0.6]:
			var r := _radius_at(prof, z) + 0.05
			k._ellipsoid(&"metal", Vector3(cos(a) * r, sin(a) * r, z), Vector3(0.18, 0.18, 0.18), Basis(), false, 3, 6)
	# cowling and the radial engine peeking out of it
	k._ring(&"plastic_yellow", Vector3(0, 0, -13.6), Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN), 3.4, 2.2, 0.5, 20, [], false)
	for i in 7:
		var a := TAU * i / 7.0
		k._rod(&"metal", Vector3(cos(a) * 1.2, sin(a) * 1.2, -13.9), Vector3(cos(a) * 3.0, sin(a) * 3.0, -13.9), 0.45, false)
		k._ellipsoid(&"metal", Vector3(cos(a) * 3.0, sin(a) * 3.0, -13.9), Vector3(0.55, 0.55, 0.55), Basis(), false, 4, 8)
	for xs in [-1.0, 1.0]:
		k._rod(&"metal", Vector3(xs * 2.6, -2.2, -11.5), Vector3(xs * 3.0, -2.9, -6.0), 0.3, false)   # exhausts
	# open cockpit: a windscreen, a padded rim and the pilot
	k._ring(&"plastic_brown", Vector3(0, 3.95, 1.5), Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), 1.9, 0.5, 0.35, 14, [], false)
	k._box(&"bottle_glass", Vector3(0, 4.9, -1.0), Vector3(3.2, 1.6, 0.08), Basis(Vector3.RIGHT, deg_to_rad(-25.0)), false)
	_pilot(k, Vector3(0, 4.0, 1.6))
	# wings: a lower and an upper, with rounded tips, stripes and roundels
	var lower_y := -1.6
	var upper_y := 6.4
	_wing(k, Vector3(0, lower_y, -3.0), 36.0, 7.0, &"plastic_yellow")
	_wing(k, Vector3(0, upper_y, -4.2), 32.0, 6.6, &"plastic_yellow")
	for xs in [-1.0, 1.0]:
		_roundel(k, Vector3(xs * 11.5, upper_y + 0.31, -4.2), 2.6)
		_roundel(k, Vector3(xs * 12.5, lower_y + 0.31, -3.0), 2.4)
		# interplane struts (an N each side) and the bracing wires
		var outer: float = xs * 11.0
		k._rod(&"plastic_white", Vector3(outer, lower_y, -5.6), Vector3(outer, upper_y, -6.7), 0.32, false)
		k._rod(&"plastic_white", Vector3(outer, lower_y, -0.6), Vector3(outer, upper_y, -1.9), 0.32, false)
		k._rod(&"plastic_white", Vector3(outer, lower_y, -5.6), Vector3(outer, upper_y, -1.9), 0.22, false)
		k._rod(&"metal", Vector3(xs * 2.5, lower_y, -3.0), Vector3(outer, upper_y, -4.2), 0.07, false)
		k._rod(&"metal", Vector3(xs * 2.5, upper_y, -4.2), Vector3(outer, lower_y, -3.0), 0.07, false)
		# cabane struts from the fuselage up to the top wing
		k._rod(&"plastic_white", Vector3(xs * 1.8, 3.4, -6.0), Vector3(xs * 2.6, upper_y, -6.4), 0.28, false)
		k._rod(&"plastic_white", Vector3(xs * 1.8, 3.4, -2.0), Vector3(xs * 2.6, upper_y, -2.2), 0.28, false)
		# undercarriage: a V of struts down to spoked wheels with white hubs
		k._rod(&"plastic_white", Vector3(xs * 2.4, -3.0, -8.0), Vector3(xs * 3.4, -6.4, -6.0), 0.35, false)
		k._rod(&"plastic_white", Vector3(xs * 2.4, -3.0, -4.0), Vector3(xs * 3.4, -6.4, -6.0), 0.35, false)
		_wheel(k, Vector3(xs * 4.1, -6.4, -6.0), 1.7)
	k._rod(&"metal", Vector3(-3.4, -6.4, -6.0), Vector3(3.4, -6.4, -6.0), 0.18, false)
	# tail: stabiliser, a blue fin with a white star roundel, and a tail skid
	_wing(k, Vector3(0, 0.6, 13.6), 13.0, 3.6, &"plastic_yellow")
	k._box(&"plastic_blue", Vector3(0, 3.6, 14.2), Vector3(0.45, 6.0, 3.8), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	for xs in [-1.0, 1.0]:
		_roundel(k, Vector3(xs * 0.26, 3.6, 14.3), 1.2, Basis(Vector3.FORWARD, xs * PI * 0.5))
	k._rod(&"metal", Vector3(0, -1.4, 14.5), Vector3(0, -2.6, 16.0), 0.15, false)
	# the wind-up key in its side: it's a toy after all
	k._rod(&"metal", Vector3(4.0, 0.8, 5.0), Vector3(6.4, 0.8, 5.0), 0.3, false)
	for ys in [-1.0, 1.0]:
		k._ellipsoid(&"metal", Vector3(6.6, 0.8 + ys * 1.5, 5.0), Vector3(0.3, 1.4, 1.1), Basis(), false, 6, 10)
	root.add_child(k.made_as("cage/plane_body").finish())
	var prop := CageKit.blank("Propeller", rng, &"wood")
	prop.collision_layer = 0
	for sgn in [-1.0, 1.0]:
		prop._box(&"wood_honey", Vector3(0, sgn * 3.6, 0), Vector3(1.2, 7.2, 0.28), Basis(Vector3.UP, sgn * 0.3), false)
		prop._box(&"plastic_red", Vector3(0, sgn * 6.9, 0), Vector3(1.22, 0.7, 0.3), Basis(Vector3.UP, sgn * 0.3), false)
	prop._ellipsoid(&"plastic_red", Vector3(0, 0, -0.4), Vector3(1.1, 1.1, 1.6), Basis(), false, 6, 10)
	prop.position = Vector3(0, 0, -14.6)
	root.add_child(prop.made_as("cage/plane_propeller").finish())
	return root


## A lathe around the Z axis (the profile is [radius, z] pairs).
static func _lathe_z(k: CageKit, mat: StringName, prof: Array, seg: int, at: Vector3) -> void:
	var st := k._st(mat)
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var v := [at + Vector3(cos(a0) * p0.x, sin(a0) * p0.x, p0.y), at + Vector3(cos(a1) * p0.x, sin(a1) * p0.x, p0.y),
				at + Vector3(cos(a1) * p1.x, sin(a1) * p1.x, p1.y), at + Vector3(cos(a0) * p1.x, sin(a0) * p1.x, p1.y)]
			var am := (a0 + a1) * 0.5
			var slope := (p1.x - p0.x) / maxf(absf(p1.y - p0.y), 0.001)
			var n := Vector3(cos(am), sin(am), -slope * signf(p1.y - p0.y)).normalized()
			var uv := [Vector2(a0, p0.y * 0.2), Vector2(a1, p0.y * 0.2), Vector2(a1, p1.y * 0.2), Vector2(a0, p1.y * 0.2)]
			if (v[1] - v[0]).length_squared() > 1e-6:
				k._face(st, [v[0], v[1], v[2]], [uv[0], uv[1], uv[2]], n, false)
			k._face(st, [v[0], v[2], v[3]], [uv[0], uv[2], uv[3]], n, false)


static func _radius_at(prof: Array, z: float) -> float:
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		if z >= p0.y and z <= p1.y:
			return lerpf(p0.x, p1.x, (z - p0.y) / maxf(p1.y - p0.y, 0.001))
	return 0.0


## A wing `span` wide and `chord` deep at `c`: a slab with rounded tips, a
## white stripe and the hinge line of the ailerons.
static func _wing(k: CageKit, c: Vector3, span: float, chord: float, mat: StringName) -> void:
	k._box(mat, c, Vector3(span - chord, 0.6, chord), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(mat, c + Vector3(xs * (span - chord) * 0.5, 0, 0), Vector3(chord * 0.5, 0.3, chord * 0.5), Basis(), false, 4, 14)
		k._box(&"plastic_white", c + Vector3(xs * span * 0.3, 0.31, 0), Vector3(1.2, 0.02, chord - 0.4), Basis(), false)
		k._box(&"plastic_black", c + Vector3(xs * span * 0.33, 0.31, chord * 0.22), Vector3(span * 0.28, 0.02, 0.1), Basis(), false)


## A roundel sticker: blue, white and red rings, flat on a surface whose
## normal is `basis.y`.
static func _roundel(k: CageKit, c: Vector3, r: float, basis := Basis()) -> void:
	var rings := [[&"plastic_blue", 1.0], [&"plastic_white", 0.66], [&"plastic_red", 0.33]]
	for i in rings.size():
		var rr: float = r * float(rings[i][1])
		var st := k._st(rings[i][0])
		var o := c + basis.y * (0.01 * i)
		for s in 18:
			var a0 := TAU * s / 18.0
			var a1 := TAU * (s + 1) / 18.0
			var p0 := o + (basis.x * cos(a0) + basis.z * sin(a0)) * rr
			var p1 := o + (basis.x * cos(a1) + basis.z * sin(a1)) * rr
			k._face(st, [o, p0, p1], [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0)], basis.y, false)


## A chunky toy wheel: a black tyre, a white hub, five spokes.
static func _wheel(k: CageKit, c: Vector3, r: float) -> void:
	var axis := Basis(Vector3.UP, Vector3.RIGHT, Vector3.BACK)
	k._ring(&"plastic_black", c, axis, r * 0.62, 1.0, r * 0.38, 18, [], false)
	k._rod(&"plastic_white", c - Vector3.RIGHT * 0.45, c + Vector3.RIGHT * 0.45, r * 0.62, false)
	k._rod(&"plastic_red", c - Vector3.RIGHT * 0.55, c + Vector3.RIGHT * 0.55, r * 0.2, false)


## The pilot: a little mouse in a leather cap, goggles up, red scarf flying.
static func _pilot(k: CageKit, at: Vector3) -> void:
	k._ellipsoid(&"fur_light", at + Vector3(0, 1.5, 0), Vector3(1.1, 1.0, 1.0), Basis(), false, 6, 10)
	k._ellipsoid(&"plastic_brown", at + Vector3(0, 1.85, 0.1), Vector3(1.15, 0.75, 1.05), Basis(), false, 6, 10)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"fur_light", at + Vector3(xs * 1.0, 2.3, 0.2), Vector3(0.55, 0.55, 0.2), Basis(), false, 5, 8)
		k._ring(&"metal", at + Vector3(xs * 0.45, 2.15, -0.75), Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), 0.3, 0.2, 0.1, 10, [], false)
	k._ellipsoid(&"button_eye", at + Vector3(0, 1.35, -1.0), Vector3(0.22, 0.18, 0.15), Basis(), false, 4, 6)
	k._ellipsoid(&"plastic_red", at + Vector3(0, 0.75, 0), Vector3(1.2, 0.35, 1.1), Basis(), false, 5, 10)
	k._box(&"plastic_red", at + Vector3(0.6, 0.85, 1.8), Vector3(0.5, 0.15, 2.4), Basis(Vector3.UP, 0.25) * Basis(Vector3.RIGHT, 0.15), false)


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
	var model := _model_mesh(kind)
	if model:
		_meshes[kind] = model
		return model
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


## The ground cover from models: paper bedding tufts of crumpled paper, seeds
## and peanuts, the Blender-made plastic plant and snow clumps (null without
## the model files: then the procedural ones above).
static func _model_mesh(kind: String) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var parts := []
	match kind:
		"fluff":
			if not ResourceLoader.exists(env("cage_paper")):
				return null
			for i in 5:
				var a := TAU * i / 5.0 + rng.randf()
				var d := rng.randf_range(0.2, 1.1) if i else 0.0
				var s := rng.randf_range(1.2, 1.7) if i else 1.9
				parts.append([env("cage_paper"), xf(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.6)), s,
					Vector3(cos(a) * d, -0.1 * s, sin(a) * d))])
		"seeds":
			if not ResourceLoader.exists(env("cage_seed")) or not ResourceLoader.exists(env("cage_peanut")):
				return null
			for i in 7:
				var at := Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
				var id := "cage_seed" if i % 2 == 0 else "cage_peanut"
				parts.append([env(id), xf(Basis(Vector3.UP, rng.randf() * TAU), rng.randf_range(0.4, 0.5), at)])
		"plant":
			if not ResourceLoader.exists(made("cage/plant")):
				return null
			parts.append([made("cage/plant"), Transform3D()])
		_:
			if not ResourceLoader.exists(made("cage/snowball")):
				return null
			parts.append([made("cage/snowball"), Transform3D()])
	return CageKit.cluster_mesh(parts)
