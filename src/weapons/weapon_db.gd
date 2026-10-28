class_name WeaponDB
## Loads every WeaponData in res://data/weapons once and hands them out (the
## carrot guns: loot). Thrown things (res://data/throwables: the carrot
## grenade) and your arsenal's guns (res://data/arsenal: Arsenal, yours
## alone) are looked up by id too, but are never loot.

const DIR := "res://data/weapons"
const THROWN_DIR := "res://data/throwables"
const ARSENAL_DIR := "res://data/arsenal"

static var _all: Array[WeaponData] = []
static var _thrown: Array[WeaponData] = []
static var _arsenal: Array[WeaponData] = []


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
	for w in thrown():
		if w.id == id:
			return w
	for w in arsenal():
		if w.id == id:
			return w
	return null


static func thrown() -> Array[WeaponData]:
	if _thrown.is_empty():
		for f in ResourceLoader.list_directory(THROWN_DIR):
			if f.ends_with(".tres"):
				var w: WeaponData = load(THROWN_DIR.path_join(f))
				if w:
					_thrown.append(w)
	return _thrown


## The arsenal's guns (Arsenal): only you carry them; no bot picks one up.
static func arsenal() -> Array[WeaponData]:
	if _arsenal.is_empty():
		for f in ResourceLoader.list_directory(ARSENAL_DIR):
			if f.ends_with(".tres"):
				var w: WeaponData = load(ARSENAL_DIR.path_join(f))
				if w:
					_arsenal.append(w)
		_arsenal.sort_custom(func(a, b): return a.id < b.id)
	return _arsenal


static func is_arsenal(data: WeaponData) -> bool:
	return data != null and arsenal().has(data)


## Every random gun is this one (Rocket Party, a run modifier), unless empty.
static var only: StringName = &""


static func random_weapon(rng: RandomNumberGenerator) -> WeaponData:
	if only != &"" and get_weapon(only):
		return get_weapon(only)
	var total := 0.0
	for w in all():
		total += w.loot_weight
	var r := rng.randf() * total
	for w in all():
		r -= w.loot_weight
		if r <= 0.0:
			return w
	return all().back()
