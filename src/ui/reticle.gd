class_name Reticle
extends RefCounted
## The crosshair, in the player's Workshop style and colour. `gap` follows
## the gun's real spread (the HUD), so every style shows how tight your shot
## is; each is outlined dark so it reads on snow and on bark. Shared by the
## HUD and the Workshop's preview.

const STYLES := ["cross", "dot", "circle", "chevron", "carrot", "acorn", "paw"]
const INK := Color(0, 0, 0, 0.6)


static func draw(ci: CanvasItem, c: Vector2, gap: float, style: String, col: Color) -> void:
	match style:
		"dot":
			ci.draw_arc(c, gap + 4.0, 0.0, TAU, 40, Color(col, col.a * 0.35), 1.5, true)
			_dot(ci, c, 3.2, col)
		"circle":
			ci.draw_arc(c, gap + 6.0, 0.0, TAU, 48, INK, 4.0, true)
			ci.draw_arc(c, gap + 6.0, 0.0, TAU, 48, col, 2.0, true)
			_dot(ci, c, 1.6, col)
		"chevron":
			var pts := PackedVector2Array([c + Vector2(-11, gap + 12), c + Vector2(0, gap + 2), c + Vector2(11, gap + 12)])
			ci.draw_polyline(pts, INK, 5.0, true)
			ci.draw_polyline(pts, col, 2.5, true)
			_dot(ci, c, 1.6, col)
			_ticks(ci, c, gap, col, [Vector2.LEFT, Vector2.RIGHT])
		"carrot":
			_ticks(ci, c, gap, col, [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN])
			var body := PackedVector2Array([c + Vector2(-4.5, -5), c + Vector2(4.5, -5), c + Vector2(0, 9)])
			ci.draw_colored_polygon(_grow(body, c, 1.8), INK)
			ci.draw_colored_polygon(body, Color(1.0, 0.55, 0.12))
			for dx in [-3.0, 0.0, 3.0]:
				ci.draw_line(c + Vector2(dx * 0.5, -5), c + Vector2(dx, -10), Color(0.35, 0.8, 0.25), 2.0, true)
		"acorn":
			_ticks(ci, c, gap, col, [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN])
			ci.draw_circle(c + Vector2(0, 2), 5.5, INK)
			ci.draw_circle(c + Vector2(0, 2), 4.2, Color(0.75, 0.5, 0.25))
			ci.draw_arc(c + Vector2(0, -0.5), 4.8, PI, TAU, 16, Color(0.4, 0.25, 0.12), 3.2, true)
			ci.draw_line(c + Vector2(0, -4), c + Vector2(1.5, -7.5), Color(0.4, 0.25, 0.12), 1.6, true)
		"paw":
			_ticks(ci, c, gap, col, [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN])
			_dot(ci, c + Vector2(0, 2.5), 3.6, col)
			for toe in [Vector2(-5, -3), Vector2(-1.8, -6), Vector2(1.8, -6), Vector2(5, -3)]:
				_dot(ci, c + toe, 1.6, col)
		_:
			_ticks(ci, c, gap, col, [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN])
			_dot(ci, c, 1.6, col)


static func _ticks(ci: CanvasItem, c: Vector2, gap: float, col: Color, dirs: Array) -> void:
	for dir in dirs:
		var a: Vector2 = c + dir * gap
		var b: Vector2 = c + dir * (gap + 10.0)
		ci.draw_line(a, b, INK, 4.0)
		ci.draw_line(a, b, col, 2.0)


static func _dot(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(p, r + 0.9, INK)
	ci.draw_circle(p, r, col)


static func _grow(poly: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out
