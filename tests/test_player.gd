extends TestCase
## The player's hands-on loop, driven through real input events:
## look at a gun → [E] pick it up, open a crate, walk over ammo, heal.

const BUN := "res://data/critters/bun.tres"

var player: Critter
var pc: PlayerController
var rig: CameraRig


func before_each() -> void:
	make_arena()
	player = spawn_critter(BUN, Vector3(0, 0.1, 0), 0.0)
	pc = PlayerController.new()
	pc.name = "PlayerController"
	player.add_child(pc)
	rig = CameraRig.new()
	add_child(rig)
	rig.set_target(player)
	rig.first_person = false
	pc.rig = rig
	rig.yaw = 0.0
	rig.pitch = -0.25
	await wait_physics(5)


func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await wait_frames(2)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await wait_frames(1)


func test_pick_up_weapon_with_interact() -> void:
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.PRIZE)
	Pickup.spawn(self, Pickup.weapon_spec(w), Vector3(0, 0.3, -1.4))
	await wait_physics(20)
	check(pc.focused_pickup() != null, "the gun in front is focused")
	await _press(&"interact")
	check(player.current_weapon() == w, "picked up and equipped the shotgun")
	check(player.visual.holder.get_child_count() == 1, "gun model is in the paws")


func test_open_crate() -> void:
	var crate := LootCrate.new()
	add_child(crate)
	crate.global_position = Vector3(0, 0, -1.6)
	await wait_physics(20)
	var before := get_tree().get_nodes_in_group(&"pickups").size()
	await _press(&"interact")
	await wait_physics(5)
	check(crate.opened, "crate opened")
	check(get_tree().get_nodes_in_group(&"pickups").size() >= before + 2, "loot popped out")


func test_walk_over_ammo_and_heal() -> void:
	Pickup.spawn(self, Pickup.ammo_spec(WeaponData.AmmoType.SHELLS, 10), player.global_position + Vector3(0, 0.3, 0))
	Pickup.spawn(self, Pickup.clover_spec(2), player.global_position + Vector3(0.3, 0.3, 0))
	await wait_physics(40)
	check(player.inventory.ammo[WeaponData.AmmoType.SHELLS] == 10, "shells collected automatically")
	check(player.inventory.clovers == 2, "clovers collected")
	player.health = 30.0
	await _press(&"heal")
	check_near(player.health, 70.0, 0.01, "a clover heals 40")
	check(player.inventory.clovers == 1, "one clover used")


func test_treasure_chest_needs_a_held_unlock() -> void:
	var chest := TreasureChest.new(false)
	add_child(chest)
	chest.global_position = Vector3(0, 0, -1.6)
	await wait_physics(10)
	# a tap does nothing
	await _press(&"interact")
	await wait_physics(5)
	check(not chest.opened, "a tap doesn't open a treasure chest")
	# holding for most of the time, then letting go, resets the lock
	Input.action_press(&"interact")
	await wait_physics(int(chest.open_time * 60 * 0.6))
	Input.action_release(&"interact")
	check(chest.progress > 0.4 and not chest.opened, "progress builds while held (%.2f)" % chest.progress)
	await wait_physics(40)
	check(chest.progress < 0.05, "letting go resets the lock (%.2f)" % chest.progress)
	# holding for the full time opens it and spills high-tier loot
	var before := get_tree().get_nodes_in_group(&"pickups").size()
	Input.action_press(&"interact")
	await wait_physics(int(chest.open_time * 60) + 10)
	Input.action_release(&"interact")
	check(chest.opened, "held for %.1f s → opened" % chest.open_time)
	var weapons := 0
	var best := 0
	for p in get_tree().get_nodes_in_group(&"pickups"):
		if (p as Pickup).is_weapon():
			weapons += 1
			best = maxi(best, (p as Pickup).rarity_tier())
	check(get_tree().get_nodes_in_group(&"pickups").size() >= before + 4, "chest spills plenty of loot")
	check(weapons >= 2 and best >= Rarity.Tier.PRIZE, "two guns, Prize tier or better (%d guns, best tier %d)" % [weapons, best])
