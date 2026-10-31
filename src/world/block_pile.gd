class_name BlockPile
extends Node3D
## Toys built into something blasts can knock apart (Block Castle: ToyProps):
## its ToyBlocks, which rests on which (ToyBlock.stack), and every blast near
## enough (Events.explosion: a rocket, a grenade, a boss's stomp or blow)
## knocks loose the blocks it reaches, thrown out from it, harder the nearer.
## What rested on them comes down after.

const THROW := 11.0            ## m/s a block right by a blast flies off at
const TOPPLE := 0.5           ## rad/s a toppling stack starts tipping over at...
const BITE := 0.45             ## ...when a blast this much of its radius from them knocks blocks out of it

var blocks: Array[ToyBlock] = []
var reach := 30.0              ## metres from its middle its blocks go out to
var stack_first := true        ## off: its blocks' resting on each other is already worked out (a log cabin's roof)
var topples := false           ## a tall stack (a brick tower): what rests on the blocks a blast knocks out tips over away from it, as one, not straight down onto them


func _init() -> void:
	name = "BlockPile"


func _ready() -> void:
	if stack_first:
		ToyBlock.stack(blocks)
	Events.explosion.connect(_on_blast)


func _on_blast(pos: Vector3, radius: float) -> void:
	if not is_inside_tree() or Vector2(pos.x - global_position.x, pos.z - global_position.z).length() > reach + radius:
		return
	_drop_gone()
	var hit: Array[ToyBlock] = []
	var near := {}   # block -> how far the blast is from it
	var bite := radius * (BITE if topples else 0.9)   # (a stack's bricks hold each other in: it knocks out the ones right by it)
	for b in blocks:
		var d := b.surface_distance(pos)
		if d <= bite:
			hit.append(b)
			near[b] = d
	if topples:
		_tip(hit, _resting_on(hit), pos)
	for b in hit:
		var k := 1.0 - clampf(float(near[b]) / maxf(radius, 0.1), 0.0, 1.0)
		var away := b.global_position - pos
		var dir := (away.normalized() if away.length() > 0.1 else Vector3.UP) + Vector3.UP * 0.5
		var throw := THROW
		if topples:   # (out from under what's on it)
			dir = Vector3(away.x, 0.0, away.z).normalized() + Vector3.UP * 0.2
			throw *= 1.6
		b.loosen(dir.normalized() * b.mass() * throw * (0.35 + 0.65 * k), pos)
		blocks.erase(b)


## What rests on `hit`, all the way up, with nothing else holding it up.
func _resting_on(hit: Array[ToyBlock]) -> Array[ToyBlock]:
	var gone := {}
	for b in hit:
		gone[b] = true
	var out: Array[ToyBlock] = []
	var queue: Array[ToyBlock] = []
	queue.append_array(hit)
	var i := 0
	while i < queue.size():
		for a in queue[i].above:
			if not gone.has(a) and a.under.all(func(u): return gone.has(u)):
				gone[a] = true
				out.append(a)
				queue.append(a)
		i += 1
	return out


## Tip `tipping` over away from the blast at `pos`, as one: turning about
## the far edge of the top of what it hit (`hit`, about to be knocked out).
func _tip(hit: Array[ToyBlock], tipping: Array[ToyBlock], pos: Vector3) -> void:
	if hit.is_empty() or tipping.is_empty():
		return
	var top := -INF
	var mid := Vector3.ZERO
	var half := 0.0
	for b in hit:
		top = maxf(top, b.global_position.y + b.size.y * 0.5)
		mid += b.global_position / hit.size()
		half = maxf(half, maxf(b.size.x, b.size.z) * 0.5)
	var away := Vector3(mid.x - pos.x, 0.0, mid.z - pos.z)
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	var pivot := Vector3(mid.x, top, mid.z) - away * half
	var spin := Vector3.UP.cross(-away) * TOPPLE
	for b in tipping:
		b.loosen(spin.cross(b.global_position - pivot) * b.mass(), Vector3.INF, spin)
		blocks.erase(b)


## Forget the blocks that are gone already: knocked loose, or come down when
## what held them up went (freed by now, some of them, and a typed array
## won't erase what's freed: it'd stay on the list, an error every blast).
func _drop_gone() -> void:
	var left: Array[ToyBlock] = []
	for o in blocks:
		if is_instance_valid(o) and not (o as ToyBlock).loose:
			left.append(o)
	blocks = left
