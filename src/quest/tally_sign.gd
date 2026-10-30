class_name TallySign
extends Node3D
## The tally on the Big Red Barn's door (BossLore: Brutus, "Nine Days"): a
## chalkboard hung on the open door, DAYS SINCE BRUTUS, the days chalked up
## as tally marks and a number. It has never got past nine. `wipe_to` rubs
## the count out and chalks a new one (the Kernel Hunt's prologue ends with
## it back at zero: MissionOutro). Faces +Z.

const SIZE := Vector2(2.3, 1.6)
const SMUDGE := preload("res://src/quest/chalk_smudge.gdshader")
const CHALK := Color(0.93, 0.95, 0.9)
const RED_CHALK := Color(1.0, 0.52, 0.46)

var count := 9
var _board: MeshInstance3D
var _number: Label3D
var _marks: Node3D
var _smudge: MeshInstance3D


func _init(days := 9) -> void:
	count = days
	name = "TallySign"


func _ready() -> void:
	_board = MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(SIZE.x, SIZE.y, 0.07)
	_board.mesh = slab
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color(0.13, 0.19, 0.16)
	slate.roughness = 0.95
	_board.material_override = slate
	add_child(_board)
	# a plank frame round it
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.17)
	wood.roughness = 0.9
	for side in [[Vector3(0, SIZE.y * 0.5 + 0.05, 0.01), Vector3(SIZE.x + 0.2, 0.12, 0.1)],
			[Vector3(0, -SIZE.y * 0.5 - 0.05, 0.01), Vector3(SIZE.x + 0.2, 0.12, 0.1)],
			[Vector3(SIZE.x * 0.5 + 0.05, 0, 0.01), Vector3(0.12, SIZE.y, 0.1)],
			[Vector3(-SIZE.x * 0.5 - 0.05, 0, 0.01), Vector3(0.12, SIZE.y, 0.1)]]:
		var f := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = side[1]
		f.mesh = b
		f.material_override = wood
		f.position = side[0]
		add_child(f)
	_label("DAYS SINCE", Vector3(-0.32, 0.5, 0.045), 46, CHALK)
	_label("BRUTUS", Vector3(-0.32, 0.17, 0.045), 74, RED_CHALK)
	_number = _label(str(count), Vector3(0.72, -0.28, 0.045), 190, CHALK)
	_marks = Node3D.new()
	_marks.position = Vector3(-0.62, -0.36, 0.045)
	add_child(_marks)
	_chalk_marks(count)
	# the rubbed-out smear a wipe leaves (unseen till then)
	_smudge = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(SIZE.x * 0.95, SIZE.y * 0.62)
	_smudge.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = SMUDGE
	sm.set_shader_parameter(&"amount", 0.0)   # (set, so a tween has somewhere to start)
	_smudge.material_override = sm
	_smudge.position = Vector3(0.0, -0.3, 0.04)
	add_child(_smudge)


func _label(text: String, at: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.title_font()
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = at
	add_child(l)
	return l


## `n` days as chalk tally marks: fours struck through by a fifth.
func _chalk_marks(n: int) -> void:
	for c in _marks.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CHALK
	mat.roughness = 1.0
	for i in mini(n, 10):
		var group := i / 5
		var k := i % 5
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.045, 0.5, 0.01)
		bar.mesh = b
		bar.material_override = mat
		var x := group * 0.62 + k * 0.11
		if k == 4:   # (the fifth strikes the four through)
			bar.mesh = b.duplicate()
			(bar.mesh as BoxMesh).size = Vector3(0.045, 0.62, 0.01)
			bar.position = Vector3(group * 0.62 + 0.165, 0.0, 0.004)
			bar.rotation.z = deg_to_rad(-62.0)
		else:
			bar.position = Vector3(x, 0.0, 0.0)
			bar.rotation.z = deg_to_rad(randf_range(-4.0, 4.0))
		_marks.add_child(bar)


## Rub the count out and chalk up `n` instead, over `seconds`: the marks and
## the number smeared away, a pale smudge left behind, the new number chalked
## on. Returns the tween (to wait on).
func wipe_to(n: int, seconds := 2.4) -> Tween:
	count = n
	var tw := create_tween().set_ignore_time_scale(true)
	var smear := seconds * 0.45
	tw.tween_property(_number, "modulate:a", 0.0, smear)
	tw.parallel().tween_property(_number, "scale", Vector3(1.6, 0.85, 1.0), smear)
	tw.parallel().tween_property(_marks, "scale", Vector3(1.5, 0.05, 1.0), smear)   # (rubbed flat)
	tw.parallel().tween_property(_smudge.material_override, "shader_parameter/amount", 1.0, smear)
	tw.tween_callback(func():
		_chalk_marks(n)
		_number.text = str(n)
		_number.scale = Vector3.ONE)
	tw.tween_interval(seconds * 0.15)
	tw.tween_property(_number, "modulate:a", 1.0, seconds * 0.4)
	tw.parallel().tween_property(_marks, "scale", Vector3.ONE, seconds * 0.4)
	return tw
