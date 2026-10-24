class_name FXTextures
## Procedurally generated textures for effects (no image assets needed):
## a soft radial blob for billboarded particles, blood splats and scorch marks.

static var _cache: Dictionary = {}


static func soft_blob() -> Texture2D:
	if not _cache.has("blob"):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_cache["blob"] = t
	return _cache["blob"]


## A soft streak for wind ribbons (particle trails): it fades across its
## width and toward both ends (u across the ribbon, v along it).
static func streak() -> Texture2D:
	if not _cache.has("streak"):
		var img := Image.create(16, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			var along := sin(PI * (y + 0.5) / 64.0)
			for x in 16:
				var across := 1.0 - pow(absf((x + 0.5) / 8.0 - 1.0), 2.0)
				img.set_pixel(x, y, Color(1, 1, 1, along * along * across))
		_cache["streak"] = ImageTexture.create_from_image(img)
	return _cache["streak"]


## Irregular splat: a core blob, satellite droplets and a few streaks.
## `variant` seeds the shape so a handful of variants can be cached.
static func splat(variant: int, color: Color) -> Texture2D:
	var key := "splat_%d_%s" % [variant, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var c := Vector2(size, size) * 0.5
	_disc(img, c, size * rng.randf_range(0.18, 0.24), color, 1.0)
	for i in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var d := size * rng.randf_range(0.12, 0.3)
		_disc(img, c + Vector2.from_angle(a) * d, size * rng.randf_range(0.06, 0.12), color, 0.95)
	for i in rng.randi_range(10, 22):
		var a := rng.randf() * TAU
		var d := size * rng.randf_range(0.25, 0.46)
		_disc(img, c + Vector2.from_angle(a) * d, size * rng.randf_range(0.012, 0.035), color, 0.9)
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var start := size * 0.2
		for s in 12:
			var d := start + s * size * 0.018
			_disc(img, c + Vector2.from_angle(a) * d, size * (0.03 - s * 0.002), color, 0.9)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func scorch() -> Texture2D:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var n := noise.get_noise_2d(x, y) * 0.35
			var a := clampf(1.0 - smoothstep(0.35, 1.0, d + n), 0.0, 1.0) * 0.9
			img.set_pixel(x, y, Color(0.05, 0.04, 0.03, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["scorch"] = tex
	return tex


static func _disc(img: Image, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	var size := img.get_width()
	var r2 := radius * radius
	for y in range(maxi(0, int(center.y - radius - 1)), mini(size, int(center.y + radius + 2))):
		for x in range(maxi(0, int(center.x - radius - 1)), mini(size, int(center.x + radius + 2))):
			var d2 := Vector2(x + 0.5, y + 0.5).distance_squared_to(center)
			if d2 > r2:
				continue
			# soft 1.5 px edge, darker towards the centre like drying blood
			var edge := clampf((radius - sqrt(d2)) / 1.5, 0.0, 1.0)
			var prev := img.get_pixel(x, y)
			var a := maxf(prev.a, edge * alpha)
			var shade := lerpf(1.0, 0.7, clampf(1.0 - sqrt(d2) / radius, 0.0, 1.0) * 0.5)
			img.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, a))
