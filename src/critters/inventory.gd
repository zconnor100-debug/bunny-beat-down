class_name Inventory
extends RefCounted
## Three weapon slots, carrot reserves per ammo type, and clover heals.

signal changed

const SLOTS := 3
const AMMO_CAP := {
	WeaponData.AmmoType.LIGHT: 180,
	WeaponData.AmmoType.SHELLS: 40,
	WeaponData.AmmoType.HEAVY: 300,
	WeaponData.AmmoType.ROCKET: 8,
}
## Carrots in one ammo pickup.
const AMMO_PICKUP := {
	WeaponData.AmmoType.LIGHT: 36,
	WeaponData.AmmoType.SHELLS: 10,
	WeaponData.AmmoType.HEAVY: 60,
	WeaponData.AmmoType.ROCKET: 2,
}
const MAX_CLOVERS := 5

var weapons: Array = [null, null, null]   # Array[WeaponInstance or null]
var ammo := {
	WeaponData.AmmoType.LIGHT: 0,
	WeaponData.AmmoType.SHELLS: 0,
	WeaponData.AmmoType.HEAVY: 0,
	WeaponData.AmmoType.ROCKET: 0,
}
var clovers := 0
## Spare carrots carried, times this (Deep Pockets).
var ammo_cap_scale := 1.0


func first_free_slot() -> int:
	for i in SLOTS:
		if weapons[i] == null:
			return i
	return -1


func has_any_weapon() -> bool:
	for w in weapons:
		if w != null:
			return true
	return false


func weapon_count() -> int:
	var n := 0
	for w in weapons:
		if w != null:
			n += 1
	return n


## Puts a weapon in `slot` (or the first free one); returns whatever was there.
func put_weapon(w: WeaponInstance, slot := -1) -> WeaponInstance:
	if slot < 0:
		slot = first_free_slot()
	if slot < 0:
		slot = 0
	var old: WeaponInstance = weapons[slot]
	weapons[slot] = w
	changed.emit()
	return old


func take_weapon(slot: int) -> WeaponInstance:
	var w: WeaponInstance = weapons[slot]
	weapons[slot] = null
	changed.emit()
	return w


## Adds carrots; returns how many did not fit.
func add_ammo(type: int, amount: int) -> int:
	var cap: int = roundi(AMMO_CAP[type] * ammo_cap_scale)
	var fit := mini(amount, cap - ammo[type])
	ammo[type] += fit
	if fit > 0:
		changed.emit()
	return amount - fit


func take_ammo(type: int, wanted: int) -> int:
	var got := mini(wanted, ammo[type])
	ammo[type] -= got
	if got > 0:
		changed.emit()
	return got


func add_clovers(n: int) -> int:
	var fit := mini(n, MAX_CLOVERS - clovers)
	clovers += fit
	if fit > 0:
		changed.emit()
	return n - fit


## Score used by AI to decide whether a gun on the floor is an upgrade.
static func weapon_score(w: WeaponInstance) -> float:
	if w == null:
		return 0.0
	var base := {&"carrot_pistol": 1.0, &"carrot_smg": 2.0, &"carrot_shotgun": 2.2, &"carrot_rifle": 2.7,
		&"carrot_lmg": 2.6, &"carrot_sniper": 2.3, &"carrot_rocket_launcher": 2.4}
	return base.get(w.data.id, 1.5) * w.damage_scale()
