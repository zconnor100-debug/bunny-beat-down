class_name Workshop
extends RefCounted
## The Workshop, in the Burrow: carrot-gun upgrades bought with acorns and
## kept for good. ATTACHMENTS change how your guns handle (each one you own
## and fit goes on every gun you pick up); LOOKS are yours to show off: the
## reticle and its colour, the guns' skin, the muzzle flash and smoke, your
## tracers, the burst when you beat a critter down, and your wardrobe: a hat,
## something for your face, your neck and your back (Outfits pieces no rogue
## wears; a cost of -1 means it can only be earned, as a Milestone's reward),
## and a coat over your fur and all of it (coat_material).
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
		["berry", "Berry", 15], ["sky", "Sky", 15], ["gold", "Gold", 40], ["ruby", "Ruby", -1]]},
	"skin": {"label": "Gun skin", "options": [["stock", "Stock", 0], ["fern_camo", "Fern camo", 60], ["candy", "Candy stripe", 60],
		["midnight", "Midnight", 60], ["bubblegum", "Bubblegum", 60], ["frost", "Frost", 80], ["gilded", "Gilded", 150],
		["ruby", "Ruby", -1], ["toxic", "Toxic stripe", -1], ["ember", "Ember", -1], ["jade", "Jade", -1], ["obsidian", "Obsidian", -1],
		["pearl", "Pearl", -1], ["royal", "Royal", -1], ["zebra", "Zebra stripe", -1], ["carrot_king", "Carrot King", -1],
		["sapphire", "Sapphire", -1], ["diamond", "Diamond", -1], ["looking_glass", "Looking Glass", -1]]},
	"flash": {"label": "Muzzle flash", "options": [["carrot", "Carrot", 0], ["lime", "Lime", 30], ["blueberry", "Blueberry", 30],
		["plum", "Plum", 30], ["bubblegum", "Bubblegum", 30], ["rainbow", "Rainbow", 80], ["gold", "Gold", -1]]},
	"smoke": {"label": "Muzzle smoke", "options": [["none", "None", 0], ["puff", "White puff", 25], ["matching", "Matching colour", 40],
		["spores", "Spore cloud", 60]]},
	"tracer": {"label": "Your tracers", "options": [["cream", "Cream", 0], ["carrot", "Carrot", 25], ["leaf", "Leaf", 25],
		["sky", "Sky", 25], ["plum", "Plum", 25], ["gold", "Gold", 60], ["ruby", "Ruby", -1], ["jade", "Jade", -1]]},
	"kill_fx": {"label": "Beat-down burst", "options": [["none", "None", 0], ["confetti", "Confetti", 40],
		["leaves", "Autumn leaves", 40], ["carrots", "Carrot shower", 50], ["hearts", "Hearts", 50],
		["fireworks", "Fireworks", -1], ["gold_rush", "Gold rush", -1]]},
	"wear_hat": {"label": "Hat", "options": [["none", "None", 0], ["flap_beanie", "Ear-flap beanie", 50],
		["flower_crown", "Flower crown", 60], ["santa_hat", "Santa hat", 70], ["fedora", "Fedora", 80],
		["witch_hat", "Witch's hat", 90], ["wizard_hat", "Wizard's hat", 110], ["grad_cap", "Mortarboard", -1],
		["jester_hat", "Jester's cap", -1], ["cheese_hat", "Cheese hat", -1], ["laurel_wreath", "Laurel wreath", -1]]},
	"wear_face": {"label": "Face", "options": [["none", "None", 0], ["heart_glasses", "Heart glasses", 40],
		["glasses_3d", "3D glasses", 40], ["pixel_shades", "Pixel shades", 75],
		["star_glasses", "Star glasses", -1], ["snorkel_mask", "Snorkel mask", -1]]},
	"wear_neck": {"label": "Neck", "options": [["none", "None", 0], ["sapphire_necklace", "Sapphire necklace", 50],
		["ring_necklace", "Silver ring necklace", 60]]},
	"wear_back": {"label": "Back", "options": [["none", "None", 0], ["butterfly_wings", "Butterfly wings", 120],
		["jetpack", "Jetpack", 150], ["fairy_wings", "Fairy wings", -1], ["dark_wings", "Dark wings", -1],
		["windup_key", "Wind-up key", -1]]},
	"coat": {"label": "Coat", "options": [["natural", "Your own fur", 0], ["mended_mirror", "Mended mirror", -1],
		["golden_acorn", "Golden acorn", -1], ["starry_night", "Starry night", -1], ["tiger_stripe", "Tiger stripe", -1],
		["smouldering", "Smouldering", -1]]},
}

## Your wardrobe's slots, in the order they're shown.
const WARDROBE := ["wear_hat", "wear_face", "wear_neck", "wear_back"]
## Shown with the wardrobe (on you, in the portrait), after its slots.
const COAT := "coat"
const COAT_TINT := preload("res://src/fx/coat_tint.gdshader")
const COAT_GLOW := preload("res://src/fx/coat_glow.gdshader")
## The coats besides the Mended Mirror: [its colour's pattern (coat_tint), colour
## a, colour b, pattern scale, its glow's pattern (coat_glow, 0: none), glow colour].
const COATS := {
	"golden_acorn": [1, Color(1.0, 0.8, 0.36), Color(0.72, 0.46, 0.12), 3.5, 1, Color(1.0, 0.8, 0.38)],
	"starry_night": [2, Color(0.08, 0.1, 0.3), Color(0.26, 0.14, 0.42), 7.0, 2, Color(1.0, 0.96, 0.82)],
	"tiger_stripe": [3, Color(1.0, 0.6, 0.22), Color(0.07, 0.05, 0.05), 2.2, 0, Color.BLACK],
	"smouldering": [4, Color(0.2, 0.18, 0.18), Color(0.34, 0.28, 0.25), 2.6, 4, Color(1.0, 0.42, 0.08)],
}

## The palette the looks pick from.
const COLORS := {
	"white": Color(1, 1, 1), "cream": Color(1.0, 0.9, 0.7), "carrot": Color(1.0, 0.55, 0.12), "leaf": Color(0.45, 0.9, 0.3),
	"berry": Color(1.0, 0.3, 0.35), "sky": Color(0.45, 0.8, 1.0), "gold": Color(1.0, 0.82, 0.25), "lime": Color(0.7, 1.0, 0.25),
	"blueberry": Color(0.35, 0.5, 1.0), "plum": Color(0.75, 0.4, 1.0), "bubblegum": Color(1.0, 0.5, 0.8),
	"ruby": Color(0.95, 0.1, 0.25), "jade": Color(0.2, 0.88, 0.6),
}


static var _coats := {}   # coat id -> its overlay (coat_material)


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


## A worn piece's name, the way it reads in a sentence ("ear-flap beanie",
## "golden acorn coat").
static func piece_name(id: String) -> String:
	for o in LOOKS[COAT].options:
		if o[0] == id:
			return String(o[1]).to_lower() + " coat"
	for cat in WARDROBE:
		for o in LOOKS[cat].options:
			if o[0] == id:
				var n := String(o[1])
				return n if n.substr(0, 2) == "3D" else n[0].to_lower() + n.substr(1)
	return id.replace("_", " ")


## What you're wearing, as a phrase ("wizard's hat, pixel shades and
## golden acorn coat"), or "".
static func outfit_phrase() -> String:
	var names := wearing().map(func(id): return piece_name(id))
	if names.size() <= 1:
		return "" if names.is_empty() else names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## What you're wearing: the Outfits piece in each wardrobe slot, skipping
## the empty ones.
static func outfit() -> Array:
	var out := []
	for cat in WARDROBE:
		var id := look(cat)
		if id != "none":
			out.append(id)
	return out


## Your guns' kit (GunKit.dress): the sight and the laser if they're fitted,
## and your skin (or `skin` instead, to try one on).
static func kit(skin := "") -> Dictionary:
	return {"sight": fitted("red_dot"), "laser": fitted("laser"), "skin": skin if skin != "" else look("skin")}


## A coat's overlay, over your fur and all you wear (Outfits.dress_player),
## or null for your own fur. The Mended Mirror: your Doppelbunny's cracked
## mirror (DoppelBrain.look), its cracks mended in gold, with a softer rim and
## no flashes of a bad reflection (so the two of you are told apart). The
## others (COATS): a colour multiplied over you, and its glow over that.
static func coat_material(id: String) -> ShaderMaterial:
	if _coats.has(id):
		return _coats[id]
	var m: ShaderMaterial = null
	if id == "mended_mirror":
		m = ShaderMaterial.new()
		m.shader = DoppelBrain.SHADER
		m.set_shader_parameter(&"rim_color", Color(1.0, 0.78, 0.42))
		m.set_shader_parameter(&"crack_color", Color(1.0, 0.76, 0.22))
		m.set_shader_parameter(&"crack_width", 0.07)
		m.set_shader_parameter(&"rim_strength", 0.45)
		m.set_shader_parameter(&"flashes", 0.0)
	elif COATS.has(id):
		var c: Array = COATS[id]
		m = ShaderMaterial.new()
		m.shader = COAT_TINT
		m.set_shader_parameter(&"pattern", c[0])
		m.set_shader_parameter(&"color_a", c[1])
		m.set_shader_parameter(&"color_b", c[2])
		m.set_shader_parameter(&"scale", c[3])
		if int(c[4]) > 0:
			var glow := ShaderMaterial.new()
			glow.shader = COAT_GLOW
			glow.set_shader_parameter(&"pattern", c[4])
			glow.set_shader_parameter(&"glow_color", c[5])
			glow.set_shader_parameter(&"scale", c[3])
			m.next_pass = glow
	if m:
		_coats[id] = m
	return m


## Everything a rogue can see on you (and talk about: Cast.OUTFIT_LINES):
## your outfit, then your coat if it isn't your own fur.
static func wearing() -> Array:
	var coat := look(COAT)
	return outfit() + ([] if coat == LOOKS[COAT].options[0][0] else [coat])


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
