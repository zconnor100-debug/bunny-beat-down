class_name ToyRoom
extends RefCounted
## The kid's bedroom round Toy Box Bash's floor: wallpapered walls with a
## sunny window and drawings, and the furniture that hems the floor in (the
## bed with its frilly skirt, a cubby shelf of toy bins, a bookshelf, a
## dresser and a desk), a ceiling with glow-in-the-dark stars and a slowly
## turning planet mobile. Only the boundary is solid; the room is scenery.

const CEILING := 400.0


static func build(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var hx := ToyFloor.HX
	var hz := ToyFloor.HZ
	var y0 := ToyFloor.FLOOR
	# the boundary: the play floor's four edges, solid and tall
	var body := StaticBody3D.new()
	body.name = "RoomBounds"
	body.collision_layer = Layers.WORLD
	parent.add_child(body)
	for b in [[Vector3(0, 200, -hz - 3.0), Vector3(hx * 2.0 + 12.0, 420.0, 6.0)], [Vector3(0, 200, hz + 3.0), Vector3(hx * 2.0 + 12.0, 420.0, 6.0)],
			[Vector3(-hx - 3.0, 200, 0), Vector3(6.0, 420.0, hz * 2.0)], [Vector3(hx + 3.0, 200, 0), Vector3(6.0, 420.0, hz * 2.0)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[1]
		cs.shape = box
		cs.position = b[0]
		body.add_child(cs)
	var k := CageKit.blank("Bedroom", rng)
	k.collision_layer = 0
	var wall_h := CEILING - y0
	# north wall with the window, west wall with a door and drawings
	var win := Rect2(-330.0, y0 + 120.0, 420.0, 200.0)
	k._box(&"wallpaper", Vector3((-hx - 300.0 + win.position.x) * 0.5, y0 + wall_h * 0.5, -hz - 6.0), Vector3(win.position.x + hx + 300.0, wall_h, 12.0), Basis(), false)
	k._box(&"wallpaper", Vector3((win.end.x + hx + 400.0) * 0.5, y0 + wall_h * 0.5, -hz - 6.0), Vector3(hx + 400.0 - win.end.x, wall_h, 12.0), Basis(), false)
	k._box(&"wallpaper", Vector3(win.get_center().x, (y0 + win.position.y) * 0.5, -hz - 6.0), Vector3(win.size.x, win.position.y - y0, 12.0), Basis(), false)
	k._box(&"wallpaper", Vector3(win.get_center().x, (win.end.y + CEILING) * 0.5, -hz - 6.0), Vector3(win.size.x, CEILING - win.end.y, 12.0), Basis(), false)
	for x in [win.position.x, win.get_center().x, win.end.x]:
		k._box(&"plastic_white", Vector3(x, win.get_center().y, -hz - 3.0), Vector3(10.0, win.size.y + 10.0, 8.0), Basis(), false)
	for y in [win.position.y, win.end.y]:
		k._box(&"plastic_white", Vector3(win.get_center().x, y, -hz - 3.0), Vector3(win.size.x + 10.0, 10.0, 8.0), Basis(), false)
	for side in [[win.position.x - 50.0], [win.end.x + 50.0]]:
		k._box(&"gingham", Vector3(side[0], (win.end.y + 40.0 + y0 + 60.0) * 0.5, -hz + 4.0), Vector3(70.0, win.end.y + 40.0 - y0 - 60.0, 6.0), Basis(), false)
	k._box(&"wallpaper", Vector3(-hx - 6.0, y0 + wall_h * 0.5, 0), Vector3(12.0, wall_h, hz * 2.0 + 24.0), Basis(), false)
	k._box(&"plastic_white", Vector3(-hx - 1.0, y0 + 95.0, 190.0), Vector3(4.0, 190.0, 110.0), Basis(), false)
	k._ellipsoid(&"coin", Vector3(-hx + 1.5, y0 + 95.0, 150.0), Vector3(1.5, 5.0, 5.0), Basis(), false)
	for d in [[-150.0, &"paint_yellow"], [-20.0, &"paint_blue"], [-280.0, &"paint_pink"]]:
		var z: float = d[0]
		k._box(&"plastic_white", Vector3(-hx - 0.5, y0 + 170.0, z), Vector3(2.0, 80.0, 100.0), Basis(), false)
		k._box(d[1], Vector3(-hx + 0.2, y0 + 170.0, z), Vector3(1.0, 64.0, 84.0), Basis(), false)
		k._ellipsoid(StringName("crayon_" + String(ToyProps.CREW[rng.randi() % 8])), Vector3(-hx + 0.8, y0 + 175.0, z), Vector3(0.5, 18.0, 18.0), Basis(), false, 6, 12)
	# east: the bed (headboard to the north) with a frilly skirt, then a cubby shelf
	var bed := Rect2(hx + 2.0, -hz, 320.0, 330.0)
	var top := y0 + 95.0
	k._box(&"wood_honey", Vector3(bed.get_center().x, y0 + 45.0, bed.get_center().y), Vector3(bed.size.x, 30.0, bed.size.y), Basis(), false)
	k._box(&"paper", Vector3(bed.get_center().x, top - 15.0, bed.get_center().y), Vector3(bed.size.x, 30.0, bed.size.y), Basis(), false)
	k._box(&"gingham", Vector3(bed.get_center().x, top + 2.0, bed.get_center().y + 40.0), Vector3(bed.size.x + 8.0, 6.0, bed.size.y - 70.0), Basis(), false)
	k._box(&"gingham", Vector3(bed.position.x - 1.0, top - 25.0, bed.get_center().y + 40.0), Vector3(4.0, 50.0, bed.size.y - 70.0), Basis(), false)
	for i in int(bed.size.y / 12.0):
		var z := bed.position.y + 6.0 + i * 12.0
		k._box(&"curtain", Vector3(bed.position.x - 2.0 - (i % 2) * 1.5, y0 + 26.0, z), Vector3(3.0, 52.0, 12.5), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"pillow_white", Vector3(bed.get_center().x + xs * 75.0, top + 22.0, bed.position.y + 45.0), Vector3(65.0, 20.0, 34.0), Basis(), false)
	k._box(&"wood_honey", Vector3(bed.get_center().x, y0 + 90.0, bed.position.y - 6.0), Vector3(bed.size.x + 20.0, 180.0, 12.0), Basis(), false)
	k._ellipsoid(&"fur_light", Vector3(bed.get_center().x - 40.0, top + 40.0, bed.position.y + 110.0), Vector3(28.0, 40.0, 24.0), Basis(), false)
	k._ellipsoid(&"fur_light", Vector3(bed.get_center().x - 40.0, top + 92.0, bed.position.y + 110.0), Vector3(20.0, 18.0, 18.0), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._ellipsoid(&"fur_light", Vector3(bed.get_center().x - 40.0 + xs * 9.0, top + 130.0, bed.position.y + 110.0), Vector3(5.0, 26.0, 3.0), Basis(), false)
	var cub := Rect2(hx + 2.0, bed.end.y, 90.0, hz - bed.end.y)
	k._box(&"paint_white", Vector3(cub.get_center().x, y0 + 65.0, cub.get_center().y), Vector3(cub.size.x, 130.0, cub.size.y), Basis(), false)
	for row in 2:
		for i in int(cub.size.y / 90.0):
			var c := Vector3(cub.position.x - 0.5, y0 + 33.0 + row * 62.0, cub.position.y + 45.0 + i * 90.0)
			k._box(StringName("plastic_" + String(ToyProps.CREW[(i + row * 3) % 8])), c, Vector3(2.0, 50.0, 78.0), Basis(), false)
	# south: a bookshelf, a dresser and a desk
	var south := hz + 2.0
	k._box(&"wood_honey", Vector3(-hx * 0.5 - 100.0, y0 + 170.0, south + 45.0), Vector3(hx - 200.0 + 20.0, 340.0, 90.0), Basis(), false)
	for shelf in 4:
		var y := y0 + 12.0 + shelf * 82.0
		var x := -hx + 15.0
		while x < -230.0:
			var bw := rng.randf_range(10.0, 22.0)
			var bh := rng.randf_range(50.0, 72.0)
			k._box(StringName("paint_" + String(ToyProps.CREW[rng.randi() % 8])), Vector3(x + bw * 0.5, y + bh * 0.5, south - 1.0), Vector3(bw - 1.0, bh, 3.0), Basis(), false)
			x += bw
	k._box(&"paint_white", Vector3(30.0, y0 + 80.0, south + 40.0), Vector3(320.0, 160.0, 80.0), Basis(), false)
	for row in 3:
		for col in 2:
			var c := Vector3(-55.0 + col * 170.0, y0 + 25.0 + row * 50.0, south - 1.5)
			k._box(&"paint_teal", c, Vector3(150.0, 42.0, 3.0), Basis(), false)
			k._ellipsoid(&"coin", c + Vector3(0, 0, -2.5), Vector3(5.0, 5.0, 2.0), Basis(), false)
	k._box(&"wood_light", Vector3((260.0 + hx) * 0.5, y0 + 108.0, south + 40.0), Vector3(hx - 260.0, 8.0, 80.0), Basis(), false)
	for x in [270.0, hx - 10.0]:
		k._box(&"wood_light", Vector3(x, y0 + 52.0, south + 40.0), Vector3(8.0, 104.0, 74.0), Basis(), false)
	# ceiling: glow stars and the planet mobile
	k._box(&"ceiling", Vector3(0, CEILING + 5.0, 0), Vector3(hx * 2.0 + 900.0, 10.0, hz * 2.0 + 900.0), Basis(), false)
	for i in 30:
		var at := Vector3(rng.randf_range(-hx, hx), CEILING - 0.5, rng.randf_range(-hz, hz))
		k._ellipsoid(&"glow_star", at, Vector3(4.0, 0.3, 4.0), Basis(Vector3.UP, rng.randf() * TAU), false, 2, 5)
	k._box(&"oak", Vector3(0, y0 - 3.0, 0), Vector3(hx * 2.0 + 900.0, 6.0, hz * 2.0 + 900.0), Basis(), false)
	parent.add_child(k.finish())
	for gi in ModelUtil.find_all(k, "GeometryInstance3D"):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mobile(parent, rng)


static func _mobile(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var spin := Spinner.new()
	spin.name = "Mobile"
	spin.speed = 0.08
	parent.add_child(spin)
	spin.position = Vector3(60.0, 0, -20.0)
	var k := CageKit.blank("MobileParts", rng)
	k.collision_layer = 0
	k._rod(&"metal", Vector3(0, ToyRoom.CEILING, 0), Vector3(0, 300.0, 0), 0.8, false)
	k._rod(&"wood_light", Vector3(-80, 300.0, 0), Vector3(80, 300.0, 0), 1.4, false)
	k._rod(&"wood_light", Vector3(0, 300.0, -80), Vector3(0, 300.0, 80), 1.4, false)
	var planets := [[Vector3(-80, 0, 0), 16.0, &"plastic_orange"], [Vector3(80, 0, 0), 12.0, &"plastic_blue"],
		[Vector3(0, 0, -80), 10.0, &"plastic_red"], [Vector3(0, 0, 80), 14.0, &"plastic_lime"]]
	for p in planets:
		var at: Vector3 = p[0]
		var drop := rng.randf_range(40.0, 90.0)
		k._rod(&"metal", at + Vector3(0, 300.0, 0), at + Vector3(0, 300.0 - drop, 0), 0.25, false)
		k._ellipsoid(p[2], at + Vector3(0, 300.0 - drop - float(p[1]), 0), Vector3.ONE * float(p[1]), Basis(), false, 10, 18)
	k._lathe(&"plastic_yellow", [Vector2(30.0, 239.0), Vector2(30.0, 241.0), Vector2(22.0, 241.0), Vector2(22.0, 239.0)], 24,
		Vector3(80, 0, 0), false)
	spin.add_child(k.finish())
