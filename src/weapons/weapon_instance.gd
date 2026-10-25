class_name WeaponInstance
extends RefCounted
## A specific gun someone is carrying: shared WeaponData + its rarity and the
## carrots currently loaded.

var data: WeaponData
var rarity: int = Rarity.Tier.BABY
var ammo_in_mag: int = 0
## Carrots per magazine, times this (the holder's Carrot Quiver, Workshop).
var mag_scale := 1.0
## A mutation built into the gun (a nemesis's signature gun: Boons.gun_mutation),
## and whose signature gun it is ("" for an ordinary one).
var mutation := ""
var signature := ""


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
	var n := "%s %s" % [Rarity.NAMES[rarity], data.display_name]
	return "%s's %s" % [signature, n] if signature != "" else n


## The same gun, for a save or a rewind: [data, rarity, carrots loaded, mutation, signature].
func pack() -> Array:
	return [data, rarity, ammo_in_mag, mutation, signature]


static func unpack(g: Array) -> WeaponInstance:
	var w := WeaponInstance.new(g[0], g[1], false)
	w.ammo_in_mag = g[2]
	if g.size() > 4:
		w.mutation = g[3]
		w.signature = g[4]
	return w


## For the profile (a run's keepsake, a bot's stolen gun): plain values.
func to_dict() -> Dictionary:
	return {"id": String(data.id), "rarity": rarity, "mutation": mutation, "signature": signature}


static func from_dict(d: Dictionary) -> WeaponInstance:
	var data_ := WeaponDB.get_weapon(StringName(d.get("id", "")))
	if data_ == null:
		return null
	var w := WeaponInstance.new(data_, int(d.get("rarity", 0)))
	w.mutation = String(d.get("mutation", ""))
	w.signature = String(d.get("signature", ""))
	return w
