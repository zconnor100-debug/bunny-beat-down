class_name LootCrate
extends StaticBody3D
## A garden crate. Opening it pops out a weapon (better odds than floor loot),
## carrots for it, and sometimes a clover or armor.

const MODEL := "res://assets/props/loot_crate.glb"

var opened := false
var model_path := MODEL
var weights: Array = Rarity.CRATE_WEIGHTS
var supply := false         ## landed supply drop: hide the chute, extra loot
var rng := RandomNumberGenerator.new()
var _lid: Node3D


func _ready() -> void:
	add_to_group(&"crates")
	if supply:
		add_to_group(&"supply_crates")
	collision_layer = Layers.WORLD
	set_meta(&"surface", &"wood")
	var model := ModelUtil.instantiate(model_path)
	var size := Vector3(0.8, 0.55, 0.55)
	if model:
		add_child(model)
		_lid = ModelUtil.find_named(model, "Lid")
		var chute := ModelUtil.find_named(model, "Chute")
		if chute:
			chute.get_parent().remove_child(chute)
			chute.free()
		var box := ModelUtil.aabb_of(model)
		if box.size.length() > 0.1:
			size = box.size
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


func open(by: Node) -> void:
	if opened:
		return
	opened = true
	remove_from_group(&"supply_crates")
	Audio.play_at(&"crate_open", global_position)
	if _lid:
		var tw := create_tween()
		tw.tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var parent := get_parent()
	var up := global_transform.basis.y
	var tier := Rarity.roll(weights, rng)
	var w := WeaponInstance.new(WeaponDB.random_weapon(rng), tier)
	var specs := [Pickup.weapon_spec(w), Pickup.ammo_spec(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type])]
	if rng.randf() < 0.5:
		specs.append(Pickup.clover_spec(rng.randi_range(1, 2)))
	if rng.randf() < 0.35 or supply:
		specs.append(Pickup.armor_spec(50.0))
	if supply:
		var w2 := WeaponInstance.new(WeaponDB.random_weapon(rng), Rarity.roll(weights, rng))
		specs.append(Pickup.weapon_spec(w2))
		specs.append(Pickup.ammo_spec(w2.data.ammo_type, Inventory.AMMO_PICKUP[w2.data.ammo_type] * 2))
	for i in specs.size():
		var a := -0.6 + 1.2 * i / maxf(specs.size() - 1, 1)
		var out := global_transform.basis * Vector3(sin(a), 0, cos(a))
		Pickup.spawn(parent, specs[i], global_position + up * 0.8, out * 2.5 + up * 3.5)
	Events.item_picked_up.emit(by, "crate")
