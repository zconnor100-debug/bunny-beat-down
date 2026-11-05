extends TestCase
## Critter body: animator, hitboxes, damage, ragdoll and dismemberment, using
## the project-owned test mannequin so it never depends on third-party art.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena()


func test_visual_builds_with_rig_roles() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	check(c.visual.rig != null, "rig bound")
	check(c.visual.hitboxes.size() >= 10, "hitboxes built (%d)" % c.visual.hitboxes.size())
	check(c.visual.physical_bones.size() >= 10, "ragdoll bodies built (%d)" % c.visual.physical_bones.size())
	check(c.visual.springs != null, "spring bones for ears/tail")


func test_poser_moves_bones_within_modifier() -> void:
	# get_bone_global_pose() must reflect poses set earlier in the same modifier
	# pass, or the IK chain maths would read stale transforms.
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(2)
	c.look_pitch = 0.6
	c.aim_point = c.get_eye_position() + c.look_direction() * 20.0
	await wait_frames(4)
	var head := c.visual.current_bone_global(c.visual.rig.bone[&"head"])
	var rest: Transform3D = c.visual.rig.rest[&"head"]
	check(head.basis.y.angle_to(rest.basis.y) > 0.2, "head pitched by aim (%.2f rad)" % head.basis.y.angle_to(rest.basis.y))
	# hand should be on the gun grip when armed
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), 0))
	await wait_frames(4)
	var hand_world := c.visual.bone_world_position(&"r_hand")
	var grip_world := c.visual.holder.global_position
	check(hand_world.distance_to(grip_world) < 0.08, "right paw on the grip (%.3f m away)" % hand_world.distance_to(grip_world))


func test_ray_hits_hitbox_area() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(4)
	var from := c.get_chest_position() + Vector3(0, 0, -5)
	var q := PhysicsRayQueryParameters3D.create(from, c.get_chest_position() + Vector3(0, 0, 5), Layers.SHOT_MASK)
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty(), "ray hits the critter")
	if hit:
		check(hit.collider is Area3D and (hit.collider as Node).has_meta(&"critter"), "hit a critter hitbox (%s)" % hit.collider)


func test_projectile_damages_and_kills() -> void:
	var target := spawn_critter(TEST_DEF, Vector3(0, 0.1, -6))
	var shooter := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0)
	var dir := (target.get_chest_position() - shooter.get_chest_position()).normalized()
	var shots := 0
	for i in 24:   # (bot on bot: AIBrain.DAMAGE_BETWEEN_BOTS makes it ~3x the shots)
		if not target.alive:
			break
		Projectiles.fire(shooter, w, shooter.get_chest_position() + dir * 0.5, dir, 0.0, shooter.visual.hitbox_rids)
		shots += 1
		await wait_physics(6)
	check(not target.alive, "target died after pistol hits (hp %.1f)" % target.health)
	check(shots > 8, "bots' shots at each other are softened (%d shots)" % shots)
	check(target.visual.ragdolled, "target went ragdoll")
	check(shooter.kills == 1, "shooter credited with the kill")


func test_a_critter_holds_a_few_carrots_and_works_them_out() -> void:
	var target := spawn_critter(TEST_DEF, Vector3(0, 0.1, -6))
	var shooter := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	target.max_health = 100000.0
	target.health = target.max_health
	await wait_physics(3)
	var pr := Projectiles.instance
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0)
	var dir := (target.get_chest_position() - shooter.get_chest_position()).normalized()
	var shoot := func(n: int) -> void:
		for i in n:
			Projectiles.fire(shooter, w, shooter.get_chest_position() + dir * 0.5, dir, 0.0, shooter.visual.hitbox_rids)
			await wait_physics(4)
	await shoot.call(Projectiles.MAX_IN_ONE + 4)
	check(pr.stuck_in(target) == Projectiles.MAX_IN_ONE, "it holds %d carrots at a time (%d)" % [Projectiles.MAX_IN_ONE, pr.stuck_in(target)])
	check(pr.falling_count() > 0, "the next ones knocked the oldest out, and they're dropping")
	var shown := func() -> int:
		return target.visual.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.has_meta(&"stuck_in") and m.is_visible_in_tree()).size()
	target.visual.set_first_person(true)
	check(shown.call() == 0, "looking out of its eyes, it doesn't see the carrots in it")
	target.visual.set_first_person(false)
	check(shown.call() == Projectiles.MAX_IN_ONE, "back in third person they show again")
	pr._clock += Projectiles.WORK_LOOSE * 1.4   # (a while later)
	await wait_physics(30)
	check(pr.stuck_in(target) == 0, "after a while it's worked them all out")
	await wait_physics(int(Projectiles.FALL_S * 60.0) + 10)
	check(pr.falling_count() == 0, "and they've dropped and gone")
	# a corpse keeps the ones in it
	await shoot.call(3)
	target.health = 1.0
	var info := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, null)
	info.bone_role = &"chest"
	target.take_damage(info)
	await wait_physics(3)
	pr._clock += Projectiles.WORK_LOOSE * 1.4
	await wait_physics(30)
	check(not target.alive and pr.stuck_in(target) == 3, "a corpse keeps the carrots in it (%d)" % pr.stuck_in(target))


func test_a_carrot_in_the_ground_sticks_without_an_error() -> void:
	var shooter := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	var errors := count_errors()
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0)
	var from := shooter.get_chest_position()
	var dir := (Vector3(0, 0, -4) - from).normalized()   # (into the ground a few metres ahead)
	Projectiles.fire(shooter, w, from + dir * 0.5, dir, 0.0, shooter.visual.hitbox_rids)
	await wait_physics(20)
	var logged := errors.done()
	var stuck := get_node("Ground").get_children().filter(func(n): return n.has_meta(&"stuck_in"))
	check(stuck.size() == 1, "the carrot stuck in the ground (%d)" % stuck.size())
	check(logged.is_empty(), "without an error (%s)" % logged)


func test_a_reveal_wears_off_on_time_even_after_a_hitch() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	for m in c.visual.meshes:
		m.material_overlay = null   # (no rim: not one of your opponents)
	var errors := count_errors()
	OS.delay_msec(150)   # (a hitch: after it, the timers' clock, game time, runs ahead of the wall clock)
	c.visual.reveal(0.3)
	check(c.visual.revealed(), "Pack Sense: seen through walls")
	await get_tree().create_timer(0.45, false).timeout
	var logged := errors.done()
	check(not c.visual.revealed(), "the glow comes off on time, even after a hitch")
	check(c.visual.meshes.all(func(m): return m.material_overlay == null), "and it looks as it did")
	check(logged.is_empty(), "without an error (%s)" % logged)


func test_ragdoll_falls_to_ground() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null)
	info.direction = Vector3(1, 0, 0)
	info.impulse = 8.0
	info.bone_role = &"chest"
	c.take_damage(info)
	await wait_physics(120)
	var head := c.visual.bone_world_position(&"head")
	check(head.y < 0.45, "head ends up near the ground (y=%.2f)" % head.y)
	check(head.y > -0.2, "ragdoll did not fall through the floor (y=%.2f)" % head.y)


func test_a_squirrels_tail_goes_with_its_ragdoll() -> void:
	# (its tail and hip bones are roots of their own beside the pelvis: the body
	# flew off without them and the skin stretched across the floor between)
	var c := spawn_critter("res://data/critters/squirrel.tres", Vector3(0, 0.1, 0))
	await wait_physics(3)
	var skel := c.visual.skeleton
	var tail: int = c.visual.rig.chains[&"tail"][0]
	var gap := func() -> float:
		return (skel.global_transform * skel.get_bone_global_pose(tail).origin).distance_to(c.visual.bone_world_position(&"hips"))
	var before: float = gap.call()
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null)
	info.direction = Vector3(0, 0.3, -1).normalized()
	info.impulse = 30.0
	info.bone_role = &"chest"
	info.position = c.get_chest_position()
	c.take_damage(info)
	await wait_physics(60)
	await wait_frames(2)
	check(c.visual.bone_world_position(&"hips").distance_to(Vector3(0, 0.5, 0)) > 0.2, "the body was thrown")
	check(absf(gap.call() - before) < 0.1, "the tail stayed on it (%.2f m from the hips, %.2f before)" % [gap.call(), before])


func test_a_squirrels_eyes_sit_in_its_sockets() -> void:
	# (each eyeball goes in its own socket, up under the brow: +x is its left,
	# it faces +Z. Its left one sat low, the top of the socket showing over it)
	var c := spawn_critter("res://data/critters/squirrel.tres", Vector3(0, 0.1, 0))
	await wait_physics(2)
	var spec: Dictionary = c.visual.rig.data["eye_bulge"]
	var mids := {}   # side -> [sum, count]
	for m: MeshInstance3D in c.visual.meshes:
		var mesh := m.mesh as ArrayMesh
		if mesh == null:
			continue
		var to_skel := EyeBulge._to_skeleton(m, c.visual)
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			if mat == null or mat.resource_name != spec["material"]:
				continue
			for v: Vector3 in mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var p := to_skel * v
				var side := "+x" if p.x >= 0.0 else "-x"
				var s: Array = mids.get(side, [Vector3.ZERO, 0])
				mids[side] = [s[0] + p, s[1] + 1]
	check(mids.size() == 2, "two eyeballs found (%d)" % mids.size())
	for side: String in mids:
		var mid: Vector3 = mids[side][0] / mids[side][1]
		var t: Array = spec["to"][side]
		var goal := Vector3(t[0], t[1], t[2])
		check(mid.distance_to(goal) < 0.003, "the %s eyeball's in its socket (%s, wanted %s)" % [side, mid, goal])
	if mids.size() == 2:
		var left: Vector3 = mids["+x"][0] / mids["+x"][1]
		var right: Vector3 = mids["-x"][0] / mids["-x"][1]
		check(absf(left.y - right.y) < 0.004 and left.y > 0.648,
			"the left one's up under its brow, level with the right (%.3f, %.3f)" % [left.y, right.y])


func test_dismember_spawns_gib_and_hides_limb() -> void:
	Settings.set_value(&"gore", Settings.Gore.BLOOD, false)
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null)
	info.direction = Vector3(1, 0, 0)
	info.bone_role = &"chest"
	c.take_damage(info)
	await wait_physics(2)
	var gibs_before := _count_gibs()
	c.visual.dismember(&"l_upper_arm", Vector3(2, 3, 0))
	await wait_physics(5)
	check(_count_gibs() == gibs_before + 1, "one limb gib spawned")
	var idx: int = c.visual.rig.bone[&"l_upper_arm"]
	check(c.visual.limb_hider.hidden.has(idx), "limb hidden on the corpse")
	check(not c.visual.physical_bones.has(&"l_upper_arm"), "limb ragdoll body removed")
	check(not c.visual.hitboxes.has(&"l_lower_arm"), "limb hitboxes removed")
	await wait_frames(3)
	var hand := c.visual.attachments.get(&"l_hand") as Node3D
	check(hand == null, "attachments in the severed limb were freed")
	# the gib's copy of the body collapses into the cut, so skin weighted partly
	# to the body pinches shut there instead of stretching off in spikes
	var gib: Node = null
	for node in get_tree().root.find_children("*", "RigidBody3D", true, false):
		if node.has_meta(&"gib"):
			gib = node
	var gskel := ModelUtil.find_first(gib, "Skeleton3D") as Skeleton3D
	var cut := gskel.get_bone_global_pose(idx).origin
	var sub := c.visual.rig.subtree(idx)
	var spread := 0.0
	for i in gskel.get_bone_count():
		if not sub.has(i):
			spread = maxf(spread, gskel.get_bone_global_pose(i).origin.distance_to(cut))
	check(spread < 0.01, "the rest of the body sits in the cut (%.3f m away at most)" % spread)


func _count_gibs() -> int:
	var n := 0
	for node in get_tree().root.find_children("*", "RigidBody3D", true, false):
		if node.has_meta(&"gib"):
			n += 1
	return n


func test_scaled_critter_hitboxes_and_ragdoll() -> void:
	# the frog is scaled up a lot: hit capsules and ragdoll bodies inherit that scale
	var c := spawn_critter("res://data/critters/frog.tres", Vector3(0, 0.1, 0))
	await wait_physics(4)
	var want := 0.85 * c.def.body_scale
	check(c.def.body_scale >= 1.4, "frogs are scaled up to be hittable (×%.2f)" % c.def.body_scale)
	check_near(c.visual.rig.world_head_top, want, 0.01, "frog is %.2f m tall" % want)
	var space := get_world_3d().direct_space_state
	# a ray at the top of the (scaled) head must hit, and one well above must miss
	for probe in [[c.visual.rig.world_head_top * 0.92, true], [c.visual.rig.world_head_top * 1.5, false]]:
		var y: float = probe[0]
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, y, -4), Vector3(0, y, 4), Layers.HITBOXES)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		check(hit.is_empty() != probe[1], "ray at y=%.2f %s" % [y, "hits" if probe[1] else "misses"])
	# hit capsules are wider than the body for small critters
	var area: Area3D = c.visual.hitboxes[&"chest"]
	var shape_node := area.get_child(0) as CollisionShape3D
	check(shape_node.global_basis.get_scale().x > c.def.body_scale - 0.05, "hit capsule inherits the body scale (%s)" % shape_node.global_basis.get_scale())
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null)
	info.direction = Vector3(1, 0, 0)
	info.impulse = 8.0
	info.bone_role = &"chest"
	c.take_damage(info)
	await wait_physics(120)
	var head := c.visual.bone_world_position(&"head")
	check(head.y > -0.2 and head.y < 0.6, "scaled ragdoll settles on the ground (head y=%.2f)" % head.y)


## Beaten down, a critter keeps its shape: its ragdoll's bodies, jointed
## round the pose it fell in (not the model's rest pose, which pulled them
## apart and out straight), never get much further apart than they were
## standing. (Before: two and a half to four and a half times as far.)
func test_a_ragdoll_keeps_its_shape() -> void:
	for id in ["bun", "squirrel", "hamster", "frog"]:
		var c := spawn_critter("res://data/critters/%s.tres" % id, Vector3(0, 0.1, 0))
		await wait_physics(10)
		var alive := _span(c)
		var info := DamageInfo.make(5000.0, DamageInfo.Kind.EXPLOSION, null, &"carrot_rocket_launcher")
		info.direction = Vector3(0.3, 0.6, -1).normalized()
		info.impulse = 30.0
		info.dismember_power = 0.0
		info.position = c.get_chest_position()
		c.take_damage(info)
		var most := 0.0
		for i in 240:
			await wait_physics(1)
			most = maxf(most, _span(c))
		check(most < alive * 1.7, "%s: down, as big as it was standing, near enough (%.2f m, %.2f standing)" % [id, most, alive])
		c.queue_free()
		await wait_physics(3)


## How far apart a critter's ragdoll bodies are, the furthest two (standing:
## where its bones are).
func _span(c: Critter) -> float:
	var pts: Array[Vector3] = []
	for pb: PhysicalBone3D in c.visual.physical_bones.values():
		var at := c.visual.skeleton.global_transform * c.visual.current_bone_global(c.visual.skeleton.find_bone(pb.bone_name)).origin
		pts.append(pb.global_position if c.visual.ragdolled else at)
	var most := 0.0
	for a in pts:
		for b in pts:
			most = maxf(most, a.distance_to(b))
	return most
