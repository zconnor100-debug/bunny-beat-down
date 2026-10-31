class_name WarrenFlag
extends Node3D
## The Warren's flag (the Kernel Hunt's Act II, ClockworkMission): a tall
## pole with a pennant, acorn-brown with a gold-green acorn on it, run up over
## Block Castle once the courtyard's taken (`raise`), flapping.

const POLE := 26.0             ## metres tall (over the castle's towers)
const CLOTH := Color(0.55, 0.33, 0.16)
const MARK := Color(0.8, 1.0, 0.34)
const FLAP := preload("res://src/quest/warren_flag.gdshader")

var _cloth: MeshInstance3D
var _t := 0.0


func _init() -> void:
	name = "WarrenFlag"


func _ready() -> void:
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.3
	cyl.height = POLE
	cyl.radial_segments = 10
	pole.mesh = cyl
	pole.position.y = POLE * 0.5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.18)
	wood.roughness = 0.8
	pole.material_override = wood
	add_child(pole)
	var knob := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.55
	ball.height = 1.1
	knob.mesh = ball
	knob.position.y = POLE + 0.3
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.78, 0.3)
	gold.metallic = 0.7
	gold.roughness = 0.3
	knob.material_override = gold
	add_child(knob)
	_cloth = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11.0, 7.0)
	plane.subdivide_width = 16
	plane.subdivide_depth = 8
	plane.orientation = PlaneMesh.FACE_Z
	_cloth.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = FLAP
	mat.set_shader_parameter(&"cloth", CLOTH)
	mat.set_shader_parameter(&"mark", MARK)
	_cloth.material_override = mat
	_cloth.position = Vector3(5.6, 0.0, 0.0)   # (its near edge on the pole)
	add_child(_cloth)
	_cloth.position.y = 4.0


## Up it goes, over a few seconds.
func raise(seconds := 3.0) -> void:
	var tw := create_tween()
	tw.tween_property(_cloth, "position:y", POLE - 3.8, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Audio.play_at(&"victory_fanfare", global_position + Vector3.UP * 6.0, -4.0, 0.0, {"max_distance": 400.0, "unit_size": 25.0})
