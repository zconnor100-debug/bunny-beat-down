class_name WindKey
extends Node3D
## A wind-up key, brass, turning (the Kernel Hunt's Act II, ClockworkMission):
## what the Tin Tyrant puts in the back of every critter he winds (the Wound),
## and, much bigger, on top of each of his winding stations (WindingStation).
## Its shaft sticks out along +Z from where it's fixed, and its bow (two loops)
## turns round the shaft at `speed` degrees a second. `fit` puts one in a
## critter's back, between its shoulders.

const BRASS := Color(0.86, 0.66, 0.3)

var speed := 300.0             ## degrees a second it turns
var _bow: Node3D
var _t := 0.0


## `size`: metres from the shaft's root to the far edge of the bow.
func _init(size := 1.0) -> void:
	name = "WindKey"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BRASS
	mat.metallic = 0.85
	mat.roughness = 0.32
	mat.rim_enabled = true
	mat.rim = 0.3
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07 * size
	cyl.bottom_radius = 0.07 * size
	cyl.height = 0.42 * size
	cyl.radial_segments = 10
	cyl.rings = 1
	shaft.mesh = cyl
	shaft.rotation.x = PI * 0.5
	shaft.position.z = 0.21 * size
	shaft.material_override = mat
	add_child(shaft)
	var collar := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.13 * size
	disc.bottom_radius = 0.15 * size
	disc.height = 0.06 * size
	disc.radial_segments = 14
	disc.rings = 1
	collar.mesh = disc
	collar.rotation.x = PI * 0.5
	collar.position.z = 0.03 * size
	collar.material_override = mat
	add_child(collar)
	_bow = Node3D.new()
	_bow.position.z = 0.5 * size
	add_child(_bow)
	var hub := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.1 * size
	ball.height = 0.2 * size
	ball.radial_segments = 10
	ball.rings = 6
	hub.mesh = ball
	hub.scale = Vector3(0.7, 1.0, 1.0)
	hub.material_override = mat
	_bow.add_child(hub)
	for ys in [-1.0, 1.0]:
		# a loop either side of the shaft, in the plane the shaft's in (turned
		# a little apart, like a butterfly's wings)
		var loop := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.13 * size
		torus.outer_radius = 0.22 * size
		torus.rings = 18
		torus.ring_segments = 8
		loop.mesh = torus
		loop.rotation = Vector3(0.0, 0.0, PI * 0.5)
		loop.scale = Vector3(1.0, 0.55, 1.0)   # (flatter across: a pressed loop of brass)
		loop.position = Vector3(0.0, ys * 0.27 * size, 0.06 * size)
		loop.material_override = mat
		_bow.add_child(loop)
	for mi in ModelUtil.find_all(self, "MeshInstance3D"):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _process(delta: float) -> void:
	_t += delta
	_bow.rotation.z += deg_to_rad(speed) * delta


## How far round it's turned (radians: the stations' arms follow it).
func turned() -> float:
	return _bow.rotation.z


## A key in `c`'s back, between its shoulders (on its chest bone, so it goes
## where the body goes, ragdoll and all), sized to it. Null if it has no chest.
static func fit(c: Critter) -> WindKey:
	var v := c.visual
	if v == null or v.rig == null or not v.attachments.has(&"chest"):
		return null
	var f := OutfitFit.of(v)
	var att: BoneAttachment3D = v.attachments[&"chest"]
	var y := lerpf(f.chest_y, f.shoulder_y, 0.35)
	var back := f.back_at(y)
	var key := WindKey.new(maxf(f.chest_w, 0.05) * 1.25)
	# (the model faces +Z: its back is -Z, and the key's shaft sticks out along its own +Z)
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, y, back + f.chest_w * 0.06))
	key.transform = (v.rig.rest[&"chest"] as Transform3D).affine_inverse() * xf
	att.add_child(key)
	return key
