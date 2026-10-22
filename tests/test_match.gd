extends TestCase
## End-to-end smoke test: a real (small) match runs headless — the balloon
## drops everyone, bots loot, fight, and the Briar ends it with one winner.

const GAME := "res://scenes/game.tscn"


func test_full_match_with_bots() -> void:
	Settings.set_value(&"opponents", 7, false)
	Settings.set_value(&"difficulty", Settings.Difficulty.HARD, false)
	Settings.set_value(&"seed", 4242, false)
	Settings.set_value(&"quality", 0, false)
	GameSession.quick = true
	Engine.time_scale = 4.0
	var game: Node = load(GAME).instantiate()
	get_tree().root.add_child(game)
	# wait for loading
	var t := 0.0
	while (game.match_manager == null or game.match_manager.phase == MatchManager.Phase.LOADING) and t < 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var mm: MatchManager = game.match_manager
	check(mm != null and mm.phase == MatchManager.Phase.DROPPING, "match reached the drop")
	if mm == null:
		return
	# the player must be registered (and on the balloon) exactly once
	check(mm.critters.count(mm.player) == 1, "player is in the match exactly once (%d)" % mm.critters.count(mm.player))
	check(mm.dropship.passengers.count(mm.player) <= 1, "player boarded the balloon once")
	var states: Array = []
	mm.player.state_changed.connect(func(st): states.append(st))
	# the player jumps right away and then stands still (a sitting duck)
	await wait_physics(30)
	mm.player_jump()
	var picked := [0]
	Events.item_picked_up.connect(func(_who, _what): picked[0] += 1)
	var deaths := [0]
	Events.critter_died.connect(func(_v, _i): deaths[0] += 1)
	var sim := 0.0
	while sim < 420.0 and mm.phase != MatchManager.Phase.ENDED:
		await get_tree().physics_frame
		sim += 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
		if mm.phase == MatchManager.Phase.DROPPING and sim > 80.0:
			break
	print("    simulated %.0f s: phase=%s pickups=%d deaths=%d alive=%d" % [sim, MatchManager.Phase.keys()[mm.phase], picked[0], deaths[0], mm.alive_critters().size()])
	check(mm.phase != MatchManager.Phase.DROPPING, "everyone left the balloon")
	var landed := states.find(Critter.State.GROUND)
	check(landed >= 0 and not states.slice(landed).has(Critter.State.FREEFALL), "no second drop after landing (states %s)" % [states])
	for c in mm.critters:
		if is_instance_valid(c) and c.alive:
			check(c.state == Critter.State.GROUND, "%s landed (state %d)" % [c.display_name, c.state])
	check(picked[0] >= 4, "bots picked up loot (%d)" % picked[0])
	check(deaths[0] >= 2, "critters fought and died (%d)" % deaths[0])
	Engine.time_scale = 1.0
	game.queue_free()
	await wait_frames(3)
