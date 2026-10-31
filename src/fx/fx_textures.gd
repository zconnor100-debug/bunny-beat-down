class_name FXTextures
## Procedurally generated textures for effects (no image assets needed):
## a soft radial blob for billboarded particles, blood splats and scorch
## marks, tongues of flame and puffs of smoke (Fire).

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


## A white particle shape (for tinting): "heart", "leaf" or "chip" (a
## confetti square), drawn by its signed distance with a soft edge.
static func shape(kind: String) -> Texture2D:
	if _cache.has("shape_" + kind):
		return _cache["shape_" + kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, 1.0 - (y + 0.5) / n * 2.0)   # -1..1, y up
			var d := 1.0
			match kind:
				"heart":
					# two discs and a point: the classic heart
					var a := p.distance_to(Vector2(-0.33, 0.25)) - 0.42
					var b := p.distance_to(Vector2(0.33, 0.25)) - 0.42
					var tip := (absf(p.x) * 0.9 + (p.y + 0.85) * -0.62) if p.y < 0.25 else 1.0
					d = minf(minf(a, b), maxf(tip, -p.y - 0.85))
				"cog":
					# a gear: eight square-ish teeth round a disc, a hole in the middle
					var r := p.length()
					var tooth := clampf(cos(atan2(p.y, p.x) * 8.0) * 3.0, -1.0, 1.0) * 0.5 + 0.5
					d = maxf(r - (0.68 + 0.22 * tooth), 0.24 - r)
				"leaf":
					# a pointed oval, and a vein
					var q := Vector2(p.x * 1.9, p.y)
					d = q.length() - 0.9 + absf(p.y) * 0.25
					if absf(p.x) < 0.04 and absf(p.y) < 0.75:
						d = maxf(d, 0.02)
				_:
					d = maxf(absf(p.x) - 0.75, absf(p.y) - 0.45)
			var alpha := clampf(0.5 - d * 18.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["shape_" + kind] = t
	return t


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


## A tongue of flame, white (the particle's colour tints it): a soft round
## root, narrowing to a ragged point at the top, brightest down its middle.
static func flame() -> Texture2D:
	if _cache.has("flame"):
		return _cache["flame"]
	var w := 64
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.07
	for y in h:
		var v := (y + 0.5) / h   # 0 at the top .. 1 at the bottom
		for x in w:
			var u := (x + 0.5) / w - 0.5
			u += noise.get_noise_2d(x * 0.8, y * 0.6) * 0.09 * (1.0 - v)   # (raggeder toward the tip)
			var a := 0.0
			if v > 0.68:   # the root: round
				a = 1.0 - Vector2(u, (v - 0.68) * 1.15).length() / 0.3
			else:          # up to the tip
				var half := 0.3 * pow(clampf((v - 0.03) / 0.65, 0.0, 1.0), 0.75)
				a = 1.0 - absf(u) / maxf(half, 0.001)
			a = smoothstep(0.0, 0.55, a)
			var core := clampf(1.0 - absf(u) / 0.12, 0.0, 1.0) * smoothstep(0.25, 0.8, v)   # (a hot middle)
			var c := lerpf(0.82, 1.0, core)
			img.set_pixel(x, y, Color(c, c, c, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["flame"] = tex
	return tex


## A puff of smoke, white (tinted by the particle): a billowing clump of
## rounded lumps, lit from above (darker underneath).
static func smoke_puff() -> Texture2D:
	if _cache.has("smoke"):
		return _cache["smoke"]
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.fractal_octaves = 4
	noise.frequency = 0.045
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5) * 2.0   # -1..1, y down
			var lump := noise.get_noise_2d(x, y)
			var d := p.length() + lump * 0.35
			var a := clampf(1.0 - smoothstep(0.45, 0.95, d), 0.0, 1.0) * (0.75 + 0.25 * clampf(lump + 0.5, 0.0, 1.0))
			var shade := clampf(0.78 - p.y * 0.22 + lump * 0.25, 0.45, 1.0)   # (lit from above)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["smoke"] = tex
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
