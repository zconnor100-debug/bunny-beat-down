class_name Spinner
extends Node3D
## Turns slowly about its own Y axis: the bedroom ceiling's mobile, and the
## goldfish circling in the fishbowl (`bob` makes children bob up and down).

@export var speed := 0.2
@export var bob := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	rotate_y(speed * delta)
	if bob > 0.0:
		_t += delta
		for i in get_child_count():
			var c := get_child(i) as Node3D
			if c:
				c.position.y = sin(_t * 1.3 + i * 1.7) * bob
