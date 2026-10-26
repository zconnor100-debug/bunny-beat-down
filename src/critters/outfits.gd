class_name Outfits
extends RefCounted
## The rogues' own looks: every member of the Cast wears the same outfit and
## fur every match, picked to match who they are (Captain Carrot's captain's
## cap and medal, Sir Toadsworth's top hat and monocle, Dam Dan's hard hat).
## You play in your own skins; outfits are the rogues'.
##
## A piece is a model (assets/env/outfit_<id>/, built by tools/env from the
## recipes; credited in assets/credits/outfits.json) and how it's worn: its
## slot says where (on the crown, across the eyes, round the neck, on the
## back) and OutfitFit measures every critter's head and chest from its mesh,
## so one hat fits a bunny, a fox and a hamster. Pieces ride on the bones
## (they follow every move and the ragdoll) and fly off when the head does.
##
## Adding a look: a line in LOOKS. Adding a piece: a recipe (category
## "outfit") built with tools/env/process_models.py, then a line in PIECES.

## Slots: "hat" (on the crown), "glasses" (over the eyes), "monocle" (the
## right eye), "mask" (over the muzzle, under the eyes), "band" (round the
## forehead), "bow" (under the chin), "collar" (round the neck), "pendant"
## (hung flat down the chest), "medal" (on the chest), "cape" (hung from the shoulders), "wings" and "pack" (on the
## back).
## Every piece is measured (OutfitShapes: where its head-hole is, how wide it
## is) and fitted to the critter (OutfitFit: its skull's breadth at every
## height, its eyes, the outline of its back and chest), so most need only:
## yaw (and roll, pitch): degrees that turn the model to face the way the
##   critter does (and stand it the right way up);
## sink: how far down the head a hat's rim sits, from the top of the skull (0)
##   to the brow just over the eyes (1): a party hat perched on top 0.1, a top
##   hat 0.5, a cap 0.85, a pulled-down beanie 1; its head-hole is made as wide
##   as the skull is there, so it hugs the head; to_chin: down over the face;
##   on_crown: its middle sat on top of the head (a beret, tipped one way);
## fit: the hole that much wider than the skull (a crown sits looser);
## size: times the slot's own measure (the eyes' spread, the face, the neck,
##   the shoulders, the back);
## back: how far behind the top of the skull a hat sits (share of its depth);
## mid: a pack in the middle of the back (a wind-up key), not hung from the shoulders;
## tall: a hat that stands tall by design (a top hat, a chef's hat); the rest
##   are squashed a little (to 70 %, at most) so the inside of the crown sits
##   on the skull rather than floating over a flat-topped squirrel;
## hole / hole_w: the head-hole's middle [x, z] and width, where measuring
##   can't find them (a closed top hat, a cavalier's curled brim); rim: the
##   height its rim is at, where a chin strap hangs below it;
## flat: squash it to this share of its height (a band as thin as a band);
## two_sided: draw both faces (a cape's inside shows from the front);
## fold: a necklace laid flat: what's in front of the neck hangs down the chest
##   (its pendant on the chest, facing forward); pendants ("pendant" slot)
##   are always pressed onto the chest and their ends round the neck;
## thick: a fine chain made this much (of the head's height) thicker;
## lay: nothing further out in front than the critter is (a chain on the chest);
## hide: material names of parts left off (a shako's chin strap a frog has no
##   chin for);
## inset: a pack's own straps (this share of its depth) sunk into the back,
##   and it leans with the back, so it's worn against it;
## eye: "left" for a monocle on the left eye;
## swing: [material, degrees]: that part (a chin strap) swung back under the
##   chin, hinged where it hangs from;
## on: a species' own touches, as a look's: {"beaver": {"grow": 0.85}};
## hug: a mask's cloth laid against the face and down the neck instead of
##   standing out in front (on a hamster's round face, a beak);
## tint: its colour when the look doesn't give one (a model that came pale).
const PIECES := {
	"captain_hat": {"slot": "hat", "sink": 0.55},
	"top_hat": {"slot": "hat", "tall": true, "sink": 0.35, "fit": 0.85, "hole": [0.0, 0.0], "hole_w": 0.26},
	"gent_top_hat": {"slot": "hat", "tall": true, "sink": 0.35, "fit": 0.88},
	"crown": {"slot": "hat", "tall": true, "sink": 0.4, "fit": 1.1},
	"cowboy_hat": {"slot": "hat", "sink": 0.75},
	"beret": {"slot": "hat", "sink": 1.0, "fit": 1.06},
	"bucket_hat": {"slot": "hat", "sink": 0.9},
	"cavalier_hat": {"slot": "hat", "sink": 0.6, "hole": [-0.05, 0.0], "hole_w": 0.5},
	"straw_hat": {"slot": "hat", "sink": 0.55, "hole": [0.0, 0.0], "hole_w": 0.4},
	"deerstalker": {"slot": "hat", "sink": 0.9},
	"fez": {"slot": "hat", "tall": true, "sink": 0.15, "fit": 0.62},
	"fur_hat": {"slot": "hat", "sink": 0.9},
	"mountie_hat": {"slot": "hat", "sink": 0.8},
	"bearskin": {"slot": "hat", "tall": true, "sink": 0.9, "rim": 0.1},
	"band_hat": {"slot": "hat", "tall": true, "sink": 0.8, "rim": 0.12},
	"robin_hat": {"slot": "hat", "sink": 0.5},
	"trucker_red": {"slot": "hat", "sink": 0.85},
	"trucker_blue": {"slot": "hat", "sink": 0.85},
	"trucker_yellow": {"slot": "hat", "sink": 0.85},
	"hard_hat": {"slot": "hat", "sink": 0.85},
	"party_hat": {"slot": "hat", "tall": true, "sink": 0.1, "fit": 0.55},
	"propeller_hat": {"slot": "hat", "sink": 0.85},
	"beanie": {"slot": "hat", "sink": 1.0},
	"viking_helmet": {"slot": "hat", "sink": 0.9, "yaw": 90.0},
	"pirate_hat": {"slot": "hat", "sink": 0.8},
	"wizard_hat": {"slot": "hat", "tall": true, "sink": 0.6, "hole": [0.0, 0.0], "hole_w": 0.22},
	"knight_helmet": {"slot": "hat", "to_chin": true, "fit": 1.12, "yaw": 22.5},   # (the model's front facet, the cross, is turned one facet over)
	"chef_hat": {"slot": "hat", "tall": true, "sink": 0.7, "fit": 0.95},
	"sunglasses": {"slot": "glasses"},
	"aviators": {"slot": "glasses"},
	"goggles": {"slot": "glasses", "lenses": [0.165, 0.22, 0.05]},
	"monocle": {"slot": "monocle"},
	"bandana_mask": {"slot": "mask"},
	"headband": {"slot": "band", "flat": 1.0, "fit": 1.0, "tint": "#2f5fd0"},
	"bow_tie": {"slot": "bow"},
	"scarf": {"slot": "collar", "flat": 0.6},
	"bead_necklace": {"slot": "collar", "fit": 1.15, "yaw": 90.0, "hole": [0.3, 0.0], "hole_w": 1.45, "flat": 0.5, "fold": true},
	"medal": {"slot": "medal"},
	"cape": {"slot": "cape", "two_sided": true},
	"backpack": {"slot": "pack", "yaw": 90.0, "inset": 0.22},
	# yours only (the Workshop's wardrobe: no rogue wears these)
	"witch_hat": {"slot": "hat", "tall": true, "sink": 0.7, "hole_w": 0.17, "on": {"beaver": {"up": 0.1}}},
	"santa_hat": {"slot": "hat", "sink": 0.9, "yaw": 180.0, "on": {"beaver": {"grow": 0.82, "up": 0.08}}},
	"grad_cap": {"slot": "hat", "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.45, "tint": "#23232b"},
	"fedora": {"slot": "hat", "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.34, "on": {"beaver": {"grow": 0.88}}},
	"flower_crown": {"slot": "hat", "tall": true, "sink": 0.45, "fit": 1.1, "hole": [0.0, 0.0], "hole_w": 0.72,
		"on": {"beaver": {"grow": 0.8, "up": 0.12}}},
	"jester_hat": {"slot": "hat", "tall": true, "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.38, "on": {"beaver": {"grow": 1.25, "fwd": -0.12, "up": 0.1}}},
	"flap_beanie": {"slot": "hat", "sink": 1.0, "rim": 0.13, "on": {"beaver": {"up": -0.16}}},
	"heart_glasses": {"slot": "glasses", "tint": "#ff6fae", "on": {"beaver": {"size": 1.45, "up": 0.05}}},
	"star_glasses": {"slot": "glasses", "size": 1.1},
	"glasses_3d": {"slot": "glasses", "on": {"beaver": {"size": 1.3}}},
	"pixel_shades": {"slot": "glasses", "yaw": 90.0, "on": {"beaver": {"size": 1.3}}},
	"sapphire_necklace": {"slot": "collar", "yaw": 90.0, "hole": [0.32, 0.0045], "fit": 1.06, "rim": 0.15, "flat": 0.3, "fold": true},
	"ring_necklace": {"slot": "collar", "fit": 1.2, "flat": 0.45, "rim": 0.21, "thick": 0.03, "lay": true},
	"jetpack": {"slot": "pack", "size": 1.8},
	"fairy_wings": {"slot": "wings", "size": 1.4, "two_sided": true},
	"dark_wings": {"slot": "wings", "size": 1.7, "two_sided": true},
	"butterfly_wings": {"slot": "wings", "size": 1.4, "two_sided": true},
	# earned: a win on each map, and beating your nemesis
	"snorkel_mask": {"slot": "glasses", "lens": [-0.06, 0.141, 0.085], "on": {"beaver": {"fwd": 0.12}}},
	"cheese_hat": {"slot": "hat", "sink": 0.95, "tint": "#f2c447"},
	"windup_key": {"slot": "pack", "roll": 90.0, "yaw": -90.0, "size": 1.2, "mid": true},
	# the costume notes (2026-10-25)
	"ninja_headband": {"slot": "band", "flat": 1.0, "fit": 1.0},
	"eyelashes": {"slot": "lashes", "roll": 180.0},
	"earring": {"slot": "earring"},
	"shoulder_pads": {"slot": "shoulders", "yaw": 90.0, "size": 1.35, "on": {"bandit_bunny": {"fwd": -0.12, "up": 0.06}}},
	"jewel_necklace": {"slot": "pendant", "size": 1.25},
	"neckerchief": {"slot": "collar", "rim": 0.25, "max_h": 0.9},
	# the bandana's model worn cowboy-style: its loop round the neck, the
	# triangle down the front (spec "model": another piece's model and shape)
	"neck_bandana": {"slot": "collar", "model": "bandana_mask", "rim": 0.27, "fit": 1.05, "max_h": 0.5},
	"mustache": {"slot": "mustache"},
	"laurel_wreath": {"slot": "hat", "sink": 0.5, "fit": 1.05, "hole": [0.0, 0.0], "tall": true, "yaw": 90.0},
}

## Who wears what: the fur (one of the species' skins) and the pieces, each
## a piece id or [piece id, tint].
const LOOKS := {
	# Each piece: "id", or ["id", "#tint"], or ["id", "#tint" or "", {a rogue's
	# own touches: see wear_piece}]. Game Notes 37-77 (2026-10-25) tuned these.
	# bandit bunnies (hooded: their extras are on the body, not the head)
	"Captain Carrot": {"skin": "wild_hare", "wear": [["captain_hat", "", {"grow": 1.18, "fwd": 0.08, "tilt": -8.0}], ["medal", "", {"size": 1.6}],
		["shoulder_pads", "#d8b040"]]},
	"Vex": {"skin": "shadow", "wear": [["bandana_mask", "#5d7a3a", {"grow": 1.3, "up": -0.04, "fwd": -0.05}], ["ninja_headband", "", {"up": 0.02}],
		"earring"]},
	"Bunnicula": {"skin": "frost", "wear": [["cape", "#2a1a2e"], ["bow_tie", "#8a1a24"], ["earring", "#c8c8d0"]]},
	"Lop-Eared Larry": {"skin": "default", "wear": [["beanie", "#d8a23a", {"fwd": 0.12, "grow": 1.16}], "backpack"]},
	"Snickerdoodle": {"skin": "toxic", "wear": ["party_hat", "sunglasses", ["shoulder_pads", "#e0569a"]]},
	"Cottontail Kate": {"skin": "default", "wear": [["shoulder_pads", "#f2efe6"], ["earring", ""]]},
	"Hops McGee": {"skin": "wild_hare", "wear": [["viking_helmet", "", {"fwd": 0.08}], "shoulder_pads"]},
	# squirrels (Kernel's the model: big hats a size up, eyes in their sockets)
	"Nutsy": {"skin": "default", "wear": [["headband", "#ffd23a", {"flat": 0.6}], ["bandana_mask", "#3a7fd6", {"grow": 1.3}]]},
	"Acorn Al": {"skin": "grey", "wear": [["trucker_red", "", {"up": 0.1}], ["backpack", "", {"size": 1.35}]]},
	"Sir Scamper": {"skin": "fox_squirrel", "wear": [["cavalier_hat", "", {"hole": [-0.07, 0.0], "two_sided": true, "side": 0.05}], ["cape", "#8a2a32"]]},
	"Hazel": {"skin": "default", "wear": [["robin_hat", "", {"grow": 1.4, "up": 0.1}]]},
	"Twitch": {"skin": "blueberry", "wear": [["goggles", "", {"up": 0.05}]]},
	"Kernel": {"skin": "black", "wear": [["straw_hat", "", {"up": 0.03, "grow": 1.14}]]},
	"Bushytail Betty": {"skin": "fox_squirrel", "wear": [["beanie", "#e07a3a"], ["aviators", "", {"deep": 0.72, "fwd": 0.14, "size": 1.15, "up": -0.04}]]},
	# foxes
	"Sly": {"skin": "silver", "wear": [["deerstalker", "", {"turn": -7.0, "grow": 1.06}]]},
	"Vixen Vera": {"skin": "default", "wear": ["aviators", ["jewel_necklace", "", {"size": 1.7}]]},
	"Fennick": {"skin": "fennec", "wear": [["trucker_yellow", "", {"fwd": -0.07}]]},
	"Foxy Roxy": {"skin": "kitsune", "wear": ["sunglasses", ["bow_tie", "#e0569a"]]},
	"Sir Reynard": {"skin": "default", "wear": [["top_hat", "#5a4a62"], ["monocle", "", {"size": 1.2}], ["bow_tie", "#1c1c22"]]},
	"Ember": {"skin": "default", "wear": ["goggles", ["neckerchief", "#d8452a"]]},
	"Duchess": {"skin": "arctic", "wear": [["bearskin", "", {"flat": 2.3, "up": 0.05, "fwd": -0.1, "swing": ["bearskinhat_1_gold", 50.0]}], ["cape", "#5b3a8a", {"size": 1.3}]]},
	# raccoons
	"Bandit Bill": {"skin": "default", "wear": [["pirate_hat", "", {"fwd": 0.07}]]},
	"Trash Panda": {"skin": "cinnamon", "wear": [["bucket_hat", "", {"fwd": 0.08, "grow": 1.12}], ["backpack", "", {"size": 1.3}]]},
	"Rocco": {"skin": "red_panda", "wear": [["headband", "#2f5fd0", {"up": -0.04, "tilt": 10.0}]]},
	"Masky": {"skin": "default", "wear": [["bandana_mask", "#3a3a40"]]},
	"Dumpster Dot": {"skin": "blonde", "wear": [["beanie", "#6b8f5a", {"fwd": 0.07}], ["neckerchief", "#b0a080"]]},
	"Grimsby": {"skin": "starry_night", "wear": [["fur_hat", "", {"fwd": 0.06, "grow": 1.05}], ["neckerchief", "#7a7a80"]]},
	"Lady Garbage": {"skin": "starry_night", "wear": [["crown", "", {"fwd": 0.07}], "bead_necklace"]},
	# frogs
	"Croaker": {"skin": "toad_chaps", "wear": [["cowboy_hat", "", {"fwd": -0.06}]]},
	"Lily Pad Lou": {"skin": "tree_frog", "wear": [["bucket_hat", "#a8c890", {"fwd": -0.06, "tilt": 7.0, "grow": 1.1}]]},
	"Hopscotch": {"skin": "poison_dart", "wear": [["propeller_hat", "", {"fwd": -0.08, "tilt": 8.0}]]},
	"Sir Toadsworth": {"skin": "golden", "wear": [["top_hat", "#26262c", {"grow": 1.1}], ["mustache", "", {"fwd": -0.03}], ["monocle", "", {"eye": "left", "fwd": -0.18, "side": -0.04}], "bow_tie"]},
	"Puddles": {"skin": "default", "wear": [["beanie", "#3b6fb5", {"fwd": -0.06}]]},
	"Bog Boss": {"skin": "default", "wear": [["band_hat", "", {"up": 0.12, "fwd": -0.25, "tilt": 10.0, "hide": ["hat_1_chinstrap", "hat_1_peak", "hat_1_trim"]}]]},
	"Gulp": {"skin": "default", "wear": [["sunglasses", "", {"size": 0.8, "up": 0.06, "fwd": -0.06}], "medal"]},
	# beavers
	"Chompers": {"skin": "default", "wear": [["knight_helmet", "", {"grow": 1.42, "fwd": 0.08, "up": 0.03}]]},
	"Dam Dan": {"skin": "default", "wear": ["hard_hat"]},
	"Buck Toothington": {"skin": "honey", "wear": [["mountie_hat", "", {"grow": 1.18, "up": 0.08}], ["monocle", "", {"size": 1.5, "up": -0.07, "side": 0.03}]]},
	"Timber": {"skin": "lumberjack", "wear": [["beanie", "#b33a2a", {"fwd": 0.06}]]},
	"Lodge Lady": {"skin": "default", "wear": [["beret", "#7a4a2a"], "backpack"]},
	"Gnawman": {"skin": "chocolate", "wear": [["bucket_hat", "#8a9a70"], ["sunglasses", "", {"size": 1.15}]]},
	"Dr. Splash": {"skin": "bubblegum", "wear": [["goggles", "", {"up": 0.07}], ["cape", "#c03030"]]},
	# hamsters
	"Squeaks": {"skin": "default", "wear": [["bandana_mask", "#e8c640", {"grow": 1.25, "up": 0.02, "hug": true}],
		["backpack", "", {"inset": 0.0, "fwd": 0.45, "tilt": -12.0}]]},   # (the look the owner approved: deeper in a round back)
	"Cheeks McGee": {"skin": "panda", "wear": ["trucker_blue", "sunglasses"]},
	"Nibbler": {"skin": "dove", "wear": [["bandana_mask", "#c0302a", {"grow": 1.35, "up": 0.02, "hug": true}]]},
	"Pudge": {"skin": "black_bear", "wear": ["fez", ["bow_tie", "#c0302a"]]},
	"Whisker Biscuit": {"skin": "cotton_candy", "wear": [["chef_hat", "", {"up": -0.07}]]},
	"Turbo": {"skin": "turbo_tee", "wear": [["trucker_red", "", {"tilt": 14.0, "fwd": -0.06}], "goggles"]},
	"Wheelie": {"skin": "dove", "wear": [["top_hat", "#2e2e36"], ["bow_tie", "#d8b040"]]},
}

## Bones the slots ride on.
const ON_HEAD := ["hat", "glasses", "monocle", "mask", "band", "lashes", "mustache", "earring"]
## Pieces stop drawing this far away (a bot that far off is a speck).
const DRAW_DISTANCE := 110.0


static func model_path(id: String) -> String:
	var own := String(PIECES.get(id, {}).get("model", id))   # (a piece may borrow another's model)
	return "res://assets/env/outfit_%s/outfit_%s.glb" % [own, own]


static func look_of(rogue: String) -> Dictionary:
	return LOOKS.get(rogue, {})


## Dress your own critter: your skin (Settings) and what you wear from the
## Workshop's wardrobe (or `wear` instead, to try things on). A hat takes the
## place of the acorn helmet.
static func dress_player(c: Critter, wear: Variant = null) -> void:
	if c.visual == null or c.visual.rig == null:
		return
	var pieces: Array = wear if wear is Array else Workshop.outfit()
	for id in pieces:
		wear_piece(c.visual, id)
	if c.visual.helmet and is_instance_valid(c.visual.helmet):
		c.visual.helmet.visible = not pieces.any(func(id): return PIECES.get(id, {}).get("slot", "") == "hat")


## Take off every piece (to dress again).
static func undress(v: CritterVisual) -> void:
	for piece in v.outfit:
		if is_instance_valid(piece):
			piece.queue_free()
	v.outfit.clear()
	if v.helmet and is_instance_valid(v.helmet):
		v.helmet.visible = true


## Dress a critter as `rogue` (its skin and pieces). Nothing for a name that
## has no look (the player, test critters).
static func dress(c: Critter, rogue: String) -> void:
	var look := look_of(rogue)
	if look.is_empty() or c.visual == null or c.visual.rig == null:
		return
	if look.has("skin"):
		c.visual.apply_skin(String(look.skin))
	for item in look.get("wear", []):
		var id: String = item[0] if item is Array else item
		var tint := Color(item[1]) if item is Array and item.size() > 1 and String(item[1]) != "" else Color.WHITE
		var adjust: Dictionary = item[2] if item is Array and item.size() > 2 else {}
		wear_piece(c.visual, id, tint, adjust)


## Put one piece on (returns it, or null if its model is missing). `adjust`:
## a rogue's own touches (LOOKS: ["piece", "#tint", {...}]): any PIECES key
## for this wearer only (sink, fit, size, two_sided...), and nudges after it's
## fitted: fwd / up (shares of the head's depth / height, or the chest's for
## pieces on the body), side (a share of the head's, or the shoulders', width:
## to its left), grow (bigger about its middle), tilt (degrees, front up),
## turn (degrees, to its left) and deep (front to back, about its front).
static func wear_piece(v: CritterVisual, id: String, tint := Color.WHITE, adjust := {}) -> Node3D:
	var spec: Dictionary = PIECES.get(id, {})
	if spec.is_empty():
		return null
	# (the piece's own touches for this species, under the rogue's own)
	var own: Dictionary = spec.get("on", {}).get(String(v.def.id), {})
	if not own.is_empty():
		adjust = own.merged(adjust, true)
	spec = spec.merged(adjust, true)
	if tint == Color.WHITE and spec.has("tint"):
		tint = Color(spec.tint)
	var m := ModelUtil.instantiate(model_path(id))
	if m == null:
		return null
	if spec.has("hide"):
		_hide_parts(m, id, spec.hide)
	var fit := OutfitFit.of(v)
	var slot: String = spec.slot
	var role := &"head" if ON_HEAD.has(slot) else &"chest"
	var att: BoneAttachment3D = v.attachments.get(role)
	if att == null or not fit.valid:
		m.free()
		return null
	var holder := Node3D.new()
	holder.name = "Outfit_" + id
	holder.add_child(m)
	var turn := Basis(Vector3.UP, deg_to_rad(float(spec.get("yaw", 0.0)))) \
		* Basis(Vector3.RIGHT, deg_to_rad(float(spec.get("pitch", 0.0)))) * Basis(Vector3.BACK, deg_to_rad(float(spec.get("roll", 0.0))))
	var box: AABB = Transform3D(turn, Vector3.ZERO) * ModelUtil.aabb_of(m)   # (the bounds, turned to face the critter's way)
	var xf := _place(fit, id, spec, turn, box)
	if not adjust.is_empty():
		xf = _nudge(xf, box, fit, ON_HEAD.has(slot), adjust)
	m.transform = Transform3D(turn, Vector3.ZERO)
	if slot == "cape":
		var cape := _drape(v, m, xf, fit, id)
		holder.free()
		if cape:
			_finish(v, cape, spec, tint)
		return cape
	if slot == "mask":
		_wrap(v, m, xf, fit, id, spec.get("hug", false))
	if spec.get("fold", false):
		_reshape(v, m, xf, id, "fold", _folded.bind(fit))
	if slot == "pendant":
		_reshape(v, m, xf, id, "press", _pressed.bind(fit))
	if spec.has("thick"):
		_reshape(v, m, xf, id, "thick%s" % spec.thick, _thickened.bind(fit.head_h * float(spec.thick)))
	if spec.get("lay", false):
		_reshape(v, m, xf, id, "lay", _laid.bind(fit))
	if spec.has("swing"):
		_swing_part(m, id, String(spec.swing[0]), float(spec.swing[1]))
	var ear: PackedInt32Array = v.rig.chains.get(&"ear_r", PackedInt32Array())
	if slot == "earring" and ear.size() > 0:
		# pierced through the ear itself, near its root, so it swings with it
		var bone := ear[0]
		var base := v.skeleton.get_bone_global_rest(bone)
		var tip := v.skeleton.get_bone_global_rest(ear[1]).origin if ear.size() > 1 else base.origin + Vector3.UP * fit.head_h * 0.3
		if ear.size() > 2:
			base = v.skeleton.get_bone_global_rest(ear[1])
			tip = v.skeleton.get_bone_global_rest(ear[2]).origin
			bone = ear[1]
		var at := base.origin.lerp(tip, 0.3) + Vector3(-fit.head_h * 0.05, 0, fit.head_d * 0.02)   # (its outer side)
		xf.origin += at - xf * Vector3(box.get_center().x, box.end.y, box.get_center().z)
		var ear_att := BoneAttachment3D.new()
		ear_att.bone_idx = bone
		v.skeleton.add_child(ear_att)
		holder.transform = base.affine_inverse() * xf
		ear_att.add_child(holder)
		_finish(v, ear_att, spec, tint)
		v.outfit.erase(ear_att)
		v.outfit.append(holder)
		holder.tree_exiting.connect(func(): if is_instance_valid(ear_att): ear_att.queue_free())
		return holder
	holder.transform = (v.rig.rest[role] as Transform3D).affine_inverse() * xf
	att.add_child(holder)
	_finish(v, holder, spec, tint)
	if slot == "pack" and not spec.get("mid", false):
		# straps over the shoulders, so it's worn, not stuck on
		var straps := _straps(fit, Color(spec.get("strap_color", "#3b2c22")))
		straps.transform = (v.rig.rest[role] as Transform3D).affine_inverse()
		straps.name = "Outfit_%s_straps" % id
		att.add_child(straps)
		_finish(v, straps, {}, Color.WHITE)
	return holder


## A backpack's straps (skeleton space): from the top of the pack, over each
## shoulder and down the front of the chest, lying on the body's outline.
static func _straps(f: OutfitFit, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := cape_top(f)
	var over_y := f.shoulder_y + f.head_h * 0.13
	var low := lerpf(f.hip_y, f.chest_y, 0.75)
	var half_w := f.head_h * 0.045
	var lift := f.head_d * 0.025
	for sgn: float in [-1.0, 1.0]:
		var x := f.head_c.x + sgn * minf(f.shoulder_w * 0.27, f.body_width_at(f.chest_y) * 0.33)
		var p0 := Vector3(x, top - f.head_h * 0.05, f.back_at(top) - lift)
		var mid_z := (f.front_at(f.shoulder_y) + f.back_at(f.shoulder_y)) * 0.5
		var over := Vector3(x, over_y, mid_z)
		var p2 := Vector3(x - sgn * f.head_h * 0.04, low, f.front_at(low) + lift)
		var c := over * 2.0 - (p0 + p2) * 0.5
		var pts: Array[Vector3] = []
		for i in 17:
			var t := i / 16.0
			var q := p0.lerp(c, t).lerp(c.lerp(p2, t), t)
			# lying on the body: outside its front and back where it passes them
			if q.y < over_y - f.head_h * 0.06:
				if q.z > mid_z:
					q.z = maxf(q.z, f.front_at(q.y) + lift)
				else:
					q.z = minf(q.z, f.back_at(q.y) - lift)
			pts.append(q)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var side := Vector3(half_w, 0, 0)
			var tangent := (b - a).normalized()
			var n := tangent.cross(Vector3.RIGHT).normalized() * (1.0 if a.z > mid_z or a.y > over_y - f.head_h * 0.06 else -1.0)
			for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
				st.set_normal(n)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


## Draw a piece like the critter (its render layer, out to DRAW_DISTANCE),
## dyed, and count it as worn.
static func _finish(v: CritterVisual, piece: Node3D, spec: Dictionary, tint: Color) -> void:
	for gi in ModelUtil.find_all(piece, "GeometryInstance3D"):
		var g := gi as GeometryInstance3D
		g.layers = CritterVisual.RENDER_LAYER
		g.visibility_range_end = DRAW_DISTANCE
		if (tint != Color.WHITE or spec.get("two_sided", false)) and g is MeshInstance3D:
			_tint(g as MeshInstance3D, tint, spec.get("two_sided", false))
	v.outfit.append(piece)
	v.match_first_person(piece)   # (your own outfit only casts a shadow in first person)


## A cape, skinned to the critter's back: its top rides the chest and its hem
## the hips, so it stays on the back as the critter hunches, leans and runs
## instead of swinging out behind like a board. At rest it drapes: down the
## back as far as the back bulges out, then straight down from there.
## `m` is the cape model (turned), `xf` where _place put it.
static func _drape(v: CritterVisual, m: Node3D, xf: Transform3D, f: OutfitFit, id: String) -> MeshInstance3D:
	var skel := v.skeleton
	var key := v.def.resolved_model() + ":" + id
	if not _draped.has(key):
		_draped[key] = _drape_mesh(v, m, xf, f)
	var made: Array = _draped[key]
	if made.is_empty():
		return null
	var body: MeshInstance3D = null   # (beside the critter's own skinned mesh, in its space)
	for bm in v.meshes:
		if bm.mesh != null and bm.skin != null:
			body = bm
			break
	if body == null:
		return null
	var cape := MeshInstance3D.new()
	cape.name = "Outfit_" + id
	cape.mesh = made[0]
	cape.skin = made[1]
	body.get_parent().add_child(cape)
	cape.transform = body.transform
	cape.skeleton = cape.get_path_to(skel)
	return cape


const DRAPE_SLOPE := 0.6   ## how steeply a cape leans out over a bulge (out per unit down)
static var _draped := {}   # model path:piece -> [ArrayMesh, Skin] (the same for every critter of a kind)


## The draped cape's mesh and skin, for _drape: built once per model.
static func _drape_mesh(v: CritterVisual, m: Node3D, xf: Transform3D, f: OutfitFit) -> Array:
	var skel := v.skeleton
	var binds: Array[int] = []
	var heights: Array[float] = []
	for role in [&"chest", &"spine", &"hips"]:
		var b: int = v.rig.bone.get(role, -1)
		if b >= 0:
			binds.append(b)
			heights.append(skel.get_bone_global_rest(b).origin.y)
	if binds.is_empty():
		return []
	# (built like the critter's own body mesh: beside it, in its space, with its
	# skin's bind poses, so it scales and moves exactly as the body does)
	var body: MeshInstance3D = null
	for bm in v.meshes:
		if bm.mesh != null and bm.skin != null:
			body = bm
			break
	if body == null:
		return []
	var to_mesh := (skel.global_transform.affine_inverse() * body.global_transform).affine_inverse()
	var skin := Skin.new()
	for b in binds:
		var pose := to_mesh * skel.get_bone_global_rest(b)
		for k in body.skin.get_bind_count():
			var kb := body.skin.get_bind_bone(k)
			if (kb if kb >= 0 else skel.find_bone(body.skin.get_bind_name(k))) == b:
				pose = body.skin.get_bind_pose(k).affine_inverse()
				break
		skin.add_bind(b, pose.affine_inverse())
	# the model's surfaces, in skeleton space
	var surfaces := []   # [arrays, material, primitive]
	var lo := INF
	# (over a tail at the hips: the part below the top of the tail lies back
	# along it instead of the tail poking through; not squashed to fit above it)
	var hem := (f.tail_top if f.tail_top > 0.0 else f.tail_y) + f.head_h * 0.02 if f.cape_over_tail and f.tail_y > 0.0 else -INF
	for g in ModelUtil.find_all(m, "MeshInstance3D"):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_skel := xf * _under(mi, m)
		var nb := to_skel.basis.inverse().transposed()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in vs.size():
				vs[i] = to_skel * vs[i]
				if hem > -INF and vs[i].y < hem:
					# (below the top of the tail: laid back along it, as cloth over a log)
					var d := hem - vs[i].y
					vs[i] = Vector3(vs[i].x, hem - d * 0.12, vs[i].z - d * 0.99)
				lo = minf(lo, vs[i].y)
			arr[Mesh.ARRAY_VERTEX] = vs
			if arr[Mesh.ARRAY_NORMAL] != null:
				var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in ns.size():
					ns[i] = (nb * ns[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = ns
			if arr[Mesh.ARRAY_TANGENT] != null:
				var ts: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for i in ts.size() / 4:
					var t := (to_skel.basis * Vector3(ts[i * 4], ts[i * 4 + 1], ts[i * 4 + 2])).normalized()
					ts[i * 4] = t.x
					ts[i * 4 + 1] = t.y
					ts[i * 4 + 2] = t.z
				arr[Mesh.ARRAY_TANGENT] = ts
			surfaces.append([arr, mi.get_active_material(si), mi.mesh.surface_get_primitive_type(si)])
	if surfaces.is_empty():
		return []
	# the drape: the cape's inside goes onto a line down the back that only
	# ever steps outward (it hangs straight down past the bulge)
	var top := cape_top(f)
	const STEPS := 24
	var step := maxf(top - lo, 0.01) / STEPS
	var line := PackedFloat32Array()   # z of the drape line at each step down from the top
	var inside := PackedFloat32Array() # z of the cape's inside (its front) there
	var raw := PackedFloat32Array()
	for i in STEPS + 1:
		raw.append(f.drape_back_at(top - step * i) - f.head_d * 0.04 * clampf(i / 4.0, 0.0, 1.0))
	var run := INF
	for i in STEPS + 1:
		# (and it leans out ahead of a bulge lower down, as cloth does, rather
		# than kinking round it: at most DRAPE_SLOPE out per unit down)
		var ahead := raw[i]
		for j in range(i + 1, STEPS + 1):
			ahead = minf(ahead, raw[j] + (j - i) * step * DRAPE_SLOPE)
		run = minf(run, ahead)
		line.append(run)
		inside.append(-INF)
	for s in surfaces:
		for p: Vector3 in s[0][Mesh.ARRAY_VERTEX]:
			if p.y <= top:
				var i := clampi(roundi((top - p.y) / step), 0, STEPS)
				inside[i] = maxf(inside[i], p.z)
	var shift := PackedFloat32Array()
	for i in STEPS + 1:
		# (steps the cape has no vertex at borrow the nearest that has)
		var j := i
		while j > 0 and inside[j] == -INF:
			j -= 1
		shift.append(minf(line[i] - inside[j], f.head_d * 0.15) if inside[j] > -INF else 0.0)
	var mesh := ArrayMesh.new()
	for s in surfaces:
		var arr: Array = s[0]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vs.size() * 4)
		weights.resize(vs.size() * 4)
		for i in vs.size():
			var p := vs[i]
			var t := maxf(top - p.y, 0.0) / step
			var k := mini(int(t), STEPS - 1)
			p.z += lerpf(shift[k], shift[k + 1], clampf(t - k, 0.0, 1.0))
			vs[i] = p
			# chest down to the hips: the two bones it's between
			var a := heights.size() - 1
			for h in heights.size():
				if p.y >= heights[h]:
					a = h
					break
			var w := 1.0
			if a > 0 and p.y < heights[a - 1] and p.y >= heights[a]:
				w = (p.y - heights[a]) / maxf(heights[a - 1] - heights[a], 0.001)
				bones[i * 4] = a - 1
				weights[i * 4] = w
				bones[i * 4 + 1] = a
				weights[i * 4 + 1] = 1.0 - w
			else:
				bones[i * 4] = a
				weights[i * 4] = 1.0
		var nb := to_mesh.basis.inverse().transposed()
		for i in vs.size():
			vs[i] = to_mesh * vs[i]
		if arr[Mesh.ARRAY_NORMAL] != null:
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in ns.size():
				ns[i] = (nb * ns[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = ns
		if arr[Mesh.ARRAY_TANGENT] != null:
			var ts: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in ts.size() / 4:
				var t := (to_mesh.basis * Vector3(ts[i * 4], ts[i * 4 + 1], ts[i * 4 + 2])).normalized()
				ts[i * 4] = t.x
				ts[i * 4 + 1] = t.y
				ts[i * 4 + 2] = t.z
			arr[Mesh.ARRAY_TANGENT] = ts
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(s[2], arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	return [mesh, skin]


## A bandana's knot and tails pulled in onto the back of the head and neck
## (sized to the snout, on a big head its loop would leave them hanging in
## the air behind): every vertex behind the middle of the head goes no
## further back, and no further out to the side, than the critter does
## there. `hug`: and every vertex in front goes no further forward than the
## face (and below it the neck), so the cloth lies on it. The bent meshes are
## made once per model.
static func _wrap(v: CritterVisual, m: Node3D, xf: Transform3D, f: OutfitFit, id: String, hug := false) -> void:
	# (per fit, too: two hamsters can wear one bandana at different sizes)
	var key := v.def.resolved_model() + ":" + id + (":hug" if hug else "") + ":%d" % hash(xf)
	for g in ModelUtil.find_all(m, "MeshInstance3D"):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		var gk := key + ":" + String(m.get_path_to(mi))
		if not _wrapped.has(gk):
			var to_skel := xf * _under(mi, m)
			var back_to := to_skel.affine_inverse()
			var mesh := ArrayMesh.new()
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				for i in vs.size():
					var p := to_skel * vs[i]
					if p.z < f.head_c.z:
						p.z = maxf(p.z, f.back_at(p.y) - f.head_d * 0.03)
						var half := maxf(f.body_width_at(p.y), f.head_width_at(p.y)) * 0.5 + f.head_d * 0.03
						p.x = f.head_c.x + clampf(p.x - f.head_c.x, -half, half)
					elif hug:
						p.z = minf(p.z, f.front_at(p.y) + f.head_d * 0.04)
					vs[i] = back_to * p
				arr[Mesh.ARRAY_VERTEX] = vs
				mesh.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
				mesh.surface_set_material(si, mi.mesh.surface_get_material(si))
			_wrapped[gk] = mesh
		mi.mesh = _wrapped[gk]


static var _wrapped := {}   # model path:piece:node -> the piece's mesh, bent to that model


## A node's transform relative to `root` (the root's own transform included).
static func _under(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var at: Node = n
	while at != null:
		if at is Node3D:
			t = (at as Node3D).transform * t
		if at == root:
			break
		at = at.get_parent()
	return t


## Reshape a piece in the critter's frame: `fn` gets every vertex and normal
## of every mesh in it ([PackedVector3Array, PackedVector3Array], skeleton
## space) and returns them moved. Made once per model, piece and fit.
static func _reshape(v: CritterVisual, m: Node3D, xf: Transform3D, id: String, tag: String, fn: Callable) -> void:
	var key := "%s:%s:%s:%d" % [v.def.resolved_model(), id, tag, hash(xf)]
	var mis: Array = ModelUtil.find_all(m, "MeshInstance3D").filter(func(g): return (g as MeshInstance3D).mesh != null)
	if not _reshaped.has(key):
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		var all := []   # per mesh: its surfaces' arrays
		for g in mis:
			var mi := g as MeshInstance3D
			var to_skel := xf * _under(mi, m)
			var nb := to_skel.basis.inverse().transposed()
			var surfs := []
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ns: Variant = arr[Mesh.ARRAY_NORMAL]
				for i in vs.size():
					pts.append(to_skel * vs[i])
					nrm.append((nb * (ns as PackedVector3Array)[i]).normalized() if ns != null else Vector3.ZERO)
				surfs.append(arr)
			all.append(surfs)
		var moved: Array = fn.call(pts, nrm)
		var out_pts: PackedVector3Array = moved[0]
		var out_nrm: PackedVector3Array = moved[1]
		var made := []
		var at := 0
		for j in mis.size():
			var mi := mis[j] as MeshInstance3D
			var back_to := (xf * _under(mi, m)).affine_inverse()
			var nb := back_to.basis.inverse().transposed()
			var mesh := ArrayMesh.new()
			for si in all[j].size():
				var arr: Array = all[j][si]
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ns: Variant = arr[Mesh.ARRAY_NORMAL]
				for i in vs.size():
					vs[i] = back_to * out_pts[at + i]
					if ns != null:
						(ns as PackedVector3Array)[i] = (nb * out_nrm[at + i]).normalized()
				at += vs.size()
				arr[Mesh.ARRAY_VERTEX] = vs
				if ns != null:
					arr[Mesh.ARRAY_NORMAL] = ns
				mesh.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
				mesh.surface_set_material(si, mi.mesh.surface_get_material(si))
			made.append(mesh)
		_reshaped[key] = made
	var made: Array = _reshaped[key]
	for j in mis.size():
		(mis[j] as MeshInstance3D).mesh = made[j]


static var _reshaped := {}   # model:piece:how:fit -> the piece's meshes, reshaped


## A necklace laid flat round the neck: what sticks out in front of the neck
## folds down onto the chest (a pendant hangs on it, facing forward).
static func _folded(pts: PackedVector3Array, nrm: PackedVector3Array, f: OutfitFit) -> Array:
	var gap := f.head_d * 0.03
	var base := INF   # (its underside, so a pendant keeps its thickness when it's folded)
	for p in pts:
		if p.z > f.front_at(p.y) + gap:
			base = minf(base, p.y)
	var down := Basis(Vector3.RIGHT, PI / 2.0)   # (forward turns to down, up to forward)
	for i in pts.size():
		var p := pts[i]
		var edge := f.front_at(p.y) + gap
		if p.z <= edge:
			continue
		var y := p.y - (p.z - edge)
		pts[i] = Vector3(p.x, y, f.front_at(y) + gap + maxf(p.y - base, 0.0))
		nrm[i] = down * nrm[i]
	return [pts, nrm]


## A pendant necklace pressed onto the chest: each bit of it (a grid across it,
## so a curved one flattens too) as far forward as the critter is there,
## keeping its thickness, and its ends round the sides of the neck.
static func _pressed(pts: PackedVector3Array, nrm: PackedVector3Array, f: OutfitFit) -> Array:
	var gap := f.head_d * 0.02
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	const NX := 10
	const NY := 16
	var span := (hi - lo).max(Vector2(0.001, 0.001))
	var cell := func(p: Vector3) -> int:
		return clampi(int((p.y - lo.y) / span.y * NY), 0, NY) * (NX + 1) + clampi(int((p.x - lo.x) / span.x * NX), 0, NX)
	var back := {}   # cell -> its back (the furthest back of it)
	for p in pts:
		var c: int = cell.call(p)
		back[c] = minf(back.get(c, INF), p.z)
	for i in pts.size():
		var p := pts[i]
		p.z += f.front_at(p.y) + gap - float(back[cell.call(p)])
		var half := maxf(f.body_width_at(p.y), f.neck_w) * 0.5 + gap
		var off := p.x - f.head_c.x
		if absf(off) > half:
			p.z -= absf(off) - half
			p.x = f.head_c.x + signf(off) * half
		pts[i] = p
	return [pts, nrm]


## Laid on the critter: nothing further out in front than the critter is at
## that height (a little room for fur).
static func _laid(pts: PackedVector3Array, nrm: PackedVector3Array, f: OutfitFit) -> Array:
	for i in pts.size():
		pts[i].z = minf(pts[i].z, f.front_at(pts[i].y) + f.head_d * 0.04)
	return [pts, nrm]


## A fine chain made thicker: every vertex pushed out along its normal.
static func _thickened(pts: PackedVector3Array, nrm: PackedVector3Array, by: float) -> Array:
	for i in pts.size():
		pts[i] += nrm[i] * by
	return [pts, nrm]


## Leave parts of a model off (by material name): the meshes made once.
static func _hide_parts(m: Node3D, id: String, names: Array) -> void:
	for g in ModelUtil.find_all(m, "MeshInstance3D"):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		var key := "%s:%s:%s" % [id, m.get_path_to(mi), ",".join(names)]
		if not _trimmed.has(key):
			var mesh := ArrayMesh.new()
			for si in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(si)
				if mat and names.has(mat.resource_name):
					continue
				mesh.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), mi.mesh.surface_get_arrays(si))
				mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			_trimmed[key] = mesh
		mi.mesh = _trimmed[key]


static var _trimmed := {}   # piece:node:names -> its mesh without those parts


## Swing one part of a model (by material) about the top of it, its bottom
## going back: a chin strap swung back under the chin. Model space (+Z its
## front, as turned); the meshes made once.
static func _swing_part(m: Node3D, id: String, part: String, degrees: float) -> void:
	for g in ModelUtil.find_all(m, "MeshInstance3D"):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		var key := "%s:%s:%s:%s" % [id, m.get_path_to(mi), part, degrees]
		if not _swung.has(key):
			var to_m := _under(mi, m)
			var back_to := to_m.affine_inverse()
			var mesh := ArrayMesh.new()
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var mat := mi.mesh.surface_get_material(si)
				if mat and mat.resource_name == part:
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var top := -INF
					var hinge_z := 0.0
					for p in vs:
						var q := to_m * p
						if q.y > top:
							top = q.y
							hinge_z = q.z
					var pivot := Vector3(0.0, top, hinge_z)
					var r := Basis(Vector3.RIGHT, deg_to_rad(degrees))
					for i in vs.size():
						vs[i] = back_to * (pivot + r * (to_m * vs[i] - pivot))
					arr[Mesh.ARRAY_VERTEX] = vs
					if arr[Mesh.ARRAY_NORMAL] != null:
						var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
						for i in ns.size():
							ns[i] = (back_to.basis * (r * (to_m.basis * ns[i]))).normalized()
						arr[Mesh.ARRAY_NORMAL] = ns
				mesh.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
				mesh.surface_set_material(si, mat)
			_swung[key] = mesh
		mi.mesh = _swung[key]


static var _swung := {}   # piece:node:part:degrees -> its mesh with that part swung


## A rogue's nudges to a fitted piece (see wear_piece).
static func _nudge(xf: Transform3D, box: AABB, f: OutfitFit, on_head: bool, a: Dictionary) -> Transform3D:
	var mid := xf * box.get_center()
	var depth := f.head_d if on_head else maxf(f.chest_front - f.chest_back, 0.05)
	var height := f.head_h if on_head else maxf(f.neck_y - f.chest_y, 0.05)
	var turn := Basis(Vector3.UP, deg_to_rad(float(a.get("turn", 0.0)))) * Basis(Vector3.RIGHT, deg_to_rad(-float(a.get("tilt", 0.0))))
	var grow := float(a.get("grow", 1.0))
	var about := Transform3D(turn.scaled(Vector3.ONE * grow), mid - (turn.scaled(Vector3.ONE * grow)) * mid)
	var width := f.head_w if on_head else f.shoulder_w
	var shift := Vector3(float(a.get("side", 0.0)) * width, float(a.get("up", 0.0)) * height, float(a.get("fwd", 0.0)) * depth)
	var out := Transform3D(Basis.IDENTITY, shift) * about * xf
	if a.has("deep"):
		# shorter (or longer) front to back, about its front: glasses' arms
		var front := out * Vector3(box.get_center().x, box.get_center().y, box.end.z)
		var squash := Basis().scaled(Vector3(1.0, 1.0, float(a.deep)))
		out = Transform3D(squash, front - squash * front) * out
	return out


## Where a piece goes (skeleton space): its scale (k) and where its origin
## goes, so that the measured parts of it land on the measured parts of the
## critter. `turn` stands the model the right way round, `box` is its bounds
## turned so.
static func _place(f: OutfitFit, id: String, spec: Dictionary, turn: Basis, box: AABB) -> Transform3D:
	var slot: String = spec.slot
	var shape: Dictionary = OutfitShapes.SHAPES.get(String(spec.get("model", id)), {})
	var size := float(spec.get("size", 1.0))
	var w := maxf(box.size.x, 0.001)
	var k := 1.0
	var at := Vector3.ZERO
	match slot:
		"hat", "band", "collar", "mask":
			# the head-hole (or a ring's middle) goes round the head, the muzzle or the neck
			var hole: Array = spec.get("hole", shape.get("hole", [0.0, 0.0]))
			var hw := float(spec.get("hole_w", 0.0))
			var tall := float(shape.get("box", [0, 0, 0, 0, 0.3, 0])[4])   # (its height, unturned)
			var p := Vector3.ZERO   # the point of it that goes to (the head's middle, seat): turned below
			var seat: float
			var round: float
			var mid_z: float
			match slot:
				"hat":
					seat = lerpf(f.crown_y, f.brow_y, float(spec.get("sink", 0.8)))
					round = minf(f.head_width_at(seat), f.head_width_at(f.eye_y))   # (not out to a hamster's ears)
					if f.hat_size > 1.0 and not spec.get("on_crown", false):
						# a bigger hat for a big head: it slides down until the skull fills
						# it (no lower than just above the eyes) and is that much wider
						var want := round * f.hat_size
						var floor_y := maxf(f.brow_y - f.head_h * 0.04, seat - f.head_h * 0.25)
						while seat > floor_y and f.head_width_at(seat) < want:
							seat -= f.head_h * 0.01
						round = want
					if spec.get("to_chin", false):
						# a helmet over the whole head: as wide as the face
						seat = f.chin_y - f.head_h * 0.05
						round = maxf(f.head_width_at(f.eye_y), f.head_width_at(lerpf(f.chin_y, f.crown_y, 0.5)))
					elif spec.get("on_crown", false):
						seat = f.crown_y - f.head_h * 0.03
					mid_z = f.crown_z - float(spec.get("back", 0.04)) * f.head_d
					p = Vector3(float(hole[0]), float(spec.get("rim", shape.get("rim", 0.0))), float(hole[1]))
				"band":
					seat = lerpf(f.brow_y, f.crown_y, 0.3)
					round = minf(f.head_width_at(seat), f.head_width_at(f.eye_y))
					mid_z = f.crown_z
					p = Vector3(float(hole[0]), tall * 0.5, float(hole[1]))
				"mask":
					# a bandana's cloth over the muzzle, its top edge just under the eyes;
					# its loop is sized to the snout, so on a big round head the back of it
					# goes unseen inside (mid_z: set below, once its depth is known)
					seat = f.eye_y - f.head_h * 0.07
					round = clampf(f.head_width_at(f.muzzle_y) * 0.9, f.muzzle_w * 1.25, f.muzzle_w * 1.9)
					p = Vector3(float(hole[0]), tall, float(hole[1]))
				_:
					# round the neck: between the shoulders and the chin (its loop: the
					# middle of the model, or spec "rim" for a neckerchief whose tails
					# hang below it)
					seat = minf(lerpf(f.shoulder_y, minf(f.neck_y, f.chin_y), 0.55), f.chin_y - f.head_h * 0.1)
					round = maxf(f.body_width_at(seat), f.neck_w * 0.8)
					mid_z = (f.front_at(seat) + f.back_at(seat)) * 0.5
					p = Vector3(float(hole[0]), float(spec.get("rim", tall * 0.5)), float(hole[1]))
			if spec.get("on_crown", false):
				p = box.get_center()   # (a beret: its middle on top of the head, tipped down one side)
				if hw <= 0.0:
					hw = box.size.x
			elif (spec.has("roll") or spec.has("pitch")) and not spec.has("hole"):
				# (stood up some other way: its measured hole doesn't apply; the bounds' foot does)
				p = Vector3(box.get_center().x, box.position.y + box.size.y * 0.25, box.get_center().z)
				if hw <= 0.0:
					hw = box.size.x * 0.8
			else:
				p = turn * p
			if hw <= 0.0:
				# its width across the critter, turned: a quarter turn swaps width and depth
				hw = absf(turn.x.x) * float(shape.get("w", w)) + absf(turn.z.x) * float(shape.get("d", w))
			k = round * float(spec.get("fit", 1.04)) * size / maxf(hw, 0.001)
			var flat := float(spec.get("flat", 1.0))
			# front to back: no deeper than the head there (a ring round a narrow
			# raccoon's muzzle, a chef's hat on a hamster's short head)
			var hd := absf(turn.x.z) * float(shape.get("w", w)) + absf(turn.z.z) * float(shape.get("d", box.size.z))
			var deep := f.front_at(seat) - f.back_at(seat)
			var kz := clampf(deep * float(spec.get("fit", 1.04)) * size / maxf(hd, 0.001), k * (0.8 if slot == "hat" else 0.7), k * (1.0 if slot == "hat" else 1.3))
			if spec.get("to_chin", false):
				kz = k   # (a helmet over the whole head: as deep as it's wide, or a long snout comes out the front)
			if slot == "mask":
				# its front on the front of the muzzle; the cloth no lower than just
				# under the chin
				kz = k
				var front := f.muzzle_z
				for i in 5:   # (in front of whatever bulges below the snout: a hamster's cheeks)
					front = maxf(front, f.front_at(lerpf(f.chin_y, seat, i / 4.0)))
				mid_z = front + f.head_d * 0.05 - (box.end.z - p.z) * k
				flat *= clampf((seat - f.chin_y + f.head_h * 0.12) / maxf(tall * k, 0.001), 0.6, 1.0)
			if slot == "hat" and not spec.get("tall", false) and not shape.get("open", false) and shape.has("top") \
					and not (spec.has("roll") or spec.has("pitch")):
				# the inside of the crown down onto the skull (a little room for fur)
				var inside := (float(shape.top) - float(shape.rim)) * k
				flat *= clampf((f.crown_y - seat + f.head_h * 0.04) / maxf(inside, 0.001), 0.7, 1.0) * (1.0 if spec.get("to_chin", false) else f.hat_stretch)
			if spec.has("max_h"):
				# (no longer than this share of the head's height: a neckerchief's tails)
				flat *= minf(1.0, f.head_h * float(spec.max_h) / maxf(tall * k, 0.001))
			at = Vector3(f.head_c.x - p.x * k, seat - p.y * k * flat, mid_z - p.z * kz)
			return Transform3D(Basis().scaled(Vector3(k, k * flat, kz)), at)
		"glasses":
			# lenses over the eyes: they're about a quarter of the way in from each end
			# (or a mask's one wide lens, `lens`: [middle x, middle y, half width],
			# a little wider than the eyes are apart)
			var mid := Vector2(box.get_center().x, box.get_center().y)
			size *= f.glasses_size
			k = f.eye_x * size / (w * 0.27)
			var lens_z := box.end.z
			if spec.has("lens"):
				var lens: Array = spec.lens
				mid = Vector2(float(lens[0]), float(lens[1]))
				k = f.eye_x * 1.75 * size / float(lens[2])
			if spec.has("lenses"):
				# (two lenses not where the box puts them, goggles: [their middles'
				# height, how far each is from the middle, how far forward])
				var ls: Array = spec.lenses
				mid = Vector2(0.0, float(ls[0]))
				k = f.eye_x * size / float(ls[1])
				lens_z = float(ls[2])
			# (the lenses just in front of the eyes: a snout goes through the bridge;
			# a mask's one wide lens has to clear the whole face)
			var front := (maxf(f.face_z, f.eye_z) if spec.has("lens") else f.eye_z) + f.head_d * 0.04
			at = Vector3(f.head_c.x - mid.x * k, f.eye_y - mid.y * k, front - lens_z * k)
		"monocle":
			# the ring (at the top of the model; its chain hangs below) on the right
			# eye, as wide as the eye
			k = f.eye_x * 1.25 * f.glasses_size * size / w
			var ring := Vector2(box.get_center().x, box.end.y - w * 0.5)
			var eye_x := f.eye_x if spec.get("eye", "right") == "left" else -f.eye_x   # (its right eye is -x)
			at = Vector3(f.head_c.x + eye_x - ring.x * k, f.eye_y - ring.y * k, f.eye_z + f.head_d * 0.03 - box.end.z * k)
		"lashes":
			# along the top of each eye's lid, a little to the outside (a pair:
			# their middles about 0.4 of the model's width out each side)
			k = (f.eye_x + f.eye_r * 0.3) * size / (w * 0.4)
			at = Vector3(f.head_c.x - box.get_center().x * k, f.eye_y + f.eye_r * 0.85 - box.get_center().y * k,
				f.eye_z + f.head_d * 0.01 - box.end.z * k)
		"mustache":
			# under the nose, on the upper lip
			k = maxf(f.muzzle_w, f.eye_x * 2.0) * 1.35 * size / w
			at = Vector3(f.head_c.x - box.get_center().x * k, lerpf(f.muzzle_y, f.chin_y, 0.35) - box.get_center().y * k,
				f.muzzle_z + f.head_d * 0.02 - box.position.z * k * 0.6)
		"earring":
			# hanging from the side of the head, about where the ear meets it
			k = f.head_h * 0.22 * size / maxf(box.size.y, 0.001)
			var side := f.head_width_at(f.brow_y) * 0.5
			at = Vector3(f.head_c.x - side - box.get_center().x * k, f.brow_y - box.end.y * k, f.head_c.z - box.get_center().z * k)
		"shoulders":
			# a pad on each shoulder, as far apart as the shoulders
			k = f.shoulder_w * 1.15 * size / w
			var top := f.shoulder_y + f.head_h * 0.12
			at = Vector3(f.head_c.x - box.get_center().x * k, top - box.end.y * k,
				(f.front_at(f.shoulder_y) + f.back_at(f.shoulder_y)) * 0.5 - box.get_center().z * k)
		"bow":
			var y := minf(f.chin_y - f.head_h * 0.06, f.neck_y + f.head_h * 0.05)
			k = maxf(f.neck_w, f.head_w * 0.55) * 0.5 * size / w
			at = Vector3(f.head_c.x - box.get_center().x * k, y - box.get_center().y * k, f.front_at(y) + f.head_d * 0.01 - box.position.z * k)
		"pendant":
			# a necklace that hangs flat at the front of the neck, from under the chin
			var top := minf(lerpf(f.shoulder_y, minf(f.neck_y, f.chin_y), 0.9), f.chin_y - f.head_h * 0.03)
			k = maxf(maxf(f.body_width_at(top), f.neck_w), f.head_w * 0.6) * 0.6 * size / w
			var front := -INF
			for i in 4:
				front = maxf(front, f.front_at(top - box.size.y * k * i / 3.0))
			at = Vector3(f.head_c.x - box.get_center().x * k, top - box.end.y * k, front + f.head_d * 0.01 - box.position.z * k)
		"medal":
			var y := lerpf(f.chest_y, f.neck_y, 0.4)
			k = f.body_width_at(y) * 0.22 * size / w
			at = Vector3(f.head_c.x + f.body_width_at(y) * 0.2 - box.get_center().x * k, y - box.get_center().y * k,
				f.front_at(y) + f.head_d * 0.01 - box.position.z * k)
		"cape":
			# as wide as the back it hangs down (a squirrel is wider below than at
			# the shoulders) and the shoulders and arms, down to near the ground
			# (over a tail: it drapes)
			var top := cape_top(f)
			var bottom := top * 0.1
			if f.cape_over_tail and f.tail_y > 0.0:
				bottom = f.tail_y + f.head_h * 0.02   # (its hem resting on top of the tail)
			var wide := f.shoulder_w * 1.35
			for i in 6:
				wide = maxf(wide, f.body_width_at(lerpf(top, f.hip_y, i / 5.0)) * 1.05)
			k = wide * size / w
			var ky := minf(k, (top - bottom) / maxf(box.size.y, 0.001))
			if f.cape_over_tail:
				ky = maxf(ky, k * 0.75)   # (not crushed flat on top of a tail at the hips: it drapes down over it)
			at = Vector3(f.head_c.x - box.get_center().x * k, top - box.end.y * ky, f.back_at(top) + f.head_d * 0.03 - box.end.z * k)
			return Transform3D(Basis().scaled(Vector3(k, ky, k)), at)
		"wings":
			var y := lerpf(f.chest_y, f.neck_y, 0.4)
			k = f.shoulder_w * 1.6 * size / w
			at = Vector3(f.head_c.x - box.get_center().x * k, y - box.get_center().y * k, f.back_at(y) + f.head_d * 0.04 - box.end.z * k)
		"pack":
			# its top just under the head, most of the way down the back, no wider than the back
			var top := cape_top(f)
			var y := lerpf(f.hip_y, top, 0.6)
			k = minf((top - f.hip_y) * 0.85 / maxf(box.size.y, 0.001), minf(f.body_width_at(y), f.shoulder_w) * 0.9 / w) * size
			if spec.get("mid", false):
				# (a wind-up key: in the middle of the back, not hung from the shoulders)
				top = lerpf(f.hip_y, top, 0.75) + box.size.y * k * 0.5
			var back := minf(f.back_at(top - box.size.y * k * 0.3), f.back_at(top - box.size.y * k * 0.7))
			if float(spec.get("inset", 0.0)) > 0.0:
				# worn against the back: its own straps sunk into it, and it leans as
				# the back does between its top and bottom (a round hamster's back
				# slopes away at the top)
				var hk := box.size.y * k
				var hi := f.back_at(top - hk * 0.15)
				var lo := f.back_at(top - hk * 0.85)
				var lean := atan2(hi - lo, hk * 0.7)   # (+: its top tips in, toward the body)
				at = Vector3(f.head_c.x - box.get_center().x * k, top - box.end.y * k,
					(hi + lo) * 0.5 + f.head_d * 0.02 - (box.end.z - float(spec.inset) * box.size.z) * k)
				var placed := Transform3D(Basis().scaled(Vector3.ONE * k), at)
				var pivot := placed * Vector3(box.get_center().x, box.get_center().y, box.end.z - float(spec.inset) * box.size.z)
				var r := Basis(Vector3.RIGHT, lean)
				return Transform3D(r, pivot - r * pivot) * placed
			at = Vector3(f.head_c.x - box.get_center().x * k, top - box.end.y * k, back + f.head_d * 0.02 - box.end.z * k)
	return Transform3D(Basis().scaled(Vector3(k, k * float(spec.get("flat", 1.0)), k)), at)


## Where a cape's top edge and a pack's top go: just under the head, at the
## shoulders (a fox's long neck: lower than its head).
static func cape_top(f: OutfitFit) -> float:
	return minf(f.neck_y - f.head_h * 0.05, lerpf(f.shoulder_y, f.neck_y, 0.3))


static func _tint(mi: MeshInstance3D, tint: Color, two_sided := false) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s) as BaseMaterial3D
		if mat == null:
			continue
		var copy := mat.duplicate() as BaseMaterial3D
		if two_sided:
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
		if tint != Color.WHITE:
			# dyed: one flat colour (a dark texture under a tint only goes darker)
			copy.albedo_texture = null
			copy.albedo_color = Color(tint, mat.albedo_color.a)
		mi.set_surface_override_material(s, copy)
