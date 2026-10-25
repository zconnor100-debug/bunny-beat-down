class_name Workshop
extends RefCounted
## The Workshop, in the Burrow: carrot-gun upgrades bought with acorns and
## kept for good. ATTACHMENTS change how your guns handle (each one you own
## and fit goes on every gun you pick up); LOOKS are yours to show off: the
## reticle and its colour, the guns' skin, the muzzle flash and smoke, your
## tracers, the burst when you beat a critter down, and your wardrobe: a hat,
## something for your face, your neck and your back (Outfits pieces no rogue
## wears; a cost of -1 means it can only be earned, as a Milestone's reward).
## Kept in the PlayerProfile with the rest of the Burrow.

const ATTACHMENTS := {
	"red_dot": {"name": "Red Dot Sight", "cost": 90,
		"text": "A sight on top of every gun: a red dot to aim with in first person, and aimed shots 25% tighter."},
	"long_mag": {"name": "Carrot Quiver", "cost": 110, "text": "Every magazine holds 30% more carrots."},
	"muffler": {"name": "Muffler", "cost": 100,
		"text": "Bots hear your shots half as far off, and your muzzle flash doesn't give you away."},
	"laser": {"name": "Laser Pointer", "cost": 80, "text": "A red beam on every gun; shots from the hip 20% tighter."},
	"stock": {"name": "Padded Stock", "cost": 70, "text": "Holding the trigger blooms your shots 30% less."},
}

## Each look: its options as [id, name, cost in acorns]; the first is free.
const LOOKS := {
	"reticle": {"label": "Reticle", "options": [["cross", "Cross", 0], ["dot", "Dot", 20], ["circle", "Circle", 30],
		["chevron", "Chevron", 30], ["carrot", "Carrot", 50], ["acorn", "Acorn", 50], ["paw", "Paw print", 60]]},
	"reticle_color": {"label": "Reticle colour", "options": [["white", "White", 0], ["carrot", "Carrot", 15], ["leaf", "Leaf", 15],
		["berry", "Berry", 15], ["sky", "Sky", 15], ["gold", "Gold", 40]]},
	"skin": {"label": "Gun skin", "options": [["stock", "Stock", 0], ["fern_camo", "Fern camo", 60], ["candy", "Candy stripe", 60],
		["midnight", "Midnight", 60], ["bubblegum", "Bubblegum", 60], ["frost", "Frost", 80], ["gilded", "Gilded", 150]]},
	"flash": {"label": "Muzzle flash", "options": [["carrot", "Carrot", 0], ["lime", "Lime", 30], ["blueberry", "Blueberry", 30],
		["plum", "Plum", 30], ["bubblegum", "Bubblegum", 30], ["rainbow", "Rainbow", 80]]},
	"smoke": {"label": "Muzzle smoke", "options": [["none", "None", 0], ["puff", "White puff", 25], ["matching", "Matching colour", 40],
		["spores", "Spore cloud", 60]]},
	"tracer": {"label": "Your tracers", "options": [["cream", "Cream", 0], ["carrot", "Carrot", 25], ["leaf", "Leaf", 25],
		["sky", "Sky", 25], ["plum", "Plum", 25], ["gold", "Gold", 60]]},
	"kill_fx": {"label": "Beat-down burst", "options": [["none", "None", 0], ["confetti", "Confetti", 40],
		["leaves", "Autumn leaves", 40], ["carrots", "Carrot shower", 50], ["hearts", "Hearts", 50]]},
	"wear_hat": {"label": "Hat", "options": [["none", "None", 0], ["flap_beanie", "Ear-flap beanie", 50],
		["flower_crown", "Flower crown", 60], ["santa_hat", "Santa hat", 70], ["fedora", "Fedora", 80],
		["witch_hat", "Witch's hat", 90], ["wizard_hat", "Wizard's hat", 110], ["grad_cap", "Mortarboard", -1],
		["jester_hat", "Jester's cap", -1]]},
	"wear_face": {"label": "Face", "options": [["none", "None", 0], ["heart_glasses", "Heart glasses", 40],
		["glasses_3d", "3D glasses", 40], ["pixel_shades", "Pixel shades", 75],
		["star_glasses", "Star glasses", -1]]},
	"wear_neck": {"label": "Neck", "options": [["none", "None", 0], ["sapphire_necklace", "Sapphire necklace", 50],
		["ring_necklace", "Silver ring necklace", 60]]},
	"wear_back": {"label": "Back", "options": [["none", "None", 0], ["butterfly_wings", "Butterfly wings", 120],
		["jetpack", "Jetpack", 150], ["fairy_wings", "Fairy wings", -1], ["dark_wings", "Dark wings", -1]]},
}

## Your wardrobe's slots, in the order they're shown.
const WARDROBE := ["wear_hat", "wear_face", "wear_neck", "wear_back"]

## The palette the looks pick from.
const COLORS := {
	"white": Color(1, 1, 1), "cream": Color(1.0, 0.9, 0.7), "carrot": Color(1.0, 0.55, 0.12), "leaf": Color(0.45, 0.9, 0.3),
	"berry": Color(1.0, 0.3, 0.35), "sky": Color(0.45, 0.8, 1.0), "gold": Color(1.0, 0.82, 0.25), "lime": Color(0.7, 1.0, 0.25),
	"blueberry": Color(0.35, 0.5, 1.0), "plum": Color(0.75, 0.4, 1.0), "bubblegum": Color(1.0, 0.5, 0.8),
}


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func owns(item: String) -> bool:
	if _free(item):
		return true
	return (_book().get_value("workshop", "owned", []) as Array).has(item)


## An attachment, or a look as "category:id".
static func cost(item: String) -> int:
	if ATTACHMENTS.has(item):
		return int(ATTACHMENTS[item].cost)
	var opt := _option(item)
	return int(opt[2]) if not opt.is_empty() else -1


## Spend acorns on an attachment or a look. False if it's yours already or
## you're short.
static func buy(item: String) -> bool:
	var price := cost(item)
	if price < 0 or owns(item) or Burrow.acorns() < price:
		return false
	var list: Array = (_book().get_value("workshop", "owned", []) as Array).duplicate()
	list.append(item)
	_book().set_value("workshop", "owned", list)
	Burrow.add_acorns(-price)
	if ATTACHMENTS.has(item):
		set_fitted(item, true)
	return true


## Attachments you own are fitted unless you take them off.
static func fitted(att: String) -> bool:
	return owns(att) and not (_book().get_value("workshop", "off", []) as Array).has(att)


static func set_fitted(att: String, on: bool) -> void:
	var off: Array = (_book().get_value("workshop", "off", []) as Array).duplicate()
	off.erase(att)
	if not on:
		off.append(att)
	_book().set_value("workshop", "off", off)
	PlayerProfile.save()


## The option worn for a look (its id).
static func look(category: String) -> String:
	var id := String(_book().get_value("workshop", category, ""))
	if id == "" or not owns("%s:%s" % [category, id]):
		return LOOKS[category].options[0][0]
	return id


## Wear an owned option. False if it isn't yours.
static func set_look(category: String, id: String) -> bool:
	if not owns("%s:%s" % [category, id]):
		return false
	_book().set_value("workshop", category, id)
	PlayerProfile.save()
	return true


static func look_name(category: String, id: String) -> String:
	var opt := _option("%s:%s" % [category, id])
	return opt[1] if not opt.is_empty() else id


## What you're wearing: the Outfits piece in each wardrobe slot, skipping
## the empty ones.
static func outfit() -> Array:
	var out := []
	for cat in WARDROBE:
		var id := look(cat)
		if id != "none":
			out.append(id)
	return out


## Earned only (a Milestone's reward), not for sale.
static func earned_only(item: String) -> bool:
	var opt := _option(item)
	return not opt.is_empty() and int(opt[2]) < 0


static func color(id: String, t := 0.0) -> Color:
	if id == "rainbow":
		return Color.from_hsv(fposmod(t, 1.0), 0.75, 1.0)
	return COLORS.get(id, Color.WHITE)


static func _option(item: String) -> Array:
	var parts := item.split(":")
	if parts.size() != 2 or not LOOKS.has(parts[0]):
		return []
	for o in LOOKS[parts[0]].options:
		if o[0] == parts[1]:
			return o
	return []


static func _free(item: String) -> bool:
	var opt := _option(item)
	return not opt.is_empty() and int(opt[2]) == 0
