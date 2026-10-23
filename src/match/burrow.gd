class_name Burrow
extends RefCounted
## Between matches, in the Burrow: the ACORNS you earn each match (placement,
## beat-downs, revenge on rivals), the PERKS you unlock with them and equip
## (real power: there's nobody else's fairness to protect in a game against
## bots), and RUN MODIFIERS that change a match and how many acorns it pays.
## Kept with the PlayerProfile (a separate file for automated test runs).

const SLOTS := 2                      ## perks you can take into a match

const PERKS := {
	"thick_fur": {"name": "Thick Fur", "cost": 60, "text": "Drop in with 50 shield."},
	"pocket_clover": {"name": "Pocket Clovers", "cost": 40, "text": "Start with two lucky clovers."},
	"quick_paws": {"name": "Quick Paws", "cost": 80, "text": "Reload 25% faster."},
	"spring_legs": {"name": "Spring Legs", "cost": 60, "text": "Jump 30% higher."},
	"lucky_start": {"name": "Lucky Start", "cost": 120, "text": "Land holding a carrot gun (at least Prize tier)."},
	"second_wind": {"name": "Second Wind", "cost": 150, "text": "Once a match, a hit that would beat you down leaves you at 1 HP."},
	"light_step": {"name": "Light Step", "cost": 90, "text": "Bots take longer to spot you."},
	"hawk_eye": {"name": "Hawk Eye", "cost": 70, "text": "Enemy name tags show twice as far away."},
}

const MODIFIERS := {
	"low_gravity": {"name": "Low Gravity", "bonus": 1.2, "text": "Everyone jumps and falls like the moon. +20% acorns."},
	"glass_cannon": {"name": "Glass Cannon", "bonus": 1.4, "text": "You deal 50% more damage, and take 50% more. +40% acorns."},
	"golden_hour": {"name": "Golden Hour", "bonus": 0.8, "text": "All loot one rarity better. −20% acorns."},
	"briar_rush": {"name": "Briar Rush", "bonus": 1.5, "text": "The Briar starts closing the moment you land. +50% acorns."},
}


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func acorns() -> int:
	return int(_book().get_value("burrow", "acorns", 0))


static func add_acorns(n: int) -> void:
	_book().set_value("burrow", "acorns", maxi(0, acorns() + n))
	PlayerProfile.save()


static func unlocked(perk: String) -> bool:
	return (_book().get_value("burrow", "unlocked", []) as Array).has(perk)


## Spend acorns on a perk. False if it's already yours or you're short.
static func unlock(perk: String) -> bool:
	if not PERKS.has(perk) or unlocked(perk) or acorns() < int(PERKS[perk].cost):
		return false
	var list: Array = (_book().get_value("burrow", "unlocked", []) as Array).duplicate()
	list.append(perk)
	_book().set_value("burrow", "unlocked", list)
	add_acorns(-int(PERKS[perk].cost))
	return true


static func equipped() -> Array:
	return (_book().get_value("burrow", "equipped", []) as Array).filter(func(p): return unlocked(p))


## Equip or unequip an unlocked perk (at most SLOTS at once). Returns success.
static func set_equipped(perk: String, on: bool) -> bool:
	var list: Array = equipped().duplicate()
	if on:
		if not unlocked(perk) or list.has(perk) or list.size() >= SLOTS:
			return false
		list.append(perk)
	else:
		list.erase(perk)
	_book().set_value("burrow", "equipped", list)
	PlayerProfile.save()
	return true


static func has_perk(perk: String) -> bool:
	return equipped().has(perk)


static func modifiers() -> Array:
	return _book().get_value("burrow", "modifiers", []) as Array


static func modifier_on(mod: String) -> bool:
	return modifiers().has(mod)


static func set_modifier(mod: String, on: bool) -> void:
	var list: Array = modifiers().duplicate()
	if on and not list.has(mod) and MODIFIERS.has(mod):
		list.append(mod)
	elif not on:
		list.erase(mod)
	_book().set_value("burrow", "modifiers", list)
	PlayerProfile.save()


## Acorns a match pays: by placement, 5 a beat-down, 15 a revenge on a rival,
## times the bonuses of the run modifiers you played with.
static func reward(placement: int, total: int, kills: int, revenges: int) -> int:
	var base := 5
	if placement == 1:
		base = 50
	elif placement <= maxi(2, total / 10):
		base = 30
	elif placement <= maxi(3, total / 4):
		base = 18
	elif placement <= total / 2:
		base = 10
	var bonus := 1.0
	for m in modifiers():
		bonus *= float(MODIFIERS[m].bonus)
	return int(round((base + kills * 5 + revenges * 15) * bonus))
