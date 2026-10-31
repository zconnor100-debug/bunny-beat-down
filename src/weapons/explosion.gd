class_name Explosion
## Rocket-carrot detonation: falloff damage with cover, a physical shove for
## every ragdoll and loose object nearby, and fireworks. A critter the rocket
## hit square on (`direct`) takes the full splash damage; everyone else takes
## less the further their chest is from the blast, down to none at the edge.

const SELF_DAMAGE_SCALE := 0.5
const COVER_SCALE := 0.3


static func detonate(tree: SceneTree, pos: Vector3, weapon: WeaponInstance, shooter: Node, direct: Critter = null) -> void:
	var data := weapon.data
	var radius := data.splash_radius
	if shooter is Critter and (shooter as Critter).is_player and data.projectile == WeaponData.ProjectileKind.ROCKET:
		radius *= Mastery.blast_scale()   # (Big Bang)
	FX.explosion(pos, radius)
	Audio.play_at(&"explosion", pos, 4.0, 0.1)
	Events.explosion.emit(pos, radius)
	var world := tree.root.get_world_3d()
	var space := world.direct_space_state

	for c in tree.get_nodes_in_group(&"critters"):
		var critter := c as Critter
		if critter == null or not critter.alive:
			continue
		var target := critter.get_chest_position()
		var d := pos.distance_to(target)
		if d > radius and critter != direct:
			continue
		var t := 1.0 if critter == direct else 1.0 - d / radius
		var dmg := data.splash_damage * pow(t, 0.8) * weapon.damage_scale()
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, target, Layers.SIGHT_MASK)
		if critter != direct and space.intersect_ray(q):
			dmg *= COVER_SCALE
		if critter == shooter:
			dmg *= SELF_DAMAGE_SCALE
		var info := DamageInfo.make(dmg, DamageInfo.Kind.EXPLOSION, shooter, data.id)
		info.position = pos
		info.direction = ((target - pos).normalized() + Vector3.UP * 0.7).normalized()
		info.impulse = data.impulse * (0.4 + t)
		info.dismember_power = data.dismember_power * t
		info.bone_role = &"chest"
		critter.take_damage(info)

	# a boss takes the splash where the blast meets it (Boss.receive_blast), and
	# so do the things a mission has you blow up (Act II's winding stations)
	for b in tree.get_nodes_in_group(&"bosses"):
		var boss := b as Boss
		if boss and boss.alive and not (shooter is Critter and (shooter as Critter).team == boss.team):
			boss.receive_blast(pos, radius, data.splash_damage * weapon.damage_scale(), shooter, data.id)
	for t in tree.get_nodes_in_group(&"blast_targets"):
		t.receive_blast(pos, radius, data.splash_damage * weapon.damage_scale(), shooter, data.id)

	# shove ragdolls, gibs and props
	var shape := SphereShape3D.new()
	shape.radius = radius
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis(), pos)
	sq.collision_mask = Layers.RAGDOLL | Layers.DEBRIS
	for r in space.intersect_shape(sq, 96):
		var body: Object = r.collider
		if body is RigidBody3D or body is PhysicalBone3D:
			var bp: Vector3 = (body as Node3D).global_position
			var off := bp - pos
			var t2 := clampf(1.0 - off.length() / radius, 0.0, 1.0)
			var push := (off.normalized() + Vector3.UP * 0.8).normalized() * data.impulse * 0.35 * t2
			if body is RigidBody3D:
				(body as RigidBody3D).apply_central_impulse(push)
			else:
				(body as PhysicalBone3D).apply_central_impulse(push)
			if body is PhysicalBone3D and (body as Node).has_meta(&"critter") and t2 > 0.45:
				var owner_critter: Node = (body as Node).get_meta(&"critter")
				if is_instance_valid(owner_critter):
					owner_critter.blast_corpse(pos, t2)
