class_name BriarHeart
extends Boss
## The Briar Heart, the Kernel Hunt's last boss (its Finale, StarfallMission;
## docs/LORE.md). When the Starfall Acorn hit Boulder Bluff, what was left of
## it, the husk, sank into the Bluff and put down roots: the Briar, which has
## been growing under Wildwood ever since, looking for the three pieces. Where
## the husk lies its roots knotted into a heart, a knot of thorny vines as big
## as the Big Red Barn, and it beats. Now it has all three Kernels, each shut
## in a thorny pod on a vine of its own. It doesn't walk: it's rooted in the
## Bluff, and turns, slowly, to face whoever it's after. Built in code (no
## model: VineMesh), in the cracked husk of the Acorn.
##   Pods: it opens them one at a time to drink the light (`bloom`): the
##     Kernel's showing, and that's the time to shoot it (POD_OPEN; shut, its
##     thorns take most of it, POD_SHUT). Break a pod and its Kernel flies
##     free (`kernels`), and the Heart reels (stunned).
##   Its knot shrugs off carrots (BODY) while it has a Kernel left; with the
##     last pod broken it splits open (`opened`: enraged), and the light at
##     its heart is out where you can hit it (CORE).
##   Thorn Volley: thorns flung high, coming down where you're standing.
##   Root Burst: roots ripping up out of the ground in a line toward you
##     (they throw you off your feet).
##   Lash: a vine sweeping right round its foot, at anyone close (jump it).
## Its health is its three pods' and its heart's, together (the bar).

signal pod_opened(i: int)
signal pod_broken(i: int)
signal opened

const H := 17.0                     ## the knot: how tall (its point sunk in the Bluff)...
const W := 15.0                     ## ...how wide...
const D := 10.0                     ## ...and how deep
const CY := 9.4                     ## the middle of it (the height of its heart)
const PODS := 3
const POD_R := 2.5                  ## a pod's size (its hitbox's radius)
const POD_SHARE := 0.22             ## of its health in each pod (the rest is its heart's)
const POD_OPEN := 1.6               ## hits on an open pod count this much...
const POD_SHUT := 0.18              ## ...on a shut one, this much (blasts: POD_SHUT_BLAST)
const POD_SHUT_BLAST := 0.6
const BODY := 0.1                   ## hits on the knot while it has a Kernel left...
const BODY_OPEN := 0.5              ## ...once it's split open...
const CORE := 2.0                   ## ...and on the light at its heart
const CORE_FLOOR := 0.5             ## its heart can't be worn below this share of its own till it's open
const BLOOM_EVERY := [9.0, 7.0, 6.0]   ## seconds between its pods opening, by difficulty...
const BLOOM_FOR := [7.5, 6.0, 5.0]     ## ...and how long one stays open
const SHUDDER := 0.8                ## seconds a pod shudders before it opens
const REST := 1.6                   ## seconds between two of its moves
const THORN_R := 3.4
const ROOT_W := 5.0
const LASH_R := 24.0
const BEAT := 1.25                  ## seconds a heartbeat (lub-dub), calm
const GLOW := Color(0.8, 1.0, 0.34)
const SAP := Color(0.3, 0.1, 0.34)
const HUSK := Color(0.56, 0.4, 0.18)

## Where each pod hangs (its local place: in front is -z), and the point on
## the knot its vine comes out of.
const POD_AT := [Vector3(-12.6, 13.0, -2.0), Vector3(12.6, 13.0, -2.0), Vector3(2.4, 4.2, -11.5)]
const ARM_FROM := [Vector3(-5.0, 11.5, -0.5), Vector3(5.0, 11.5, -0.5), Vector3(0.8, 3.2, -3.6)]

var pod_hp: Array[float] = []
var pod_max := 0.0
var core_hp := 0.0
var core_max := 0.0
var split := false                  ## it's split open: its heart's out
var kernels: Array[StarfallKernel] = []   ## the Kernels freed from its pods (the ending takes them)
var bloom_i := -1                   ## the pod open now (-1: none)
var _pods: Array[Dictionary] = []   # {node, sepals: [Node3D], kernel, area, arm, arm_mat, broken, open (0..1), shudder}
var _root: Node3D                   # everything that rises out of the Bluff
var _knot: Node3D
var _hinge_l: Node3D                # the front of the knot, in halves, that swing open
var _hinge_r: Node3D
var _mats: Array[ShaderMaterial] = []
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _core_area: Area3D
var _husk: Array[Node3D] = []
var _stalk: ArrayMesh               # (a thorny stalk: what bursts up out of the ground)
var _stalk_mat: ShaderMaterial
var _stalk_thorns: MultiMesh
var _thorn_mesh: Mesh
var _bloom_t := 5.0
var _bloom_left := 0.0
var _next_pod := 0
var _rest_until := 0.0
var _beat_t := 0.0
var _beat_k := 0.0                  # (0..1: how far the knot is swollen with a beat)
var _rise := 1.0                    # (0: still under the Bluff, 1: up)
var _drink_t := 0.0
var _swell := 0.0                   # (its groan swells the knot)
var _gather := Vector3.ZERO         # (where the freed Kernels hang, over it)
var _diff := 1


func _init() -> void:
	super()
	name = "BriarHeart"
	id = "briar"
	display_name = "The Briar Heart"
	title = "the Acorn's Roots"
	from_below = true
	land_time = 2.6
	base_health = 15000.0
	walk_speed = 0.0
	turn_speed = 0.32
	intro_scale = 1.4   # (it's big, and wide: its arrival's camera stands well back, inside the Briar's ring)
	blood = SAP


func setup(mm: Node, difficulty := 1) -> void:
	super(mm, difficulty)
	_diff = clampi(difficulty, 0, 2)
	_split_health()


func _split_health() -> void:
	pod_max = max_health * POD_SHARE
	core_max = max_health - pod_max * PODS
	pod_hp.clear()
	for i in PODS:
		pod_hp.append(pod_max)
	core_hp = core_max
	health = max_health


# ---- what it looks like (all of it code: no model) ------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	data = {}
	size = 1.0
	if pod_hp.is_empty():
		_split_health()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1301
	_root = Node3D.new()
	_root.name = "Rising"
	add_child(_root)
	model = _root
	_build_husk(rng)
	_knot = Node3D.new()
	_knot.name = "Knot"
	_root.add_child(_knot)
	_hinge_l = Node3D.new()
	_hinge_l.position = Vector3(-W * 0.42, 0.0, -D * 0.12)
	_knot.add_child(_hinge_l)
	_hinge_r = Node3D.new()
	_hinge_r.position = Vector3(W * 0.42, 0.0, -D * 0.12)
	_knot.add_child(_hinge_r)
	var bark := _vine_mat(0.35, 0.55)
	var thorn_at: Array[Transform3D] = []
	# heart-shaped loops of vine, nested: the outer one round its edge, the
	# smaller ones in front of it and behind (a fat heart, made of rings)
	for s in [1.0, 0.86, 0.68, 0.48, 0.27]:
		var z := D * 0.5 * sqrt(maxf(0.0, 1.0 - s * s))
		for side in ([0.0] if s >= 1.0 else [-1.0, 1.0]):
			var wob := rng.randf() * TAU
			var r := lerpf(0.95, 0.7, 1.0 - s)
			if side < 0.0:   # (the front: in halves, so it can split open down the middle)
				for half in [0, 1]:
					var pts := PackedVector3Array()
					var radii := PackedFloat32Array()
					for i in 25:
						var t := PI * (i / 24.0) + (PI if half == 0 else 0.0)
						var p := _loop_point(t, s, z * side, wob)
						var hinge := _hinge_l if half == 0 else _hinge_r
						pts.append(p - hinge.position)
						radii.append(r * (1.0 - 0.25 * absf(sin(t * 2.0))))
					var mi := _vine(pts, radii, bark)
					(_hinge_l if half == 0 else _hinge_r).add_child(mi)
					var at := VineMesh.thorns(pts, radii, rng, 1.7, 2, 1.3)
					var thorns := VineMesh.thorn_multimesh(at, 1.2)
					(_hinge_l if half == 0 else _hinge_r).add_child(thorns)
			else:
				var pts := PackedVector3Array()
				var radii := PackedFloat32Array()
				for i in 49:
					var t := TAU * i / 48.0
					pts.append(_loop_point(t, s, z * side, wob))
					radii.append(r * (1.0 - 0.25 * absf(sin(t * 2.0))))
				_knot.add_child(_vine(pts, radii, bark))
				thorn_at.append_array(VineMesh.thorns(pts, radii, rng, 1.7, 2, 1.3))
	# vines binding it, wound round and round from its point to its top
	for k in 6:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var p0 := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		for i in 41:
			var u := i / 40.0
			var y := lerpf(-1.0, H * 0.88, u)
			var w := _half_width(y)
			var a := p0 + u * TAU * 1.2
			pts.append(Vector3(cos(a) * w * 0.98, y, sin(a) * D * 0.5 * sqrt(clampf(w / (W * 0.5), 0.05, 1.0)) * 0.98))
			radii.append(0.62 * (1.0 - 0.4 * u))
		_knot.add_child(_vine(pts, radii, bark))
		thorn_at.append_array(VineMesh.thorns(pts, radii, rng, 1.5, 2, 1.2))
	_knot.add_child(VineMesh.thorn_multimesh(thorn_at, 1.2))
	# the light at its heart (behind the vines, till it splits open)
	_core = MeshInstance3D.new()
	_core.name = "Core"
	var ball := SphereMesh.new()
	ball.radius = 2.7
	ball.height = 5.4
	_core.mesh = ball
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = GLOW
	_core_mat.emission_enabled = true
	_core_mat.emission = GLOW
	_core_mat.emission_energy_multiplier = 3.0
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.position = Vector3(0, CY, 0)
	_knot.add_child(_core)
	_core_light = OmniLight3D.new()
	_core_light.light_color = GLOW
	_core_light.omni_range = 34.0
	_core_light.light_energy = 3.0
	_core_light.shadow_enabled = false
	_core.add_child(_core_light)
	for i in PODS:
		_build_pod(i, rng, bark)
	_build_hits()
	_build_stalk(rng)
	for gi in ModelUtil.find_all(_root, "GeometryInstance3D"):
		(gi as GeometryInstance3D).layers = CritterVisual.RENDER_LAYER   # (no blood decals on it)
	_root.position.y = 0.0


## A point on its heart-shaped loops: the outline (`t` round it, 0 the top
## of its cleft, PI its point) scaled `s` toward its middle, `z` in front of
## it or behind, wobbling a little like a vine would.
func _loop_point(t: float, s: float, z: float, wob: float) -> Vector3:
	var o := _outline(t)
	var c := Vector2(0.0, CY)
	var p := c + (o - c) * s
	var w := 0.35 * sin(t * 5.0 + wob) + 0.2 * sin(t * 11.0 + wob * 2.0)
	return Vector3(p.x + w, p.y + w * 0.6, z + 0.4 * sin(t * 3.0 + wob))


## The heart's outline (the old curve: x = 16 sin³t, y = 13 cos t - 5 cos 2t
## - 2 cos 3t - cos 4t), in metres: its point at the bottom, 1.5 m under
## the ground, its lobes H up.
func _outline(t: float) -> Vector2:
	var x := 16.0 * pow(sin(t), 3.0)
	var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
	return Vector2(x / 16.0 * W * 0.5, (y + 17.0) / 29.0 * (H + 1.5) - 1.5)


## How wide it is (half) at height `y`.
func _half_width(y: float) -> float:
	var best := 0.6
	for i in 64:
		var t := PI * i / 63.0
		var o := _outline(t)
		if absf(o.y - y) < 0.9:
			best = maxf(best, absf(o.x))
	return best


func _vine(pts: PackedVector3Array, radii: PackedFloat32Array, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VineMesh.tube(pts, radii, 9)
	mi.material_override = mat
	return mi


func _vine_mat(pulses: float, steady: float) -> ShaderMaterial:
	var m := VineMesh.bark_material(pulses, steady)
	m.set_shader_parameter(&"pulse_speed", 6.0)
	m.set_shader_parameter(&"pulse_every", 9.0)
	_mats.append(m)
	return m


## The Starfall Acorn's husk, split, its halves lying open either side of its
## foot like the shell it hatched out of (open side up, toward it), mottled
## and streaked like an acorn's; and its cap, tipped over behind it.
func _build_husk(rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 113
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.36, 0.23, 0.1))
	ramp.set_color(1, Color(0.82, 0.62, 0.32))
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.96, 0.9)
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(2.0, 7.0, 1.0)   # (streaked along it, like an acorn's)
	mat.metallic = 0.1
	mat.roughness = 0.42
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.78, 0.3)
	mat.emission_energy_multiplier = 0.05
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.rim_enabled = true
	mat.rim = 0.3
	for side in [-1.0, 1.0]:
		var half := MeshInstance3D.new()
		half.name = "Husk"
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.0
		sm.is_hemisphere = true
		sm.radial_segments = 28
		sm.rings = 10
		half.mesh = sm
		half.material_override = mat
		var hold := Node3D.new()
		hold.position = Vector3(side * W * 0.46, 2.0, 1.2 + rng.randf_range(-0.5, 0.5))
		# (its dome down and out, sunk in the Bluff; its open side up and in, toward the knot)
		hold.rotation = Vector3(0.0, rng.randf_range(-0.2, 0.2), -side * deg_to_rad(114.0))
		_root.add_child(hold)
		hold.add_child(half)
		half.scale = Vector3(6.6, 7.8, 6.6)
		_husk.append(hold)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cm := SphereMesh.new()
	cm.radius = 1.0
	cm.height = 1.0
	cm.is_hemisphere = true
	cm.radial_segments = 28
	cm.rings = 8
	cap.mesh = cm
	var cap_mat := mat.duplicate() as StandardMaterial3D
	cap_mat.albedo_color = Color(0.36, 0.26, 0.14)
	cap_mat.metallic = 0.1
	cap_mat.roughness = 0.85
	cap_mat.emission_energy_multiplier = 0.1
	cap.material_override = cap_mat
	var hold := Node3D.new()
	hold.position = Vector3(-3.0, 0.4, D * 0.85)
	hold.rotation = Vector3(deg_to_rad(150.0), 0.6, deg_to_rad(12.0))
	_root.add_child(hold)
	hold.add_child(cap)
	cap.scale = Vector3(8.4, 3.6, 8.4)
	_husk.append(hold)


## Pod `i`: a thorny bud of five sepals shut round its Kernel, at the end of
## its own vine coming out of the knot.
func _build_pod(i: int, rng: RandomNumberGenerator, _bark: ShaderMaterial) -> void:
	var at: Vector3 = POD_AT[i]
	var from: Vector3 = ARM_FROM[i]
	var arm_mat := _vine_mat(1.0, 0.25)
	arm_mat.set_shader_parameter(&"pulse_speed", -5.0)   # (the light running back along it, into the heart)
	var arm := Node3D.new()
	arm.name = "Arm%d" % i
	arm.position = from
	_knot.add_child(arm)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var lift := Vector3.UP * (4.5 if i < 2 else 2.0)
	for k in 21:
		var u := k / 20.0
		var p := (1.0 - u) * (1.0 - u) * from + 2.0 * u * (1.0 - u) * (from.lerp(at, 0.5) + lift) + u * u * at   # (a curve up and over)
		pts.append(p - from)
		radii.append(lerpf(0.95, 0.6, u))
	arm.add_child(_vine(pts, radii, arm_mat))
	arm.add_child(VineMesh.thorn_multimesh(VineMesh.thorns(pts, radii, rng, 1.4, 2, 1.0), 1.0))
	var pod := Node3D.new()
	pod.name = "Pod%d" % i
	pod.position = at - from
	arm.add_child(pod)
	var sepal_mat := StandardMaterial3D.new()
	sepal_mat.albedo_color = Color(0.2, 0.13, 0.2)
	sepal_mat.roughness = 0.6
	sepal_mat.emission_enabled = true
	sepal_mat.emission = Color(0.55, 0.22, 0.75)
	sepal_mat.emission_energy_multiplier = 0.15
	sepal_mat.rim_enabled = true
	sepal_mat.rim = 0.5
	var sepals: Array[Node3D] = []
	var down := Vector3(0.0, -0.35, -0.2).normalized() if i < 2 else Vector3(0.0, 0.3, -1.0).normalized()   # (the way it opens)
	var bud := Basis(IKMath.from_to(Vector3.UP, down))
	for k in 5:
		var hinge := Node3D.new()   # (each sepal swings open from its foot)
		var a := TAU * k / 5.0
		hinge.basis = bud * Basis(Vector3.UP, a)
		hinge.position = -bud.y * POD_R * 0.9
		pod.add_child(hinge)
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		leaf.mesh = sm
		leaf.material_override = sepal_mat
		leaf.scale = Vector3(1.25, POD_R * 1.05, 0.45)
		leaf.position = Vector3(0.0, POD_R * 0.95, POD_R * 0.42)
		var flap := Node3D.new()
		flap.name = "Sepal"
		hinge.add_child(flap)
		flap.add_child(leaf)
		var thorn_at: Array[Transform3D] = []
		for j in 4:
			var tb := Basis(IKMath.from_to(Vector3.UP, Vector3(rng.randf_range(-0.4, 0.4), 0.25, 1.0).normalized()))
			thorn_at.append(Transform3D(tb.scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), Vector3(rng.randf_range(-0.5, 0.5), POD_R * (0.4 + 0.35 * j), POD_R * 0.75)))
		flap.add_child(VineMesh.thorn_multimesh(thorn_at, 1.0))
		sepals.append(flap)
	var k := StarfallKernel.new()
	pod.add_child(k)
	k.scale = Vector3.ONE * 2.6
	var area := Area3D.new()
	area.name = "Hit_pod_%d" % i
	area.collision_layer = Layers.HITBOXES
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta(&"critter", self)
	area.set_meta(&"role", StringName("pod_%d" % i))
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = POD_R * 1.15
	cs.shape = sph
	area.add_child(cs)
	pod.add_child(area)
	hitboxes[StringName("pod_%d" % i)] = area
	hitbox_rids.append(area.get_rid())
	_pods.append({"node": pod, "arm": arm, "arm_mat": arm_mat, "sepals": sepals, "kernel": k, "area": area, "broken": false,
		"open": 0.0, "want": 0.0, "shudder": 0.0, "sway": rng.randf() * TAU})


## Where it's hit (the knot's body, its heart once it's split, the pods: their
## own), and the body critters can't walk through.
func _build_hits() -> void:
	var area := Area3D.new()
	area.name = "Hit_heart"
	area.collision_layer = Layers.HITBOXES
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta(&"critter", self)
	area.set_meta(&"role", &"heart")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W * 0.86, H * 0.82, D * 0.8)
	cs.shape = box
	cs.position = Vector3(0, H * 0.48, 0)
	area.add_child(cs)
	_root.add_child(area)
	hitboxes[&"heart"] = area
	hitbox_rids.append(area.get_rid())
	_core_area = Area3D.new()
	_core_area.name = "Hit_core"
	_core_area.collision_layer = 0
	_core_area.collision_mask = 0
	_core_area.monitoring = false
	_core_area.monitorable = false
	_core_area.set_meta(&"critter", self)
	_core_area.set_meta(&"role", &"core")
	var ccs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.0
	ccs.shape = sph
	_core_area.add_child(ccs)
	_core.add_child(_core_area)
	hitboxes[&"core"] = _core_area
	hitbox_rids.append(_core_area.get_rid())
	var body := AnimatableBody3D.new()
	body.name = "Solid"
	body.sync_to_physics = false
	body.collision_layer = Layers.CRITTERS
	body.collision_mask = 0
	var bcs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = W * 0.4
	cyl.height = H
	bcs.shape = cyl
	bcs.position = Vector3(0, H * 0.5, 0)
	body.add_child(bcs)
	_root.add_child(body)
	_solids.append(body)


## What comes bursting up out of the ground (a Root Burst): a thorny stalk,
## built once.
func _build_stalk(rng: RandomNumberGenerator) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var bend := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
	for k in 9:
		var u := k / 8.0
		pts.append(Vector3.UP * u * 5.5 + (bend - Vector3.UP) * u * u * 2.0 + Vector3.DOWN * 0.8)
		radii.append(lerpf(0.75, 0.12, u))
	_stalk = VineMesh.tube(pts, radii, 7)
	_stalk_mat = _vine_mat(0.0, 0.6)
	var mmi := VineMesh.thorn_multimesh(VineMesh.thorns(pts, radii, rng, 0.9, 2, 0.9), 0.8)
	_stalk_thorns = mmi.multimesh
	_thorn_mesh = mmi.multimesh.mesh
	mmi.free()


func _set_hittable(on: bool) -> void:
	super(on)
	if _core_area:
		_core_area.collision_layer = Layers.HITBOXES if on and split else 0
	for i in _pods.size():
		if _pods[i].broken:
			(_pods[i].area as Area3D).collision_layer = 0


# ---- where it is ------------------------------------------------------------------------------------------

func get_chest_position() -> Vector3:
	if _core and is_inside_tree():
		return _core.global_position
	return global_position + Vector3.UP * CY


## Where to shoot it (the bots aim here): the pod that's open, or its heart
## once it's split; else the top of the knot.
func get_eye_position() -> Vector3:
	if bloom_i >= 0 and is_inside_tree():
		return pod_point(bloom_i)
	if split and _core:
		return _core.global_position
	return to_global(Vector3(0.0, H * 0.72, -D * 0.3)) if is_inside_tree() else global_position + Vector3.UP * H * 0.72


func pod_point(i: int) -> Vector3:
	return (_pods[i].node as Node3D).global_position if i >= 0 and i < _pods.size() else get_chest_position()


func pod_open(i: int) -> bool:
	return i >= 0 and i < _pods.size() and not _pods[i].broken and float(_pods[i].open) > 0.6


func pods_left() -> int:
	return _pods.filter(func(p): return not p.broken).size()


func bone_point(role: StringName, along := 0.0) -> Vector3:
	var s := String(role)
	if s.begins_with("pod_"):
		return pod_point(int(s.get_slice("_", 1)))
	if role == &"core":
		return get_chest_position()
	return global_position + Vector3.UP * lerpf(0.0, H, along)


func mouth_position() -> Vector3:
	return get_eye_position()


func eye_positions() -> Array[Vector3]:
	return []


# ---- every frame ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if state == State.WAITING:
		return
	_tend_bloom(delta)
	_tend_kernels(delta)


## Rooted: it only turns to face whoever it's after, and does what it picks.
func _fight(delta: float) -> void:
	_retarget_t -= delta
	if target == null or not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = RETARGET_EVERY
		target = _pick_target()
	_speed = 0.0
	if target == null:
		return
	face_toward(target.global_position, delta)
	var next := _choose(target)
	if next:
		start(next)
		_rest_until = _clock + next.length + REST * (0.65 if enraged else 1.0)


func _choose(t: Critter) -> BossAction:
	if _clock < _rest_until:
		return null
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	var close := foes_near(global_position, LASH_R - 3.0).size()
	if close > 0 and is_ready(&"lash"):
		return _lash()
	if d > 16.0 and is_ready(&"roots"):
		return _root_burst(t)
	if is_ready(&"volley"):
		return _volley(t)
	return null


## Its heart beats (lub-dub: the knot swells, its light brightens); its pods
## sway on their vines, opening and shutting; the front of the knot swung
## open once it's split.
func _animate(delta: float) -> void:
	if _knot == null:
		return
	var period := BEAT * (0.62 if enraged else 1.0) * (0.5 if not alive else 1.0)
	var was := _beat_t
	_beat_t = fmod(_beat_t + delta / period, 1.0)
	if _beat_t < was and alive and state != State.WAITING and visible:
		_thump()
	var lub := exp(-pow((_beat_t - 0.08) / 0.05, 2.0))
	var dub := exp(-pow((_beat_t - 0.3) / 0.06, 2.0)) * 0.7
	_beat_k = (lub + dub) if alive else 0.0
	if alive:   # (going down, its death has the knot)
		_knot.scale = Vector3.ONE * (1.0 + 0.04 * _beat_k + _swell)   # (evenly: its pods' and heart's hitboxes ride it, and Jolt won't stretch a sphere)
	for m in _mats:
		m.set_shader_parameter(&"glow_base", (0.3 + 0.75 * _beat_k) * (1.0 if alive else 0.0))
	if _core_light and alive:
		_core_light.light_energy = (3.0 if not split else 6.0) * (0.7 + 0.6 * _beat_k)
		_core_mat.emission_energy_multiplier = (3.0 if not split else 7.0) * (0.75 + 0.5 * _beat_k)
	for i in _pods.size():
		var p: Dictionary = _pods[i]
		if p.broken:
			continue
		var want := float(p.want)
		p.open = move_toward(float(p.open), want, delta * (1.6 if want > float(p.open) else 2.4))
		p.shudder = maxf(0.0, float(p.shudder) - delta)
		var shake := sin(_clock * 47.0) * 0.08 * (1.0 if float(p.shudder) > 0.0 else 0.0)
		var open := float(p.open)
		for s in p.sepals:
			(s as Node3D).rotation = Vector3(deg_to_rad(lerpf(-14.0, 72.0, open)) + shake, 0.0, 0.0)
		var arm := p.arm as Node3D
		arm.rotation = Vector3(sin(_clock * 0.9 + float(p.sway)) * 0.035, sin(_clock * 0.6 + float(p.sway)) * 0.05, 0.0)
		(p.kernel as StarfallKernel).scale = Vector3.ONE * lerpf(2.2, 3.0, open)


func _thump() -> void:
	if not is_inside_tree():
		return
	Audio.play_at(&"heart_beat", global_position + Vector3.UP * CY, 2.0 if not enraged else 4.0, 0.0,
		{"max_distance": 600.0, "unit_size": 45.0})
	if _rise >= 1.0 and fmod(_clock, 2.0) < 1.0:
		Events.explosion.emit(global_position + Vector3.UP * 2.0, 3.0)


# ---- its pods ---------------------------------------------------------------------------------------------

## One pod at a time opens, stays open a while (the Heart drinking from it),
## and shuts again.
func _tend_bloom(delta: float) -> void:
	if not alive or state != State.FIGHTING or split:
		return
	if bloom_i >= 0:
		var p: Dictionary = _pods[bloom_i]
		if p.broken:
			bloom_i = -1
			_bloom_t = BLOOM_EVERY[_diff] * 0.6
			return
		if float(p.shudder) <= 0.0 and float(p.want) < 1.0:
			p.want = 1.0
			pod_opened.emit(bloom_i)
			Audio.play_at(&"pod_bloom", pod_point(bloom_i), 6.0, 0.05, {"max_distance": 400.0, "unit_size": 25.0})
			(p.kernel as StarfallKernel).pulse(1.0)
		if float(p.want) >= 1.0:
			_bloom_left -= delta
			_drink_t -= delta
			if _drink_t <= 0.0:
				_drink_t = 0.22
				_drink(bloom_i)
			if _bloom_left <= 0.0:
				p.want = 0.0
				bloom_i = -1
				_bloom_t = BLOOM_EVERY[_diff]
		return
	_bloom_t -= delta
	if _bloom_t > 0.0:
		return
	for k in PODS:
		var i := (_next_pod + k) % PODS
		if not _pods[i].broken:
			_next_pod = (i + 1) % PODS
			bloom_i = i
			_bloom_left = BLOOM_FOR[_diff]
			_pods[i].shudder = SHUDDER
			return


## The Heart drinking from an open pod: the Kernel's light running down its
## vine into the knot.
func _drink(i: int) -> void:
	var from := pod_point(i)
	FX.burst(from, (get_chest_position() - from).normalized(), {"amount": 4, "lifetime": 0.9, "speed": Vector2(6.0, 10.0),
		"spread": 12.0, "gravity": 0.0, "size": 0.35, "scale": Vector2(0.6, 1.5), "color": Color(GLOW, 0.8), "fade": true,
		"additive": true, "damping": 0.5, "aabb": 30.0})


## Pod `i` broken: its sepals fly off, its Kernel goes up out of it, free, to
## hang over the Bluff, and its vine withers; the Heart reels.
func _break_pod(i: int, by: Node) -> void:
	var p: Dictionary = _pods[i]
	if p.broken:
		return
	p.broken = true
	p.want = 0.0
	pod_hp[i] = 0.0
	(p.area as Area3D).collision_layer = 0
	if bloom_i == i:
		bloom_i = -1
		_bloom_t = BLOOM_EVERY[_diff] * 0.6
	var at := pod_point(i)
	Audio.play_at(&"root_snap", at, 10.0, 0.0, {"max_distance": 700.0, "unit_size": 40.0})
	FX.burst(at, Vector3.UP, {"amount": 70, "lifetime": 2.4, "speed": Vector2(3.0, 12.0), "spread": 170.0, "gravity": -0.4,
		"size": 0.5, "scale": Vector2(0.6, 1.5), "color": Color(GLOW, 0.95), "fade": true, "additive": true, "damping": 1.3, "aabb": 40.0})
	BossFX.chips(at, 2.6, Color(0.24, 0.15, 0.22))
	Events.explosion.emit(at, 12.0)
	for s in p.sepals:
		var flap := s as Node3D
		var tw := flap.create_tween()
		var fling := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)).normalized() * randf_range(6.0, 11.0)
		tw.tween_property(flap, "position", flap.position + flap.get_parent().global_basis.inverse() * fling, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(flap, "scale", Vector3.ONE * 0.05, 0.9).set_delay(0.3)
		tw.tween_callback(flap.queue_free)
	# the Kernel, free: up out of it, and over the Bluff with the others
	var k := p.kernel as StarfallKernel
	var world := get_parent()
	var from := k.global_position
	k.get_parent().remove_child(k)
	world.add_child(k)
	k.global_position = from
	k.scale = Vector3.ONE * 2.2
	k.pulse(1.0)
	kernels.append(k)
	(p.arm_mat as ShaderMaterial).set_shader_parameter(&"alive", 0.15)
	var arm := p.arm as Node3D
	var droop := arm.create_tween()
	droop.tween_property(arm, "rotation:x", 0.22, 1.2)
	pod_broken.emit(i)
	if pods_left() == 0:
		_split_open()
	else:
		stun(2.4, {}, 1.5)
		Events.announce.emit("A KERNEL'S FREE!", "%d to go. It's reeling: hit it!" % pods_left())
	if by is Critter and (by as Critter).is_player:
		Events.player_hit_confirmed.emit(self, 0.0, true, false)


## The freed Kernels go up over the Bluff and hang there, turning round each other.
func _tend_kernels(delta: float) -> void:
	if kernels.is_empty() or not is_inside_tree():
		return
	_gather = global_position + Vector3.UP * (H + 13.0)
	for j in kernels.size():
		var k := kernels[j]
		if not is_instance_valid(k):
			continue
		var a := _clock * 0.7 + TAU * j / 3.0
		var want := _gather + Vector3(cos(a), 0.15 * sin(a * 2.0), sin(a)) * 4.0
		k.global_position = k.global_position.lerp(want, clampf(delta * 1.2, 0.0, 1.0))


## Its last Kernel's out: it splits open down the front, and there's the
## light at its heart. Enraged: faster, and the rest of it hits harder.
func _split_open() -> void:
	split = true
	bloom_i = -1
	_cancel_action()
	if _core_area:
		_core_area.collision_layer = Layers.HITBOXES
	var tw := create_tween()
	tw.tween_property(_hinge_l, "rotation:y", deg_to_rad(-58.0), 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_hinge_r, "rotation:y", deg_to_rad(58.0), 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_core, "position", Vector3(0.0, CY, -D * 0.62), 1.3).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_core, "scale", Vector3.ONE * 1.15, 1.3)
	Audio.play_at(&"briar_groan", global_position + Vector3.UP * CY, 12.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
	BossFX.chips(get_chest_position(), 3.0, Color(0.24, 0.15, 0.22))
	opened.emit()
	enraged = true
	enraged_now.emit()
	Events.announce.emit("THE BRIAR HEART IS SPLIT OPEN!", "Its heart's out. Hit the light!")
	var roar := _roar_action()
	if roar:
		start(roar)


# ---- getting hurt ---------------------------------------------------------------------------------------

## What a hit on `role` counts for (by what it is: a pod, open or shut; its
## knot; its heart).
func part_scale(role: StringName, blast := false) -> float:
	var s := String(role)
	if s.begins_with("pod_"):
		var i := int(s.get_slice("_", 1))
		return POD_OPEN if pod_open(i) else (POD_SHUT_BLAST if blast else POD_SHUT)
	if role == &"core":
		return CORE if split else BODY
	return BODY_OPEN if split else BODY


func take_damage(info: DamageInfo) -> void:
	if not alive or state == State.WAITING:
		return
	var by := info.attacker as Critter
	if by and by.team == team:
		return
	var role := info.bone_role
	var pod := int(String(role).get_slice("_", 1)) if String(role).begins_with("pod_") else -1
	if pod >= 0 and _pods[pod].broken:
		role = &"heart"
		pod = -1
	var amount := info.amount * armor * part_scale(role, info.kind == DamageInfo.Kind.EXPLOSION)
	info.headshot = (pod >= 0 and pod_open(pod)) or (role == &"core" and split)
	if _clock < vulnerable_until:
		amount *= vulnerable_k
	if by and not by.is_player:
		amount *= BOT_DAMAGE
	info.amount = amount
	var before := health
	if pod >= 0:
		pod_hp[pod] = maxf(0.0, pod_hp[pod] - amount)
	else:
		core_hp = maxf(core_max * CORE_FLOOR if not split else 0.0, core_hp - amount)
	health = core_hp
	for v in pod_hp:
		health += v
	last_hit_pos = info.position if info.position != Vector3.ZERO else get_chest_position()
	if by:
		_threat[by] = float(_threat.get(by, 0.0)) + amount * (2.0 if by.is_player else 1.0)
		by.damage_dealt += amount
	_hit_fx(info)
	if by and by.is_player:
		Events.player_hit_confirmed.emit(self, amount, info.headshot, health <= 0.0)
		StatBook.note_hit(info.weapon_id, amount, info.headshot, info.kind == DamageInfo.Kind.EXPLOSION)
		StatBook.note_boss_damage(id, before - health)
	health_changed.emit(health, max_health)
	if pod >= 0 and pod_hp[pod] <= 0.0:
		_break_pod(pod, info.attacker)
	if health <= 0.0:
		_die(info)


## A blast (Explosion): a pod caught in it takes it (shut, it's not much
## safer than open), else the knot, where the blast meets it.
func receive_blast(pos: Vector3, radius: float, damage: float, shooter: Node, weapon_id: StringName) -> void:
	var best_role := &""
	var best := INF
	for i in _pods.size():
		if _pods[i].broken:
			continue
		var d := maxf(0.0, pos.distance_to(pod_point(i)) - POD_R)
		if d < best:
			best = d
			best_role = StringName("pod_%d" % i)
	var middle := get_chest_position()
	var local := global_transform.affine_inverse() * pos
	var knot_d := maxf(0.0, Vector3(local.x / (W * 0.5), (local.y - H * 0.5) / (H * 0.5), local.z / (D * 0.5)).length() - 1.0) * W * 0.5
	if split and pos.distance_to(_core.global_position) - 3.0 < knot_d:
		knot_d = maxf(0.0, pos.distance_to(_core.global_position) - 3.0)
		if knot_d < best:
			best = knot_d
			best_role = &"core"
	if knot_d < best:
		best = knot_d
		best_role = &"heart"
	if best > radius or best_role == &"":
		return
	var info := DamageInfo.make(damage * pow(1.0 - best / radius, 0.8), DamageInfo.Kind.EXPLOSION, shooter, weapon_id)
	info.position = pos
	info.direction = (middle - pos).normalized()
	info.bone_role = best_role
	take_damage(info)


func _hit_fx(info: DamageInfo) -> void:
	var k := clampf(info.amount / 30.0, 0.3, 1.0)
	if info.headshot:
		FX.burst(last_hit_pos, -info.direction, {"amount": 8, "lifetime": 0.8, "speed": Vector2(2.0, 5.0), "spread": 60.0,
			"gravity": 0.5, "size": 0.18, "scale": Vector2(0.6, 1.3), "color": Color(GLOW, 0.9), "fade": true, "additive": true, "damping": 2.0})
	else:
		BossFX.chips(last_hit_pos, 0.35 + 0.4 * k, Color(0.26, 0.16, 0.24))
	FX.blood_hit(last_hit_pos, -info.direction, k * 0.6, SAP)


## A sound of its (`pitch` 1: a little jitter; else just that).
func _sound(key: StringName, at: Vector3, db: float, pitch := 1.0, reach := 600.0, unit := 40.0) -> void:
	var s := Audio.play_at(key, at, db, 0.05 if pitch == 1.0 else 0.0, {"max_distance": reach, "unit_size": unit})
	if s and pitch != 1.0:
		s.pitch_scale = pitch


func enrage_line() -> String:
	return "Split open: its heart's out. Hit the light!"


func attack_name(what: StringName) -> String:
	return {&"thorns": "Thorn Volley", &"roots": "Root Burst", &"lash": "Lash", &"landing": "the Briar Heart rising",
		&"groan": "Groan"}.get(what, super(what))


# ---- Thorn Volley -----------------------------------------------------------------------------------------

func _volley(t: Critter) -> BossAction:
	cooldown(&"volley", 6.5)
	var n := 7 if enraged else 5
	var a := BossAction.new(&"volley", 2.4)
	a.on(0.0, func():
		Audio.play_at(&"thorn_volley", get_eye_position(), 6.0, 0.05, {"max_distance": 500.0, "unit_size": 35.0})
		BossFX.chips(to_global(Vector3(0, H * 0.9, 0)), 1.6, Color(0.26, 0.16, 0.24)))
	a.on(0.75, func():
		var aim := t.global_position if is_instance_valid(t) and t.alive else global_position + forward() * 30.0
		var lead := t.velocity * 1.2 if is_instance_valid(t) else Vector3.ZERO
		for i in n:
			var at := aim + Vector3(lead.x, 0.0, lead.z) * (0.5 if i == 0 else 1.0)
			if i > 0:
				at += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(4.0, 11.0)
			_thorn(at, 1.35 + 0.12 * i))
	return a


## One thorn, flung high from the top of the knot, coming down point first at `at`.
func _thorn(at: Vector3, flight: float) -> void:
	at.y = ground_y(at)
	warn(at, THORN_R, flight)
	var from := to_global(Vector3(randf_range(-4, 4), H * 0.95, randf_range(-2, 2)))
	var spike := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.45
	cone.height = 3.6
	cone.radial_segments = 6
	spike.mesh = cone
	spike.material_override = VineMesh.thorn_material()
	spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(spike)
	spike.global_position = from
	var arc := func(u: float):
		if not is_instance_valid(spike):
			return
		var p := from.lerp(at, u) + Vector3.UP * sin(u * PI) * 26.0
		var ahead := from.lerp(at, minf(u + 0.02, 1.0)) + Vector3.UP * sin(minf(u + 0.02, 1.0) * PI) * 26.0
		spike.global_position = p
		if ahead.distance_to(p) > 0.001:
			spike.basis = Basis(IKMath.from_to(Vector3.DOWN, (ahead - p).normalized()))
	var tw := spike.create_tween()
	tw.tween_method(arc, 0.0, 1.0, flight)
	tw.tween_callback(func():
		hurt_ring(at, THORN_R, 30.0, 12.0, 7.0, 5.0, &"thorns", false)
		BossFX.dust(at, 4.0, Color(0.32, 0.26, 0.24, 0.7))
		BossFX.chips(at, 0.9, Color(0.3, 0.22, 0.2))
		Audio.play_at(&"carrot_impact_wood", at, 2.0, 0.1, {"max_distance": 200.0})
		spike.global_position = at + Vector3.UP * 0.9)   # (stuck in the ground, point first)
	tw.tween_interval(5.0)
	tw.tween_property(spike, "global_position:y", at.y - 2.6, 1.2)
	tw.tween_callback(spike.queue_free)


# ---- Root Burst -------------------------------------------------------------------------------------------

func _root_burst(t: Critter) -> BossAction:
	cooldown(&"roots", 9.0)
	var dir := t.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else forward()
	var from := global_position + dir * (W * 0.45)
	var reach := clampf(Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length() + 10.0, 14.0, 62.0)
	var to := from + dir * reach
	var wind := 1.3
	var a := BossAction.new(&"roots", wind + 1.6)
	var thrown := {}
	a.on(0.0, func():
		warn_strip(from, to, ROOT_W, wind)
		Audio.play_at(&"root_burst", from, 4.0, 0.05, {"max_distance": 500.0, "unit_size": 35.0}))
	var n := maxi(4, int(reach / 3.2))
	for k in n:
		var u := (k + 0.5) / n
		var at := from.lerp(to, u)
		a.on(wind + 0.4 * u, func():
			var spot := Vector3(at.x, ground_y(at), at.z)
			_stalks(spot, 2 if k % 2 == 0 else 3)
			if k % 3 == 0:
				Events.explosion.emit(spot, 5.0)
			for c in foes_near(spot, ROOT_W * 0.7):
				if not thrown.has(c):
					thrown[c] = true
					hurt(c, 34.0, dir, 5.0, 11.0, &"roots"))
	return a


## A few thorny stalks bursting up out of the ground at `at`, and back down.
func _stalks(at: Vector3, count: int) -> void:
	BossFX.dust(at, 3.5, Color(0.32, 0.26, 0.24, 0.75))
	for i in count:
		var s := Node3D.new()
		get_parent().add_child(s)
		s.global_position = at + Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-1.6, 1.6))
		s.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		var mi := MeshInstance3D.new()
		mi.mesh = _stalk
		mi.material_override = _stalk_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(mi)
		var th := MultiMeshInstance3D.new()
		th.multimesh = _stalk_thorns
		th.material_override = VineMesh.thorn_material()
		th.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.add_child(th)
		s.scale = Vector3(1.0, 0.05, 1.0) * randf_range(0.8, 1.3)
		var k := s.scale.x
		var tw := s.create_tween()
		tw.tween_property(s, "scale", Vector3.ONE * k, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.1 + randf() * 0.4)
		tw.tween_property(s, "scale", Vector3(k, 0.02, k), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(s.queue_free)


# ---- Lash -------------------------------------------------------------------------------------------------

## A vine sweeping right round its foot: anyone in the ring is thrown out of
## it (unless they jumped it).
func _lash() -> BossAction:
	cooldown(&"lash", 8.0)
	var wind := 1.3
	var a := BossAction.new(&"lash", wind + 0.9)
	var whip := {"node": null}
	a.on(0.0, func():
		warn(global_position, LASH_R, wind)
		_sound(&"briar_groan", global_position + Vector3.UP * 4.0, 2.0, 1.5, 400.0, 30.0))
	a.on(wind - 0.1, func():
		whip["node"] = _whip()
		_sound(&"thorn_volley", global_position + Vector3.UP * 2.0, 6.0, 0.7, 400.0, 35.0))
	a.on(wind, func():
		hurt_ring(global_position, LASH_R, 40.0, 22.0, 17.0, 7.0, &"lash", true)
		BossFX.shockwave(global_position, LASH_R, Color(0.36, 0.22, 0.4, 0.6))
		Events.explosion.emit(global_position, 16.0))
	a.tick = func(time: float, _delta: float):
		var w = whip["node"]
		if w != null and is_instance_valid(w):
			(w as Node3D).rotation.y = clampf((time - wind + 0.1) / 0.55, 0.0, 1.0) * TAU * 1.1
	a.on(wind + 0.8, func():
		var w = whip["node"]
		if w != null and is_instance_valid(w):
			(w as Node3D).queue_free()
		whip["node"] = null)
	a.data["cancel"] = func():
		var w = whip["node"]
		if w != null and is_instance_valid(w):
			(w as Node3D).queue_free()
		whip["node"] = null
	return a


## The vine it lashes with: from its foot out to the edge of the ring, low
## over the ground, turning round it like a clock's hand.
func _whip() -> Node3D:
	var hold := Node3D.new()
	add_child(hold)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for k in 17:
		var u := k / 16.0
		pts.append(Vector3(lerpf(W * 0.35, LASH_R, u), 1.2 + sin(u * PI) * 0.8, -sin(u * PI * 1.3) * 3.0))
		radii.append(lerpf(1.0, 0.25, u))
	var mi := MeshInstance3D.new()
	mi.mesh = VineMesh.tube(pts, radii, 8)
	mi.material_override = _stalk_mat
	hold.add_child(mi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	hold.add_child(VineMesh.thorn_multimesh(VineMesh.thorns(pts, radii, rng, 1.2, 2, 1.0), 1.0))
	return hold


# ---- its groan, rising, going down ---------------------------------------------------------------------

## Its groan (as it rises, and split open): a huge double beat, the knot
## swelling, everyone near blown back (but not for the camera: show_off).
func _roar_action() -> BossAction:
	var a := BossAction.new(&"groan", 2.2)
	a.on(0.2, func():
		Audio.play_at(&"briar_groan", global_position + Vector3.UP * CY, 14.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
		_beat_t = 0.0
		hurt_ring(global_position, 30.0, 10.0, 4.0, 12.0, 6.0, &"groan", false)
		Events.explosion.emit(global_position + Vector3.UP * CY, 26.0)
		BossFX.dust(global_position, 26.0, Color(0.3, 0.24, 0.26, 0.6)))
	a.tick = func(time: float, _delta: float):
		_swell = 0.07 * sin(clampf(time / 1.6, 0.0, 1.0) * PI)
	return a


## It rises up out of Boulder Bluff, the husk and all, shaking the ground.
func _entrance() -> BossAction:
	var a := BossAction.new(&"entrance", land_time + 1.2)
	a.interruptible = false
	_rise = 0.0
	_root.position.y = -(H + 4.0)
	for p in _pods:
		(p.arm as Node3D).scale = Vector3.ONE * 0.2
	a.on(0.0, func(): warn(global_position, 20.0, land_time))
	a.tick = func(time: float, _delta: float):
		var u := clampf(time / land_time, 0.0, 1.0)
		_rise = u
		_root.position.y = -(H + 4.0) * (1.0 - u * u * (3.0 - 2.0 * u))
		if time < land_time and randf() < 0.35:
			BossFX.dust(global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)), 9.0, Color(0.34, 0.28, 0.24, 0.7))
		if time > land_time:
			var k := clampf((time - land_time) / 1.0, 0.0, 1.0)
			for p in _pods:
				(p.arm as Node3D).scale = Vector3.ONE * lerpf(0.2, 1.0, k * k * (3.0 - 2.0 * k))
	a.on(land_time, func():
		_root.position.y = 0.0
		_rise = 1.0
		hurt_ring(global_position, 20.0, 40.0, 10.0, 14.0, 10.0, &"landing")
		BossFX.shockwave(global_position, 26.0, Color(0.34, 0.28, 0.24, 0.7))
		BossFX.chips(global_position + Vector3.UP * 2.0, 3.0, Color(0.4, 0.34, 0.3))
		Events.explosion.emit(global_position, 22.0)
		Audio.play_at(&"root_burst", global_position, 12.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
		Audio.play_at(&"boss_stomp", global_position, 4.0, 0.0, {"max_distance": 700.0, "unit_size": 40.0}))
	a.data["cancel"] = func():
		_root.position.y = 0.0
		_rise = 1.0
		for p in _pods:
			(p.arm as Node3D).scale = Vector3.ONE
	return a


func _after_entrance() -> void:
	_root.position.y = 0.0
	_rise = 1.0
	for p in _pods:
		(p.arm as Node3D).scale = Vector3.ONE
	_bloom_t = 3.0


## It goes down: its beat races, it convulses, the light goes out of it, and
## what's left sags, grey, in the husk.
func _death_action() -> BossAction:
	bloom_i = -1
	var a := BossAction.new(&"death", 4.2)
	a.blend_out = 0.0
	a.interruptible = false
	a.tick = func(time: float, _delta: float):
		if time < 2.2:
			_knot.scale = Vector3.ONE * (1.0 + sin(time * (8.0 + time * 10.0)) * 0.05 * (1.0 - time / 2.2))
		else:
			var u := clampf((time - 2.2) / 1.8, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			_knot.scale = Vector3.ONE * lerpf(1.0, 0.94, e)   # (it sags, and leans: evenly, as the beat)
			_knot.position.y = lerpf(0.0, -1.6, e)
			_knot.rotation.z = lerpf(0.0, 0.08, e)
			for m in _mats:
				m.set_shader_parameter(&"alive", 1.0 - e * 0.85)
			if _core_light:
				_core_light.light_energy = 8.0 * (1.0 - e)
				_core_mat.emission_energy_multiplier = 7.0 * (1.0 - e) + 0.05
				_core_mat.albedo_color = GLOW.lerp(Color(0.22, 0.2, 0.18), e)   # (its light going out, grey like the rest of it)
				_core.scale = Vector3.ONE * lerpf(1.15 if split else 1.0, 0.3, e)
	a.on(0.1, func(): _sound(&"briar_groan", global_position + Vector3.UP * CY, 14.0, 0.8, 900.0, 60.0))
	a.on(2.2, func():
		var at := get_chest_position()
		FX.burst(at, Vector3.UP, {"amount": 90, "lifetime": 2.8, "speed": Vector2(4.0, 16.0), "spread": 180.0, "gravity": -0.3,
			"size": 0.6, "scale": Vector2(0.6, 1.5), "color": Color(GLOW, 0.95), "fade": true, "additive": true, "damping": 1.2, "aabb": 50.0})
		BossFX.shockwave(global_position, 30.0, Color(0.34, 0.28, 0.24, 0.7))
		Events.explosion.emit(at, 24.0)
		Audio.play_at(&"explosion", at, 6.0, 0.05, {"max_distance": 800.0, "unit_size": 50.0}))
	a.length = 4.2
	return a


func _action_done(a: BossAction) -> void:
	if a.name == &"death":
		set_physics_process(false)
		_fallen()
		return
	if state == State.ARRIVING:
		state = State.FIGHTING
		_after_entrance()


func _fallen() -> void:
	for m in _mats:
		m.set_shader_parameter(&"alive", 0.15)
		m.set_shader_parameter(&"glow_base", 0.0)
	if _core_mat:
		_core_mat.albedo_color = Color(0.22, 0.2, 0.18)
		_core.scale = Vector3.ONE * 0.3
		_core_light.light_energy = 0.0


## Crumbling into the ground (the ending: StarfallOutro), over `seconds`.
func crumble(seconds := 4.0) -> void:
	var tw := create_tween()
	tw.tween_property(_knot, "position:y", -H - 3.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_knot, "scale", Vector3.ONE * 0.7, seconds)
	for p in _pods:
		tw.parallel().tween_property(p.arm, "scale", Vector3.ONE * 0.05, seconds * 0.6)


## The husk's pieces (two halves and the cap), for the ending to put back together.
func husk() -> Array[Node3D]:
	return _husk


# ---- rewind (TimeKeeper) ---------------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var s := super()
	s["pods"] = pod_hp.duplicate()
	s["core"] = core_hp
	return s


func restore(s: Dictionary) -> void:
	super(s)
	if not alive:
		return
	var pods: Array = s.get("pods", [])
	for i in mini(pods.size(), pod_hp.size()):
		if not _pods[i].broken:   # (a pod that's broken stays broken: its Kernel's out)
			pod_hp[i] = maxf(1.0, float(pods[i]))
	core_hp = maxf(1.0, float(s.get("core", core_hp)))
	health = core_hp
	for v in pod_hp:
		health += v
	health_changed.emit(health, max_health)
	bloom_i = -1
	for p in _pods:
		p.want = 0.0
