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
	# another blast there: the blocks that came down after the others (freed
	# by now) come off its list, not stay on it
	var pile := k.get_node("BlockPile") as BlockPile
	Events.explosion.emit(corner + Vector3(-3, 0, 0), 6.0)
	check(pile.blocks.all(func(b): return is_instance_valid(b)), "nothing freed left on its list")


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
	var body := b.loosen(Vector3.DOWN * 40.0, Vector3.INF, Vector3.ZERO)   # (flat: tumbling, a corner could land beside it first)
	await wait_physics(60)
	check(body != null and c.health < 1000.0 and (c.is_knocked() or c.visual.knocked), "hurt (%.0f) and bowled over" % (1000.0 - c.health))


## Brick City's towers: a course of plastic bricks each, the bricks above
## coming down when a blast knocks one out from under them.
func test_a_brick_tower_comes_down() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var k := ToyProps.brick_tower(rng)
	add_child(k)
	await wait_physics(2)
	var bricks: Array = k.find_children("*", "ToyBlock", true, false)
	check(bricks.size() >= 4 and bricks.all(func(b): return b.get_meta(&"piece", "") == "Brick"), "a brick a course (%d)" % bricks.size())
	check(bricks.filter(func(b): return not (b as ToyBlock).under.is_empty()).size() == bricks.size() - 1, "each on the one under it")
	Events.explosion.emit(Vector3(4.0, 1.5, 0.0), 4.0)
	await wait_physics(30)
	check(k.find_children("*", "ToyBlock", true, false).is_empty() and _loose_count(k) == bricks.size(),
		"its bottom bricks blasted out: the whole tower comes down (%d loose)" % _loose_count(k))
	# what stood on them tips over (it doesn't just drop back onto them and stand)
	await wait_physics(180)
	var top := 0.0
	for b in k.find_children("Loose*", "RigidBody3D", true, false):
		top = maxf(top, (b as RigidBody3D).global_position.y)
	check(top < bricks.size() * 3.0 * 0.5, "it's fallen over: its highest brick %.1f m up (it stood %.0f m)" % [top, bricks.size() * 3.0])


## A loose letter block on the floor: a blast sends it flying.
func test_a_letter_block_is_blasted_about() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var k := ToyProps.letter_block(rng)
	add_child(k)
	await wait_physics(2)
	var n := k.find_children("*", "ToyBlock", true, false).size()
	check(n >= 1, "a block (or two) of its own")
	Events.explosion.emit(Vector3(2.5, 1.0, 0.0), 4.0)
	await wait_physics(10)
	check(_loose_count(k) == n, "blasted loose")


## The block fort: its gate and pillars and courses come apart; the beam over
## the pillars comes down once both are gone.
func test_the_block_fort_comes_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var k := ToyProps.block_fort(rng)
	add_child(k)
	await wait_physics(2)
	var blocks: Array = k.find_children("*", "ToyBlock", true, false)
	check(blocks.size() >= 20, "block by block (%d)" % blocks.size())
	var pillars := blocks.filter(func(b): return b.get_meta(&"piece", "") == "FortPillar")
	var beam: ToyBlock = null
	for b in blocks:
		if (b as ToyBlock).under.size() == 2 and (b as ToyBlock).under.all(func(u): return pillars.has(u)):
			beam = b
	check(pillars.size() == 2 and beam != null, "the beam rests on both pillars")
	pillars[0].loosen(Vector3(30, 0, 0))
	await wait_physics(5)
	check(is_instance_valid(beam) and not beam.loose, "one pillar gone: the beam's still up on the other")
	pillars[1].loosen(Vector3(30, 0, 0))
	await wait_physics(5)
	check(not is_instance_valid(beam) or beam.loose, "both gone: it comes down")


## The log cabin: log by log, wall by wall; the roof on its two gable ends.
func test_the_log_cabin_comes_apart() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var k := ToyProps.log_cabin(rng)
	add_child(k)
	await wait_physics(2)
	var pieces: Array = k.find_children("*", "ToyBlock", true, false)
	var logs := pieces.filter(func(b): return b.get_meta(&"piece", "") == "Log")
	var gables := pieces.filter(func(b): return b.get_meta(&"piece", "") == "Gable")
	var slats := pieces.filter(func(b): return b.get_meta(&"piece", "") == "RoofSlat")
	check(logs.size() >= 20 and gables.size() == 2 and slats.size() == 10, "logs %d, gable ends %d, roof slats %d" % [logs.size(), gables.size(), slats.size()])
	check(slats.all(func(sl): return (sl as ToyBlock).under.size() == 2), "the roof on both gable ends")
	check(gables.all(func(g): return not (g as ToyBlock).under.is_empty()), "the gable ends on their walls")
	# a wall's bottom log out: the logs over it come down
	var bottom: ToyBlock = null
	for l in logs:
		if not (l as ToyBlock).above.is_empty() and (l as ToyBlock).under.is_empty() and absf((l as ToyBlock).position.y - 0.75) < 0.2:
			bottom = l
			break
	check(bottom != null, "a bottom log with logs on it")
	if bottom:
		var above: ToyBlock = bottom.above[0]
		bottom.loosen(Vector3(0, 0, 20))
		await wait_physics(5)
		check(not is_instance_valid(above) or above.loose, "the log over it comes down too")
	gables[0].loosen(Vector3(10, 0, 0))
	await wait_physics(5)
	check(slats.all(func(sl): return is_instance_valid(sl) and not (sl as ToyBlock).loose), "one gable end gone: the roof holds")
	if is_instance_valid(gables[1]) and not gables[1].loose:
		gables[1].loosen(Vector3(-10, 0, 0))
	await wait_physics(5)
	check(slats.all(func(sl): return not is_instance_valid(sl) or (sl as ToyBlock).loose), "both gone: the roof comes down")
