extends TestCase
## How carrots fly: within a gun's range a shot lands where the crosshair is
## (the drop is made up for), automatics stay tight for the first shots of a
## burst and spread out when you hold the trigger, a short break settles them
## again, and the shotgun throws a pattern you can learn.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena()


## Steps a carrot exactly as Projectiles does and returns where it is when it
## has covered `distance` horizontally.
func _fly(origin: Vector3, dir: Vector3, data: WeaponData, distance: float) -> Vector3:
	var g := data.projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))
	var pos := origin
	var vel := dir * data.projectile_speed
	var dt := 1.0 / 60.0
	while Vector2(pos.x - origin.x, pos.z - origin.z).length() < distance:
		pos += vel * dt
		vel.y -= g * dt
	return pos


func test_shots_land_on_the_crosshair_in_range() -> void:
	for id in [&"carrot_pistol", &"carrot_smg", &"carrot_rifle", &"carrot_lmg", &"carrot_shotgun"]:
		var data := WeaponDB.get_weapon(id)
		var origin := Vector3(0, 2, 0)
		var dist := data.falloff_end * 0.9
		var target := origin + Vector3(0, 0, -dist)
		var dir := Projectiles.zeroed(origin, (target - origin).normalized(), dist, data)
		var hit := _fly(origin, dir, data, dist)
		check(absf(hit.y - target.y) < 0.15, "%s: %.0f m out the carrot lands on the crosshair (%.2f m off)" % [id, dist, hit.y - target.y])
		# unzeroed, it would have dropped well below
		var plain := _fly(origin, (target - origin).normalized(), data, dist)
		check(target.y - plain.y > 0.1 or data.projectile_gravity == 0.0, "%s: (without zeroing it drops %.2f m)" % [id, target.y - plain.y])


func test_bursts_bloom_and_settle() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_smg"), 0))
	await wait_physics(30)   # (equip)
	var w := c.current_weapon()
	w.ammo_in_mag = w.magazine_size()
	c.inventory.ammo[w.data.ammo_type] = 999
	c.aim_point = c.get_eye_position() + Vector3(0, 0, -30)
	var calm := c.current_spread_deg()
	c.want_fire = true
	var spreads := []
	var fired := 0
	var frames := 0
	while fired < 14 and frames < 300:
		var before := w.ammo_in_mag
		await wait_physics(1)
		frames += 1
		if w.ammo_in_mag < before:
			fired += 1
			spreads.append(c.current_spread_deg())
	c.want_fire = false
	check(fired >= 14, "the SMG fired a long burst (%d shots)" % fired)
	check(spreads.size() >= 3 and float(spreads[1]) - calm < 0.05, "the first shots of a burst stay tight (%.2f vs %.2f°)" % [float(spreads[1]) if spreads.size() > 1 else -1.0, calm])
	check(float(spreads[spreads.size() - 1]) > calm + 1.5, "holding the trigger spreads them out (%.2f → %.2f°)" % [calm, float(spreads[spreads.size() - 1])])
	await wait_physics(40)   # two thirds of a second off the trigger
	check(c.current_spread_deg() < calm + 0.3, "a short break settles the gun again (%.2f°)" % c.current_spread_deg())


func test_shotgun_pattern() -> void:
	var dir := Vector3(0, 0, -1)
	var n := 9
	var spread := 4.2
	var angles := []
	for i in n:
		var d := Projectiles._pattern_dir(dir, spread, i, n)
		angles.append(rad_to_deg(d.angle_to(dir)))
	check(float(angles[0]) < 0.01, "one pellet straight down the middle")
	for i in range(1, n):
		check(float(angles[i]) <= spread + 0.01 and float(angles[i]) >= spread * 0.5, "pellet %d sits in the ring (%.2f° of %.1f°)" % [i, angles[i], spread])
