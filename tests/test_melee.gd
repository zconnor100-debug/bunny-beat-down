extends TestCase
## Melee: with empty paws every critter swings its own species' club, which
## hits whoever is in front of it (not behind), and bots without a gun brawl.

const TEST_DEF := "res://data/critters/test_critter.tres"
const ROSTER := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]


func before_each() -> void:
	make_arena(60.0)


func test_a_swing_hits_in_front_only() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))   # facing -Z
	var reach := Critter.MELEE_REACH * 1.0
	await wait_physics(3)
	reach = Critter.MELEE_REACH * me.visual.rig.scale
	var front := spawn_critter(TEST_DEF, Vector3(0, 0.1, -reach * 0.9), PI)
	var behind := spawn_critter(TEST_DEF, Vector3(0, 0.1, reach * 0.9))
	await wait_physics(3)
	me.want_melee = true
	await wait_physics(2)
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
	# a gun in the paws puts the club away, and then there's no swinging
	me.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol")))
	await wait_physics(2)
	check(me.visual.club_model == null, "picking up a gun puts the club away")
	me.want_melee = true
	await wait_physics(2)
	check(not me.is_swinging(), "no club swings with a gun in hand")


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
	foe.place_at(Vector3(0, 0.1, -Critter.MELEE_REACH * bot.visual.rig.scale * 0.9), PI)
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
