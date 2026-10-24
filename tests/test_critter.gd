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
