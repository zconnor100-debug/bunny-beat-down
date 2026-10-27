class_name ThrowArc
extends Node3D
## The carrot grenade's aiming arc, while the throw button's held: dots along
## the lob to where it first comes down, a marker there, and a faint ring as
## wide as the blast. Drawn over everything, so it reads behind cover too.

const DOT_EVERY := 0.45           ## metres between dots along the arc
const MAX_DOTS := 64
const COLOR := Color(1.0, 0.66, 0.25, 0.95)

var _dots: MultiMeshInstance3D
var _mark: MeshInstance3D
var _blast: MeshInstance3D


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = COLOR
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	dot.radial_segments = 8
	dot.rings = 4
	dot.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = MAX_DOTS
	mm.visible_instance_count = 0
	_dots = MultiMeshInstance3D.new()
	_dots.multimesh = mm
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)
	_mark = _ring(0.3, 0.55, mat)
	var faint := mat.duplicate() as StandardMaterial3D
	faint.albedo_color = Color(COLOR, 0.4)
	_blast = _ring(0.95, 1.0, faint)
	visible = false


func _ring(inner: float, outer: float, mat: Material) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 48
	t.ring_segments = 6
	t.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Shows the arc through `pts` (Grenade.arc), the blast `radius` round its end.
func show_arc(pts: PackedVector3Array, radius: float) -> void:
	visible = true
	global_transform = Transform3D.IDENTITY
	var mm := _dots.multimesh
	var n := 0
	var until := 1.2   # (none right by the paw: they'd blot out the face, or the view in first person)
	var run := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		while run + seg >= until and n < MAX_DOTS:
			mm.set_instance_transform(n, Transform3D(Basis(), a.lerp(b, (until - run) / maxf(seg, 0.0001))))
			n += 1
			until += DOT_EVERY
		run += seg
	mm.visible_instance_count = n
	var end := pts[pts.size() - 1]
	_mark.global_position = end + Vector3.UP * 0.05
	_blast.global_position = end + Vector3.UP * 0.05
	_blast.scale = Vector3(radius, 1.0, radius)


func hide_arc() -> void:
	visible = false
