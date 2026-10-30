class_name BurnSpot
extends Node3D
## One of the places the Carrot Patch is set alight (the Kernel Hunt's Act I,
## PatchMission): a gold-green ring on the ground round a row of the Patch.
## Stand in it, you or a ranger, with none of the Touched in it, and it
## catches (`progress`, 0 to 1 over BURN_TIME: faster with more of you in it):
## smoke first, then it goes up (Fire) and stays lit (`lit`). With any of the
## Touched in it, it stops where it is; with nobody, it dies back slowly.

const RADIUS := 5.5
const BURN_TIME := 12.0        ## seconds to catch, with one of you in it...
const FASTER := 0.35           ## ...and this much faster for each more (three more at most)
const COOL := 0.03             ## of the way lost each second with nobody in it
const RING := Color(0.8, 1.0, 0.34)    ## (the Touched's gold-green: the Patch's light)
const CATCHING := Color(1.0, 0.5, 0.12)

signal caught

var progress := 0.0
var lit := false
var ours := 0                  ## of yours in it now (you, the rangers)
var theirs := 0                ## of the Touched in it now
var fire: Fire
var _ring: Decal
var _fill: Decal
var _smoke_t := 0.0


func _init() -> void:
	name = "BurnSpot"


func _ready() -> void:
	add_to_group(&"burn_spots")
	add_to_group(&"objectives")
	_ring = BossFX._decal(BossFX._texture("ring"), Vector3(RADIUS * 2.0, BossFX.DEPTH, RADIUS * 2.0), Color(RING, 0.8))
	add_child(_ring)
	_fill = BossFX._decal(BossFX._texture("disc"), Vector3(0.1, BossFX.DEPTH, 0.1), Color(CATCHING, 0.6))
	add_child(_fill)
	_show()


func _physics_process(delta: float) -> void:
	if lit or not is_inside_tree():
		return
	ours = 0
	theirs = 0
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c == null or not c.alive or c.state != Critter.State.GROUND:
			continue
		if Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length() > RADIUS:
			continue
		if c.team == 1:
			ours += 1
		elif c.team == 2:
			theirs += 1
	if theirs > 0:
		pass   # (held where it is)
	elif ours > 0:
		progress = minf(1.0, progress + delta / BURN_TIME * (1.0 + FASTER * mini(ours - 1, 3)))
		_smoke_t -= delta
		if _smoke_t <= 0.0 and progress > 0.15:
			_smoke_t = 0.5
			FX.burst(global_position + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)), Vector3.UP,
				{"amount": 6, "lifetime": 2.2, "speed": Vector2(1.0, 2.2), "spread": 20.0, "gravity": -0.6, "size": 1.4,
				"scale": Vector2(0.6, 1.4), "color": Color(0.25, 0.23, 0.2, 0.5 * progress), "fade": true, "aabb": 10.0})
		if progress >= 1.0:
			ignite()
	else:
		progress = maxf(0.0, progress - COOL * delta)
	_show()


## It goes up: the fire, and it stays lit.
func ignite() -> void:
	if lit:
		return
	lit = true
	progress = 1.0
	remove_from_group(&"objectives")
	fire = Fire.new(RADIUS * 1.6, false)
	add_child(fire)
	fire.grow(1.6)
	Audio.play_at(&"fire_ignite", global_position + Vector3.UP, 4.0, 0.05, {"max_distance": 200.0, "unit_size": 10.0})
	var tw := create_tween()
	tw.tween_property(_ring, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(_fill, "modulate", Color(0.08, 0.06, 0.05, 0.85), 2.5)   # (scorched)
	caught.emit()


func _show() -> void:
	if _fill == null or lit:
		return
	var r := maxf(0.1, RADIUS * 2.0 * progress)
	_fill.size = Vector3(r, BossFX.DEPTH, r)
	# the ring pulses while one of the Touched is standing in it
	var warn := theirs > 0 and int(Time.get_ticks_msec() / 250) % 2 == 0
	_ring.modulate = Color(BossFX.WARN, 0.9) if warn else Color(RING, 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
