extends TestCase
## Situational awareness: red minimap blips, directional footsteps, enemy
## highlighting, and getting critters out of traps.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena(80.0)


func test_minimap_blips_for_firing_and_nearby_movers() -> void:
	var player := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var near := spawn_critter(TEST_DEF, Vector3(8, 0.1, 0))
	var far := spawn_critter(TEST_DEF, Vector3(30, 0.1, 30))
	var mm := Minimap.new()
	add_child(mm)
	mm.player = player
	await wait_physics(5)
	check(mm.enemy_blips().is_empty(), "standing still and quiet: no blips")
	near.move_input = Vector2(0, 1)
	far.move_input = Vector2(0, 1)
	await wait_physics(20)
	var blips := mm.enemy_blips()
	check(blips.size() == 1 and blips[0].critter == near and blips[0].near, "only the critter walking within 20 m shows (%d)" % blips.size())
	Events.shot_fired.emit(far, far.global_position, &"carrot_pistol")
	blips = mm.enemy_blips()
	var firing := blips.filter(func(b): return b.critter == far)
	check(firing.size() == 1 and firing[0].firing, "a firing critter shows anywhere on the map")
	Events.shot_fired.emit(player, player.global_position, &"carrot_pistol")
	check(mm.enemy_blips().filter(func(b): return b.critter == player).is_empty(), "your own shots never blip")


func test_footsteps_behind_you_are_muffled() -> void:
	var ear := Node3D.new()
	add_child(ear)
	ear.global_transform = Transform3D(Basis(), Vector3(0, 1, 0))   # facing -Z
	Audio.listener = ear
	check(not Audio.is_behind_listener(Vector3(0, 1, -10)), "in front is clear")
	check(Audio.is_behind_listener(Vector3(0, 1, 10)), "behind is muffled")
	check(not Audio.is_behind_listener(Vector3(10, 1, 0)), "to the side stays clear (panning does the work)")
	var p := Audio.play_at(&"footstep_grass", Vector3(0, 1, 10), 0.0, 0.0, {"directional": true, "max_distance": 34.0})
	if p:
		check(p.bus == &"SFXBehind" and is_equal_approx(p.max_distance, 34.0), "directional footstep goes through the muffled bus")
	Audio.listener = null


func test_enemies_get_rim_light_and_name_tag() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(2)
	c.visual.set_enemy_highlight("Sly")
	check(c.visual.meshes[0].material_overlay != null, "rim-light overlay applied")
	check(c.visual.name_tag != null and c.visual.name_tag.text.contains("Sly"), "name tag shows the name")
	var info := DamageInfo.make(999.0, DamageInfo.Kind.BULLET, null)
	info.bone_role = &"chest"
	c.take_damage(info)
	await wait_physics(2)
	check(c.visual.meshes[0].material_overlay == null and c.visual.name_tag == null, "corpses lose the highlight")


func test_far_name_tags_shrink_and_grow_upward() -> void:
	# (Game Note 79: a far-off critter was hidden under its own name tag)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	cam.current = true
	var near := spawn_critter(TEST_DEF, Vector3(0, 0.1, -6))
	var far := spawn_critter(TEST_DEF, Vector3(0, 0.1, -40))
	await wait_physics(2)
	near.visual.set_enemy_highlight("Sly")
	far.visual.set_enemy_highlight("Nutsy")
	await wait_frames(2)
	check_near(near.visual.name_tag.scale.x, 1.0, 0.001, "up close it keeps its full size")
	check(far.visual.name_tag.scale.x < 0.55, "40 m off it's smaller: %.2f" % far.visual.name_tag.scale.x)
	check(far.visual.name_tag.scale.x >= CritterVisual.NAME_TAG_MIN_SCALE, "but never too small to read")
	check(far.visual.name_tag.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM, "a second line (a gang) goes up, not over the critter")
	far.visual.name_tag.modulate = Color(0.85, 0.45, 1.0)
	far.visual.reveal_name_tag(0.05)
	await wait_frames(2)
	await get_tree().create_timer(0.15).timeout
	check(far.visual.name_tag.modulate.is_equal_approx(Color(0.85, 0.45, 1.0)), "after a reveal it goes back to its own colour")


func test_trapped_critter_is_rescued() -> void:
	# a navmesh over the arena, then a tight box of walls around a critter
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navsrc"
	get_node("Ground").add_to_group(&"navsrc")
	region.navigation_mesh = nm
	add_child(region)
	var trap := StaticBody3D.new()
	trap.collision_layer = Layers.WORLD
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3 if side.x != 0 else 1.6, 4.0, 0.3 if side.z != 0 else 1.6)
		cs.shape = box
		cs.position = side * 0.65 + Vector3(0, 2, 0)
		trap.add_child(cs)
	add_child(trap)
	trap.add_to_group(&"navsrc")
	trap.global_position = Vector3(10, 0, 10)
	region.bake_navigation_mesh(false)
	await wait_physics(10)
	var c := spawn_critter(TEST_DEF, Vector3(10, 0.1, 10))
	await wait_physics(5)
	c.move_input = Vector2(0, 1)
	await wait_physics(int(60 * 5.0))
	var out := Vector2(c.global_position.x - 10, c.global_position.z - 10).length()
	check(out > 0.8, "critter was popped out of the trap (%.2f m from the centre)" % out)
