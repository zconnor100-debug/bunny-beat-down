class_name WeaponInstance
extends RefCounted
## A specific gun someone is carrying: shared WeaponData + its rarity and the
## carrots currently loaded.

var data: WeaponData
var rarity: int = Rarity.Tier.BABY
var ammo_in_mag: int = 0
## Carrots per magazine, times this (the holder's Carrot Quiver, Workshop).
var mag_scale := 1.0


func _init(data_: WeaponData = null, rarity_: int = 0, full := true) -> void:
	data = data_
	rarity = rarity_
	if data and full:
		ammo_in_mag = magazine_size()


func magazine_size() -> int:
	return maxi(1, roundi(data.magazine * Rarity.MAGAZINE[rarity] * mag_scale))


func damage_scale() -> float:
	return Rarity.DAMAGE[rarity]


func reload_time() -> float:
	return data.reload_time * Rarity.RELOAD[rarity]


func display_name() -> String:
	return "%s %s" % [Rarity.NAMES[rarity], data.display_name]
