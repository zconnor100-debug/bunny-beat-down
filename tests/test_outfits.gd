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
		check(specs_box.end.z > f.glasses_eyes.z, "%s: and in front of them (%.3f, the eyes' front %.3f)" % [sp, specs_box.end.z, f.glasses_eyes.z])
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


## Every vertex of a piece, in the role bone's rest frame (where OutfitFit measures).
func _points_in(v: CritterVisual, piece: Node3D, role: StringName) -> Array:
	var to_rest: Transform3D = (v.rig.rest[role] as Transform3D) * (v.attachments[role] as Node3D).global_transform.affine_inverse()
	var pts := []
	for mi in ModelUtil.find_all(piece, "MeshInstance3D"):
		var xf := to_rest * (mi as MeshInstance3D).global_transform
		for si in (mi as MeshInstance3D).mesh.get_surface_count():
			for q: Vector3 in (mi as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * q)
	return pts


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


## Mirror, Mirror's top tier: the Mended Mirror coat, your Doppelbunny's
## cracked mirror mended in gold, over your fur and all you wear (not your
## gun); the Doppelbunny still wears its own silver one.
func test_the_mended_mirror_coat() -> void:
	PlayerProfile.reset_for_tests()
	DoppelData.reset_for_tests()
	check(Workshop.look(Workshop.COAT) == "natural" and Workshop.coat_material("natural") == null, "your own fur to start")
	check(not Workshop.buy("coat:mended_mirror") and Workshop.earned_only("coat:mended_mirror"), "the coat isn't for sale")
	var tiers := Mastery.tiers("mirror_mirror")
	check(tiers[1].reward.get("look", "") == "skin:looking_glass" and tiers[2].reward.get("look", "") == "coat:mended_mirror",
		"Mirror, Mirror: the Looking Glass skin at 5, the coat at 10")
	for i in 9:
		DoppelData.note_mirror("beaten")
	Mastery.check()
	check(Workshop.owns("skin:looking_glass") and not Workshop.owns("coat:mended_mirror"), "nine Mirror Matches won: the skin, not yet the coat")
	DoppelData.note_mirror("beaten")
	Mastery.check()
	check(Workshop.owns("coat:mended_mirror") and Workshop.set_look(Workshop.COAT, "mended_mirror"), "ten: the coat is yours, and worn")
	DoppelData.reset_for_tests()
	var coat := Workshop.coat_material("mended_mirror")
	check(coat.shader == DoppelBrain.SHADER and float(coat.get_shader_parameter(&"flashes")) == 0.0, "the Doppelbunny's mirror, without its bad flashes")
	var gold: Color = coat.get_shader_parameter(&"crack_color")
	check(gold.r > gold.b + 0.5, "its cracks mended in gold (%s)" % gold)
	Burrow.add_acorns(500)
	Workshop.buy("wear_hat:fedora")
	Workshop.set_look("wear_hat", "fedora")
	var c := spawn_critter("res://data/critters/bun.tres", Vector3(0, 0.1, 0))
	c.is_player = true
	await wait_physics(2)
	c.visual.kit = Workshop.kit()
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN))
	Outfits.dress_player(c)
	check(c.visual.meshes.all(func(m): return m.material_overlay == coat), "over your fur")
	var hat_meshes := ModelUtil.find_all(c.visual.outfit[0], "MeshInstance3D")
	check(not hat_meshes.is_empty() and hat_meshes.all(func(m): return m.material_overlay == coat), "and the fedora")
	check(ModelUtil.find_all(c.visual.weapon_model, "GeometryInstance3D").all(func(g): return g.material_overlay != coat), "not the gun")
	c.visual.go_ragdoll(Vector3.ZERO)
	check(c.visual.meshes.all(func(m): return m.material_overlay == coat), "still on when you're beaten down")
	# your Doppelbunny, dressed as you, wears its silver mirror over the coat
	var d := spawn_critter("res://data/critters/bun.tres", Vector3(4, 0.1, 0))
	await wait_physics(2)
	Outfits.dress_player(d)
	d.visual.set_enemy_highlight("Doppel-Bun", true)
	DoppelBrain.look(d)
	check(d.visual.meshes.all(func(m): return m.material_overlay is ShaderMaterial and m.material_overlay != coat \
		and (m.material_overlay as ShaderMaterial).shader == DoppelBrain.SHADER), "the Doppelbunny wears its own mirror, not your coat")
	d.visual.go_ragdoll(Vector3.ZERO)
	check(d.visual.meshes.all(func(m): return m.material_overlay is ShaderMaterial), "and keeps it, beaten down (only the enemy rim goes)")
	# the Burrow shows it with your wardrobe, on you
	var panel := BurrowPanel.new()
	add_child(panel)
	await wait_frames(4)
	var labels: Array = panel._list.get_children().map(func(n): return n.get_child(0).text if n is HBoxContainer else (n.text if n is Label else ""))
	var wardrobe_at := labels.find("Workshop: wardrobe (yours alone: no rogue wears these)")
	var coat_at := labels.find("Coat: Mended mirror")
	check(wardrobe_at >= 0 and coat_at > wardrobe_at, "the coat is listed with your wardrobe (%d, %d)" % [wardrobe_at, coat_at])
	var you := panel._portrait.shown_critter()
	check(you != null and you.visual.meshes.all(func(m): return m.material_overlay == coat), "and the portrait shows you in it")
	PlayerProfile.reset_for_tests()

## Four more coats, each at the top of a long ladder (the Golden Acorn for 50
## wins: the Gold muzzle flash moved down to 25), named in your look and
## talked about by the rogues; a look that moved to a tier you'd already
## reached is yours when the milestones are next checked.
func test_the_coats_from_the_ladders() -> void:
	PlayerProfile.reset_for_tests()
	var gives := {"champion": "coat:golden_acorn", "trail_boss": "coat:starry_night", "pack_breaker": "coat:tiger_stripe",
		"nemesis_hunter": "coat:smouldering", "mirror_mirror": "coat:mended_mirror", "old_hand": "coat:patchwork"}
	for ladder in gives:
		var top: Dictionary = Mastery.tiers(ladder)[-1]
		check(top.reward.get("look", "") == gives[ladder], "%s's top tier gives the %s" % [ladder, gives[ladder]])
	check(Mastery.tiers("champion")[1].reward.get("look", "") == "flash:gold" and int(Mastery.tiers("champion")[1].reward.get("acorns", 0)) == 400,
		"the Gold muzzle flash at 25 wins, with its 400 acorns")
	check(int(Mastery.tiers("trail_boss")[-1].reward.get("acorns", 0)) == 1000, "Trail Boss III still gives its 1,000 acorns too")
	check(Mastery.tiers("old_hand")[1].reward.get("look", "") == "tracer:jade" and int(Mastery.tiers("old_hand")[1].reward.get("acorns", 0)) == 200,
		"Jade tracers at 50 matches, with their 200 acorns")
	for o in Workshop.LOOKS[Workshop.COAT].options.slice(1):
		var m := Workshop.coat_material(o[0])
		check(m != null and Workshop.earned_only("coat:" + o[0]), "the %s coat is drawn, and earned only" % o[1])
		check(not Cast.OUTFIT_LINES.get(o[0], {}).get("spot", []).is_empty(), "the rogues have something to say about the %s coat" % o[1])
	var gold := Workshop.coat_material("golden_acorn")
	check(gold.shader == Workshop.COAT_TINT and gold.next_pass is ShaderMaterial and (gold.next_pass as ShaderMaterial).shader == Workshop.COAT_GLOW,
		"a colour over your fur, and its glow over that")
	check((Workshop.coat_material("tiger_stripe").next_pass as ShaderMaterial).get_shader_parameter(&"pattern") == 3,
		"the tiger stripe's amber is lit up, to be bright on any fur")
	check((Workshop.coat_material("patchwork").next_pass as ShaderMaterial).get_shader_parameter(&"pattern") == 5,
		"the patchwork's colours are lifted, to show on any fur")
	# a tier reached before its look moved there: the look comes when the milestones are next checked
	PlayerProfile._book().set_value("mastery", "champion_25", true)
	check(not Workshop.owns("flash:gold"), "Champion II reached back when it gave only acorns")
	var acorns := Burrow.acorns()
	var fresh := Mastery.check()   # (other tests' rogues may hand you a milestone or two meanwhile: those pay)
	var paid: int = fresh.reduce(func(n, m): return n + int(m.reward.get("acorns", 0)), 0)
	check(Workshop.owns("flash:gold") and Burrow.acorns() == acorns + paid and not fresh.any(func(m): return m.id == "champion_25"),
		"the Gold muzzle flash is yours now (and no acorns twice)")
	# worn: named in your look, and something for the rogues to talk about
	PlayerProfile._book().set_value("mastery", "champion_50", true)
	Mastery.check()
	check(Workshop.set_look(Workshop.COAT, "golden_acorn"), "the Golden Acorn coat, worn")
	Burrow.add_acorns(500)
	Workshop.buy("wear_hat:fedora")
	Workshop.set_look("wear_hat", "fedora")
	check(Workshop.wearing() == ["fedora", "golden_acorn"], "a rogue sees your fedora and your coat (%s)" % [Workshop.wearing()])
	check(Workshop.outfit() == ["fedora"], "(your outfit is still just the pieces)")
	check(Workshop.outfit_phrase() == "fedora and golden acorn coat", "your look: %s" % Workshop.outfit_phrase())
	check(KillCam.look_line(true, false, Workshop.outfit_phrase()) == "Dressed to win: your fedora and golden acorn coat", "and the final shot says so")
	var rng := RandomNumberGenerator.new()
	var said := {}
	for i in 40:
		rng.seed = i
		var line := Cast.outfit_say(Workshop.wearing(), "spot", "Bun", rng)
		said[String(line.get("key", "")).get_slice(".", 1)] = true
	check(said.has("golden_acorn") and said.has("fedora"), "the rogues talk about both (%s)" % [said.keys()])
	Workshop.set_look("wear_hat", "none")
	check(Workshop.outfit_phrase() == "golden acorn coat", "just the coat: %s" % Workshop.outfit_phrase())
	PlayerProfile.reset_for_tests()

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
	var pieces := []   # (and coats: Workshop.wearing)
	for cat in Workshop.WARDROBE + [Workshop.COAT]:
		for o in Workshop.LOOKS[cat].options.slice(1):
			pieces.append(o[0])
	for id in Cast.OUTFIT_LINES:
		check(pieces.has(id), "%s lines are about something you wear" % id)
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
			var piece := Outfits.wear_piece(c.visual, id)
			var box := _box_in(c.visual, piece, &"chest")
			check(box.end.y > f.shoulder_y and box.position.y > f.hip_y,
				"%s: the %s is round the neck (%.2f..%.2f; shoulders %.2f, hips %.2f)" % [sp, id, box.position.y, box.end.y, f.shoulder_y, f.hip_y])
			_check_on_chest(c.visual, piece, "%s: the %s" % [sp, id])
		c.queue_free()
		await wait_physics(1)
	# the rogues' own: Vixen Vera's jewels, Lady Garbage's beads
	for n in ["Vixen Vera", "Lady Garbage"]:
		var c := spawn_critter("res://data/critters/%s.tres" % Cast.member(n).species, Vector3(0, 0.1, 0))
		await wait_physics(2)
		Outfits.dress(c, n)
		for piece in c.visual.outfit:
			if String(piece.name).ends_with("necklace"):
				_check_on_chest(c.visual, piece, "%s's %s" % [n, piece.name])
		c.queue_free()
		await wait_physics(1)


## (Game Notes 109, 121: what hangs below the shoulders lies on the chest, not
## in the air in front of it: its back no further out than a little)
func _check_on_chest(v: CritterVisual, piece: Node3D, what: String) -> void:
	var f := OutfitFit.of(v)
	var backs := {}   # height (2 cm slices) -> the back of the piece there
	for q in _points_in(v, piece, &"chest"):
		if q.y < f.shoulder_y:
			var b := snappedf(q.y, 0.02)
			backs[b] = minf(backs.get(b, INF), q.z)
	var out := -INF
	for b in backs:
		out = maxf(out, backs[b] - f.front_at(b))
	check(backs.is_empty() or out < f.head_d * 0.1, "%s lies on the chest (%.3f in front of it)" % [what, out])   # (empty: all of it round the neck)


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
