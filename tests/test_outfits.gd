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
		var hat := Outfits.wear_piece(c.visual, "top_hat")
		var specs := Outfits.wear_piece(c.visual, "sunglasses")
		var pack := Outfits.wear_piece(c.visual, "backpack")
		await wait_frames(2)
		var hat_box := _box_in(c.visual, hat, &"head")
		check(hat_box.position.y > f.eye_y - f.head_h * 0.05 and hat_box.position.y < f.crown_y + f.head_h * 0.05,
			"%s: the hat sits on the crown (bottom %.3f, eyes %.3f, crown %.3f)" % [sp, hat_box.position.y, f.eye_y, f.crown_y])
		var specs_box := _box_in(c.visual, specs, &"head")
		check(absf(specs_box.get_center().y - f.eye_y) < f.head_h * 0.15, "%s: the glasses are at the eyes" % sp)
		check(specs_box.end.z > f.eye_z, "%s: and in front of them" % sp)
		var pack_box := _box_in(c.visual, pack, &"chest")
		check(pack_box.get_center().z < f.chest_back + f.head_d * 0.2, "%s: the pack is on the back" % sp)
		check(c.visual.outfit.size() == 4, "%s: three pieces worn, the pack with its straps" % sp)
		check(c.visual.outfit.any(func(o): return String(o.name).ends_with("_straps")), "%s: straps over the shoulders" % sp)
		c.queue_free()
		await wait_physics(1)


func test_a_headshot_knocks_the_hat_off() -> void:
	var c := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, 0))
	await wait_physics(2)
	Outfits.dress(c, "Sir Reynard")
	var worn := c.visual.outfit.size()
	check(worn == 3, "Sir Reynard wears a top hat, a monocle and a bow tie (%d pieces)" % worn)
	var info := DamageInfo.make(500.0, DamageInfo.Kind.BULLET, null, &"carrot_sniper")
	info.headshot = true
	info.bone_role = &"head"
	info.direction = Vector3.FORWARD
	info.impulse = 8.0
	c.take_damage(info)
	await wait_physics(10)
	check(not c.alive, "beaten down")
	check(c.visual.outfit.size() == 1 and String(c.visual.outfit[0].name).contains("bow_tie"),
		"the hat and monocle are knocked off, the bow tie stays (%d left on)" % c.visual.outfit.size())
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


func test_your_wardrobe_is_yours_alone() -> void:
	# every wardrobe option is a piece with a model; none of the rogues wears
	# one; the ones you can't buy are a milestone's reward
	var worn_by_rogues := {}
	for n in Outfits.LOOKS:
		for item in Outfits.LOOKS[n].wear:
			worn_by_rogues[item[0] if item is Array else item] = n
	for cat in Workshop.WARDROBE:
		for o in Workshop.LOOKS[cat].options:
			if o[0] == "none":
				continue
			check(Outfits.PIECES.has(o[0]) and ResourceLoader.exists(Outfits.model_path(o[0])), "%s is a piece with a model" % o[0])
			check(not worn_by_rogues.has(o[0]), "no rogue wears the %s (%s does)" % [o[0], worn_by_rogues.get(o[0], "")])
			var item := "%s:%s" % [cat, o[0]]
			if Workshop.earned_only(item):
				check(not Mastery.giving(item).is_empty(), "the %s is a milestone's reward" % o[1])


func test_you_wear_what_you_pick_in_the_workshop() -> void:
	PlayerProfile.reset_for_tests()
	Burrow.add_acorns(500)
	check(Workshop.outfit().is_empty(), "nothing worn to start")
	check(Workshop.buy("wear_hat:fedora") and Workshop.set_look("wear_hat", "fedora"), "buy the fedora and wear it")
	check(not Workshop.buy("wear_back:fairy_wings"), "the fairy wings aren't for sale")
	check(Workshop.owns("wear_face:none"), "going without is free")
	check(Workshop.outfit() == ["fedora"], "wearing the fedora (%s)" % [Workshop.outfit()])
	var c := spawn_critter("res://data/critters/bun.tres", Vector3(0, 0.1, 0))
	await wait_physics(2)
	Outfits.dress_player(c)
	check(c.visual.outfit.size() == 1, "the bun wears it")
	check(c.visual.helmet != null and not c.visual.helmet.visible, "a hat takes the acorn helmet's place")
	Outfits.undress(c.visual)
	check(c.visual.outfit.is_empty() and c.visual.helmet.visible, "and the helmet comes back without it")
	# a milestone gives the fairy wings
	Run._record("completed", 3)
	Mastery.check()
	check(Workshop.owns("wear_back:fairy_wings"), "three runs finished: the fairy wings are yours")


func test_the_gallery_shows_each_rogue_dressed() -> void:
	var gallery := GalleryPanel.new()
	add_child(gallery)
	await wait_frames(3)
	gallery._show("Sir Toadsworth")
	await wait_frames(3)
	var c: Critter = gallery._portrait.shown_critter()
	check(c != null and c.def.id == &"frog", "Sir Toadsworth stands in the gallery")
	check(c.visual.outfit.size() == Outfits.look_of("Sir Toadsworth").wear.size(), "in his top hat and bow tie")
	check(c.current_weapon() != null and String(c.current_weapon().data.id) == Cast.member("Sir Toadsworth").weapon, "with his favourite gun")
	gallery.queue_free()


func test_clothes_fit_each_species_snugly() -> void:
	# hats centred over the skull and no wider than a hat should be, glasses as
	# wide as the eyes are apart, a cape skinned to the back and lying on it
	var tried := {}
	for n in Cast.names():
		var sp: String = Cast.member(n).species
		if tried.has(sp):
			continue
		tried[sp] = true
		var c := spawn_critter("res://data/critters/%s.tres" % sp, Vector3(0, 0.1, 0))
		await wait_physics(2)
		var f := OutfitFit.of(c.visual)
		var cap := Outfits.wear_piece(c.visual, "trucker_red")
		var specs := Outfits.wear_piece(c.visual, "sunglasses")
		var cape := Outfits.wear_piece(c.visual, "cape")
		await wait_frames(2)
		var cap_box := _box_in(c.visual, cap, &"head")
		var skull := f.head_width_at(f.brow_y)
		check(absf(cap_box.get_center().x - f.head_c.x) < skull * 0.08, "%s: the cap is centred (%.3f vs %.3f)" % [sp, cap_box.get_center().x, f.head_c.x])
		check(cap_box.size.x < skull * 1.6, "%s: and not oversized (%.3f across a %.3f skull)" % [sp, cap_box.size.x, skull])
		check(cap_box.position.y < f.crown_y and cap_box.end.y > f.crown_y, "%s: and on the crown" % sp)
		var specs_box := _box_in(c.visual, specs, &"head")
		check(specs_box.size.x > f.eye_x * 2.0 and specs_box.size.x < f.eye_x * 6.0,
			"%s: the glasses span the eyes (%.3f, eyes %.3f apart)" % [sp, specs_box.size.x, f.eye_x * 2.0])
		var mi := cape as MeshInstance3D
		if check(mi != null and mi.skin != null, "%s: the cape is skinned to the body" % sp):
			var top := Outfits.cape_top(f)
			var box := mi.get_aabb()
			check(absf(box.end.y - top) < f.head_h * 0.15, "%s: hung from the shoulders (top %.3f, shoulders %.3f)" % [sp, box.end.y, top])
			var inside := 0
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for p in verts:
				if p.y < top - f.head_h * 0.1 and p.z > f.back_at(p.y) + f.head_d * 0.02:
					inside += 1
			check(inside < verts.size() / 20, "%s: lying on the back, not through it (%d of %d inside)" % [sp, inside, verts.size()])
		Outfits.undress(c.visual)
		await wait_frames(1)
		check(not is_instance_valid(cape) or cape.is_queued_for_deletion(), "%s: and it comes off with the rest" % sp)
		c.queue_free()
		await wait_physics(1)


func test_rogues_talk_about_what_you_wear() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	check(Cast.outfit_line([], "spot", "Bun", rng) == "", "nothing worn: nothing said")
	var pieces := []
	for cat in Workshop.WARDROBE:
		for o in Workshop.LOOKS[cat].options:
			if o[0] != "none":
				pieces.append(o[0])
	for id in Cast.OUTFIT_LINES:
		check(pieces.has(id), "%s lines are about a wardrobe piece" % id)
	for id in pieces:
		check(Cast.OUTFIT_LINES.has(id), "the %s has lines of its own" % id)
		for event in ["spot", "kill", "lose"]:
			var said := Cast.outfit_line([id], event, "Bun", rng)
			check(said != "" and not said.contains("{"), "%s/%s: \"%s\"" % [id, event, said])
	var said := Cast.outfit_say(["cheese_hat"], "kill", "Bun", rng)
	check(said.key == "o.cheese_hat.kill.0" and said.text == "Say cheese, Bun!", "each line has its key, for its voice (%s)" % said.key)
	check(Workshop.piece_name("flap_beanie") == "ear-flap beanie", "names read in a sentence (%s)" % Workshop.piece_name("flap_beanie"))
	check(KillCam.look_line(true, false, "wizard's hat") == "Dressed to win: your wizard's hat", "the replay notes your outfit when you won")
	check(KillCam.look_line(false, true, "wizard's hat").begins_with("Beaten down in"), "or went down in it")
	check(KillCam.look_line(false, false, "wizard's hat") == "" and KillCam.look_line(true, false, "") == "", "and says nothing otherwise")


func test_your_outfit_never_hides_the_crosshair() -> void:
	# a raccoon (the biggest head) in a mortarboard, seen over its shoulder
	var you := spawn_critter("res://data/critters/raccoon.tres", Vector3(0, 0.1, 0), 0.0)
	var rig := CameraRig.new()
	add_child(rig)
	rig.set_target(you)
	rig.first_person = false
	rig.yaw = 0.0
	rig.pitch = -0.35   # (looking down a little: the hat's in the way)
	await wait_physics(3)
	var hat := Outfits.wear_piece(you.visual, "grad_cap")
	var specs := Outfits.wear_piece(you.visual, "heart_glasses")
	for i in 40:
		await wait_frames(1)
	var centre := rig.get_viewport().get_visible_rect().size * 0.5
	var over := rig._screen_rect(hat).grow(CameraRig.OUTFIT_FADE_MARGIN).has_point(centre)
	var faded := (ModelUtil.find_all(hat, "GeometryInstance3D")[0] as GeometryInstance3D).transparency
	if over:
		check(faded > 0.5, "the hat over the crosshair fades out (%.2f)" % faded)
	else:
		check(faded == 0.0, "a hat clear of the crosshair stays solid (%.2f)" % faded)
	var g := ModelUtil.find_all(specs, "GeometryInstance3D")[0] as GeometryInstance3D
	check(g.transparency == 0.0 or rig._screen_rect(specs).grow(CameraRig.OUTFIT_FADE_MARGIN).has_point(centre),
		"only what's in the way fades")
	rig.pitch = 0.6   # (looking up: the hat drops out of the way)
	for i in 40:
		await wait_frames(1)
	if not rig._screen_rect(hat).grow(CameraRig.OUTFIT_FADE_MARGIN).has_point(centre):
		check((ModelUtil.find_all(hat, "GeometryInstance3D")[0] as GeometryInstance3D).transparency < 0.05, "and comes back once it's clear")
	rig.queue_free()


func test_necklaces_go_round_the_neck() -> void:
	for sp in ["bun", "fox", "raccoon", "hamster"]:
		var c := spawn_critter("res://data/critters/%s.tres" % sp, Vector3(0, 0.1, 0))
		await wait_physics(2)
		var f := OutfitFit.of(c.visual)
		for id in ["sapphire_necklace", "ring_necklace"]:
			var box := _box_in(c.visual, Outfits.wear_piece(c.visual, id), &"chest")
			check(box.end.y > f.shoulder_y and box.position.y > f.chest_y - f.head_h * 0.1,
				"%s: the %s is round the neck (%.2f..%.2f; shoulders %.2f, chest %.2f)" % [sp, id, box.position.y, box.end.y, f.shoulder_y, f.chest_y])
		c.queue_free()
		await wait_physics(1)


func test_a_hugging_bandana_lies_on_the_face() -> void:
	# (Squeaks' and Nibbler's bandanas stood out in front of their round faces like a beak)
	var c := spawn_critter("res://data/critters/hamster.tres", Vector3(0, 0.1, 0))
	await wait_physics(2)
	Outfits.dress(c, "Squeaks")
	await wait_physics(1)
	var f := OutfitFit.of(c.visual)
	# (in the head's rest pose, where OutfitFit measured the face: it's idling)
	var to_rest: Transform3D = (c.visual.rig.rest[&"head"] as Transform3D) * c.visual.attachments[&"head"].global_transform.affine_inverse()
	var worst := -INF
	for piece in c.visual.outfit:
		if not String(piece.name).contains("bandana_mask"):
			continue
		for mi in ModelUtil.find_all(piece, "MeshInstance3D"):
			var xf := to_rest * (mi as MeshInstance3D).global_transform
			for s in mi.mesh.get_surface_count():
				for p: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var q := xf * p
					worst = maxf(worst, q.z - f.front_at(q.y))
	check(worst > -INF, "Squeaks wears a bandana over his mouth")
	check(worst < f.head_d * 0.1, "nowhere more than a little in front of his face: %.3f" % worst)
	c.queue_free()
