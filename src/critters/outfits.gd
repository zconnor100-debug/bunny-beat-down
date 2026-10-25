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
## tall: a hat that stands tall by design (a top hat, a chef's hat); the rest
##   are squashed a little (to 70 %, at most) so the inside of the crown sits
##   on the skull rather than floating over a flat-topped squirrel;
## hole / hole_w: the head-hole's middle [x, z] and width, where measuring
##   can't find them (a closed top hat, a cavalier's curled brim); rim: the
##   height its rim is at, where a chin strap hangs below it;
## flat: squash it to this share of its height (a band as thin as a band);
## two_sided: draw both faces (a cape's inside shows from the front);
## tint: its colour when the look doesn't give one (a model that came pale).
const PIECES := {
	"captain_hat": {"slot": "hat", "sink": 0.55},
	"top_hat": {"slot": "hat", "tall": true, "sink": 0.35, "fit": 0.85, "hole": [0.0, 0.0], "hole_w": 0.26},
	"gent_top_hat": {"slot": "hat", "tall": true, "sink": 0.35, "fit": 0.88},
	"crown": {"slot": "hat", "tall": true, "sink": 0.4, "fit": 1.1},
	"cowboy_hat": {"slot": "hat", "sink": 0.75},
	"beret": {"slot": "hat", "on_crown": true, "fit": 0.85, "roll": 78.0, "pitch": 12.0, "hole_w": 0.3},
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
	"knight_helmet": {"slot": "hat", "to_chin": true, "fit": 1.12},
	"chef_hat": {"slot": "hat", "tall": true, "sink": 0.7, "fit": 0.95},
	"sunglasses": {"slot": "glasses"},
	"aviators": {"slot": "glasses"},
	"goggles": {"slot": "glasses", "size": 1.05},
	"monocle": {"slot": "monocle"},
	"bandana_mask": {"slot": "mask"},
	"headband": {"slot": "band", "flat": 0.3, "fit": 0.9},
	"bow_tie": {"slot": "bow"},
	"scarf": {"slot": "collar", "flat": 0.6},
	"bead_necklace": {"slot": "collar", "fit": 1.15, "yaw": 90.0, "pitch": 25.0, "hole": [0.3, 0.0], "hole_w": 1.45},
	"medal": {"slot": "medal"},
	"cape": {"slot": "cape", "two_sided": true},
	"backpack": {"slot": "pack", "yaw": 90.0},
	# yours only (the Workshop's wardrobe: no rogue wears these)
	"witch_hat": {"slot": "hat", "tall": true, "sink": 0.7, "hole_w": 0.17},
	"santa_hat": {"slot": "hat", "sink": 0.9},
	"grad_cap": {"slot": "hat", "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.45, "tint": "#23232b"},
	"fedora": {"slot": "hat", "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.34},
	"flower_crown": {"slot": "hat", "tall": true, "sink": 0.45, "fit": 1.1, "hole": [0.0, 0.0], "hole_w": 0.72},
	"jester_hat": {"slot": "hat", "tall": true, "sink": 0.7, "hole": [0.0, 0.0], "hole_w": 0.38},
	"flap_beanie": {"slot": "hat", "sink": 1.0, "rim": 0.13},
	"heart_glasses": {"slot": "glasses", "tint": "#ff6fae"},
	"star_glasses": {"slot": "glasses", "size": 1.1},
	"glasses_3d": {"slot": "glasses"},
	"pixel_shades": {"slot": "glasses", "yaw": 90.0},
	"sapphire_necklace": {"slot": "pendant", "yaw": 90.0, "roll": 90.0},
	"ring_necklace": {"slot": "collar", "fit": 1.2},
	"jetpack": {"slot": "pack"},
	"fairy_wings": {"slot": "wings", "two_sided": true},
	"dark_wings": {"slot": "wings", "size": 1.3, "two_sided": true},
	"butterfly_wings": {"slot": "wings", "two_sided": true},
}

## Who wears what: the fur (one of the species' skins) and the pieces, each
## a piece id or [piece id, tint].
const LOOKS := {
	# bandit bunnies
	"Captain Carrot": {"skin": "wild_hare", "wear": ["captain_hat", "medal"]},
	"Vex": {"skin": "shadow", "wear": [["bandana_mask", "#5d7a3a"]]},
	"Bunnicula": {"skin": "frost", "wear": [["cape", "#2a1a2e"], ["bow_tie", "#8a1a24"]]},
	"Lop-Eared Larry": {"skin": "default", "wear": [["beanie", "#d8a23a"], "backpack"]},
	"Snickerdoodle": {"skin": "toxic", "wear": ["party_hat", "sunglasses"]},
	"Cottontail Kate": {"skin": "default", "wear": [["headband", "#f2efe6"]]},
	"Hops McGee": {"skin": "wild_hare", "wear": ["viking_helmet"]},
	# squirrels
	"Nutsy": {"skin": "default", "wear": [["headband", "#ffd23a"], ["scarf", "#3a7fd6"]]},
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
const ON_HEAD := ["hat", "glasses", "monocle", "mask", "band"]
## Pieces stop drawing this far away (a bot that far off is a speck).
const DRAW_DISTANCE := 110.0


static func model_path(id: String) -> String:
	return "res://assets/env/outfit_%s/outfit_%s.glb" % [id, id]


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
		var tint := Color(item[1]) if item is Array else Color.WHITE
		wear_piece(c.visual, id, tint)


## Put one piece on (returns it, or null if its model is missing).
static func wear_piece(v: CritterVisual, id: String, tint := Color.WHITE) -> Node3D:
	var spec: Dictionary = PIECES.get(id, {})
	if spec.is_empty():
		return null
	if tint == Color.WHITE and spec.has("tint"):
		tint = Color(spec.tint)
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
	var xf := _place(fit, id, spec, turn, box)
	m.transform = Transform3D(turn, Vector3.ZERO)
	if slot == "cape":
		var cape := _drape(v, m, xf, fit, id)
		holder.free()
		if cape:
			_finish(v, cape, spec, tint)
		return cape
	holder.transform = (v.rig.rest[role] as Transform3D).affine_inverse() * xf
	att.add_child(holder)
	_finish(v, holder, spec, tint)
	return holder


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
	var run := INF
	for i in STEPS + 1:
		run = minf(run, f.back_at(top - step * i) - f.head_d * 0.04 * clampf(i / 4.0, 0.0, 1.0))
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


## Where a piece goes (skeleton space): its scale (k) and where its origin
## goes, so that the measured parts of it land on the measured parts of the
## critter. `turn` stands the model the right way round, `box` is its bounds
## turned so.
static func _place(f: OutfitFit, id: String, spec: Dictionary, turn: Basis, box: AABB) -> Transform3D:
	var slot: String = spec.slot
	var shape: Dictionary = OutfitShapes.SHAPES.get(id, {})
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
					# round the neck: between the shoulders and the chin
					seat = minf(lerpf(f.shoulder_y, minf(f.neck_y, f.chin_y), 0.55), f.chin_y - f.head_h * 0.1)
					round = maxf(f.body_width_at(seat), f.neck_w * 0.8)
					mid_z = (f.front_at(seat) + f.back_at(seat)) * 0.5
					p = Vector3(float(hole[0]), tall * 0.5, float(hole[1]))
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
			at = Vector3(f.head_c.x - p.x * k, seat - p.y * k * flat, mid_z - p.z * kz)
			return Transform3D(Basis().scaled(Vector3(k, k * flat, kz)), at)
		"glasses":
			# lenses over the eyes: they're about a quarter of the way in from each end
			k = f.eye_x * size / (w * 0.27)
			var front := maxf(f.face_z, f.eye_z) + f.head_d * 0.05
			at = Vector3(f.head_c.x - box.get_center().x * k, f.eye_y - box.get_center().y * k, front - box.end.z * k)
		"monocle":
			k = f.eye_x * 0.9 * size / w
			at = Vector3(f.head_c.x - f.eye_x - box.get_center().x * k, f.eye_y - box.get_center().y * k,
				f.eye_z + f.head_d * 0.03 - box.end.z * k)
		"bow":
			var y := f.chin_y - f.head_h * 0.06
			k = f.neck_w * 0.5 * size / w
			at = Vector3(f.head_c.x - box.get_center().x * k, y - box.get_center().y * k, f.front_at(y) + f.head_d * 0.01 - box.position.z * k)
		"pendant":
			# a necklace that hangs flat down the chest from under the chin
			var top := minf(lerpf(f.shoulder_y, minf(f.neck_y, f.chin_y), 0.55), f.chin_y - f.head_h * 0.05)
			k = maxf(f.body_width_at(top), f.neck_w) * 0.6 * size / w
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
			# the shoulders), and no lower than where a big tail leaves the body
			var top := cape_top(f)
			var bottom := f.tail_y + f.head_h * 0.05 if f.tail_y > 0.0 else top * 0.12
			var wide := f.shoulder_w * 1.15
			for i in 6:
				wide = maxf(wide, f.body_width_at(lerpf(top, maxf(bottom, f.hip_y), i / 5.0)) * 0.95)
			k = wide * size / w
			var ky := minf(k, (top - bottom) / maxf(box.size.y, 0.001))
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
			var back := minf(f.back_at(top - box.size.y * k * 0.3), f.back_at(top - box.size.y * k * 0.7))
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
