class_name Minimap
extends Control
## Top-down map rendered once from the map's ground colours (Island.map_color),
## with the Briar circles, POI names, the player arrow and the drop route drawn live.
## The same control doubles as the full-screen map (M).

var island: Island
var storm: Storm
var player: Critter
var dropship: Dropship
var full := false
var map_tex: ImageTexture
var _world_size := 1.0

## Red blips: an enemy shows up for SHOT_BLIP_TIME after it fires (anywhere on
## the island), and continuously while it is moving within NEAR_RADIUS of you.
const SHOT_BLIP_TIME := 2.5
const NEAR_RADIUS := 20.0
const BLIP_COLOR := Color(1.0, 0.18, 0.12)
var _last_shot: Dictionary = {}   # Critter -> msec of its last shot


func _ready() -> void:
	Events.shot_fired.connect(_on_shot_fired)
	Events.critter_died.connect(func(victim, _info): _last_shot.erase(victim))


func _on_shot_fired(shooter: Node, _origin: Vector3, _weapon_id: StringName) -> void:
	if shooter != player:
		_last_shot[shooter] = Time.get_ticks_msec()


func build(island_: Island) -> void:
	island = island_
	var n := 384
	var span := island.terrain.island_radius * 2.0 + 60.0
	_world_size = span
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for zi in n:
		for xi in n:
			var x := (float(xi) / (n - 1) - 0.5) * span
			var z := (float(zi) / (n - 1) - 0.5) * span
			var c := island.map_color(x, z)
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
	_draw_enemy_blips()
	if player and is_instance_valid(player):
		var pp := world_to_map(Vector2(player.global_position.x, player.global_position.z))
		var yaw := player.look_yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(fwd.y, -fwd.x)
		var s := 9.0 if full else 7.0
		draw_colored_polygon(PackedVector2Array([pp + fwd * s, pp - fwd * s * 0.6 + side * s * 0.7, pp - fwd * s * 0.3, pp - fwd * s * 0.6 - side * s * 0.7]), UITheme.CARROT)
		draw_polyline(PackedVector2Array([pp + fwd * s, pp - fwd * s * 0.6 + side * s * 0.7, pp - fwd * s * 0.3, pp - fwd * s * 0.6 - side * s * 0.7, pp + fwd * s]), UITheme.INK, 1.5)


## Enemies that should show as red blips right now: [{critter, firing, near, age}].
func enemy_blips() -> Array:
	var out := []
	if player == null or not is_instance_valid(player):
		return out
	var now := Time.get_ticks_msec()
	var pp := player.global_position
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c == null or c == player or not c.alive or c.state != Critter.State.GROUND:
			continue
		var since_shot := (now - int(_last_shot.get(c, -1000000))) / 1000.0
		var firing := since_shot < SHOT_BLIP_TIME
		var flat := Vector2(c.global_position.x - pp.x, c.global_position.z - pp.z)
		var near := flat.length() <= NEAR_RADIUS and Vector2(c.velocity.x, c.velocity.z).length() > 0.5
		if firing or near:
			out.append({"critter": c, "firing": firing, "near": near, "age": since_shot})
	return out


func _draw_enemy_blips() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for b in enemy_blips():
		var c: Critter = b.critter
		var mp := world_to_map(Vector2(c.global_position.x, c.global_position.z))
		var r := (5.5 if full else 4.0)
		var alpha := 1.0 if b.near else clampf(1.0 - b.age / SHOT_BLIP_TIME, 0.25, 1.0)
		if b.firing:
			# a ring that pulses outward while they're shooting
			draw_arc(mp, r + 3.0 + pulse * 4.0, 0.0, TAU, 20, Color(BLIP_COLOR, 0.6 * alpha), 1.5)
		draw_circle(mp, r + 1.5, Color(0, 0, 0, 0.7 * alpha))
		draw_circle(mp, r, Color(BLIP_COLOR, alpha))
