extends Node3D
## Stage for tests/capture_eyes.gd: each species' head, straight on and from
## the side, through an orthographic camera with a grid of the skeleton's own
## coordinates over it (model units: lines every 0.02, labelled every 0.1), to
## read off where the eyes are (rig.json "eye": [x, y, z] of the right eye).

var out_dir := "user://eyes"
const IDS := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]


func _ready() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.env.fog_density = 0.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(cam)
	cam.current = true
	for id in IDS:
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % id)
		c.preview = true
		add_child(c)
		c.place_at(Vector3.ZERO, PI)   # facing +Z, toward the camera
		c.process_mode = Node.PROCESS_MODE_DISABLED
		c.visual.poser.aim_dir = Vector3(0, 0, 1)   # (looking at the camera, not twisted toward -Z)
		for i in 4:
			await get_tree().process_frame
		var r := c.visual.rig
		var s := r.size
		var f := OutfitFit.of(c.visual)
		# model space -> world: the model is turned PI and scaled by size; with the
		# critter turned PI too, model +X is world +X and model +Z is world +Z
		var lo_y := f.neck_y - 0.05
		var hi_y := r.head_top + 0.05
		var span := maxf(hi_y - lo_y, f.head_w * 1.3)
		cam.size = span * s * 1.05
		cam.global_position = Vector3(0, (lo_y + hi_y) * 0.5 * s, 10.0)
		cam.look_at(cam.global_position - Vector3(0, 0, 1), Vector3.UP)
		# (for tools: model units per image height, and the model height at the middle)
		print("EYEVIEW %s %.5f %.5f" % [id, span * 1.05, (lo_y + hi_y) * 0.5])
		await _snap("eyes_%s_plain" % id)
		var grid := _grid(s, Vector2(-span * 0.6, lo_y), Vector2(span * 0.6, hi_y), 3.0)
		add_child(grid)
		await _snap("eyes_%s_front" % id)
		grid.queue_free()
		var side := _grid(s, Vector2(-span * 0.6, lo_y), Vector2(span * 0.6, hi_y), 3.0, true)
		add_child(side)
		cam.global_position = Vector3(10.0, (lo_y + hi_y) * 0.5 * s, 0)
		cam.look_at(Vector3(0, cam.global_position.y, 0), Vector3.UP)
		await _snap("eyes_%s_side" % id)
		side.queue_free()
		c.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## Grid lines in model units (x across, y up; `side`: z across, seen from +X),
## drawn in a plane `out` world metres toward the camera.
func _grid(s: float, lo: Vector2, hi: Vector2, out: float, side := false) -> Node3D:
	var root := Node3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var at := func(u: float, v: float) -> Vector3:
		return Vector3(out, v * s, u * s) if side else Vector3(u * s, v * s, out)
	var u := snappedf(lo.x, 0.02)
	while u <= hi.x:
		var strong := absf(u - snappedf(u, 0.1)) < 0.001
		im.surface_set_color(Color(1, 0.2, 0.2, 0.9) if strong else Color(1, 1, 1, 0.35))
		im.surface_add_vertex(at.call(u, lo.y))
		im.surface_add_vertex(at.call(u, hi.y))
		u += 0.02
	var v := snappedf(lo.y, 0.02)
	while v <= hi.y:
		var strong := absf(v - snappedf(v, 0.1)) < 0.001
		im.surface_set_color(Color(1, 0.2, 0.2, 0.9) if strong else Color(1, 1, 1, 0.35))
		im.surface_add_vertex(at.call(lo.x, v))
		im.surface_add_vertex(at.call(hi.x, v))
		v += 0.02
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	root.add_child(mi)
	# labels on the 0.1 lines
	var k := snappedf(lo.x, 0.1)
	while k <= hi.x:
		_label(root, "%.1f" % k, at.call(k, lo.y + 0.01), s)
		k += 0.1
	k = snappedf(lo.y, 0.1)
	while k <= hi.y:
		_label(root, "%.1f" % k, at.call(lo.x + 0.01, k), s)
		k += 0.1
	return root


func _label(root: Node3D, text: String, pos: Vector3, s: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0015 * s
	l.font_size = 48
	l.modulate = Color(1, 0.9, 0.3)
	l.outline_size = 8
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	root.add_child(l)
