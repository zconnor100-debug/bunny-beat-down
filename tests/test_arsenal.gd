extends TestCase
## Your arsenal (Arsenal, data/arsenal): three guns only you carry, for gangs
## and your Doppelbunny. The Root Rumbler spins up before it fires, tightens
## as it keeps going and slows you down; the Big Root .50 goes through
## critters and thin cover and steadies when you kneel; the Carrot Lobber's
## carrots go off on whoever they hit, or a moment after they land. You win
## them on the Trail (a Grudge or Mirror Match) and call one in from your
## third beat-down, once a match: pick it, throw its flare, and a crate drops
## on the flare with it inside.
## No bot ever picks one up, opens that crate, steals one or keeps one.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	Run.in_match = false


func after_each() -> void:
	Run.in_match = false
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	await super.after_each()


func _gun(id: StringName) -> WeaponInstance:
	return WeaponInstance.new(WeaponDB.get_weapon(id), Rarity.Tier.PRIZE)


func test_three_guns_that_are_yours_alone() -> void:
	var ids := WeaponDB.arsenal().map(func(w): return w.id)
	check(ids == [&"big_root_50", &"carrot_lobber", &"root_rumbler"], "the arsenal: %s" % [ids])
	check(WeaponDB.all().size() == 7 and not WeaponDB.all().any(func(w): return WeaponDB.is_arsenal(w)), "never loot")
	var rng := RandomNumberGenerator.new()
	var rolled := {}
	for i in 400:
		rolled[WeaponDB.random_weapon(rng).id] = true
	check(not rolled.keys().any(func(id): return WeaponDB.is_arsenal(WeaponDB.get_weapon(id))), "no crate ever rolls one")
	make_arena()
	var bot := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var you := spawn_critter(TEST_DEF, Vector3(4, 0.1, 0))
	you.is_player = true
	await wait_physics(3)
	var p := Pickup.spawn(self, Pickup.weapon_spec(_gun(&"root_rumbler")), Vector3(0, 0.3, 2))
	await wait_frames(1)
	check(not p.anyone_may_take() and not p.try_collect(bot) and bot.current_weapon() == null, "a bot can't pick one up")
	var brain := AIBrain.new()
	bot.add_child(brain)
	brain.set_physics_process(false)
	check(brain._find_loot() != p, "or even go for it")
	check(p.try_collect(you) and you.current_weapon().data.id == &"root_rumbler", "you can")
	you.take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, bot))
	await wait_frames(2)
	var dropped := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return (n as Pickup).is_weapon())
	check(dropped.is_empty(), "beaten down, it goes back to the Burrow: nobody finds it on you")
	for i in 3:
		PlayerProfile.note_kill(&"root_rumbler")
	check(PlayerProfile.favourite_gun() == &"", "your Doppelbunny never brings one (your favourite gun leaves them out)")
	Run.start(5)
	Run.choose(Run.choices()[0])
	Run.finish_match(1, 20, 4, true, [_gun(&"root_rumbler"), _gun(&"carrot_rifle")], 3, {})
	var keep: Array = Run.pending().filter(func(r): return r is Dictionary and r.has("keepsake"))
	check(keep.size() == 1 and keep[0].keepsake.size() == 1 and keep[0].keepsake[0].id == "carrot_rifle", "and it's never a keepsake: %s" % [keep])


func test_the_root_rumbler_spins_up_then_mows() -> void:
	make_arena()
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	you.is_player = true
	await wait_physics(3)
	you.give_weapon(_gun(&"root_rumbler"))
	you.inventory.add_ammo(WeaponData.AmmoType.HEAVY, 300)
	await wait_physics(int(Engine.physics_ticks_per_second * 1.0))   # (equipped)
	var shots := [0]
	var count := func(shooter, _o, _id): if shooter == you: shots[0] += 1
	Events.shot_fired.connect(count)
	you.aim_point = you.get_eye_position() + Vector3(0, 0, -20)
	you.want_fire = true
	await wait_physics(int(Engine.physics_ticks_per_second * 0.5))
	check(shots[0] == 0 and you.spin > 0.5 and you.spin < 1.0, "half a second in, the barrels are still winding up (spin %.2f)" % you.spin)
	var wide := you.current_spread_deg()
	await wait_physics(int(Engine.physics_ticks_per_second * 1.5))
	var fired: int = shots[0]
	check(fired >= 14 and fired <= 24, "then it mows: %d carrots in about the next second (1,200 a minute)" % fired)
	check(you.current_spread_deg() < wide * 0.75, "and tightens as it keeps going (%.1f° from %.1f°)" % [you.current_spread_deg(), wide])
	you.move_input = Vector2(0, 1)
	you.want_sprint = true
	await wait_physics(int(Engine.physics_ticks_per_second * 0.5))
	var flat := Vector2(you.velocity.x, you.velocity.z).length()
	check(flat < you.def.move_speed * 0.6, "you can't sprint while it spins, and you're slow (%.1f m/s)" % flat)
	you.want_fire = false
	you.move_input = Vector2.ZERO
	you.want_sprint = false
	Events.shot_fired.disconnect(count)
	await wait_physics(int(Engine.physics_ticks_per_second * 0.6))
	check(you.spin == 0.0, "let go, it runs down")


## A critter facing you `d` metres down the -Z axis.
func _target(d: float) -> Critter:
	return spawn_critter(TEST_DEF, Vector3(0, 0.1, -d), PI)


func _wall(z: float, thick: float) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, thick)
	cs.shape = box
	b.add_child(cs)
	add_child(b)
	b.position = Vector3(0, 1.5, z)


func test_the_big_root_goes_through_them_and_their_cover() -> void:
	make_arena(120.0)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	you.is_player = true
	var a := _target(10.0)
	var b := _target(14.0)
	_wall(18.0 * -1.0, 0.4)
	var c := _target(22.0)
	await wait_physics(3)
	var hp := [a.health, b.health, c.health]
	var big := _gun(&"big_root_50")
	# straight down the line, chest high (aiming at one critter's chest from another's swaying one drifts off the far ones)
	var from := Vector3(0.0, a.get_chest_position().y, -1.0)
	var dir := Vector3(0, 0, -1)
	Projectiles.fire(you, big, from, dir, 0.0, you.visual.hitbox_rids)
	await wait_physics(12)
	check(not a.alive, "one chest hit and it's down")
	check(b.health < hp[1] or not b.alive, "the slug goes on through it into the next (%.0f)" % b.health)
	check(c.health < hp[2] or not c.alive, "and through the 40 cm wall behind them (%.0f)" % c.health)
	# a thick wall stops it
	var d := spawn_critter(TEST_DEF, Vector3(1.5, 0.1, -40.0), PI)
	_wall(-34.0, 1.5)
	await wait_physics(3)
	var hp_d := d.health
	Projectiles.fire(you, big, Vector3(1.5, from.y, -1.0), dir, 0.0, you.visual.hitbox_rids)
	await wait_physics(12)
	check(d.health == hp_d, "but not through a metre and a half of it")
	# it steadies kneeling
	you.give_weapon(big)
	you.want_aim = true
	await wait_physics(int(Engine.physics_ticks_per_second * 1.0))
	var standing := you.current_spread_deg()
	you.want_crouch = true
	await wait_physics(int(Engine.physics_ticks_per_second * 0.5))
	check(standing > 1.0 and you.current_spread_deg() < standing * 0.3, "scoped in, it sways standing (%.1f°) and steadies kneeling (%.1f°)" % [
		standing, you.current_spread_deg()])


## The usual case: the slug beats the first one down, and it falls apart as a
## ragdoll right in the slug's path; it carries on through that too.
func test_the_big_root_goes_on_through_one_it_just_beat_down() -> void:
	make_arena(120.0)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	you.is_player = true
	var a := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, -10.0), PI)
	var b := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, -14.0), PI)
	await wait_physics(3)
	var hp := b.health
	var from := Vector3(0.0, a.get_chest_position().y, -1.0)
	Projectiles.fire(you, _gun(&"big_root_50"), from, Vector3(0, 0, -1), 0.0, you.visual.hitbox_rids)
	await wait_physics(12)
	check(not a.alive, "the first fox is down")
	check(b.health < hp or not b.alive, "and the slug went on through its ragdoll into the next (%.0f of %.0f)" % [b.health, hp])


func test_the_carrot_lobber_lobs_carrots_that_go_off() -> void:
	make_arena()
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	you.is_player = true
	var them := _target(8.0)
	await wait_physics(3)
	var lobber := _gun(&"carrot_lobber")
	var hp := them.health
	# aimed as your shots are: zeroed for the drop onto where you're aiming (their chest)
	var from := Vector3(0.0, you.get_chest_position().y, -0.6)
	var to := Vector3(0.0, them.get_chest_position().y, them.global_position.z)
	var dir := Projectiles.zeroed(from, (to - from).normalized(), from.distance_to(to), lobber.data)
	Projectiles.fire(you, lobber, from, dir, 0.0, you.visual.hitbox_rids)
	await wait_frames(1)
	var flying := get_tree().get_nodes_in_group(&"grenades")
	check(flying.size() == 1 and (flying[0] as Grenade).weapon.data.id == &"carrot_lobber" and is_equal_approx((flying[0] as Grenade).fuse, 1.5),
		"it lobs a carrot bomb, on a short fuse")
	await wait_physics(int(Engine.physics_ticks_per_second * 0.8))
	check(get_tree().get_nodes_in_group(&"grenades").is_empty() and (them.health < hp or not them.alive),
		"that goes off on whoever it hits, at once (%.0f)" % them.health)
	# into the ground in front of you: a moment after it lands
	Projectiles.fire(you, lobber, from, Vector3(0, -0.3, -1).normalized(), 0.0, you.visual.hitbox_rids)
	await wait_physics(int(Engine.physics_ticks_per_second * 1.0))
	check(get_tree().get_nodes_in_group(&"grenades").size() == 1, "on the ground it waits a moment")
	await wait_physics(int(Engine.physics_ticks_per_second * 0.7))
	check(get_tree().get_nodes_in_group(&"grenades").is_empty(), "then goes off")


func _match(opponents: int) -> MatchManager:
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, opponents, 1, 31)
	return mm


func test_won_on_the_trail_then_called_in_once_a_match() -> void:
	# a Grudge Match won: a gun for your arsenal
	var seed_ := 1
	while not Run.generate(seed_)[0].any(func(st): return st.kind == "grudge"):
		seed_ += 1
	Run.start(seed_)
	Run.choose(Run.state().trail[0].map(func(st): return st.kind).find("grudge"))
	Run.finish_match(1, 20, 4, true, [], 3, {})
	var offer: Array = Run.pending().filter(func(r): return r is Dictionary and r.has("arsenal"))
	check(offer.size() == 1 and offer[0].arsenal.size() == 3, "make the goal in a Grudge Match: pick a gun for your arsenal (%s)" % [Run.pending()])
	while not Run.pending().is_empty() and not (Run.pending()[0] is Dictionary and Run.pending()[0].has("arsenal")):
		Run.take_pending()
	Run.take_pending("", {}, &"root_rumbler")
	check(Arsenal.unlocked() == [&"root_rumbler"] and Arsenal.locked().size() == 2, "the Root Rumbler is yours, for good")
	Arsenal.unlock(&"carrot_lobber")
	# a match: not before your third beat-down
	var mm := await _match(4)
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 30.0, c.global_position.z), 0.0)
		if c != you:
			c.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(int(Engine.physics_ticks_per_second * 1.5))
	check(not mm.call_in(), "not before your third beat-down")
	var bots := mm.critters.filter(func(c): return c != you)
	for i in Arsenal.CALL_AT:
		bots[i].take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	await wait_frames(2)
	check(mm.can_call_in() and mm.call_in(), "three beat-downs: call it in")
	check(not mm.call_in(), "(once a match)")
	var drops := get_tree().get_nodes_in_group(&"supply_drops")
	check(drops.size() == 1 and (drops[0] as Node3D).global_position.distance_to(you.global_position) < Arsenal.CALL_HEIGHT + Arsenal.CALL_DISTANCE + 2.0,
		"a crate drops beside you")
	await wait_physics(int(Engine.physics_ticks_per_second * (Arsenal.CALL_HEIGHT / Arsenal.CALL_FALL + 0.5)))
	var crates := get_tree().get_nodes_in_group(&"crates").filter(func(n): return (n as LootCrate).player_only)
	if not check(crates.size() == 1, "it's landed: a crate for you alone (%d)" % crates.size()):
		return
	var crate: LootCrate = crates[0]
	crate.open(bots[3])
	check(not crate.opened, "a bot can't open it")
	crate.open(you)
	await wait_frames(2)
	var guns := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return (n as Pickup).is_weapon() and (n as Pickup).spec.has("one_of"))
	check(guns.size() == 2 and guns.all(func(g): return not (g as Pickup).anyone_may_take()), "inside: both your guns (%d)" % guns.size())
	(guns[0] as Pickup).try_collect(you)
	await wait_frames(2)
	var left := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion() \
		and (n as Pickup).is_weapon() and (n as Pickup).spec.has("one_of"))
	check(left.is_empty() and WeaponDB.is_arsenal(you.current_weapon().data), "you take one; the other goes back (%s)" % you.current_weapon().data.id)


# ---- the Cunning boons: for a gang, and your Doppelbunny --------------------------------------------

## Calling it in by flare: RB brings up the pick of your guns, the D-pad picks
## one out and A takes it: a flare in your paw. Held RB aims it along its arc,
## let go throws it; it lands burning, and a crate with only that gun in it
## (for you alone) comes down on it.
func test_called_in_by_flare() -> void:
	PlayerProfile.reset_for_tests()
	Arsenal.unlock(&"root_rumbler")
	Arsenal.unlock(&"carrot_lobber")
	var mm := await _match(4)
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 30.0, c.global_position.z), 0.0)
		if c != you:
			c.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(int(Engine.physics_ticks_per_second * 1.5))
	var pc := you.get_node("PlayerController") as PlayerController
	var rig := CameraRig.new()   # (as game.gd wires it)
	add_child(rig)
	rig.set_target(you)
	rig.first_person = false
	rig.yaw = you.look_yaw
	rig.pitch = -0.2
	pc.rig = rig
	pc.match_manager = mm
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(not pc.call_menu, "not before your third beat-down")
	var bots := mm.critters.filter(func(c): return c != you)
	for i in Arsenal.CALL_AT:
		bots[i].take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	await wait_frames(2)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	check(pc.call_menu and pc.call_choice == 0, "three beat-downs: RB brings up the pick of your guns")
	await _press(JOY_BUTTON_DPAD_RIGHT)
	check(pc.call_choice == 1 and you.inventory.shields == 0, "the D-pad picks one out (and puts on no shield)")
	var want: StringName = Arsenal.unlocked()[1]
	await _press(JOY_BUTTON_A)
	check(not pc.call_menu and pc.flare_gun == want and not mm.called_in, "A takes it: its flare's in your paw, nothing called in yet")
	await _press(JOY_BUTTON_RIGHT_SHOULDER, 0.5)
	await wait_physics(20)
	check(mm.called_in and pc.flare_gun == &"", "held and let go: the flare's thrown, the call-in spoken for")
	var flares := _all(get_tree().root).filter(func(n): return n is Flare)
	if not check(flares.size() == 1, "one flare, burning (%d)" % flares.size()):
		return
	var flare: Flare = flares[0]
	await wait_physics(int(Engine.physics_ticks_per_second * (Flare.WAIT + 2.5)))
	var drops := get_tree().get_nodes_in_group(&"supply_drops")
	check(drops.size() == 1, "it lands, and a crate's sent down")
	await wait_physics(int(Engine.physics_ticks_per_second * (Arsenal.CALL_HEIGHT / Arsenal.CALL_FALL + 0.5)))
	var crates := get_tree().get_nodes_in_group(&"crates").filter(func(n): return (n as LootCrate).player_only)
	if not check(crates.size() == 1, "landed: a crate for you alone (%d)" % crates.size()):
		return
	var crate: LootCrate = crates[0]
	var gap := Vector2(crate.global_position.x - flare.global_position.x, crate.global_position.z - flare.global_position.z).length()
	check(gap < 1.0, "right on the flare (%.1f m off)" % gap)
	crate.open(you)
	await wait_frames(2)
	var guns := get_tree().get_nodes_in_group(&"pickups").filter(_arsenal_gun)
	check(guns.size() == 1 and ((guns[0] as Pickup).spec.weapon as WeaponInstance).data.id == want and not (guns[0] as Pickup).spec.has("one_of"),
		"inside: the gun you picked, and only that (%d)" % guns.size())
	PlayerProfile.reset_for_tests()


func _arsenal_gun(n: Node) -> bool:
	return (n as Pickup).is_weapon() and WeaponDB.is_arsenal(((n as Pickup).spec.weapon as WeaponInstance).data)


## Your flare's smoke brings the bots that can see it: the nearest few (and
## the gangs they run with) come for the crate and hold round it, one of them
## calling it out; one too far off to see it, or with nothing to fight with,
## stays out of it.
func test_a_flare_brings_them_running() -> void:
	make_arena(500.0)
	var mm := MatchManager.new()
	add_child(mm)
	mm.world_root = self
	var you := spawn_critter(TEST_DEF, Vector3(200, 0.1, 200))   # (well out of their sight)
	you.is_player = true
	mm.player = you
	mm.critters.append(you)
	var at := Vector3(0, 0, -20)
	# near and armed, near and armed, far and armed (but a near one's gang
	# mate), far and armed, near with bare paws
	var spots := [Vector3(40, 0.1, -60), Vector3(-30, 0.1, -50), Vector3(-220, 0.1, 0), Vector3(0, 0.1, 210), Vector3(25, 0.1, -10)]
	var bots: Array[Critter] = []
	for i in spots.size():
		var c := spawn_critter(TEST_DEF, spots[i], 0.0)
		c.display_name = Cast.names()[i]
		if i < 4:
			c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
		var b := AIBrain.new()
		b.name = "AIBrain"
		b.match_manager = mm
		b.skill = 0.8
		c.add_child(b)
		b.set_physics_process(false)   # (only the ones that come move: this arena has no map to roam)
		mm.critters.append(c)
		bots.append(c)
	mm.make_gang([bots[0], bots[2]])
	await wait_physics(3)
	var coming := mm.flare_lit(at)
	check(bots[0] in coming and bots[1] in coming, "the two nearby come for it")
	check(bots[2] in coming, "and the gang mate of one of them, from across the map")
	check(not bots[3] in coming and not bots[4] in coming, "too far off to see it, or nothing to fight with: they stay out of it")
	check(coming.all(func(c): return (c.get_node("AIBrain") as AIBrain).contesting()), "each is on its way")
	for c in coming:
		c.get_node("AIBrain").set_physics_process(true)
	await wait_physics(int(Engine.physics_ticks_per_second * 9.0))
	for c in [bots[0], bots[1]]:
		var d := Vector2(c.global_position.x - at.x, c.global_position.z - at.z).length()
		check(d < AIBrain.CONTEST_FAR + 3.0, "%s holds by the crate (%.1f m off)" % [c.display_name, d])


## A pad button pressed (and let go `hold` seconds later).
func _press(button: JoyButton, hold := 0.05) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await wait_physics(maxi(1, roundi(hold * 60.0)))
	var r := InputEventJoypadButton.new()
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await wait_frames(2)


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


## A bare match: you, and three bots ganged up on you (no brains running).
func _pack() -> Array:
	make_arena(160.0)
	var mm := MatchManager.new()
	add_child(mm)
	mm.world_root = self
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	you.is_player = true
	mm.player = you
	mm.critters.append(you)
	var bots := []
	for i in 3:
		var c := spawn_critter(TEST_DEF, Vector3(-6 + i * 6, 0.1, -18), PI)
		c.display_name = Cast.names()[i]
		var b := AIBrain.new()
		b.name = "AIBrain"
		b.match_manager = mm
		b.skill = 0.8
		c.add_child(b)
		b.set_physics_process(false)
		mm.critters.append(c)
		bots.append(c)
	mm.make_gang(bots)
	await wait_physics(3)
	return [mm, you, bots]


func test_gang_buster_breaks_the_pack() -> void:
	Boons.reset()
	var got := await _pack()
	var mm: MatchManager = got[0]
	var you: Critter = got[1]
	var bots: Array = got[2]
	for b in bots:
		(b.get_node("AIBrain") as AIBrain).target = you
	bots[0].take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	mm._gang_member_down(bots[0])
	check(not bots.slice(1).any(func(b): return (b.get_node("AIBrain") as AIBrain).panicking()), "(without the boon, they hold together)")
	Boons.add("gang_buster")
	bots[1].take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	mm._gang_member_down(bots[1])
	var last := bots[2].get_node("AIBrain") as AIBrain
	check(last.panicking() and last.target != you and last._shy_until > last._clock + 2.5, "Gang Buster: beat one down and the rest panic and run")
	last._act(0.1)
	check(bots[2].want_sprint, "flat out")
	Boons.reset()


func test_pack_sense_shows_you_the_whole_gang() -> void:
	Boons.reset()
	var got := await _pack()
	var mm: MatchManager = got[0]
	var you: Critter = got[1]
	var bots: Array = got[2]
	mm.gang_spotted(bots[0], you)
	check(not bots.any(func(b): return b.visual.revealed()), "(without the boon, walls hide them)")
	Boons.add("pack_sense")
	mm.gang_spotted(bots[0], you)
	check(bots.all(func(b): return b.visual.revealed()), "Pack Sense: one calls you out, and you see them all through walls")
	await get_tree().create_timer(Boons.value("pack_sense") + 0.2, false).timeout
	check(not bots.any(func(b): return b.visual.revealed()), "for %d s" % int(Boons.value("pack_sense")))
	Boons.reset()


func test_cardboard_you_draws_their_fire() -> void:
	Boons.reset()
	Boons.add("cardboard_you")
	var got := await _pack()
	var mm: MatchManager = got[0]
	var you: Critter = got[1]
	var bot: Critter = got[2][1]
	var brain := bot.get_node("AIBrain") as AIBrain
	var rifle := WeaponDB.get_weapon(&"carrot_rifle")
	bot.give_weapon(WeaponInstance.new(rifle))
	bot.inventory.add_ammo(rifle.ammo_type, 60)
	await wait_physics(int(Engine.physics_ticks_per_second * 0.8))
	mm._on_clover_eaten(you)   # (as Events.clover_eaten calls it in a set-up match)
	await wait_frames(1)
	var decoys := get_tree().get_nodes_in_group(&"decoys")
	check(decoys.size() == 1 and (decoys[0] as Decoy).global_position.distance_to(you.global_position) < 0.5, "eat a clover: a cardboard you, where you stood")
	you.place_at(Vector3(9, 0.1, 0), 0.0)   # (you slip away)
	await wait_physics(2)
	brain.target = you
	brain.mode = AIBrain.Mode.FIGHT
	for i in int(Engine.physics_ticks_per_second * 1.0):
		brain._last_seen_t = brain._clock
		brain._last_seen_pos = you.get_chest_position()
		brain._clock += 1.0 / Engine.physics_ticks_per_second
		brain._fight(1.0 / Engine.physics_ticks_per_second)
		await get_tree().physics_frame
	var eye := bot.get_eye_position()
	var to_card := ((decoys[0] as Decoy).aim_point() - eye).normalized()
	var to_you := (you.get_chest_position() - eye).normalized()
	check(bot.look_direction().angle_to(to_card) < bot.look_direction().angle_to(to_you), "the bots after you shoot at it instead")
	await get_tree().create_timer(Boons.value("cardboard_you"), false).timeout
	check(Decoy.fooling(bot) == null, "until it folds over (%d s)" % int(Boons.value("cardboard_you")))
	Boons.reset()


func test_habit_breaker_fools_your_doppelbunny() -> void:
	Boons.reset()
	DoppelData.reset_for_tests()
	# a player who nearly always pushes in
	var rows := PackedFloat32Array()
	for i in 400:
		var f := PackedFloat32Array()
		f.resize(DoppelSense.INPUTS)
		f[11] = 1.0
		var y := PackedFloat32Array()
		y.resize(DoppelSense.LABELS)
		y[0] = 1 if i % 20 != 0 else 3
		rows.append_array(f)
		rows.append_array(y)
	DoppelData.add_match(rows, false)
	Boons.add("habit_breaker")
	make_arena(80.0)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 10))
	you.is_player = true
	spawn_critter(TEST_DEF, Vector3(0, 0.1, -20), PI)
	var rec := DoppelRecorder.new()
	rec.name = "DoppelRecorder"
	you.add_child(rec)
	await wait_physics(5)
	you.move_input = Vector2(0, 1)   # (pushing in, as ever)
	await wait_physics(int(Engine.physics_ticks_per_second * 0.6))
	check(not rec.fooled(), "doing what you always do, it reads you")
	you.move_input = Vector2(-1, 0)  # (circling left: something you rarely do)
	await wait_physics(int(Engine.physics_ticks_per_second * 0.6))
	check(rec.fooled(), "do what you rarely do, and it can't")
	var doppel := spawn_critter(TEST_DEF, Vector3(0, 0.1, -10), PI)
	var brain := DoppelBrain.new()
	brain.net = DoppelNet.new()
	brain.target = you
	doppel.add_child(brain)
	brain.set_physics_process(false)
	brain._decide()
	check(int(brain.picked.get("fooled", 0)) == 1, "your Doppelbunny moves at random, with none of your tricks")
	you.move_input = Vector2.ZERO
	rec.finish()
	DoppelData.reset_for_tests()
	Boons.reset()
