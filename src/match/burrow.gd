class_name Burrow
extends RefCounted
## Between matches, in the Burrow: the ACORNS you earn each match (placement,
## beat-downs, revenge on rivals, bounties), the PERKS you unlock with them
## and equip (real power: there's nobody else's fairness to protect in a game
## against bots), UPGRADES to the Burrow itself (a third perk slot), RUN
## MODIFIERS that change a match and how many acorns it pays, and the
## Workshop's gun upgrades and looks (Workshop). Kept with the PlayerProfile
## (a separate file for automated test runs).

const SLOTS := 2                      ## perks you can take into a match (see slots())

const PERKS := {
	"thick_fur": {"name": "Thick Fur", "cost": 60, "text": "Drop in with 50 shield."},
	"pocket_clover": {"name": "Pocket Clovers", "cost": 40, "text": "Start with two lucky clovers."},
	"quick_paws": {"name": "Quick Paws", "cost": 80, "text": "Reload 25% faster."},
	"spring_legs": {"name": "Spring Legs", "cost": 60, "text": "Jump 30% higher."},
	"lucky_start": {"name": "Lucky Start", "cost": 120, "text": "Land holding a carrot gun (at least Prize tier)."},
	"second_wind": {"name": "Second Wind", "cost": 150, "text": "Once a match, a hit that would beat you down leaves you at 1 HP."},
	"light_step": {"name": "Light Step", "cost": 90, "text": "Bots take longer to spot you."},
	"hawk_eye": {"name": "Hawk Eye", "cost": 70, "text": "Enemy name tags show twice as far away."},
	"big_appetite": {"name": "Big Appetite", "cost": 70, "text": "Lucky clovers heal 60 instead of 40."},
	"deep_pockets": {"name": "Deep Pockets", "cost": 60, "text": "Carry half as many spare carrots again."},
	"adrenaline": {"name": "Adrenaline", "cost": 110, "text": "Every beat-down heals you 20 HP."},
	"thorn_coat": {"name": "Thorn Coat", "cost": 90, "text": "The Briar hurts you half as much."},
	"regrowth": {"name": "Regrowth", "cost": 130, "text": "Your shield grows back to 25 when you haven't been hit for 6 seconds."},
	"scavenger": {"name": "Scavenger", "cost": 80, "text": "Critters you beat down drop a lucky clover."},
	"acorn_magnet": {"name": "Acorn Magnet", "cost": 140, "text": "Every match pays 25% more acorns."},
	"bounty_hunter": {"name": "Bounty Hunter", "cost": 100, "text": "Bounties pay double."},
}

## Upgrades to the Burrow itself, bought once.
const UPGRADES := {
	"third_slot": {"name": "A Bigger Burrow", "cost": 250, "text": "Take a third perk into every match."},
}

const MODIFIERS := {
	"low_gravity": {"name": "Low Gravity", "bonus": 1.2, "text": "Everyone jumps and falls like the moon. +20% acorns."},
	"glass_cannon": {"name": "Glass Cannon", "bonus": 1.4, "text": "You deal 50% more damage, and take 50% more. +40% acorns."},
	"golden_hour": {"name": "Golden Hour", "bonus": 0.8, "text": "All loot one rarity better. −20% acorns."},
	"briar_rush": {"name": "Briar Rush", "bonus": 1.5, "text": "The Briar starts closing the moment you land. +50% acorns."},
	"pea_soup": {"name": "Pea Soup", "bonus": 1.25, "text": "Thick fog: everyone sees half as far. +25% acorns."},
	"fragile": {"name": "Fragile Fluff", "bonus": 1.3, "text": "Everyone (you too) has half the health. +30% acorns."},
	"rocket_party": {"name": "Rocket Party", "bonus": 1.15, "text": "Every carrot gun is a rocket launcher. +15% acorns."},
	"most_wanted": {"name": "Most Wanted", "bonus": 1.5, "text": "Every 40 seconds the nearest bots are told where you are. +50% acorns."},
	"stampede": {"name": "Stampede", "bonus": 1.25, "text": "Bots run 20% faster. +25% acorns."},
	"clover_drought": {"name": "Clover Drought", "bonus": 1.2, "text": "Lucky clovers heal half as much. +20% acorns."},
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


## Perks you can take into a match: two, three with A Bigger Burrow.
static func slots() -> int:
	return SLOTS + (1 if unlocked("third_slot") else 0)


## Spend acorns on a perk or a Burrow upgrade. False if it's already yours or
## you're short.
static func unlock(perk: String) -> bool:
	var item: Dictionary = PERKS.get(perk, UPGRADES.get(perk, {}))
	if item.is_empty() or unlocked(perk) or acorns() < int(item.cost):
		return false
	var list: Array = (_book().get_value("burrow", "unlocked", []) as Array).duplicate()
	list.append(perk)
	_book().set_value("burrow", "unlocked", list)
	add_acorns(-int(item.cost))
	return true


static func equipped() -> Array:
	return (_book().get_value("burrow", "equipped", []) as Array).filter(func(p): return unlocked(p)).slice(0, slots())


## Equip or unequip an unlocked perk (at most SLOTS at once). Returns success.
static func set_equipped(perk: String, on: bool) -> bool:
	var list: Array = equipped().duplicate()
	if on:
		if not PERKS.has(perk) or not unlocked(perk) or list.has(perk) or list.size() >= slots():
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
## times the bonuses of the run modifiers you played with (and Acorn Magnet).
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
	var bonus := 1.25 if has_perk("acorn_magnet") else 1.0
	for m in modifiers():
		bonus *= float(MODIFIERS[m].bonus)
	return int(round((base + kills * 5 + revenges * 15) * bonus))
