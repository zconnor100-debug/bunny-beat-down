class_name BlockPile
extends Node3D
## Toys built into something blasts can knock apart (Block Castle: ToyProps):
## its ToyBlocks, which rests on which (ToyBlock.stack), and every blast near
## enough (Events.explosion: a rocket, a grenade, a boss's stomp or blow)
## knocks loose the blocks it reaches, thrown out from it, harder the nearer.
## What rested on them comes down after.

const THROW := 11.0            ## m/s a block right by a blast flies off at

var blocks: Array[ToyBlock] = []
var reach := 30.0              ## metres from its middle its blocks go out to


func _init() -> void:
	name = "BlockPile"


func _ready() -> void:
	ToyBlock.stack(blocks)
	Events.explosion.connect(_on_blast)


func _on_blast(pos: Vector3, radius: float) -> void:
	if not is_inside_tree() or Vector2(pos.x - global_position.x, pos.z - global_position.z).length() > reach + radius:
		return
	for o in blocks.duplicate():
		if not is_instance_valid(o) or (o as ToyBlock).loose:
			blocks.erase(o)   # (gone already: knocked loose, or come down when what held it up went)
			continue
		var b := o as ToyBlock
		var d := maxf(0.0, b.global_position.distance_to(pos) - b.size.x * 0.5)
		if d > radius * 0.9:
			continue
		var k := 1.0 - clampf(d / maxf(radius, 0.1), 0.0, 1.0)
		var away := b.global_position - pos
		var dir := (away.normalized() if away.length() > 0.1 else Vector3.UP) + Vector3.UP * 0.5
		var mass := b.size.x * b.size.y * b.size.z * ToyBlock.DENSITY
		b.loosen(dir.normalized() * mass * THROW * (0.35 + 0.65 * k), pos)
		blocks.erase(b)
