class_name Arsenal
extends RefCounted
## Your arsenal: the guns only you carry (WeaponDB.arsenal: the Root Rumbler,
## the Carrot Lobber, the Big Root .50), your answers to a gang and to your
## Doppelbunny. Each is won on the Trail (make the goal in a Grudge Match or a
## Mirror Match: Run) and kept for good. In any match, from your CALL_AT-th
## beat-down, you can call them in once (MatchManager.call_in): a crate drops
## beside you with every one you've won in it, and you take one. No bot ever
## carries one, picks one up or opens that crate (Pickup.anyone_may_take). Kept
## with your profile.

const CALL_AT := 3                      ## beat-downs in a match before you can call it in
const REWARD_KINDS := ["grudge", "mirror"]   ## the Trail stops that win you one (Run.KINDS)
const CALL_HEIGHT := 28.0               ## metres up it drops from
const CALL_FALL := 9.0                  ## m/s (a supply drop drifts down at 3.5)
const CALL_DISTANCE := 6.0              ## metres from you it lands, about


## The guns you've won (ids, in WeaponDB.arsenal order).
static func unlocked() -> Array:
	var have: Array = PlayerProfile._book().get_value("arsenal", "unlocked", [])
	return WeaponDB.arsenal().filter(func(w): return have.has(String(w.id))).map(func(w): return w.id)


## The ones still to win.
static func locked() -> Array:
	var have := unlocked()
	return WeaponDB.arsenal().filter(func(w): return not have.has(w.id)).map(func(w): return w.id)


static func unlock(id: StringName) -> void:
	if WeaponDB.get_weapon(id) == null or not WeaponDB.is_arsenal(WeaponDB.get_weapon(id)):
		return
	var have: Array = PlayerProfile._book().get_value("arsenal", "unlocked", [])
	if not have.has(String(id)):
		have.append(String(id))
		PlayerProfile._book().set_value("arsenal", "unlocked", have)
		PlayerProfile.save()


## What a call-in brings (Pickup specs): every gun you've won, full, one of
## which you take (the rest go back: "one_of"), and a fill of each one's
## carrots. All of it yours alone.
static func call_in_contents() -> Array:
	var out := []
	for id in unlocked():
		var data := WeaponDB.get_weapon(id)
		var spec := Pickup.weapon_spec(WeaponInstance.new(data, Rarity.Tier.PRIZE))
		spec["one_of"] = "call_in"
		out.append(spec)
	var types := {}
	for id in unlocked():
		types[WeaponDB.get_weapon(id).ammo_type] = true
	for t in types:
		var ammo := Pickup.ammo_spec(t, Inventory.AMMO_PICKUP[t] * 2)
		ammo["yours"] = true
		out.append(ammo)
	return out
