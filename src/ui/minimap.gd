class_name Minimap
extends Control
## Top-down island map rendered once from the terrain (hill-shaded), with the
## Briar circles, POI names, the player arrow and the balloon route drawn live.
## The same control doubles as the full-screen map (M).

var island: Island
var storm: Storm
var player: Critter
var dropship: Dropship
var full := false
var map_tex: ImageTexture
var _world_size := 1.0


func build(island_: Island) -> void:
	island = island_
	var n := 256
	var span := island.terrain.island_radius * 2.0 + 60.0
	_world_size = span
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for zi in n:
		for xi in n:
			var x := (float(xi) / (n - 1) - 0.5) * span
			var z := (float(zi) / (n - 1) - 0.5) * span
			var h := island.terrain.height_at(x, z)
			var c: Color
			if h < -0.2:
				c = Color("2d6f8e").lerp(Color("153a52"), clampf(-h / 7.0, 0.0, 1.0))
			elif h < 1.6:
				c = Color("d9c79a")
			else:
				var ctl := island.terrain.control_at(x, z)
				c = Color("4d6b2c")
				c = c.lerp(Color("79a83f"), ctl.r)
				c = c.lerp(Color("3b5a22"), ctl.a)
				c = c.lerp(Color("b59562"), ctl.g)
				c = c.lerp(Color("8d8a82"), ctl.b)
				var nrm := island.terrain.normal_at(x, z)
				var shade := clampf(nrm.dot(Vector3(-0.5, 0.75, -0.4).normalized()), 0.35, 1.0)
				c = c * (0.55 + 0.6 * shade)
				c.a = 1.0
			img.set_pixel(xi, zi, c)
	map_tex = ImageTexture.create_from_image(img)


func world_to_map(p: Vector2) -> Vector2:
	return (p / _world_size + Vector2(0.5, 0.5)) * size


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if map_tex == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(4), Color(UITheme.BARK_DARK, 0.9))
	draw_texture_rect(map_tex, r, false)
	var font := UITheme.text_font(600)
	if storm and storm.active:
		var c := world_to_map(storm.center)
		var rad := storm.radius / _world_size * size.x
		draw_arc(c, rad, 0, TAU, 96, Color(0.75, 0.35, 1.0, 0.95), 2.5)
		var nc := world_to_map(storm.next_center)
		draw_arc(nc, storm.next_radius / _world_size * size.x, 0, TAU, 96, Color(1, 1, 1, 0.9), 1.5)
	if dropship and is_instance_valid(dropship) and dropship.flying:
		var a := world_to_map(Vector2(dropship.start.x, dropship.start.z))
		var b := world_to_map(Vector2(dropship.finish.x, dropship.finish.z))
		draw_dashed_line(a, b, Color(1, 1, 1, 0.8), 2.0, 8.0)
		var bp := world_to_map(Vector2(dropship.global_position.x, dropship.global_position.z))
		draw_circle(bp, 6.0, UITheme.CARROT)
	# supply drops: falling and landed-but-unopened
	for group in [&"supply_drops", &"supply_crates"]:
		for n in get_tree().get_nodes_in_group(group):
			var sp := world_to_map(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z))
			var pulse := 5.0 + sin(Time.get_ticks_msec() * 0.008) * 1.5
			draw_circle(sp, pulse + 2.0, UITheme.INK)
			draw_circle(sp, pulse, Rarity.COLORS[Rarity.Tier.GOLDEN])
	if full and island:
		for p in island.pois:
			var mp := world_to_map(p.center)
			draw_string_outline(font, mp + Vector2(-60, 4), p.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 5, Color(UITheme.INK, 0.9))
			draw_string(font, mp + Vector2(-60, 4), p.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, UITheme.CREAM)
	if player and is_instance_valid(player):
		var pp := world_to_map(Vector2(player.global_position.x, player.global_position.z))
		var yaw := player.look_yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var s := 9.0 if full else 7.0
		draw_colored_polygon(PackedVector2Array([pp + fwd * s, pp - fwd * s * 0.6 + side * s * 0.7, pp - fwd * s * 0.3, pp - fwd * s * 0.6 - side * s * 0.7]), UITheme.CARROT)
		draw_polyline(PackedVector2Array([pp + fwd * s, pp - fwd * s * 0.6 + side * s * 0.7, pp - fwd * s * 0.3, pp - fwd * s * 0.6 - side * s * 0.7, pp + fwd * s]), UITheme.INK, 1.5)
