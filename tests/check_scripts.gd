extends SceneTree
## Compiles every GDScript in src/ and tests/ and exits non-zero on any error.
##   godot --headless --path . -s tests/check_scripts.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bad := 0
	var count := 0
	for dir in ["res://src", "res://tests"]:
		for path in _scripts(dir):
			count += 1
			var s: GDScript = load(path)
			if s == null or not s.can_instantiate():
				print("BROKEN ", path)
				bad += 1
	print("%d scripts, %d broken" % [count, bad])
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
