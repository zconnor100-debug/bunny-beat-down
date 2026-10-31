extends SceneTree
## Headless test runner.
##   godot --headless --path . -s tests/run_tests.gd            # all tests
##   godot --headless --path . -s tests/run_tests.gd -- ragdoll # files matching "ragdoll"
##   godot --headless --path . -s tests/run_tests.gd -- kernel::act_two   # ...and in them, tests matching "act_two"
## Exits with code 1 if anything failed, so CI can gate on it.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var only := ""
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		filter = user_args[0]
	if filter.contains("::"):
		only = filter.get_slice("::", 1)
		filter = filter.get_slice("::", 0)
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd" and (filter.is_empty() or f.contains(filter)):
			files.append(f)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var suite: Node = script.new()
		suite.name = f.get_basename()
		root.add_child(suite)
		for m in script.get_script_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_") or (only != "" and not mname.contains(only)):
				continue
			total += 1
			suite.current_test = "%s::%s" % [f.get_basename(), mname]
			var before: int = suite.failures.size()
			await suite.before_each()
			var started := Time.get_ticks_msec()
			await Callable(suite, mname).call()
			await suite.after_each()
			var ok: bool = suite.failures.size() == before
			print("%s %s (%d ms)" % ["PASS" if ok else "FAIL", suite.current_test, Time.get_ticks_msec() - started])
			if not ok:
				for i in range(before, suite.failures.size()):
					print("    - " + suite.failures[i])
					failed.append(suite.failures[i])
		suite.queue_free()
		await process_frame
	print("\n%d tests, %d failures, %.1f s" % [total, failed.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if not failed.is_empty() else 0)
