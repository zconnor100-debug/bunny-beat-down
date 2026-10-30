extends TestCase
## The Kernel Hunt (KernelHunt): the quest line's acts and your record in
## them, the Touched's look, the tally on the Barn's door, and the prologue
## played through: you and the Barn Rangers at the Big Red Barn, three waves
## of the Touched marching on it, the ones in its yard wearing it down, and
## the ending (MissionOutro): the tally back at zero, the milestone and the
## Gazette's special edition. And the Barn falling.

const GAME := "res://scenes/game.tscn"


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	WarrenSim.reset_for_tests()


func after_each() -> void:
	KernelHunt.playing = ""
	Engine.time_scale = 1.0
	WarrenSim.reset_for_tests()
	await super()


func test_the_quest_line() -> void:
	check(KernelHunt.ACTS.size() == 5 and KernelHunt.ACTS[0].id == "prologue" and KernelHunt.ACTS[0].open, "five acts, the prologue open")
	check(KernelHunt.ACTS.slice(1).all(func(a): return String(a.get("ends", "")) != ""), "the acts each end in a boss")
	check(KernelHunt.ACTS[1].id == "carrot_patch" and KernelHunt.ACTS[1].open and KernelHunt.ACTS[1].get("after") == "prologue",
		"Act I, The Carrot Patch, open after the prologue")
	check(KernelHunt.ACTS.slice(2).all(func(a): return not a.get("open", false)), "the rest sealed")
	check(KernelHunt.unlocked("prologue") and not KernelHunt.unlocked("carrot_patch") and not KernelHunt.unlocked("starfall"),
		"Act I locked till the Barn's held")
	check(KernelHunt.RANGERS.size() == 7 and KernelHunt.RANGERS.all(func(n): return Cast.names().has(n)), "seven rangers, all of the cast")
	var counts := KernelHunt.WAVES.map(func(w): return int(w.count))
	check(counts[0] < counts[1] and counts[1] < counts[2] and KernelHunt.WAVES.back().get("giant", false), "the waves grow; the last brings a giant")
	check(not KernelHunt.done("prologue") and KernelHunt.record_line("prologue") == "Not played yet.", "not played yet")
	KernelHunt.note_result("prologue", {"won": false, "time": 200.0, "barn": 0, "rangers": 3, "touched": 9})
	Mastery.check()
	check(not KernelHunt.done("prologue") and KernelHunt.played("prologue") == 1 and KernelHunt.touched_beaten() == 9
		and not Mastery.has("days_since_brutus"), "played and lost: no milestone")
	KernelHunt.note_result("prologue", {"won": true, "time": 372.0, "barn": 64, "rangers": 5, "touched": 27})
	check(KernelHunt.done("prologue") and KernelHunt.record_line("prologue") == "Held  ·  fastest 6:12  ·  5 of 7 rangers home, at best",
		KernelHunt.record_line("prologue"))
	check(KernelHunt.unlocked("carrot_patch") and KernelHunt.record_line("carrot_patch") == "Not played yet.", "the Barn held: Act I open")
	var fresh := Mastery.check()
	check(fresh.any(func(m): return m.id == "days_since_brutus") and Workshop.owns("coat:touched") and Workshop.earned_only("coat:touched"),
		"held: Days Since Brutus: 0, and the Touched coat")
	check(not Mastery.has("every_ranger_home"), "not every ranger home yet")
	KernelHunt.note_result("prologue", {"won": true, "time": 500.0, "barn": 30, "rangers": 7, "touched": 27})
	check(Mastery.check().any(func(m): return m.id == "every_ranger_home"), "every ranger home: a milestone")
	check(KernelHunt.best("prologue").time == 372.0 and KernelHunt.best("prologue").barn == 64.0, "the best of each kept")
	var page := QuestPanel.new()
	add_child(page)
	await wait_frames(2)
	var labels: Array = page.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(labels.has("The Carrot Patch") and page.find_child("Begin", true, false) != null, "its page: Act I, to play next")
	page.show_act("prologue")
	await wait_frames(1)
	labels = page.find_children("*", "Label", true, false).filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)
	var again := page.find_child("Begin", true, false) as Button
	check(labels.has("Days Since Brutus") and again != null and again.text == "Play it again", "the prologue, to play again")
	page.show_act("starfall")
	await wait_frames(1)
	labels = page.find_children("*", "Label", true, false).filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)
	check(labels.has("Sealed. This part of the hunt comes in a later update."), "the finale, sealed")
	page.queue_free()


func test_the_touched_look() -> void:
	var m := Workshop.coat_material("touched")
	check(m != null and int(m.get_shader_parameter(&"pattern")) == 7 and m.next_pass is ShaderMaterial, "the Touched coat: veins, and their glow")
	check((Workshop.LOOKS.coat.options as Array).any(func(o): return o[0] == "touched" and int(o[2]) < 0), "a coat you earn, not buy")


func test_the_tally_on_the_barn_door() -> void:
	var sign := TallySign.new()
	add_child(sign)
	await wait_frames(1)
	check(sign._number.text == "9" and sign._marks.get_child_count() == 9, "nine days: nine marks (%d)" % sign._marks.get_child_count())
	var tw := sign.wipe_to(0, 0.3)
	await tw.finished
	await wait_frames(2)
	check(sign._number.text == "0" and sign._marks.get_child_count() == 0 and sign.count == 0, "rubbed out: zero")
	sign.queue_free()


func test_the_prologue() -> void:
	var said := []
	var hear := func(_c, text): said.append(text)
	Events.taunt.connect(hear)
	var game: Node = await _start()
	var mm: MatchManager = game.match_manager
	var d: MissionDirector = mm.mission if mm else null
	check(mm != null and mm.mode == "kernel" and d != null and mm.island.seed_value == KernelHunt.SEED, "a Kernel Hunt mission, on its own island")
	if d == null:
		Events.taunt.disconnect(hear)
		game.queue_free()
		return
	mm.player.max_health = 1e6   # (you're not what's tested here)
	mm.player.health = 1e6
	check(mm.dropship == null and (mm.storm == null or not mm.storm.active), "no balloon, no Briar")
	check(d.rangers.size() == 7 and d.rangers.all(func(r): return (r.alive and r.team == 1 and r.state == Critter.State.GROUND
		and r.visual.name_tag != null and r.current_weapon() != null)), "the seven rangers: on your side, on their feet, armed")
	check(mm.player.state == Critter.State.GROUND and mm.player.global_position.distance_to(d.barn_pos) < 40.0, "you, at the Barn")
	check(mm.player.inventory.weapons.filter(func(w): return w != null).size() >= 2, "armed")
	check(d.barn_building != null and d.tally != null and d.tally.get_parent() == d.barn_building and d.tally.count == 9,
		"the tally on the Barn's door: nine days")
	check(d.patch_pos.distance_to(d.barn_pos) > 100.0 and d.bluff_pos.distance_to(d.barn_pos) > 100.0, "the Carrot Patch and Boulder Bluff, out there")
	var bars: Array = game.hud.find_children("*", "", true, false).filter(func(n): return n is MissionBar)
	check(bars.size() == 1 and String(bars[0].status()).begins_with("The Touched come in"), "the Barn on the HUD")
	Engine.time_scale = 4.0
	await _sim(func(): return d.stage == MissionDirector.Stage.WAVE, 40.0)
	check(d.wave == 1 and d.touched_left() == 6, "wave 1: six Touched (%d)" % d.touched_left())
	var touched := mm.alive_critters().filter(func(c): return c.team == 2)
	check(touched.all(func(c): return (String(c.display_name).begins_with("Touched")
		and c.visual.meshes[0].material_overlay == Workshop.coat_material("touched"))), "gold-green, every one")
	var start := _nearest(touched, d.barn_pos)
	await _sim(func(): return false, 6.0)
	var now := _nearest(touched.filter(func(c): return c.alive), d.barn_pos)
	check(now < start - 15.0, "marching on the Barn (%.0f m, then %.0f m)" % [start, now])
	# one in the yard wears it down
	var one: Critter = touched.filter(func(c): return c.alive)[0]
	one.place_at(d.barn_pos + MissionDirector._flat(d.patch_pos - d.barn_pos).normalized() * 12.0)
	var was := d.barn
	d._wear(1.0)
	check(d.in_yard() >= 1 and d.barn < was, "in the yard, it wears the Barn down (%.1f to %.1f)" % [was, d.barn])
	# your side beats each wave down
	for n in [1, 2, 3]:
		if n > 1:
			await _sim(func(): return d.stage == MissionDirector.Stage.WAVE and d.wave == n, 40.0)
			check(d.wave == n and d.touched_left() == int(KernelHunt.WAVES[n - 1].count) + (1 if n == 3 else 0),
				"wave %d: %d Touched (%d)" % [n, int(KernelHunt.WAVES[n - 1].count), d.touched_left()])
		if n == 3:
			check(d.giant != null and d.giant.alive and d.giant.def.body_scale > 1.5 and d.giant.max_health >= 500.0,
				"and a Touched giant, as big as a shed")
		var worn := d.barn
		_beat_wave(mm)
		await _sim(func(): return d.stage != MissionDirector.Stage.WAVE, 5.0)
		if n < 3:
			check(d.stage == MissionDirector.Stage.BREATHER and is_equal_approx(d.barn, minf(100.0, worn + MissionDirector.PATCH_UP))
				and game.find_children("*", "", true, false).any(func(x): return x is SupplyDrop),
				"wave %d held: the Barn patched up (%.0f to %.0f), a crate coming down" % [n, worn, d.barn])
	check(d.stage == MissionDirector.Stage.OUTRO, "the last wave held")
	await _sim(func(): return d._outro != null, 8.0)
	check(d._outro != null and d._outro.playing and get_viewport().get_camera_3d() == d._outro._cam and not game.hud.visible,
		"the ending plays, with its own camera")
	await _sim(func(): return mm.phase == MatchManager.Phase.ENDED, 30.0)
	check(mm.phase == MatchManager.Phase.ENDED and mm.winning_team == 1, "held")
	check(d.tally.count == 0, "the tally, back at zero")
	check(KernelHunt.done("prologue") and Mastery.has("days_since_brutus"), "on your record, with its milestone")
	var ed := WarrenSim.edition()
	check(ed.get("extra", "") == "kernel" and String(ed.stories[0].title) == "THE BARN HOLDS", "the Gazette holds the front page")
	await wait_frames(3)
	var end_labels: Array = game._end.find_children("*", "Label", true, false).map(func(l): return l.text) if game._end else []
	check(end_labels.has("THE BARN HOLDS!"), "and so does the end screen: %s" % [end_labels.slice(0, 3)])
	var lines := []
	for prefix in Cast.KERNEL_LINES:
		lines.append_array(Cast.KERNEL_LINES[prefix])
	var heard := said.filter(func(t): return lines.has(t))
	print("    the rangers said: %s" % [heard])
	check(heard.has(Cast.KERNEL_LINES.kt[0]) and heard.has(Cast.KERNEL_LINES.kr[0]) and heard.has(Cast.KERNEL_LINES.kr[2]),
		"the rangers talk it through, from the tally to the roar")
	Events.taunt.disconnect(hear)
	game.queue_free()
	await wait_frames(5)


func test_the_barn_can_fall() -> void:
	var game: Node = await _start()
	var mm: MatchManager = game.match_manager
	var d: MissionDirector = mm.mission if mm else null
	if not check(d != null, "a mission"):
		game.queue_free()
		return
	mm.player.max_health = 1e6
	mm.player.health = 1e6
	Engine.time_scale = 4.0
	await _sim(func(): return d.stage == MissionDirector.Stage.WAVE, 40.0)
	d.barn = 2.0
	var fwd := MissionDirector._flat(d.patch_pos - d.barn_pos).normalized()
	for c in mm.alive_critters().filter(func(c): return c.team == 2):
		c.place_at(d.barn_pos + fwd * 10.0 + fwd.cross(Vector3.UP) * randf_range(-6.0, 6.0))
	await _sim(func(): return mm.phase == MatchManager.Phase.ENDED, 10.0)
	check(mm.phase == MatchManager.Phase.ENDED and mm.winning_team == 2, "the Touched took the Barn")
	check(not KernelHunt.done("prologue") and KernelHunt.played("prologue") == 1, "played, not held")
	check(not WarrenSim.edition().has("extra"), "no special edition for that")
	await wait_frames(3)
	var end_labels: Array = game._end.find_children("*", "Label", true, false).map(func(l): return l.text) if game._end else []
	check(end_labels.has("THE BARN HAS FALLEN"), "the end screen says so: %s" % [end_labels.slice(0, 3)])
	game.queue_free()
	await wait_frames(5)


## Act I, "The Carrot Patch", played through: the glowing carrots pulled one
## by one, the Patch's rings set alight, Brutus woken at Boulder Bluff (and
## the Warren answering), Brutus beaten, and the ending: Little Bru, and the
## first Kernel.
func test_act_one_the_carrot_patch() -> void:
	var said := []
	var hear := func(_c, text): said.append(text)
	Events.taunt.connect(hear)
	var game: Node = await _start("carrot_patch")
	var mm: MatchManager = game.match_manager
	var d := mm.mission as PatchMission if mm else null
	check(d != null and d.mission == "carrot_patch" and mm.island.seed_value == KernelHunt.SEED, "Act I, on the prologue's island")
	if d == null:
		Events.taunt.disconnect(hear)
		game.queue_free()
		return
	mm.player.max_health = 1e6
	mm.player.health = 1e6
	check(d.tally != null and d.tally.count == 0, "the tally on the Barn's door: nought")
	check(d.rangers.size() == 7 and d.rangers.all(func(r): return r.alive and r.team == 1 and (r.get_node("AIBrain") as AIBrain).escort == mm.player),
		"the seven rangers, sticking by you")
	check(mm.boss != null and mm.boss.state == Boss.State.WAITING and mm.boss.max_health < 30000.0, "Brutus, waiting (%.0f)" % (mm.boss.max_health if mm.boss else 0.0))
	check(d.carrots.size() == PatchMission.CARROTS and not d.carrots[0].lit, "five glowing carrots, none lit while the act's card is up")
	await _sim(func(): return d.carrots[0].lit, PatchMission.FIRST_LIT + 1.0)
	check(d.carrots[0].lit and not d.carrots[1].lit, "then the first lit")
	check(d.carrots[0].is_in_group(&"objectives") and not d.carrots[1].is_in_group(&"objectives"), "the lit one is where to go")
	var guards := mm.alive_critters().filter(func(c): return c.team == 2)
	check(guards.size() >= 2 and guards.all(func(c): return c.global_position.distance_to(d.carrots[0].global_position) < 20.0),
		"the Touched come up round it (%d)" % guards.size())
	var bars: Array = game.hud.find_children("*", "", true, false).filter(func(n): return n is MissionBar)
	check(bars.size() == 1 and bars[0].visible and bars[0]._name.text == "THE GLOWING CARROTS" and String(bars[0].status()).begins_with("Carrot 1 of 5"),
		"the carrots on the HUD: %s" % (bars[0].status() if bars.size() > 0 else ""))
	Engine.time_scale = 4.0
	# pull each in turn (only you, only the lit one)
	for i in PatchMission.CARROTS:
		var c: GlowCarrot = d.carrots[i]
		_beat_wave(mm)
		mm.player.place_at(c.global_position + Vector3(1.0, 0.0, 0.6))
		await _sim(func(): return false, 0.3)
		if i + 1 < PatchMission.CARROTS:
			check(not d.carrots[i + 1].channel(mm.player, 0.5) and not c.channel(d.rangers[0], 0.5), "only you, and only the lit one")
		var tries := 0
		while not c.opened and tries < 400:
			c.channel(mm.player, 1.0 / 60.0)
			await get_tree().physics_frame
			tries += 1
		check(c.opened and d.pulled == i + 1, "carrot %d pulled (%d)" % [i + 1, d.pulled])
		if i + 1 < PatchMission.CARROTS:
			check(d.carrots[i + 1].lit, "the next lit")
	check(d.step == PatchMission.Step.BURN and d.spots.size() == 3 and d.spots.all(func(s): return not s.lit), "then: burn the Patch, three rings")
	# a ring with one of the Touched in it doesn't catch; with only you, it does
	_beat_wave(mm)
	var first: BurnSpot = d.spots[0]
	mm.player.place_at(first.global_position + Vector3(1.0, 0.0, 0.0))
	await _sim(func(): return first.progress > 0.2, 8.0)
	var touched := d._spawn_touched(first.global_position + Vector3(-1.0, 0.0, 0.5), &"carrot_pistol", false, first.global_position, first.global_position)
	touched.max_health = 1e9   # (the rangers would have it down before it's seen to hold the ring)
	touched.health = 1e9
	await _sim(func(): return false, 0.3)
	var held := first.progress
	var stopped := true
	var seen := 0
	for k in 12:
		await _sim(func(): return false, 0.1)
		if first.theirs >= 1:
			seen += 1
			stopped = stopped and absf(first.progress - held) < 0.001
		held = first.progress
	check(seen >= 3 and stopped, "one of the Touched in the ring: it stops (%d ticks seen)" % seen)
	touched.take_damage(DamageInfo.make(1e10, DamageInfo.Kind.BULLET, mm.player, &"carrot_rifle"))
	for s in d.spots:
		mm.player.place_at(s.global_position + Vector3(1.0, 0.0, 0.0))
		await _sim(func():
			_beat_wave(mm)
			return s.lit, 30.0)
		check(s.lit and s.fire != null, "a ring alight")
	check(d.step == PatchMission.Step.WAKE and d.patch_fire != null and bars[0]._name.text == "BOULDER BLUFF", "the whole Patch burns: off to the Bluff")
	# get close to the Bluff and he comes
	var from_bluff := MissionDirector._flat(d.patch_pos - d.bluff_pos).normalized()
	mm.player.place_at(d._ground_at(d.bluff_pos + from_bluff * (PatchMission.WAKE_AT - 15.0)))
	await _sim(func(): return d.step == PatchMission.Step.BOSS, 6.0)
	check(d.step == PatchMission.Step.BOSS and mm.boss.state != Boss.State.WAITING and AIBrain.boss == mm.boss, "Brutus comes for you")
	await _sim(func(): return not d.answered.is_empty(), 25.0)
	check(d.answered.size() == KernelHunt.ANSWER.size() and d.answered.all(func(c): return c.team == 1), "the Warren answers (%d)" % d.answered.size())
	await wait_frames(2)
	var boss_bars: Array = game.hud.find_children("*", "", true, false).filter(func(n): return n is BossBar)
	check(boss_bars.size() == 1 and boss_bars[0].visible and not bars[0].visible, "his bar, up instead of the mission's")
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, mm.player, &"carrot_sniper"))
	check(not mm.boss.alive and mm.phase == MatchManager.Phase.PLAYING, "he's down, and it isn't over")
	await _sim(func(): return d._outro != null, 10.0)
	var o := d._outro as PatchOutro
	check(o != null and o.playing and get_viewport().get_camera_3d() == o._cam and not game.hud.visible, "the ending plays, with its own camera")
	await _sim(func(): return o != null and o.bru != null, 20.0)
	check(o != null and o.bru != null and o.kernel != null and not mm.boss.visible, "he's Little Bru, with the Kernel over him")
	await _sim(func(): return mm.phase == MatchManager.Phase.ENDED, 40.0)
	check(mm.phase == MatchManager.Phase.ENDED and mm.winning_team == 1, "done")
	check(KernelHunt.done("carrot_patch") and Mastery.has("the_first_kernel") and Workshop.owns("kill_fx:embers"), "on your record: The First Kernel, and the Patch fire")
	var ed := WarrenSim.edition()
	check(ed.get("extra", "") == "kernel" and String(ed.stories[0].title) == "BRUTUS IS LITTLE BRU AGAIN", "the Gazette's special edition")
	await wait_frames(3)
	var end_labels: Array = game._end.find_children("*", "Label", true, false).map(func(l): return l.text) if game._end else []
	check(end_labels.has("ACT I COMPLETE!"), "the end screen: %s" % [end_labels.slice(0, 3)])
	var heard := said.filter(func(t): return ["pt", "pc", "pp", "pf", "pl", "pd", "pw", "pb", "pk"].any(func(k): return (Cast.KERNEL_LINES[k] as Array).has(t)))
	print("    they said: %s" % [heard])
	check(heard.has(Cast.KERNEL_LINES.pt[0]) and heard.has(Cast.KERNEL_LINES.pb[1]) and heard.has(Cast.KERNEL_LINES.pk[0]),
		"the rangers talk it through, from the tally to the Kernel")
	Events.taunt.disconnect(hear)
	game.queue_free()
	await wait_frames(5)


## In Act I, going down yourself ends it (nobody else can pull the carrots).
func test_act_one_ends_when_you_go_down() -> void:
	var game: Node = await _start("carrot_patch")
	var mm: MatchManager = game.match_manager
	var d := mm.mission as PatchMission if mm else null
	if not check(d != null, "Act I"):
		game.queue_free()
		return
	Engine.time_scale = 4.0
	await _sim(func(): return d.carrots[0].lit, PatchMission.FIRST_LIT + 1.0)
	var guard: Critter = mm.alive_critters().filter(func(c): return c.team == 2)[0]
	mm.player.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, guard, &"carrot_rifle"))
	await _sim(func(): return mm.phase == MatchManager.Phase.ENDED, 5.0)
	check(mm.phase == MatchManager.Phase.ENDED and mm.winning_team == 2, "you down: it's over")
	check(not KernelHunt.done("carrot_patch") and KernelHunt.played("carrot_patch") == 1, "played, not done")
	check(String(d.result(false, d.report())[0]) == "THE TRAIL WENT COLD", "on the trail: %s" % d.result(false, d.report())[0])
	game.queue_free()
	await wait_frames(5)


## A mission (the prologue, unless it's `id`), loaded and started (everyone at the Barn).
func _start(id := "prologue") -> Node:
	Settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	Settings.set_value(&"quality", 0, false)
	KernelHunt.playing = id
	var game: Node = load(GAME).instantiate()
	get_tree().root.add_child(game)
	var t := 0.0
	while (game.match_manager == null or game.match_manager.phase != MatchManager.Phase.PLAYING) and t < 120.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	return game


## Physics on until `done` (or `seconds` of game time).
func _sim(done: Callable, seconds: float) -> void:
	var sim := 0.0
	while sim < seconds and not done.call():
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second


## Every Touched still standing, beaten down by you.
func _beat_wave(mm: MatchManager) -> void:
	for c in mm.alive_critters().filter(func(c): return c.team == 2):
		c.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, mm.player, &"carrot_rifle"))


func _nearest(list: Array, to: Vector3) -> float:
	var best := INF
	for c in list:
		best = minf(best, MissionDirector._flat((c as Critter).global_position - to).length())
	return best
