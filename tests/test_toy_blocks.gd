extends TestCase
## Toys that come apart (ToyBlock, BlockPile): Block Castle built block by
## block, solid till a blast knocks the blocks it reaches loose (and what
## rested on them comes down after); a far-off blast leaves it be; a domino a
## carrot tips over knocks the next over, all the way down the run; and a
## block coming down on a critter hurts it and bowls it over.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena()


func _castle() -> CageKit:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var k := ToyProps.block_castle(rng)
	add_child(k)
	k.global_position = Vector3(0, 0, 0)
	return k


func _loose_count(root: Node) -> int:
	return root.find_children("Loose*", "RigidBody3D", true, false).size()


func test_block_castle_is_built_of_blocks_that_rest_on_each_other() -> void:
	var k := _castle()
	await wait_physics(2)
	var blocks: Array = k.find_children("*", "ToyBlock", true, false)
	check(blocks.size() >= 60, "built block by block (%d)" % blocks.size())
	var pile := k.get_node_or_null("BlockPile") as BlockPile
	check(pile != null and pile.blocks.size() == blocks.size(), "one pile holds them all")
	var resting := blocks.filter(func(b): return not (b as ToyBlock).under.is_empty())
	check(resting.size() >= 25, "the upper ones rest on the lower (%d)" % resting.size())


func test_a_blast_knocks_the_blocks_it_reaches_loose_and_what_they_held_comes_down() -> void:
	var k := _castle()
	await wait_physics(2)
	var before: int = k.find_children("*", "ToyBlock", true, false).size()
	Events.explosion.emit(Vector3(60, 1, 0), 6.0)
	await wait_physics(2)
	check(_loose_count(k) == 0, "a blast far off leaves it be")
	# by the corner of the back wall, low down: the tower over it comes down too
	var corner := Vector3(-14.0, 2.0, -14.0)
	Events.explosion.emit(corner + Vector3(-3, 0, 0), 6.0)
	await wait_physics(30)
	var loose := _loose_count(k)
	var left: int = k.find_children("*", "ToyBlock", true, false).size()
	check(loose >= 3 and left == before - loose, "knocked loose: %d, %d still standing" % [loose, left])
	var tower_down := k.find_children("*", "ToyBlock", true, false).all(func(b): return (b as ToyBlock).position.distance_to(Vector3(-14, 10, -14)) > 1.0)
	check(tower_down, "the corner tower came down with what held it up")
	await wait_physics(120)
	var bodies: Array = k.find_children("Loose*", "RigidBody3D", true, false)
	check(bodies.all(func(b): return (b as RigidBody3D).global_position.y > -1.0), "and they lie on the floor, not through it")


func test_a_domino_tipped_over_knocks_the_rest_over() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var run: Array[ToyBlock] = []
	for i in 6:
		var a := i * 0.24
		var d := ToyProps.standing_domino(rng)
		add_child(d)
		d.global_position = Vector3(cos(a) * 24.0, d.size.y * 0.5, sin(a) * 24.0 - 24.0)
		d.rotation.y = -a
		run.append(d)
	await wait_physics(2)
	var first := run[0]
	var tangent := Vector3(-sin(0.0), 0.0, cos(0.0))
	first.loosen(tangent * 12.0, first.global_position + Vector3.UP * 3.0)
	await wait_physics(360)
	var standing := run.filter(func(d): return is_instance_valid(d) and not (d as ToyBlock).loose)
	check(standing.is_empty(), "every domino went over (%d still up)" % standing.size())


func test_a_block_coming_down_on_a_critter_bowls_it_over() -> void:
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	c.max_health = 1000.0
	c.health = 1000.0
	await wait_physics(3)
	var b := ToyProps.letter_piece(4.0, [1, 2, 3, 4, 5, 6])
	add_child(b)
	b.global_position = Vector3(0, 9.0, 0)
	await wait_physics(1)
	var body := b.loosen(Vector3.DOWN * 40.0)
	await wait_physics(60)
	check(body != null and c.health < 1000.0 and (c.is_knocked() or c.visual.knocked), "hurt (%.0f) and bowled over" % (1000.0 - c.health))
