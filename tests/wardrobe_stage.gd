extends Node
## Stage for tests/capture_wardrobe.gd: the Rogues' Gallery with its
## portraits, the Burrow's wardrobe (you trying things on), and every
## critter in a few wardrobe outfits.

var out_dir := "user://wardrobe"


func _ready() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _panel(p: Control) -> CanvasLayer:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.13, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	center.add_child(p)
	return layer


func _run() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	# the Gallery, on three rogues (after the first card has taken the focus)
	var gallery := GalleryPanel.new()
	var layer := _panel(gallery)
	await _snap("gallery_first")
	for n in ["Sir Toadsworth", "Captain Carrot", "Sly"]:
		gallery._show(n)
		await _snap("gallery_%s" % n.replace(" ", "_"))
	layer.queue_free()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pieces"):
			only = a.trim_prefix("pieces").trim_prefix(":")
			await _pieces(only)
			get_tree().quit()
			return
	# the Burrow, scrolled to the wardrobe, trying on a few things
	Burrow.add_acorns(400)
	var burrow := BurrowPanel.new()
	layer = _panel(burrow)
	await get_tree().process_frame
	var tries := [["wear_hat", 5, "wear_face", 3, "wear_back", 2], ["wear_hat", 3, "wear_face", 1, "wear_back", 4],
		["wear_hat", 7, "wear_face", 4, "wear_neck", 2]]
	for k in tries.size():
		var t: Array = tries[k]
		for j in range(0, t.size(), 2):
			burrow._browse[t[j]] = t[j + 1]
		burrow._rebuild("wear_hat:act")
		await _snap("burrow_wardrobe_%d" % k)
	layer.queue_free()
	# every critter in one outfit, on the portrait
	var p := CritterPortrait.new(Vector2(600, 700))
	layer = _panel(p)
	for id in CharacterSelect.ROSTER:
		Settings.set_value(&"player_character", id, false)
		p.show_player(["witch_hat", "heart_glasses", "fairy_wings"] if id in ["bun", "fox", "frog", "hamster"] else ["fedora", "pixel_shades", "jetpack"])
		await _snap("you_%s" % id)
	get_tree().quit()


## Every wardrobe piece on four heads, up close (front three-quarters).
## "pieces:a,b@beaver,fox": just those pieces, on those species.
func _pieces(only := "") -> void:
	var species := ["bun", "fox", "raccoon", "hamster"]
	if only.contains("@"):
		species = Array(only.get_slice("@", 1).split(","))
		only = only.get_slice("@", 0)
	var p := CritterPortrait.new(Vector2(500, 500))
	var layer := _panel(p)
	var ids := []
	for cat in Workshop.WARDROBE:
		for o in Workshop.LOOKS[cat].options:
			if o[0] != "none" and (only == "" or Array(only.split(",")).has(o[0])):
				ids.append(o[0])
	for sp in species:
		Settings.set_value(&"player_character", sp, false)
		for id in ids:
			p.show_player([id])
			await get_tree().process_frame
			var c: Critter = p.shown_critter()
			var f := OutfitFit.of(c.visual)
			var s: float = c.visual.rig.size
			var slot: String = Outfits.PIECES[id].slot
			var y := lerpf(f.neck_y, f.crown_y, 0.55) * s if slot in ["hat", "glasses"] else f.chest_y * s
			p._cam.position = Vector3(0.0, y + f.head_h * s * 0.15, 0.0) + Vector3(0.55, 0.05, 1.0).normalized() * (f.crown_y - f.chest_y) * s * 3.2 \
				* (-1.0 if slot == "cape" or slot == "pack" else 1.0) * Vector3(1, 1, 1) + (Vector3(0, (f.crown_y - f.chest_y) * s * 0.4, 0) if slot in ["cape", "pack"] else Vector3.ZERO)
			p._cam.look_at(Vector3(0, y, 0), Vector3.UP)
			p.set_process(false)
			c.rotation.y = PI
			c.look_yaw = PI
			await _snap("piece_%s_%s" % [sp, id])
			p.set_process(true)
