extends TestCase
## Melee: every critter swings its own species' club (three quarters of its
## height), which hits whoever is in front of it (not behind); with a gun out
## the gun is stowed for the swing and comes back after; bots without a gun brawl.

const TEST_DEF := "res://data/critters/test_critter.tres"
const ROSTER := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]


func before_each() -> void:
	make_arena(60.0)


func test_a_swing_hits_in_front_only() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))   # facing -Z
	await wait_physics(3)
	var reach := me.melee_reach()
	var front := spawn_critter(TEST_DEF, Vector3(0, 0.1, -reach * 0.9), PI)
	var behind := spawn_critter(TEST_DEF, Vector3(0, 0.1, reach * 0.9))
	await wait_physics(3)
	me.want_melee = true
	await wait_physics(2)
	await wait_frames(2)   # (the poser shows the club when the skeleton updates)
	check(me.is_swinging(), "empty paws: the swing starts")
	check(me.visual.club_model != null and me.visual.poser.club, "the club comes out")
	check(me.visual.poser.armed and me.visual.holder.visible, "and is held up in the paws (shown)")
	await wait_physics(int(Critter.MELEE_TIME * Engine.physics_ticks_per_second) + 4)
	check(front.health < front.max_health - 15.0, "the critter in front is clubbed (%.0f hp)" % front.health)
	check(is_equal_approx(behind.health, behind.max_health), "the one behind is not")
	check(not me.is_swinging(), "the swing ends")
	# the trigger swings too, with empty paws (step back in: the hit knocked it away)
	front.place_at(Vector3(0, 0.1, -reach * 0.9), PI)
	await wait_physics(3)
	var hp := front.health
	me.want_fire = true
	await wait_physics(1)
	me.want_fire = false
	await wait_physics(int(Critter.MELEE_TIME * Engine.physics_ticks_per_second) + 4)
	check(front.health < hp, "pulling the trigger with empty paws swings the club")
	# a gun in the paws puts the club away...
	me.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol")))
	await wait_physics(2)
	check(me.visual.club_model == null and me.visual.weapon_model.visible, "picking up a gun puts the club away")
	# ...but the club still swings: the gun is stowed for it and comes straight back
	front.queue_free()   # (two clubbings in, it's had enough)
	var fresh := spawn_critter(TEST_DEF, Vector3(0, 0.1, -reach * 0.9), PI)
	me.place_at(Vector3(0, 0.1, 0))
	await wait_physics(3)
	hp = fresh.health
	me.want_melee = true
	await wait_frames(3)
	check(me.is_swinging() and me.visual.club_model != null, "melee with a gun out swings the club")
	check(not me.visual.weapon_model.visible, "the gun is stowed for the swing")
	var ammo := me.current_weapon().ammo_in_mag
	me.want_fire = true
	await wait_physics(int(Critter.MELEE_TIME * Engine.physics_ticks_per_second) + 4)
	me.want_fire = false
	check(fresh.health < hp, "the bash lands")
	check(me.current_weapon().ammo_in_mag == ammo, "no shots go off mid-swing")
	await wait_physics(int(Critter.QUICK_KEEP * Engine.physics_ticks_per_second) + 4)
	check(me.visual.club_model == null and me.visual.weapon_model.visible, "the gun comes straight back")


func test_the_club_is_put_away_after_a_while() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	me.want_melee = true
	await wait_physics(int((Critter.MELEE_TIME + Critter.MELEE_KEEP) * Engine.physics_ticks_per_second) + 10)
	check(me.visual.club_model == null and not me.visual.poser.armed, "the club goes back after %.0f s" % Critter.MELEE_KEEP)


func test_unarmed_bots_brawl_up_close() -> void:
	var bot := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var foe := spawn_critter(TEST_DEF, Vector3(0, 0.1, -20.0), PI)
	var brain := AIBrain.new()
	bot.add_child(brain)
	brain.set_physics_process(false)
	await wait_physics(3)
	bot.place_at(Vector3(0, 0.1, 0))
	foe.place_at(Vector3(0, 0.1, -bot.melee_reach() * 0.9), PI)
	await wait_physics(2)
	brain.target = foe
	brain._spotted_t = -100.0
	brain.mode = AIBrain.Mode.FIGHT
	brain._fight(1.0 / Engine.physics_ticks_per_second)
	check(bot.want_melee, "a bot with bare paws next to a foe swings")
	foe.place_at(Vector3(0, 0.1, -40.0), PI)
	await wait_physics(2)
	bot.want_melee = false
	brain._fight(1.0 / Engine.physics_ticks_per_second)
	check(not bot.want_melee and brain.mode == AIBrain.Mode.LOOT, "a far-off foe sends it looking for a gun instead")


func test_every_species_has_its_own_club() -> void:
	var names := {}
	for id in ROSTER:
		var d: CritterDef = load("res://data/critters/%s.tres" % id)
		check(d.melee_name != "Club" and not names.has(d.melee_name), "%s has its own named club (%s)" % [id, d.melee_name])
		names[d.melee_name] = true
		check(ResourceLoader.exists(d.melee_model), "%s's club model exists (%s)" % [id, d.melee_model])


func test_clubs_are_three_quarters_of_the_critter() -> void:
	for id in ROSTER:
		var c := spawn_critter("res://data/critters/%s.tres" % id, Vector3(0, 0.1, 0))
		await wait_physics(2)
		c.want_melee = true
		await wait_frames(3)   # (the poser places the club when the skeleton updates)
		var club := c.visual.club_model
		if not check(club != null, "%s pulls out its club" % id):
			continue
		var box := ModelUtil.aabb_of(club)
		var world := club.global_transform.basis.get_scale()
		var length := -box.position.z * world.z
		var height := c.visual.rig.world_head_top
		check_near(length / height, CritterVisual.CLUB_LENGTH, 0.06, "%s's %s is 3/4 of its height" % [id, c.def.melee_name])
		var thick := maxf(box.size.x * world.x, box.size.y * world.y)
		check(thick > height * 0.06, "%s's club is chunky (%.2f m thick for a %.2f m critter)" % [id, thick, height])
		c.queue_free()
		await wait_physics(1)
