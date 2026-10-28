extends TestCase
## The Doppelbunny's learning (DoppelSense, DoppelRecorder, DoppelNet,
## DoppelData): it reads your decisions in a fight, not your thumbs; it
## watches you fight and keeps the moments; a small network learns a style
## from them and is measured on moments it never learned from; two styles
## make two different players; and it all stays in the test run's own files.

const TEST_DEF := "res://data/critters/test_critter.tres"
const IN := DoppelSense.INPUTS
const PER := DoppelData.PER


func before_each() -> void:
	DoppelData.reset_for_tests()


func after_each() -> void:
	DoppelData.reset_for_tests()


## `n` made-up moments of a player whose choices follow `rule`
## (features -> [move index, {flag: true}]).
func _style(rule: Callable, n: int, seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows := PackedFloat32Array()
	for i in n:
		var f := PackedFloat32Array()
		f.resize(IN)
		for k in IN:
			f[k] = rng.randf()
		f[11] = 1.0   # (always a fight)
		var did: Array = rule.call(f)
		var y := PackedFloat32Array()
		y.resize(DoppelSense.LABELS)
		y[0] = did[0]
		for flag in did[1]:
			y[1 + DoppelSense.FLAGS.find(flag)] = 1.0
		rows.append_array(f)
		rows.append_array(y)
	return rows


## Backs off when hurt; far off, it holds and goes prone; otherwise it charges in, sprinting.
func _careful(f: PackedFloat32Array) -> Array:
	if f[0] < 0.4:
		return [2, []]
	if f[12] > 0.6:
		return [0, ["prone"]]
	return [1, ["sprint"]]


## Reckless: hurt or not it charges anyone near, and far off it circles round, jumping.
func _reckless(f: PackedFloat32Array) -> Array:
	if f[12] > 0.6:
		return [4, ["jump"]]
	return [1, ["sprint", "fire"]]


func _situation(health: float, far: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(IN)
	for k in IN:
		f[k] = 0.5
	f[0] = health
	f[11] = 1.0
	f[12] = far
	return f


func _move(p: PackedFloat32Array) -> int:
	var best := 0
	for o in DoppelNet.MOVES:
		if p[o] > p[best]:
			best = o
	return best


func _flag(p: PackedFloat32Array, name: String) -> float:
	return p[DoppelNet.MOVES + DoppelSense.FLAGS.find(name)]


func test_it_reads_your_decisions_not_your_thumbs() -> void:
	var ahead := Vector3(0, 0, -10)   # (the enemy, straight ahead)
	check(DoppelSense.move_of(Vector3(0, 0, -1), ahead) == 1, "toward it: push")
	check(DoppelSense.move_of(Vector3(0, 0, 1), ahead) == 2, "away from it: back off")
	check(DoppelSense.move_of(Vector3(1, 0, 0), ahead) == 4 and DoppelSense.move_of(Vector3(-1, 0, 0), ahead) == 3, "round it: right, left")
	check(DoppelSense.move_of(Vector3(0.1, 0, 0), ahead) == 0, "barely moving: hold")
	var y := DoppelSense.label(Vector3(0, 0, -1), ahead, {"sprint": true, "prone": true})
	check(y.size() == DoppelSense.LABELS and int(y[0]) == 1 and y[1] == 1.0 and y[3] == 1.0 and y[2] == 0.0 and y[5] == 0.0,
		"a label is the move, then the flags: %s" % [y])


func test_it_watches_you_fight() -> void:
	make_arena(80.0)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 10))   # looking -Z
	you.is_player = true
	var them := spawn_critter(TEST_DEF, Vector3(0, 0.1, -20), PI)
	var rec := DoppelRecorder.new()
	you.add_child(rec)
	await wait_physics(5)
	you.move_input = Vector2(0, 1)   # (straight at them)
	you.want_sprint = true
	await wait_physics(int(Engine.physics_ticks_per_second * 1.5))
	you.move_input = Vector2.ZERO
	you.want_sprint = false
	var n := rec.rows.size() / PER
	check(n >= 4 and rec.rows.size() % PER == 0, "a moment every %.1f s of the fight (%d)" % [DoppelRecorder.STEP, n])
	var pushes := 0
	var sprints := 0
	for i in n:
		pushes += 1 if int(rec.rows[i * PER + IN]) == 1 else 0
		sprints += 1 if rec.rows[i * PER + IN + 1] == 1.0 else 0
	check(pushes >= n - 2 and sprints >= n - 2, "you pushed at them, sprinting (%d and %d of %d)" % [pushes, sprints, n])
	check(rec.rows[11] == 1.0 and rec.rows[12] > 0.3 and rec.rows[(n - 1) * PER + 12] < rec.rows[12], "with them in sight, getting closer")
	them.take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, null))
	await wait_physics(10)
	var after := rec.rows.size()
	await wait_physics(30)
	check(rec.rows.size() == after, "no fight, nothing to learn")
	rec.finish()
	check(DoppelData.matches() == 1 and DoppelData.moments() == n, "the match goes in the book (%d moments)" % DoppelData.moments())
	check(DoppelData.path() == DoppelData.TEST_PATH and DoppelData.model_path() == DoppelData.TEST_MODEL, "(the test run's own files, never yours)")


func test_it_learns_a_style_and_is_measured_honestly() -> void:
	var t0 := Time.get_ticks_msec()
	var out := DoppelNet.train(_style(_careful, 3000, 4), 4, 0.01, 2)
	check(out.likeness > 0.85 and out.likeness > out.baseline + 0.3,
		"it moves as the player would %.0f%% of the time, on moments it never learned from (always guessing: %.0f%%)" % [out.likeness * 100.0, out.baseline * 100.0])
	check(out.flags > 0.9, "and makes the same other calls %.0f%% of the time" % [out.flags * 100.0])
	var net: DoppelNet = out.net
	var hurt := net.predict(_situation(0.2, 0.3))
	var far := net.predict(_situation(0.9, 0.9))
	var close := net.predict(_situation(0.9, 0.2))
	check(_move(hurt) == 2, "hurt, it backs off")
	check(_move(far) == 0 and _flag(far, "prone") > 0.5, "far off, it holds and goes prone (%.2f)" % _flag(far, "prone"))
	check(_move(close) == 1 and _flag(close, "sprint") > 0.5 and _flag(close, "prone") < 0.5, "close, it charges in")
	var again := DoppelNet.from_dict(JSON.parse_string(JSON.stringify(net.to_dict())))
	var p := again.predict(_situation(0.9, 0.9)) if again else PackedFloat32Array()
	check(again != null and p.size() == far.size() and absf(p[0] - far[0]) < 1e-4 and absf(p[5] - far[5]) < 1e-4, "saved and loaded, it's the same player")
	print("    (trained on 2,700 moments, 4 passes, in %.1f s: plays like them %.0f%% of the time, guessing %.0f%%, other calls %.0f%%)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, out.likeness * 100.0, out.baseline * 100.0, out.flags * 100.0])


func test_two_styles_make_two_players() -> void:
	var a: DoppelNet = DoppelNet.train(_style(_careful, 2000, 5), 4, 0.01, 3).net
	var b: DoppelNet = DoppelNet.train(_style(_reckless, 2000, 6), 4, 0.01, 3).net
	var hurt := _situation(0.2, 0.3)
	var far := _situation(0.9, 0.9)
	check(_move(a.predict(hurt)) == 2 and _move(b.predict(hurt)) == 1, "hurt: the careful one backs off, the reckless one charges")
	check(_move(a.predict(far)) == 0 and _move(b.predict(far)) == 4 and _flag(b.predict(far), "jump") > 0.5,
		"far off: the careful one holds, the reckless one circles round, hopping")


func test_the_newest_moments_are_kept_and_trained_on_after_a_match() -> void:
	DoppelData.add_match(_style(_careful, 600, 7))
	DoppelData.wait()
	var m := DoppelData.model()
	check(not m.is_empty() and m.net is DoppelNet and int(m.moments) == 600 and int(m.matches) == 1,
		"after the match it trains on a worker thread, and keeps the network (%s moments)" % m.get("moments", "no"))
	check(float(m.get("likeness", 0.0)) > float(m.get("baseline", 1.0)), "already more like the player than guessing (%.0f%% vs %.0f%%)" % [
		float(m.get("likeness", 0.0)) * 100.0, float(m.get("baseline", 0.0)) * 100.0])
	var big := PackedFloat32Array()
	big.resize((DoppelData.MAX_MOMENTS + 10) * PER)
	big[10 * PER] = 5.0                                   # (the 11th moment)
	big[(DoppelData.MAX_MOMENTS + 9) * PER] = 7.0          # (the last)
	DoppelData.add_match(big, false)
	check(DoppelData.moments() == DoppelData.MAX_MOMENTS and DoppelData.matches() == 2, "at most %d moments kept" % DoppelData.MAX_MOMENTS)
	var rows := DoppelData._rows
	# (600 + 30,010 moments: the first match's 600 and the big one's first 10 go)
	check(rows[0] == 5.0 and rows[rows.size() - PER] == 7.0, "the newest ones")
	DoppelData._loaded = false   # (read back from the file)
	check(DoppelData.moments() == DoppelData.MAX_MOMENTS and DoppelData.matches() == 2 and DoppelData._rows[DoppelData._rows.size() - PER] == 7.0,
		"and they're saved")
