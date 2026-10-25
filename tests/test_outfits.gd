extends TestCase
## The rogues' outfits: every member of the Cast has a look made of pieces
## that exist, in a fur its species has; dressed, the pieces ride on the
## right bones and sit where they belong on every species (hats on the
## crown, glasses on the eyes, packs on the back); a headshot knocks them off.


func before_each() -> void:
	make_arena(80.0)


func test_every_rogue_has_a_look() -> void:
	for n in Cast.names():
		var look := Outfits.look_of(n)
		if not check(not look.is_empty(), "%s has a look" % n):
			continue
		var def: CritterDef = load("res://data/critters/%s.tres" % Cast.member(n).species)
		var skins: Array = def.skins().map(func(s): return s.get("id"))
		check(skins.has(look.skin), "%s's fur (%s) is one of the %s skins" % [n, look.skin, def.id])
		var wear: Array = look.wear
		check(not wear.is_empty(), "%s wears something" % n)
		for item in wear:
			var id: String = item[0] if item is Array else item
			check(Outfits.PIECES.has(id), "%s's %s is a piece" % [n, id])
			check(ResourceLoader.exists(Outfits.model_path(id)), "%s's model exists" % id)
	for id in Outfits.PIECES:
		check(ResourceLoader.exists(Outfits.model_path(id)), "piece %s has its model" % id)


func test_pieces_sit_where_they_belong_on_every_species() -> void:
	# one rogue of each species, dressed: a hat's bottom between the eyes and
	# just above the crown, glasses in front of the eyes, a pack behind the chest
	var tried := {}
	for n in Cast.names():
		var sp: String = Cast.member(n).species
		if tried.has(sp):
			continue
		tried[sp] = true
		var c := spawn_critter("res://data/critters/%s.tres" % sp, Vector3(0, 0.1, 0))
		await wait_physics(2)
		var f := OutfitFit.of(c.visual)
		check(f.valid, "%s measured" % sp)
		check(f.crown_y > f.eye_y and f.eye_y > f.neck_y, "%s: neck < eyes < crown (%.2f %.2f %.2f)" % [sp, f.neck_y, f.eye_y, f.crown_y])
		var hat := Outfits.wear(c.visual, "top_hat")
		var specs := Outfits.wear(c.visual, "sunglasses")
		var pack := Outfits.wear(c.visual, "backpack")
		await wait_frames(2)
		var hat_box := _box_in(c.visual, hat, &"head")
		check(hat_box.position.y > f.eye_y - f.head_h * 0.05 and hat_box.position.y < f.crown_y + f.head_h * 0.05,
			"%s: the hat sits on the crown (bottom %.3f, eyes %.3f, crown %.3f)" % [sp, hat_box.position.y, f.eye_y, f.crown_y])
		var specs_box := _box_in(c.visual, specs, &"head")
		check(absf(specs_box.get_center().y - f.eye_y) < f.head_h * 0.15, "%s: the glasses are at the eyes" % sp)
		check(specs_box.end.z > f.face_z, "%s: and in front of them" % sp)
		var pack_box := _box_in(c.visual, pack, &"chest")
		check(pack_box.get_center().z < f.chest_back + f.head_d * 0.2, "%s: the pack is on the back" % sp)
		check(c.visual.outfit.size() == 3, "%s: three pieces worn" % sp)
		c.queue_free()
		await wait_physics(1)


func test_a_headshot_knocks_the_hat_off() -> void:
	var c := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, 0))
	await wait_physics(2)
	Outfits.dress(c, "Sir Reynard")
	var worn := c.visual.outfit.size()
	check(worn == 2, "Sir Reynard wears a top hat and a monocle (%d pieces)" % worn)
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null, &"carrot_sniper")
	info.headshot = true
	info.bone_role = &"head"
	info.direction = Vector3.FORWARD
	info.impulse = 8.0
	c.take_damage(info)
	await wait_physics(10)
	check(not c.alive, "beaten down")
	check(c.visual.outfit.is_empty(), "the hat and monocle are knocked off (%d left on)" % c.visual.outfit.size())
	var flying := get_tree().get_nodes_in_group(&"debris").size() + _bodies_holding("Outfit_").size()
	check(flying >= 1, "and fly about as debris")


## A piece's bounds where they'd be in the rest pose (skeleton space): through
## the bone it rides on, so however the critter happens to be standing.
func _box_in(v: CritterVisual, piece: Node3D, role: StringName) -> AABB:
	var to_rest: Transform3D = (v.rig.rest[role] as Transform3D) * (v.attachments[role] as Node3D).global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for gi in ModelUtil.find_all(piece, "VisualInstance3D"):
		var vi := gi as VisualInstance3D
		var b: AABB = to_rest * vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _bodies_holding(prefix: String) -> Array:
	var out := []
	for n in get_tree().root.find_children("*", "RigidBody3D", true, false):
		for ch in n.get_children():
			if String(ch.name).begins_with(prefix):
				out.append(n)
	return out
