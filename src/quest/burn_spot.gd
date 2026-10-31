class_name BurnSpot
extends HoldRing
## One of the places the Carrot Patch is set alight (the Kernel Hunt's Act I,
## PatchMission): a gold-green ring on the ground round a row of the Patch.
## Stand in it, you or a ranger, with none of the Touched in it, and it
## catches (HoldRing: `progress`, 0 to 1 over BURN_TIME, faster with more of
## you in it): smoke first, then it goes up (Fire) and stays lit (`lit`). With
## any of the Touched in it, it stops where it is; with nobody, it dies back
## slowly.

const RADIUS := 5.5
const BURN_TIME := 12.0        ## seconds to catch, with one of you in it
const RING := Color(0.8, 1.0, 0.34)    ## (the Touched's gold-green: the Patch's light)
const CATCHING := Color(1.0, 0.5, 0.12)

var fire: Fire
var _smoke_t := 0.0


func _init() -> void:
	super._init(RADIUS, BURN_TIME)
	name = "BurnSpot"
	ring_color = RING
	fill_color = CATCHING


func _ready() -> void:
	add_to_group(&"burn_spots")
	super._ready()


## It goes up: the fire, and it stays lit.
func ignite() -> void:
	take()


func _filling(delta: float) -> void:
	_smoke_t -= delta
	if _smoke_t <= 0.0 and progress > 0.15:
		_smoke_t = 0.5
		FX.burst(global_position + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)), Vector3.UP,
			{"amount": 6, "lifetime": 2.2, "speed": Vector2(1.0, 2.2), "spread": 20.0, "gravity": -0.6, "size": 1.4,
			"scale": Vector2(0.6, 1.4), "color": Color(0.25, 0.23, 0.2, 0.5 * progress), "fade": true, "aabb": 10.0})


func _taken() -> void:
	fire = Fire.new(RADIUS * 1.6, false)
	add_child(fire)
	fire.grow(1.6)
	Audio.play_at(&"fire_ignite", global_position + Vector3.UP, 4.0, 0.05, {"max_distance": 200.0, "unit_size": 10.0})
	var tw := create_tween()
	tw.tween_property(_ring, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(_fill, "modulate", Color(0.08, 0.06, 0.05, 0.85), 2.5)   # (scorched)
