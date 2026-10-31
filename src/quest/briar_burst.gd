class_name BriarBurst
extends Node3D
## The Briar coming up through the floor (the end of the Kernel Hunt's
## Act III, FoamOutro): thorny vines, dark and purple-veined like the Briar's
## wall, bursting up out of the ground in a ring round where the three Kernels
## met, swaying, and its purple haze with them. The oldest stories say the
## Briar is the Acorn's roots, looking for its pieces (docs/LORE.md).

const VINES := 11
const STALK := Color(0.16, 0.08, 0.14)
const GLOW := Color(0.62, 0.22, 0.85)

var radius := 13.0
var _vines: Array[Node3D] = []
var _t := 0.0
var _mat: StandardMaterial3D
var _thorn: StandardMaterial3D


func _init(r := 13.0) -> void:
	name = "BriarBurst"
	radius = r


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = STALK
	_mat.roughness = 0.75
	_mat.emission_enabled = true
	_mat.emission = GLOW
	_mat.emission_energy_multiplier = 0.35
	_mat.rim_enabled = true
	_mat.rim = 0.5
	_thorn = _mat.duplicate() as StandardMaterial3D
	_thorn.albedo_color = Color(0.3, 0.2, 0.26)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in VINES:
		var a := TAU * i / VINES + rng.randf_range(-0.2, 0.2)
		var vine := _vine(rng, rng.randf_range(9.0, 16.0))
		add_child(vine)
		vine.position = Vector3(cos(a), 0.0, sin(a)) * radius * rng.randf_range(0.85, 1.15) + Vector3.DOWN * 18.0
		vine.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * TAU, rng.randf_range(-0.25, 0.25))
		_vines.append(vine)


## Up they come, one after another round the ring.
func burst(seconds := 1.6) -> void:
	for i in _vines.size():
		var v := _vines[i]
		var tw := create_tween()
		tw.tween_interval(i * 0.08)
		tw.tween_property(v, "position:y", 0.0, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_callback(func():
			BossFX.dust(global_position + Vector3(v.position.x, 0.0, v.position.z), 4.0, Color(0.32, 0.22, 0.3, 0.75))
			FX.burst(global_position + Vector3(v.position.x, 2.0, v.position.z), Vector3.UP, {"amount": 14, "lifetime": 2.4,
				"speed": Vector2(1.0, 3.5), "spread": 60.0, "gravity": -0.3, "size": 1.6, "scale": Vector2(0.6, 1.6),
				"color": Color(GLOW, 0.35), "fade": true, "additive": true, "damping": 1.2, "aabb": 12.0}))
	Audio.play_at(&"boss_stomp", global_position, 6.0, 0.0, {"max_distance": 500.0, "unit_size": 40.0})
	var hum := Audio.play_at(&"storm_loop", global_position, 4.0, 0.0, {"max_distance": 300.0, "unit_size": 25.0})
	if hum:
		hum.pitch_scale = 0.7
	Events.explosion.emit(global_position, 8.0)


func _process(delta: float) -> void:
	_t += delta
	for i in _vines.size():
		var v := _vines[i]
		v.rotation.z = sin(_t * 0.9 + i * 1.7) * 0.06
	_mat.emission_energy_multiplier = 0.35 + 0.25 * (0.5 + 0.5 * sin(_t * 2.3))


## A vine: a tapering stalk that bends as it climbs, thorns all up it.
func _vine(rng: RandomNumberGenerator, height: float) -> Node3D:
	var root := Node3D.new()
	var segs := 5
	var at := Vector3.ZERO
	var dir := Vector3.UP
	var bend := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
	for k in segs:
		var seg_len := height / segs
		var r0 := lerpf(0.9, 0.15, float(k) / segs)
		var r1 := lerpf(0.9, 0.15, float(k + 1) / segs)
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.bottom_radius = r0
		cyl.top_radius = r1
		cyl.height = seg_len
		cyl.radial_segments = 8
		cyl.rings = 1
		seg.mesh = cyl
		seg.material_override = _mat
		var b := Basis(IKMath.from_to(Vector3.UP, dir))
		seg.transform = Transform3D(b, at + dir * seg_len * 0.5)
		root.add_child(seg)
		for t in 3:
			var thorn := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.bottom_radius = r0 * 0.45
			cone.top_radius = 0.0
			cone.height = r0 * 1.6
			cone.radial_segments = 5
			cone.rings = 1
			thorn.mesh = cone
			thorn.material_override = _thorn
			var out := b * Vector3(cos(t * 2.1 + k), 0.0, sin(t * 2.1 + k))
			var tb := Basis(IKMath.from_to(Vector3.UP, (out + dir * 0.3).normalized()))
			thorn.transform = Transform3D(tb, at + dir * seg_len * (0.3 + 0.2 * t) + out * r0 * 0.9)
			root.add_child(thorn)
		at += dir * seg_len
		dir = (dir + bend).normalized()
	for mi in ModelUtil.find_all(root, "MeshInstance3D"):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root
