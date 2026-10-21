class_name WeaponDB
## Loads every WeaponData in res://data/weapons once and hands them out.

const DIR := "res://data/weapons"

static var _all: Array[WeaponData] = []


static func all() -> Array[WeaponData]:
	if _all.is_empty():
		for f in ResourceLoader.list_directory(DIR):
			if f.ends_with(".tres"):
				var w: WeaponData = load(DIR.path_join(f))
				if w:
					_all.append(w)
		_all.sort_custom(func(a, b): return a.id < b.id)
	return _all


static func get_weapon(id: StringName) -> WeaponData:
	for w in all():
		if w.id == id:
			return w
	return null


static func random_weapon(rng: RandomNumberGenerator) -> WeaponData:
	var total := 0.0
	for w in all():
		total += w.loot_weight
	var r := rng.randf() * total
	for w in all():
		r -= w.loot_weight
		if r <= 0.0:
			return w
	return all().back()
