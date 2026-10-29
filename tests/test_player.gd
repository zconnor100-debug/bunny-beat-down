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


## Ammo, chests and shrines are drawn big, like the guns lying about, so you
## spot them across a clearing; what's in a chest comes out over its top.
func test_loot_is_drawn_big_to_spot_it() -> void:
	var ammo := Pickup.spawn(self, Pickup.ammo_spec(WeaponData.AmmoType.LIGHT, 20), Vector3(6, 0.3, 0))
	ammo.freeze = true
	var crate := LootCrate.new()
	crate.model_scale = LootCrate.CRATE_SCALE
	add_child(crate)
	crate.global_position = Vector3(-8, 0, 0)
	var chest := TreasureChest.new(false)
	add_child(chest)
	chest.global_position = Vector3(-8, 0, 8)
	var golden := TreasureChest.new(true)
	add_child(golden)
	golden.global_position = Vector3(8, 0, 8)
	var shrine := AcornShrine.new()
	add_child(shrine)
	shrine.global_position = Vector3(0, 0, 12)
	await wait_frames(2)
	var box := ModelUtil.aabb_of(ammo._spin)
	check(maxf(box.size.x, box.size.z) > 0.6, "a box of light carrots is drawn big (%.2f m)" % maxf(box.size.x, box.size.z))
	var widths := [crate, chest, golden].map(func(c): return snappedf(c.reach * 2.0, 0.01))
	check(widths[0] > 1.5 and widths[1] > widths[0] and widths[2] > widths[1], "a garden crate, a chest bigger, the golden one bigger still (%s m)" % [widths])
	check(chest.height > 1.2, "a chest stands %.2f m" % chest.height)
	check(shrine.height > 1.7, "a shrine stands %.2f m, its acorn on top" % shrine.height)
	var spilled := []
	chest.open(player)
	for p in get_tree().get_nodes_in_group(&"pickups"):
		if p != ammo:
			spilled.append(p)
	check(not spilled.is_empty() and spilled.all(func(p): return p.global_position.y > chest.height), "the loot comes out over the top, not inside it")


## Acorn Shields: you carry up to three (walk over them) and put one on with J
## or a tap of D-pad →; held, D-pad → swaps the camera's shoulder instead.
## With three in hand, the next one goes straight on.
func test_carry_and_put_on_acorn_shields() -> void:
	player.armor = 0.0
	for i in 4:
		Pickup.spawn(self, Pickup.armor_spec(50.0), player.global_position + Vector3(0.25 * i, 0.3, 0))
	await wait_physics(40)
	check(player.inventory.shields == Inventory.MAX_SHIELDS, "three carried (%d)" % player.inventory.shields)
	check_near(player.armor, Inventory.SHIELD_ARMOR, 0.01, "the fourth went straight on")
	player.armor = 0.0
	await _press(&"shield")
	check(player.inventory.shields == 2 and is_equal_approx(player.armor, Inventory.SHIELD_ARMOR), "J puts one on")
	player.armor = 0.0
	await _pad(JOY_BUTTON_DPAD_RIGHT, 0.05)
	check(player.inventory.shields == 1 and is_equal_approx(player.armor, Inventory.SHIELD_ARMOR), "a tap of D-pad → puts one on")
	var shoulder := rig.shoulder
	player.armor = 0.0
	await _pad(JOY_BUTTON_DPAD_RIGHT, PlayerController.SHOULDER_HOLD + 0.2)
	check(rig.shoulder == -shoulder and player.inventory.shields == 1 and player.armor == 0.0, "held, it swaps the shoulder (and keeps the shield)")
	player.armor = player.max_armor
	await _press(&"shield")
	check(player.inventory.shields == 1, "not wasted on full armor")


func _pad(button: JoyButton, hold: float) -> void:
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


## On a pad LB throws grenades (hold to aim, let go to throw); LB + RB
## together still calls your arsenal in, so a grenade LB began to ready goes
## away again; Y is the previous gun now.
func test_lb_throws_a_grenade() -> void:
	player.inventory.grenades = 2
	var slot := player.current_slot
	var lb := _button(JOY_BUTTON_LEFT_SHOULDER)
	Input.parse_input_event(lb)
	await wait_frames(2)
	check(pc.readying_grenade, "LB readies a throw")
	var rb := _button(JOY_BUTTON_RIGHT_SHOULDER)
	Input.parse_input_event(rb)
	await wait_frames(2)
	check(not pc.readying_grenade and player.current_slot == slot, "LB + RB is the call-in chord: no grenade, no gun change")
	for e: InputEventJoypadButton in [lb, rb]:
		var up := e.duplicate() as InputEventJoypadButton
		up.pressed = false
		Input.parse_input_event(up)
	await wait_physics(10)
	check(player.inventory.grenades == 2, "and nothing was thrown")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, 0.5)
	await wait_physics(5)
	check(player.inventory.grenades == 1, "LB held and let go throws one (%d left)" % player.inventory.grenades)
	check(InputMap.action_has_event(&"weapon_prev", _button(JOY_BUTTON_Y)) and InputMap.action_has_event(&"grenade", _button(JOY_BUTTON_LEFT_SHOULDER)),
		"Y is the previous gun, LB the grenade")


func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	return e


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
	# (ammo and clovers that land on the Bun are scooped up straight away: count those too)
	var scooped := [0]
	var count_scoop := func(_c, _label): scooped[0] += 1
	Events.item_picked_up.connect(count_scoop)
	Input.action_press(&"interact")
	await wait_physics(int(chest.open_time * 60) + 10)
	Input.action_release(&"interact")
	Events.item_picked_up.disconnect(count_scoop)
	check(chest.opened, "held for %.1f s → opened" % chest.open_time)
	var weapons := 0
	var best := 0
	for p in get_tree().get_nodes_in_group(&"pickups"):
		if (p as Pickup).is_weapon():
			weapons += 1
			best = maxi(best, (p as Pickup).rarity_tier())
	check(get_tree().get_nodes_in_group(&"pickups").size() + scooped[0] >= before + 4, "chest spills plenty of loot")
	check(weapons >= 2 and best >= Rarity.Tier.PRIZE, "two guns, Prize tier or better (%d guns, best tier %d)" % [weapons, best])


func test_hold_to_aim_a_grenade_let_go_to_throw() -> void:
	player.inventory.grenades = 2
	var e := InputEventAction.new()
	e.action = &"grenade"
	e.pressed = true
	Input.parse_input_event(e)
	await wait_physics(4)
	check(pc.readying_grenade, "holding the grenade button readies a throw")
	check(pc._arc != null and pc._arc.visible, "and shows the arc")
	check(not player.is_throwing() and player.inventory.grenades == 2, "nothing's thrown yet")
	var r := InputEventAction.new()
	r.action = &"grenade"
	r.pressed = false
	Input.parse_input_event(r)
	await wait_physics(2)
	check(player.is_throwing() and player.inventory.grenades == 1, "letting go throws one")
	check(not pc._arc.visible, "and the arc goes away")
	await wait_physics(int(Critter.THROW_TIME * Engine.physics_ticks_per_second) + 2)
	check(get_tree().get_nodes_in_group(&"grenades").size() == 1, "it's on its way")
	player.inventory.grenades = 0
	await _press(&"grenade")
	check(not pc.readying_grenade, "with none left, nothing to ready")
