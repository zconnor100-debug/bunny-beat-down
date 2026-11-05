class_name TestCase
extends Node3D
## Base class for headless tests. Any method named test_* is run by
## tests/run_tests.gd; methods may `await` (physics frames, timers...).

var failures: Array[String] = []
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [current_test, msg])
	return cond


func check_near(a: Variant, b: Variant, tol: float, msg: String) -> bool:
	var ok := false
	if a is float or a is int:
		ok = absf(float(a) - float(b)) <= tol
	elif a is Vector3:
		ok = (a as Vector3).distance_to(b) <= tol
	return check(ok, "%s (got %s, want %s ± %s)" % [msg, a, b, tol])


## Counts the errors logged (the engine's and the scripts', not warnings) from
## count_errors() until done(). Godot logs some mistakes and carries on (a
## get_meta with no such entry, a freed object used), so no check sees them.
class ErrorCount extends Logger:
	var count := 0
	var first := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		if first.is_empty():
			first = "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function]

	## Stops counting: "" if nothing was logged, else how many and the first.
	func done() -> String:
		OS.remove_logger(self)
		return "" if count == 0 else "%d logged, the first: %s" % [count, first]


func count_errors() -> ErrorCount:
	var e := ErrorCount.new()
	OS.add_logger(e)
	return e


func wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A flat static ground plus the FX/Projectiles singletons the game expects.
func make_arena(size := 60.0) -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)
	var fx := FX.new()
	fx.name = "FX"
	add_child(fx)
	var pr := Projectiles.new()
	pr.name = "Projectiles"
	add_child(pr)


func spawn_critter(def_path: String, pos: Vector3, yaw := 0.0) -> Critter:
	var c := Critter.new()
	c.def = load(def_path)
	add_child(c)
	c.place_at(pos, yaw)
	return c
