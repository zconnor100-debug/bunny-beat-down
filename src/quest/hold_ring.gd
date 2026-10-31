class_name HoldRing
extends Node3D
## A ring on the ground to take (the Kernel Hunt: Act I's rings of the
## Carrot Patch, BurnSpot; Act II's Block Castle courtyard). Stand in it, you
## or one of yours, with none of the enemy in it, and it fills (`progress`, 0
## to 1 over `fill_time`: faster with more of you in it) till it's taken
## (`lit`, `caught`). With any of them in it, it stops where it is; with
## nobody, it slips back slowly.

const FASTER := 0.35           ## this much faster for each more of you in it (three more at most)
const COOL := 0.03             ## of the way lost each second with nobody in it
const GOLD := Color(1.0, 0.84, 0.36)
const GOLD_FILL := Color(0.98, 0.72, 0.2)

signal caught

var radius := 5.5
var fill_time := 12.0          ## seconds to take, with one of you in it
var ring_color := GOLD
var fill_color := GOLD_FILL
var progress := 0.0
var lit := false               ## taken (for good)
var ours := 0                  ## of yours in it now
var theirs := 0                ## of theirs in it now
var _ring: Decal
var _fill: Decal


func _init(r := 5.5, seconds := 12.0) -> void:
	name = "HoldRing"
	radius = r
	fill_time = seconds


func _ready() -> void:
	add_to_group(&"objectives")
	_ring = BossFX._decal(BossFX._texture("ring"), Vector3(radius * 2.0, BossFX.DEPTH, radius * 2.0), Color(ring_color, 0.8))
	add_child(_ring)
	_fill = BossFX._decal(BossFX._texture("disc"), Vector3(0.1, BossFX.DEPTH, 0.1), Color(fill_color, 0.6))
	add_child(_fill)
	_show()


func _physics_process(delta: float) -> void:
	if lit or not is_inside_tree():
		return
	ours = 0
	theirs = 0
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c == null or not c.alive or c.spared or c.state != Critter.State.GROUND:
			continue
		if Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length() > radius:
			continue
		if c.team == 1:
			ours += 1
		elif c.team == 2:
			theirs += 1
	if theirs > 0:
		pass   # (held where it is)
	elif ours > 0:
		progress = minf(1.0, progress + delta / fill_time * (1.0 + FASTER * mini(ours - 1, 3)))
		_filling(delta)
		if progress >= 1.0:
			take()
	else:
		progress = maxf(0.0, progress - COOL * delta)
	_show()


## It's taken (and stays taken).
func take() -> void:
	if lit:
		return
	lit = true
	progress = 1.0
	remove_from_group(&"objectives")
	_taken()
	caught.emit()


## While it fills (a subclass's: BurnSpot's smoke).
func _filling(_delta: float) -> void:
	pass


## Taken (a subclass's: BurnSpot's fire). By default the ring fades.
func _taken() -> void:
	var tw := create_tween()
	tw.tween_property(_ring, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(_fill, "modulate:a", 0.0, 1.8)


func _show() -> void:
	if _fill == null or lit:
		return
	var r := maxf(0.1, radius * 2.0 * progress)
	_fill.size = Vector3(r, BossFX.DEPTH, r)
	# the ring pulses while one of theirs is standing in it
	var warn := theirs > 0 and int(Time.get_ticks_msec() / 250) % 2 == 0
	_ring.modulate = Color(BossFX.WARN, 0.9) if warn else Color(ring_color, 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
