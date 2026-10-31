class_name Dam
extends Node3D
## Where Water Bottle Falls lands (the Kernel Hunt's Act III, FoamMission):
## the puddle under the bottle's spout, ringed on the ground. Carry a chew
## block into the ring and it's stacked across the water (`take`); with
## NEEDED of them the falls are dammed (`dammed`): the drips stop, and the
## puddle shrinks away.

signal took(placed: int)
signal dammed

const NEEDED := 3
const RADIUS := 8.0
const RING := Color(0.55, 0.85, 1.0)

var placed := 0
var drips: GPUParticles3D
var puddle: Node3D
var _ring: Decal


func _init() -> void:
	name = "Dam"


func _ready() -> void:
	add_to_group(&"objectives")
	_ring = BossFX._decal(BossFX._texture("ring"), Vector3(RADIUS * 2.0, BossFX.DEPTH, RADIUS * 2.0), Color(RING, 0.8))
	add_child(_ring)


func _physics_process(_delta: float) -> void:
	if placed >= NEEDED:
		return
	_ring.modulate = Color(RING, 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
	for b in get_tree().get_nodes_in_group(&"glow_carrots"):
		var block := b as ChewBlock
		if block and block.carrier and Vector2(block.carrier.global_position.x - global_position.x,
				block.carrier.global_position.z - global_position.z).length() < RADIUS:
			take(block)


## A block into the dam: it's stacked across the water, a row at a time.
func take(block: ChewBlock) -> void:
	if block.placed or placed >= NEEDED:
		return
	block.place()
	var slot := Vector3((placed - 1) * ChewBlock.SIZE * 1.05, 0.0, 0.0)
	var at := global_position + slot
	var tw := block.create_tween()
	tw.tween_property(block, "global_position", at + Vector3.UP * 3.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(block, "global_position", at, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	block.remove_from_group(&"glow_carrots")
	placed += 1
	Audio.play_at(&"carrot_impact_wood", at, 4.0, 0.05, {"max_distance": 200.0, "unit_size": 14.0})
	BossFX.dust(at, 3.0, Color(0.62, 0.5, 0.32, 0.6))
	if drips and is_instance_valid(drips):
		drips.amount_ratio = 1.0 - float(placed) / NEEDED
	took.emit(placed)
	if placed >= NEEDED:
		_dam()


func _dam() -> void:
	if is_in_group(&"objectives"):
		remove_from_group(&"objectives")
	if drips and is_instance_valid(drips):
		drips.emitting = false
	Audio.play_at(&"water_stop", global_position + Vector3.UP * 2.0, 4.0, 0.0, {"max_distance": 300.0, "unit_size": 20.0})
	var tw := create_tween()
	tw.tween_property(_ring, "modulate:a", 0.0, 1.0)
	if puddle and is_instance_valid(puddle):
		tw.parallel().tween_property(puddle, "scale", Vector3(0.05, 1.0, 0.05), 6.0).set_trans(Tween.TRANS_SINE)
	dammed.emit()
