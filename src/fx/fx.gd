class_name FX
extends Node3D
## One-shot visual effects. Gameplay calls the static helpers (FX.blood_hit(...)),
## which do nothing when no FX node is in the tree (unit tests, menus).
##
## Every particle is a billboarded soft blob (FXTextures.soft_blob) so smoke,
## blood and fluff read as volumes, never as flat paper squares.

const MAX_DECALS := 120
const BLOOD := Color(0.42, 0.015, 0.02)
const STUFFING := Color(0.96, 0.94, 0.88)

static var instance: FX

var _decals: Array[Decal] = []
var _next_decal := 0
var _process_mats: Dictionary = {}
var _draw_meshes: Dictionary = {}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


# --- public API ----------------------------------------------------------------

## A bullet/carrot hit on a living critter.
static func blood_hit(pos: Vector3, dir: Vector3, strength: float, fur: Color) -> void:
	if instance == null:
		return
	match Settings.gore:
		Settings.Gore.BLOOD:
			instance._burst(pos, dir, {"amount": int(14 + 18 * strength), "lifetime": 0.7, "speed": Vector2(1.5, 5.5) * (0.7 + strength * 0.5),
				"spread": 38.0, "gravity": 16.0, "size": 0.05, "scale": Vector2(0.5, 1.4), "color": BLOOD, "fade": true})
			instance._burst(pos, dir, {"amount": 4, "lifetime": 0.5, "speed": Vector2(0.3, 1.0), "spread": 60.0, "gravity": 0.5,
				"size": 0.22, "scale": Vector2(0.8, 1.5), "color": Color(BLOOD, 0.35), "fade": true, "damping": 2.0})
		Settings.Gore.STUFFING:
			instance._burst(pos, dir, {"amount": int(8 + 10 * strength), "lifetime": 1.4, "speed": Vector2(1.0, 3.5), "spread": 50.0,
				"gravity": 2.0, "size": 0.07, "scale": Vector2(0.6, 1.5), "color": STUFFING, "fade": true, "damping": 3.0})
	# fur tufts in every gore mode
	instance._burst(pos, dir, {"amount": int(3 + 5 * strength), "lifetime": 1.6, "speed": Vector2(0.6, 2.2), "spread": 70.0,
		"gravity": 1.2, "size": 0.05, "scale": Vector2(0.5, 1.2), "color": fur, "fade": true, "damping": 2.5})


## Big gore pop: explosions and limbs coming off.
static func gore_burst(pos: Vector3, strength: float, fur: Color) -> void:
	if instance == null:
		return
	var up := Vector3.UP
	match Settings.gore:
		Settings.Gore.BLOOD:
			instance._burst(pos, up, {"amount": int(40 * strength), "lifetime": 1.1, "speed": Vector2(2.0, 8.0) * strength,
				"spread": 85.0, "gravity": 16.0, "size": 0.07, "scale": Vector2(0.5, 1.6), "color": BLOOD, "fade": true})
			instance._burst(pos, up, {"amount": 8, "lifetime": 0.9, "speed": Vector2(0.4, 1.4), "spread": 90.0, "gravity": 0.3,
				"size": 0.35, "scale": Vector2(0.7, 1.6), "color": Color(BLOOD, 0.3), "fade": true, "damping": 1.5})
			for i in 3:
				var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.2, 1.4)
				instance._ground_splat(pos + d, randf_range(0.5, 1.1) * strength)
		Settings.Gore.STUFFING:
			instance._burst(pos, up, {"amount": int(30 * strength), "lifetime": 2.2, "speed": Vector2(1.0, 5.0) * strength,
				"spread": 90.0, "gravity": 1.5, "size": 0.1, "scale": Vector2(0.6, 1.8), "color": STUFFING, "fade": true, "damping": 2.0})
	instance._burst(pos, up, {"amount": int(14 * strength), "lifetime": 2.0, "speed": Vector2(1.0, 4.0), "spread": 90.0,
		"gravity": 1.0, "size": 0.06, "scale": Vector2(0.5, 1.3), "color": fur, "fade": true, "damping": 2.2})


## Continuous spurt from a stump. Parent it to the bone attachment it belongs to.
static func stump_fountain(parent: Node3D, dir_local: Vector3) -> void:
	if instance == null or parent == null or Settings.gore == Settings.Gore.OFF:
		return
	var p: GPUParticles3D = instance._make_particles({
		"amount": 48, "lifetime": 0.7, "speed": Vector2(1.5, 3.2), "spread": 14.0, "gravity": 16.0,
		"size": 0.045, "scale": Vector2(0.6, 1.2), "fade": true,
		"color": BLOOD if Settings.gore == Settings.Gore.BLOOD else STUFFING,
	}, false)
	p.one_shot = false
	p.local_coords = false
	parent.add_child(p)
	if dir_local.length_squared() > 0.0001:
		p.basis = Basis.looking_at(dir_local.normalized(), Vector3.UP if absf(dir_local.normalized().y) < 0.95 else Vector3.RIGHT)
	p.emitting = true
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_node(p, "", false)
	Despawner.after(p, randf_range(2.0, 3.5), func(n: Node):
		(n as GPUParticles3D).emitting = false
		Despawner.after(n, 1.0, func(m: Node): m.queue_free()))


## Decal on whatever surface was hit (only in BLOOD mode).
static func splat_decal(pos: Vector3, normal: Vector3, size: float) -> void:
	if instance == null or Settings.gore != Settings.Gore.BLOOD:
		return
	instance._decal(pos, normal, size, FXTextures.splat(randi() % 6, BLOOD))


static func impact(pos: Vector3, normal: Vector3, surface: StringName) -> void:
	if instance == null:
		return
	var col := Color(0.42, 0.33, 0.22)
	match surface:
		&"wood":
			col = Color(0.55, 0.4, 0.25)
		&"rock":
			col = Color(0.55, 0.55, 0.52)
		&"leaf", &"grass":
			col = Color(0.35, 0.5, 0.2)
		&"water":
			col = Color(0.8, 0.9, 1.0, 0.8)
		&"cloth":   # (stuffing fluff out of socks and plush)
			col = Color(0.95, 0.93, 0.9)
	instance._burst(pos, normal, {"amount": 7, "lifetime": 0.8, "speed": Vector2(0.4, 1.6), "spread": 45.0, "gravity": 1.5,
		"size": 0.12, "scale": Vector2(0.6, 1.4), "color": Color(col, 0.65), "fade": true, "damping": 2.5})
	instance._burst(pos, normal, {"amount": 6, "lifetime": 0.6, "speed": Vector2(2.0, 4.5), "spread": 35.0, "gravity": 16.0,
		"size": 0.025, "scale": Vector2(0.6, 1.3), "color": col.darkened(0.2), "fade": false})


const FLASH := Color(1.0, 0.75, 0.35, 0.9)


## Carrot-dust pop and a fleck of green at the muzzle; the player's Workshop
## looks tint the flash and add smoke ("puff", "matching", "spores"), and a
## Muffler shrinks it (`k`).
static func muzzle(pos: Vector3, dir: Vector3, big: bool, tint := FLASH, smoke := "", k := 1.0) -> void:
	if instance == null:
		return
	k *= 1.8 if big else 1.0
	instance._burst(pos, dir, {"amount": maxi(2, int(6 * k)), "lifetime": 0.25, "speed": Vector2(1.0, 3.0) * k, "spread": 18.0, "gravity": 0.0,
		"size": 0.07 * k, "scale": Vector2(0.6, 1.4), "color": tint, "fade": true, "damping": 6.0, "additive": true})
	instance._burst(pos, dir, {"amount": maxi(1, int(3 * k)), "lifetime": 0.6, "speed": Vector2(0.5, 1.5), "spread": 40.0, "gravity": 2.0,
		"size": 0.03, "scale": Vector2(0.6, 1.2), "color": Color(0.3, 0.65, 0.2), "fade": true, "damping": 2.0})
	match smoke:
		"puff", "matching":
			var c := Color(0.92, 0.92, 0.9, 0.45) if smoke == "puff" else Color(tint.lerp(Color.WHITE, 0.35), 0.5)
			instance._burst(pos, dir, {"amount": 4, "lifetime": 1.3, "speed": Vector2(0.3, 1.0), "spread": 30.0, "gravity": -0.5,
				"size": 0.2 * k, "scale": Vector2(0.7, 1.6), "color": c, "fade": true, "damping": 2.5})
		"spores":
			instance._burst(pos, dir, {"amount": 10, "lifetime": 1.8, "speed": Vector2(0.4, 1.4), "spread": 50.0, "gravity": -0.25,
				"size": 0.045, "scale": Vector2(0.5, 1.3), "color": Color(0.85, 1.0, 0.5, 0.85), "fade": true, "damping": 1.6, "additive": true})


## The burst when the player beats a critter down (a Workshop look):
## "confetti", "leaves", "carrots" or "hearts" ("none": nothing).
## The Workshop's beat-down bursts: [shape, colours, gravity, size, and
## anything else for _burst] for each.
const BEAT_DOWN_BURSTS := {
	"confetti": [["chip", [Color(1, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.3, 0.7, 1), Color(0.45, 0.9, 0.35)], 6.0, 0.09]],
	"leaves": [["leaf", [Color(0.95, 0.45, 0.1), Color(0.85, 0.2, 0.1), Color(0.95, 0.75, 0.2)], 2.2, 0.16]],
	"carrots": [["leaf", [Color(1.0, 0.5, 0.1)], 9.0, 0.14], ["blob", [Color(0.35, 0.75, 0.25)], 6.0, 0.06]],
	"hearts": [["heart", [Color(1, 0.4, 0.6), Color(1, 0.6, 0.75)], -1.2, 0.16]],
	# (earned only: Mastery ladders)
	"fireworks": [["blob", [Color(1, 0.35, 0.4), Color(0.4, 0.65, 1), Color(1, 0.85, 0.3), Color(0.55, 1, 0.5)], 3.0, 0.07,
		{"amount": 14, "speed": Vector2(6.0, 10.0), "spread": 180.0, "additive": true, "damping": 2.6, "lifetime": 1.4}]],
	"gold_rush": [["chip", [Color(1.0, 0.82, 0.25), Color(0.95, 0.65, 0.15)], 11.0, 0.1, {"amount": 12, "speed": Vector2(3.0, 7.0)}],
		["blob", [Color(1.0, 0.95, 0.6)], -0.5, 0.05, {"amount": 8, "additive": true, "lifetime": 1.0}]],
	# (earned by beating Nibbles: foam bubbling up off them, and flecks)
	"froth": [["blob", [Color(0.94, 0.99, 0.88), Color(0.8, 0.96, 0.62)], -0.7, 0.16,
		{"amount": 20, "speed": Vector2(1.2, 3.8), "spread": 85.0, "damping": 2.4, "lifetime": 1.8}],
		["chip", [Color(0.96, 1.0, 0.92)], 8.0, 0.05, {"amount": 10, "speed": Vector2(3.0, 6.0)}]],
	# (earned in the Kernel Hunt's Act I, burning the Carrot Patch: embers and a puff of smoke)
	"embers": [["blob", [Color(1.0, 0.62, 0.15), Color(1.0, 0.85, 0.4)], -1.6, 0.07,
		{"amount": 16, "speed": Vector2(1.0, 4.5), "spread": 75.0, "additive": true, "damping": 1.2, "lifetime": 2.0}],
		["blob", [Color(0.22, 0.2, 0.18, 0.6)], -0.6, 0.55, {"amount": 6, "speed": Vector2(0.6, 1.6), "spread": 50.0, "lifetime": 2.4}]],
	# (earned in the Kernel Hunt's Act II, unwinding the Tin Tyrant: cogs and springs fly)
	"cogs": [["cog", [Color(0.86, 0.66, 0.3), Color(0.75, 0.76, 0.8), Color(0.86, 0.2, 0.15)], 10.0, 0.13,
		{"amount": 10, "speed": Vector2(3.0, 7.5), "spread": 80.0, "lifetime": 1.6}],
		["chip", [Color(0.95, 0.8, 0.4)], 12.0, 0.05, {"amount": 10, "speed": Vector2(3.0, 8.0), "additive": true, "lifetime": 0.6}]],
	# (earned in the Kernel Hunt's Act III, out of Nibbles's cheeks: sunflower seeds, striped)
	"seeds": [["leaf", [Color(0.12, 0.11, 0.1), Color(0.9, 0.88, 0.8), Color(0.3, 0.28, 0.26)], 11.0, 0.12,
		{"amount": 12, "speed": Vector2(3.0, 7.0), "spread": 75.0, "lifetime": 1.6}]],
}


static func beat_down(pos: Vector3, style: String) -> void:
	if instance == null:
		return
	for s in BEAT_DOWN_BURSTS.get(style, []):
		for col in s[1]:
			var o := {"amount": 9, "lifetime": 1.8, "speed": Vector2(2.0, 5.0), "spread": 70.0, "gravity": s[2],
				"size": s[3], "scale": Vector2(0.7, 1.3), "color": col, "fade": true, "damping": 1.4, "shape": s[0]}
			if s.size() > 4:
				o.merge(s[4], true)
			instance._burst(pos, Vector3.UP, o)


static func explosion(pos: Vector3, radius: float) -> void:
	if instance == null:
		return
	var k := radius / 5.0
	instance._burst(pos, Vector3.UP, {"amount": int(36 * k), "lifetime": 0.55, "speed": Vector2(2.0, 9.0) * k, "spread": 180.0,
		"gravity": -1.0, "size": 0.9 * k, "scale": Vector2(0.6, 1.5), "color": Color(1.0, 0.62, 0.2), "fade": true,
		"damping": 7.0, "additive": true})
	instance._burst(pos, Vector3.UP, {"amount": int(26 * k), "lifetime": 2.8, "speed": Vector2(1.0, 4.0) * k, "spread": 120.0,
		"gravity": -1.6, "size": 1.3 * k, "scale": Vector2(0.7, 1.8), "color": Color(0.32, 0.3, 0.28, 0.55), "fade": true, "damping": 2.2})
	# carrot shrapnel
	instance._burst(pos, Vector3.UP, {"amount": int(24 * k), "lifetime": 1.3, "speed": Vector2(5.0, 13.0) * k, "spread": 100.0,
		"gravity": 16.0, "size": 0.05, "scale": Vector2(0.6, 1.4), "color": Color(1.0, 0.45, 0.08), "fade": false})
	instance._flash(pos, radius)
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_flash(pos, radius)
	instance._decal(pos, Vector3.UP, radius * 0.9, FXTextures.scorch())


## A one-shot burst of particles (the bosses' dust, chips and sparks: BossFX),
## cfg as the bursts here take it ("aabb": how far it spreads, if far).
static func burst(pos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	if instance:
		instance._burst(pos, dir, cfg)


## Fluffy smoke trail that follows a rocket (world-space particles).
static func smoke_trail(parent: Node3D) -> GPUParticles3D:
	if instance == null:
		return null
	var p: GPUParticles3D = instance._make_particles({"amount": 90, "lifetime": 1.6, "speed": Vector2(0.1, 0.5), "spread": 180.0,
		"gravity": -0.8, "size": 0.22, "scale": Vector2(0.6, 1.6), "color": Color(0.85, 0.85, 0.82, 0.45), "fade": true, "damping": 1.0}, false)
	p.one_shot = false
	p.local_coords = false
	p.emitting = true
	parent.add_child(p)
	return p


## A flare's red smoke, rising in a column you can see across the map, and
## sparks spitting off its burning tip (world-space particles).
static func flare_smoke(parent: Node3D) -> GPUParticles3D:
	if instance == null:
		return null
	var p: GPUParticles3D = instance._make_particles({"amount": 140, "lifetime": 7.0, "speed": Vector2(0.6, 1.4), "spread": 18.0,
		"gravity": -1.6, "size": 1.5, "scale": Vector2(0.8, 2.6), "color": Color(0.98, 0.2, 0.14, 0.62), "fade": true, "damping": 0.15}, false)
	p.one_shot = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 60, 20))
	p.rotation = Vector3(-PI * 0.5, 0.0, 0.0)   # (its particles start off along -Z: up)
	p.emitting = true
	parent.add_child(p)
	var sparks: GPUParticles3D = instance._make_particles({"amount": 24, "lifetime": 0.5, "speed": Vector2(1.0, 2.8), "spread": 70.0,
		"gravity": 6.0, "size": 0.05, "scale": Vector2(0.5, 1.2), "color": Color(1.0, 0.6, 0.25), "fade": true, "additive": true}, false)
	sparks.one_shot = false
	sparks.local_coords = false
	sparks.emitting = true
	p.add_child(sparks)
	return p


# --- internals -----------------------------------------------------------------

## The explosion's flash of light.
func _flash(pos: Vector3, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 12.0
	light.omni_range = radius * 3.0
	light.shadow_enabled = false
	add_child(light)
	light.global_position = pos + Vector3.UP * 0.5
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(light.queue_free)


func _burst(pos: Vector3, dir: Vector3, cfg: Dictionary) -> GPUParticles3D:
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_fx(pos, dir, cfg)
	var p := _make_particles(cfg, true)
	add_child(p)
	p.global_position = pos
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP
	p.global_basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


func _make_particles(cfg: Dictionary, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(cfg.get("amount", 8)))
	p.lifetime = cfg.get("lifetime", 1.0)
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.fixed_fps = 0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = cfg.get("aabb", 6.0)   # (a boss's dust spreads tens of metres)
	p.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	p.process_material = _process_material(cfg)
	p.draw_pass_1 = _draw_mesh(cfg)
	return p


func _process_material(cfg: Dictionary) -> ParticleProcessMaterial:
	var key := str(cfg.get("speed"), cfg.get("spread"), cfg.get("gravity"), cfg.get("scale"), cfg.get("color"), cfg.get("fade"), cfg.get("damping", 0.0))
	if _process_mats.has(key):
		return _process_mats[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, -1)
	m.spread = cfg.get("spread", 30.0)
	var spd: Vector2 = cfg.get("speed", Vector2(1, 2))
	m.initial_velocity_min = spd.x
	m.initial_velocity_max = spd.y
	m.gravity = Vector3(0, -cfg.get("gravity", 9.8), 0)
	var sc: Vector2 = cfg.get("scale", Vector2(1, 1))
	m.scale_min = sc.x
	m.scale_max = sc.y
	m.damping_min = cfg.get("damping", 0.0)
	m.damping_max = cfg.get("damping", 0.0) * 1.3
	m.angle_min = -180.0
	m.angle_max = 180.0
	var col: Color = cfg.get("color", Color.WHITE)
	m.color = col
	if cfg.get("fade", false):
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.6, Color(1, 1, 1, 0.85))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		m.color_ramp = gt
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1, 0.85))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	_process_mats[key] = m
	return m


func _draw_mesh(cfg: Dictionary) -> QuadMesh:
	var size: float = cfg.get("size", 0.1)
	var additive: bool = cfg.get("additive", false)
	var shape: String = cfg.get("shape", "blob")
	var key := "%s_%s_%s" % [size, additive, shape]
	if _draw_meshes.has(key):
		return _draw_meshes[key]
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FXTextures.soft_blob() if shape == "blob" else FXTextures.shape(shape)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.15
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	_draw_meshes[key] = q
	return q


func _ground_splat(pos: Vector3, size: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 3.0, Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit:
		_decal(hit.position, hit.normal, size, FXTextures.splat(randi() % 6, BLOOD))


func _decal(pos: Vector3, normal: Vector3, size: float, tex: Texture2D) -> void:
	var d: Decal
	var was := [Transform3D(), false]   # (a recycled decal was somewhere else before)
	if _decals.size() < MAX_DECALS:
		d = Decal.new()
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)
	else:
		d = _decals[_next_decal]
		_next_decal = (_next_decal + 1) % MAX_DECALS
		was = [d.global_transform, d.visible]
	d.texture_albedo = tex
	d.size = Vector3(size, 0.6, size)
	d.modulate = Color(1, 1, 1, 0.92)
	var n := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.UP
	var side := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	side = side.rotated(n, randf() * TAU)
	d.global_transform = Transform3D(Basis(side, n, side.cross(n)), pos)
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_decal(d, was[0], was[1])
