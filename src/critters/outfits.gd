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

## Slots: "hat" (sits on the crown), "glasses" (across the eyes), "monocle"
## (the right eye), "mask" (over the muzzle), "band" (round the forehead),
## "headphones" (over the crown, cups at the sides), "bow" (under the chin),
## "collar" (round the neck), "medal" (on the chest), "cape" and "pack" (on
## the back).
## size: times the slot's own width (the skull, the face, the neck...);
## yaw (and roll, pitch): degrees that turn the model to face the way the
## critter does (and stand it the right way up);
## two_sided: draw both faces (a cape's inside shows from the front);
## sink: how far a hat comes down over the crown (share of the head's height);
## back: how far back from the middle of the skull a hat sits (share of its depth);
## strap: the share of the model's height that hangs below where the head
## goes in (a chin strap, a sloping brim);
## flat: squash it to this share of its height (a band as thin as a band).
const PIECES := {
	"captain_hat": {"slot": "hat", "size": 1.15, "yaw": 0.0, "sink": 0.16},
	"top_hat": {"slot": "hat", "size": 0.95, "yaw": 0.0, "sink": 0.1},
	"gent_top_hat": {"slot": "hat", "size": 1.25, "yaw": 0.0, "sink": 0.1},
	"crown": {"slot": "hat", "size": 0.75, "yaw": 0.0, "sink": 0.04},
	"cowboy_hat": {"slot": "hat", "size": 1.7, "yaw": 0.0, "sink": 0.14},
	"beret": {"slot": "hat", "size": 1.05, "yaw": 0.0, "roll": 78.0, "sink": 0.06},
	"bucket_hat": {"slot": "hat", "size": 1.3, "yaw": 0.0, "sink": 0.2, "strap": 0.38},
	"cavalier_hat": {"slot": "hat", "size": 2.0, "yaw": 0.0, "sink": 0.12},
	"straw_hat": {"slot": "hat", "size": 1.7, "yaw": 0.0, "sink": 0.14},
	"deerstalker": {"slot": "hat", "size": 1.2, "yaw": 0.0, "sink": 0.16},
	"fez": {"slot": "hat", "size": 0.6, "yaw": 0.0, "sink": 0.04},
	"fur_hat": {"slot": "hat", "size": 1.15, "yaw": 0.0, "sink": 0.18},
	"mountie_hat": {"slot": "hat", "size": 1.6, "yaw": 0.0, "sink": 0.14},
	"bearskin": {"slot": "hat", "size": 0.95, "yaw": 0.0, "sink": 0.18, "strap": 0.26},
	"band_hat": {"slot": "hat", "size": 0.8, "yaw": 0.0, "sink": 0.12, "strap": 0.3},
	"robin_hat": {"slot": "hat", "size": 1.35, "yaw": 0.0, "sink": 0.16},
	"trucker_red": {"slot": "hat", "size": 1.0, "yaw": 0.0, "sink": 0.16},
	"trucker_blue": {"slot": "hat", "size": 1.0, "yaw": 0.0, "sink": 0.16},
	"trucker_yellow": {"slot": "hat", "size": 1.0, "yaw": 0.0, "sink": 0.16},
	"hard_hat": {"slot": "hat", "size": 1.25, "yaw": 0.0, "sink": 0.18},
	"party_hat": {"slot": "hat", "size": 0.55, "yaw": 0.0, "sink": 0.04},
	"propeller_hat": {"slot": "hat", "size": 1.05, "yaw": 0.0, "sink": 0.14},
	"beanie": {"slot": "hat", "size": 1.1, "yaw": 0.0, "sink": 0.22},
	"viking_helmet": {"slot": "hat", "size": 1.15, "yaw": 90.0, "sink": 0.22},
	"pirate_hat": {"slot": "hat", "size": 1.5, "yaw": 0.0, "sink": 0.12},
	"wizard_hat": {"slot": "hat", "size": 1.4, "yaw": 0.0, "sink": 0.12},
	"knight_helmet": {"slot": "hat", "size": 1.2, "yaw": 0.0, "sink": 0.75},
	"chef_hat": {"slot": "hat", "size": 1.05, "yaw": 0.0, "sink": 0.14},
	"sunglasses": {"slot": "glasses", "size": 1.15, "yaw": 0.0},
	"aviators": {"slot": "glasses", "size": 1.15, "yaw": 0.0},
	"goggles": {"slot": "glasses", "size": 1.2, "yaw": 0.0},
	"monocle": {"slot": "monocle", "size": 1.0, "yaw": 0.0},
	"bandana_mask": {"slot": "mask", "size": 0.75, "yaw": 0.0},
	"headband": {"slot": "band", "size": 1.02, "yaw": 0.0, "flat": 0.45},
	"headphones": {"slot": "headphones", "size": 1.45, "yaw": 90.0},
	"bow_tie": {"slot": "bow", "size": 1.0, "yaw": 0.0},
	"scarf": {"slot": "collar", "size": 1.25, "yaw": 0.0},
	"bead_necklace": {"slot": "collar", "size": 1.2, "yaw": 0.0},
	"medal": {"slot": "medal", "size": 1.0, "yaw": 0.0},
	"cape": {"slot": "cape", "size": 2.1, "yaw": 0.0, "two_sided": true},
	"backpack": {"slot": "pack", "size": 1.25, "yaw": 0.0},
}

## Who wears what: the fur (one of the species' skins) and the pieces, each
## a piece id or [piece id, tint].
const LOOKS := {
	# bandit bunnies
	"Captain Carrot": {"skin": "wild_hare", "wear": ["captain_hat", "medal"]},
	"Vex": {"skin": "shadow", "wear": [["scarf", "#6f8f45"], ["bandana_mask", "#5d7a3a"]]},
	"Bunnicula": {"skin": "frost", "wear": [["cape", "#2a1a2e"], ["bow_tie", "#8a1a24"]]},
	"Lop-Eared Larry": {"skin": "default", "wear": [["beanie", "#d8a23a"], "backpack"]},
	"Snickerdoodle": {"skin": "toxic", "wear": ["party_hat", "sunglasses"]},
	"Cottontail Kate": {"skin": "default", "wear": [["headband", "#f2efe6"]]},
	"Hops McGee": {"skin": "wild_hare", "wear": ["viking_helmet"]},
	# squirrels
	"Nutsy": {"skin": "default", "wear": ["headphones"]},
	"Acorn Al": {"skin": "grey", "wear": ["trucker_red", "backpack"]},
	"Sir Scamper": {"skin": "fox_squirrel", "wear": ["cavalier_hat", ["cape", "#8a2a32"]]},
	"Hazel": {"skin": "default", "wear": ["robin_hat"]},
	"Twitch": {"skin": "blueberry", "wear": ["goggles"]},
	"Kernel": {"skin": "black", "wear": ["straw_hat"]},
	"Bushytail Betty": {"skin": "fox_squirrel", "wear": ["beret", "aviators"]},
	# foxes
	"Sly": {"skin": "silver", "wear": ["deerstalker"]},
	"Vixen Vera": {"skin": "default", "wear": ["aviators", ["scarf", "#efe2b0"]]},
	"Fennick": {"skin": "fennec", "wear": ["trucker_yellow"]},
	"Foxy Roxy": {"skin": "kitsune", "wear": ["sunglasses", ["bow_tie", "#e0569a"]]},
	"Sir Reynard": {"skin": "default", "wear": [["top_hat", "#5a4a62"], "monocle"]},
	"Ember": {"skin": "default", "wear": ["goggles", ["scarf", "#d8452a"]]},
	"Duchess": {"skin": "arctic", "wear": ["bearskin", ["cape", "#5b3a8a"]]},
	# raccoons
	"Bandit Bill": {"skin": "default", "wear": ["pirate_hat"]},
	"Trash Panda": {"skin": "cinnamon", "wear": ["bucket_hat", "backpack"]},
	"Rocco": {"skin": "red_panda", "wear": [["headband", "#d23a2a"]]},
	"Masky": {"skin": "default", "wear": [["bandana_mask", "#3a3a40"]]},
	"Dumpster Dot": {"skin": "blonde", "wear": [["beanie", "#6b8f5a"], ["scarf", "#b0a080"]]},
	"Grimsby": {"skin": "starry_night", "wear": ["fur_hat", ["scarf", "#7a7a80"]]},
	"Lady Garbage": {"skin": "starry_night", "wear": ["crown", "bead_necklace"]},
	# frogs
	"Croaker": {"skin": "toad", "wear": ["cowboy_hat"]},
	"Lily Pad Lou": {"skin": "tree_frog", "wear": [["bucket_hat", "#a8c890"]]},
	"Hopscotch": {"skin": "poison_dart", "wear": ["propeller_hat"]},
	"Sir Toadsworth": {"skin": "golden", "wear": ["gent_top_hat", "bow_tie"]},
	"Puddles": {"skin": "default", "wear": [["beanie", "#3b6fb5"]]},
	"Bog Boss": {"skin": "default", "wear": ["band_hat"]},
	"Gulp": {"skin": "default", "wear": ["sunglasses", "medal"]},
	# beavers
	"Chompers": {"skin": "default", "wear": ["knight_helmet"]},
	"Dam Dan": {"skin": "default", "wear": ["hard_hat"]},
	"Buck Toothington": {"skin": "honey", "wear": ["mountie_hat", "monocle"]},
	"Timber": {"skin": "lumberjack", "wear": [["beanie", "#b33a2a"]]},
	"Lodge Lady": {"skin": "default", "wear": [["beret", "#7a4a2a"], "backpack"]},
	"Gnawman": {"skin": "chocolate", "wear": [["bucket_hat", "#8a9a70"], "sunglasses"]},
	"Dr. Splash": {"skin": "bubblegum", "wear": ["goggles", ["cape", "#c03030"]]},
	# hamsters
	"Squeaks": {"skin": "default", "wear": [["scarf", "#e8c640"], "backpack"]},
	"Cheeks McGee": {"skin": "panda", "wear": ["trucker_blue", "sunglasses"]},
	"Nibbler": {"skin": "dove", "wear": [["bandana_mask", "#c0302a"]]},
	"Pudge": {"skin": "black_bear", "wear": ["fez"]},
	"Whisker Biscuit": {"skin": "cotton_candy", "wear": ["chef_hat"]},
	"Turbo": {"skin": "default", "wear": ["trucker_red", "goggles"]},
	"Wheelie": {"skin": "dove", "wear": [["top_hat", "#2e2e36"], ["bow_tie", "#d8b040"]]},
}

## Bones the slots ride on.
const ON_HEAD := ["hat", "glasses", "monocle", "mask", "band", "headphones"]
## Pieces stop drawing this far away (a bot that far off is a speck).
const DRAW_DISTANCE := 110.0


static func model_path(id: String) -> String:
	return "res://assets/env/outfit_%s/outfit_%s.glb" % [id, id]


static func look_of(rogue: String) -> Dictionary:
	return LOOKS.get(rogue, {})


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
		var tint := Color(item[1]) if item is Array else Color.WHITE
		wear(c.visual, id, tint)


## Put one piece on (returns it, or null if its model is missing).
static func wear(v: CritterVisual, id: String, tint := Color.WHITE) -> Node3D:
	var spec: Dictionary = PIECES.get(id, {})
	if spec.is_empty():
		return null
	var m := ModelUtil.instantiate(model_path(id))
	if m == null:
		return null
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
	var xf := _place(fit, slot, spec, box)
	m.transform = Transform3D(turn, Vector3.ZERO)
	holder.transform = (v.rig.rest[role] as Transform3D).affine_inverse() * xf
	for gi in ModelUtil.find_all(m, "GeometryInstance3D"):
		var g := gi as GeometryInstance3D
		g.layers = CritterVisual.RENDER_LAYER
		g.visibility_range_end = DRAW_DISTANCE
		if (tint != Color.WHITE or spec.get("two_sided", false)) and g is MeshInstance3D:
			_tint(g as MeshInstance3D, tint, spec.get("two_sided", false))
	att.add_child(holder)
	v.outfit.append(holder)
	return holder


## Where a piece goes (skeleton space): its scale and the position of its
## origin (the env pipeline puts that at the bottom middle of the model).
static func _place(f: OutfitFit, slot: String, spec: Dictionary, box: AABB) -> Transform3D:
	var size := float(spec.get("size", 1.0))
	var w := maxf(box.size.x, 0.001)
	var k := 1.0
	var at := Vector3.ZERO
	match slot:
		"hat":
			k = f.head_w * size / w
			at = Vector3(f.head_c.x, f.crown_y - float(spec.get("sink", 0.15)) * f.head_h - float(spec.get("strap", 0.0)) * box.size.y * k,
				f.head_c.z - float(spec.get("back", 0.05)) * f.head_d)
		"glasses":
			k = f.face_w * size / w
			at = Vector3(f.head_c.x, f.eye_y - box.get_center().y * k, f.face_z + f.head_d * 0.04 - box.end.z * k)
		"monocle":
			k = f.face_w * 0.3 * size / w
			at = Vector3(f.head_c.x - f.face_w * 0.22, f.eye_y - box.get_center().y * k, f.face_z + f.head_d * 0.03 - box.end.z * k)
		"mask":
			k = f.face_w * size / w
			at = Vector3(f.head_c.x, f.eye_y - f.head_h * 0.08 - box.end.y * k, f.muzzle_z + f.head_d * 0.05 - box.end.z * k)
		"band":
			k = f.head_width_at(lerpf(f.eye_y, f.crown_y, 0.38)) * size / w
			at = Vector3(f.head_c.x, lerpf(f.eye_y, f.crown_y, 0.38) - box.get_center().y * k * float(spec.get("flat", 1.0)), f.head_c.z - box.get_center().z * k)
		"headphones":
			k = f.head_w * size / w
			at = Vector3(f.head_c.x, f.crown_y + f.head_h * 0.04 - box.end.y * k, f.head_c.z - box.get_center().z * k)
		"bow":
			k = f.neck_w * 0.6 * size / w
			at = Vector3(f.head_c.x, f.neck_y - f.head_h * 0.1 - box.get_center().y * k, f.neck_front + f.head_d * 0.02 - box.position.z * k)
		"collar":
			k = f.neck_w * size / w
			var mid_z := (f.neck_front + f.chest_back) * 0.5
			at = Vector3(f.head_c.x, f.neck_y - f.head_h * 0.18 - box.get_center().y * k, mid_z - box.get_center().z * k)
		"medal":
			k = f.chest_w * 0.22 * size / w
			at = Vector3(f.head_c.x + f.chest_w * 0.18, lerpf(f.chest_y, f.neck_y, 0.35) - box.get_center().y * k, f.chest_front + f.head_d * 0.02 - box.position.z * k)
		"cape":
			k = f.chest_w * size / w
			at = Vector3(f.head_c.x, maxf(f.shoulder_y, f.neck_y) + f.head_h * 0.15 - box.end.y * k, f.chest_back - f.head_d * 0.06 - box.end.z * k)
		"pack":
			k = f.chest_w * 0.75 * size / w
			at = Vector3(f.head_c.x, lerpf(f.chest_y, f.shoulder_y, 0.5) - box.get_center().y * k, f.chest_back + f.head_d * 0.04 - box.end.z * k)
	return Transform3D(Basis().scaled(Vector3(k, k * float(spec.get("flat", 1.0)), k)), at)


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
