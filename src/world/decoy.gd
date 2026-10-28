class_name Decoy
extends StaticBody3D
## Cardboard You (a boon, Boons): a flat cardboard cut-out of a critter on a
## little stand, left where you ate a clover. While it stands (`life`), the
## bots after you shoot at it instead (AIBrain._fight asks `fooling`), and
## their carrots stick in it; then it folds over and is gone.

const CARDBOARD := Color(0.74, 0.57, 0.38)
const INK := Color(0.12, 0.08, 0.06)
const FOOL_RANGE := 45.0          ## metres from a bot it fools
const FOLD_TIME := 0.4

var life := 4.0
var height := 1.0                 ## the critter it's cut out as (its head top, metres)
var _t := 0.0
var _folding := false


## Leave one where `you` stand, facing the way you face, for `seconds`.
static func spawn(parent: Node, you: Critter, seconds: float) -> Decoy:
	var d := Decoy.new()
	d.life = seconds
	d.height = you.visual.rig.world_head_top if you.visual and you.visual.rig else 1.0
	parent.add_child(d)
	d.global_position = you.global_position
	d.rotation.y = you.look_yaw
	return d


## The decoy fooling `bot` right now, if any: the nearest standing one within FOOL_RANGE.
static func fooling(bot: Critter) -> Decoy:
	var best: Decoy = null
	var best_d := FOOL_RANGE
	for n in bot.get_tree().get_nodes_in_group(&"decoys"):
		var d := n as Decoy
		if d and d.standing():
			var dist := d.global_position.distance_to(bot.global_position)
			if dist < best_d:
				best_d = dist
				best = d
	return best


func standing() -> bool:
	return _t < life


## Where the bots aim: its chest.
func aim_point() -> Vector3:
	return global_position + Vector3.UP * height * 0.5


func _ready() -> void:
	add_to_group(&"decoys")
	collision_layer = Layers.WORLD
	collision_mask = 0
	set_meta(&"surface", &"wood")
	var h := height
	var card := StandardMaterial3D.new()
	card.albedo_color = CARDBOARD
	card.roughness = 0.95
	var ink := StandardMaterial3D.new()
	ink.albedo_color = INK
	# a body, a head and two ears, cut flat; two inked eyes; a strut behind
	_piece(Vector3(0.40 * h, 0.52 * h, 0.018), Vector3(0, 0.30 * h, 0), card)
	_piece(Vector3(0.32 * h, 0.28 * h, 0.018), Vector3(0, 0.68 * h, 0), card)
	for sx in [-1.0, 1.0]:
		_piece(Vector3(0.08 * h, 0.28 * h, 0.018), Vector3(sx * 0.085 * h, 0.92 * h, 0), card).rotation.z = -sx * 0.12
		_piece(Vector3(0.035 * h, 0.035 * h, 0.006), Vector3(sx * 0.06 * h, 0.72 * h, -0.012), ink)
	var strut := _piece(Vector3(0.04, 0.5 * h, 0.012), Vector3(0, 0.24 * h, 0.12 * h), card)
	strut.rotation.x = -0.45
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.40 * h, 0.82 * h, 0.05)
	cs.shape = box
	cs.position.y = 0.41 * h
	add_child(cs)


func _piece(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = at
	add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= life and not _folding:
		_folding = true
		collision_layer = 0
		var tw := create_tween()
		tw.tween_property(self, "rotation:x", -PI / 2.0, FOLD_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(1.0)
		tw.tween_callback(queue_free)
