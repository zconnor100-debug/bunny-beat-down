class_name LootCrate
extends StaticBody3D
## A garden crate. Opening it pops out a weapon (better odds than floor loot),
## carrots for it, and sometimes a clover or armor.
##
## Containers with an `open_time` (treasure chests) must be *channelled*: the
## opener holds interact and stays put for that long, exposed, while the lid
## creaks open. Letting go, walking off or firing resets the lock.

const MODEL := "res://assets/props/loot_crate.glb"
const CHANNEL_RANGE := 2.6
const CHANNEL_MAX_SPEED := 2.0

## Garden crates are drawn big: you should spot one across a clearing.
const CRATE_SCALE := 2.0

var opened := false
var model_path := MODEL
var model_scale := 1.0      ## the plain garden crate uses CRATE_SCALE (treasure chests their own)
var height := 0.55          ## how tall it stands (what's inside comes out over the top)
var reach := 0.4            ## its middle to its furthest side (it's opened from its side)
var weights: Array = Rarity.CRATE_WEIGHTS
var supply := false         ## landed supply drop: hide the chute, extra loot
var open_time := 0.0        ## seconds to unlock (0 = instant)
var extra_weapons := 0      ## additional guns beyond the first
var contents: Array = []    ## exactly these (Pickup specs) instead of a roll: your call-in (Arsenal)
var player_only := false    ## only you open it (your call-in); bots leave it be
var display_name := "garden crate"
var rng := RandomNumberGenerator.new()
var progress := 0.0         ## 0..1 while being unlocked
var _lid: Node3D
var _last_channel_frame := -10
var _channeler: Node = null


func _ready() -> void:
	add_to_group(&"crates")
	if supply:
		add_to_group(&"supply_crates")
	if open_time > 0.0:
		add_to_group(&"treasure")
	collision_layer = Layers.WORLD
	set_meta(&"surface", &"wood")
	var model := ModelUtil.instantiate(model_path)
	var size := Vector3(0.8, 0.55, 0.55) * model_scale
	if model:
		model.scale = Vector3.ONE * model_scale
		add_child(model)
		_lid = ModelUtil.find_named(model, "Lid")
		var chute := ModelUtil.find_named(model, "Chute")
		if chute:
			chute.get_parent().remove_child(chute)
			chute.free()
		var box := ModelUtil.aabb_of(model)
		if box.size.length() > 0.1:
			size = box.size * model_scale
	else:
		# Fallback only — a plain crate until assets/props/loot_crate.glb exists.
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.38, 0.22)
		bm.material = mat
		mi.mesh = bm
		mi.position.y = size.y * 0.5
		add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y * 0.5
	add_child(cs)
	height = size.y
	reach = maxf(size.x, size.z) * 0.5


## Called every physics tick while `by` holds interact on this container.
## Returns true on the tick it opens. Instant containers open immediately.
func channel(by: Critter, delta: float) -> bool:
	if opened:
		return false
	if open_time <= 0.0:
		open(by)
		return true
	var flat_v := Vector2(by.velocity.x, by.velocity.z).length()
	if by.global_position.distance_to(global_position) > CHANNEL_RANGE * maxf(by.visual.rig.world_scale, 1.0) + reach \
			or flat_v > CHANNEL_MAX_SPEED or by.want_fire or not by.alive:
		return false
	if _channeler != by:
		_channeler = by
		progress = 0.0
		Audio.play_at(&"reload_start", global_position, -2.0, 0.0)
	_last_channel_frame = Engine.get_physics_frames()
	progress = minf(1.0, progress + delta / open_time)
	if _lid:
		# the lid strains against the lock as the critter works it
		_lid.rotation.x = -0.12 * progress + sin(Time.get_ticks_msec() * 0.03) * 0.02 * progress
	if progress >= 1.0:
		open(by)
		return true
	return false


## Who is currently unlocking this (null if nobody this tick).
func channeler() -> Node:
	return _channeler if Engine.get_physics_frames() - _last_channel_frame <= 1 else null


func _physics_process(delta: float) -> void:
	if open_time <= 0.0 or opened or progress <= 0.0:
		return
	if Engine.get_physics_frames() - _last_channel_frame > 1:
		# let go: the lock snaps shut again
		progress = maxf(0.0, progress - delta * 3.0)
		_channeler = null
		if _lid:
			_lid.rotation.x = -0.12 * progress


func open(by: Node) -> void:
	if opened or (player_only and not (by is Critter and (by as Critter).is_player)):
		return
	opened = true
	progress = 1.0
	remove_from_group(&"supply_crates")
	remove_from_group(&"treasure")
	Audio.play_at(&"crate_open", global_position, 3.0 if open_time > 0.0 else 0.0)
	if _lid:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if open_time > 0.0:
		FX.muzzle(global_position + Vector3.UP * height, Vector3.UP, true)   # a puff of golden sparkle
	var parent := get_parent()
	var up := global_transform.basis.y
	if not contents.is_empty():
		_spill(contents, parent, up)
		Events.item_picked_up.emit(by, "crate")
		return
	var tier := Rarity.roll(weights, rng)
	var w := WeaponInstance.new(WeaponDB.random_weapon(rng), tier)
	var specs := [Pickup.weapon_spec(w), Pickup.ammo_spec(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type])]
	if rng.randf() < 0.5 or open_time > 0.0:
		specs.append(Pickup.clover_spec(rng.randi_range(1, 2)))
	if rng.randf() < 0.35 or supply or open_time > 0.0:
		specs.append(Pickup.armor_spec(50.0))
	if rng.randf() < 0.4 or supply:
		specs.append(Pickup.grenade_spec(rng.randi_range(1, 2)))
	var more := extra_weapons + (1 if supply else 0)
	for i in more:
		var w2 := WeaponInstance.new(WeaponDB.random_weapon(rng), Rarity.roll(weights, rng))
		specs.append(Pickup.weapon_spec(w2))
		specs.append(Pickup.ammo_spec(w2.data.ammo_type, Inventory.AMMO_PICKUP[w2.data.ammo_type] * 2))
	_spill(specs, parent, up)
	Events.item_picked_up.emit(by, "crate")


## What's inside, tossed out in a fan in front of it.
func _spill(specs: Array, parent: Node, up: Vector3) -> void:
	for i in specs.size():
		var a := -0.6 + 1.2 * i / maxf(specs.size() - 1, 1)
		var out := global_transform.basis * Vector3(sin(a), 0, cos(a))
		Pickup.spawn(parent, specs[i], global_position + up * (height + 0.25), out * 2.5 + up * 3.5)
