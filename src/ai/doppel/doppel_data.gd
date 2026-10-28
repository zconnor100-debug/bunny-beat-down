class_name DoppelData
extends RefCounted
## What the Doppelbunny has learned from: the moments of your fights
## (DoppelRecorder: each one's DoppelSense.features, then its label), the
## newest MAX_MOMENTS of them kept, and the network trained on them
## (DoppelNet) with how alike it plays. Kept on this computer only, in
## user://, and never in automated test runs' (they use their own files,
## like Settings). Training runs on a worker thread after a match.

const PATH := "user://doppel.bin"
const TEST_PATH := "user://doppel_test.bin"
const MODEL := "user://doppel_model.json"
const TEST_MODEL := "user://doppel_model_test.json"
const MAX_MOMENTS := 30000
const PER := DoppelSense.INPUTS + DoppelSense.LABELS
const PASSES := 3
const TRAIN_ON := 9000               ## the newest moments a training run learns from (about 10 s)

static var _rows := PackedFloat32Array()
static var _loaded := false
static var _matches := 0
static var _training := -1          # (WorkerThreadPool task id, while one runs)
static var _lock := Mutex.new()


static func path() -> String:
	return TEST_PATH if Settings.is_test_run() else PATH


static func model_path() -> String:
	return TEST_MODEL if Settings.is_test_run() else MODEL


static func reset_for_tests() -> void:
	assert(Settings.is_test_run())
	wait()
	_rows = PackedFloat32Array()
	_matches = 0
	_loaded = true
	_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_MODEL))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return
	_matches = f.get_32()
	_rows = f.get_buffer(f.get_length() - 4).to_float32_array()
	if _rows.size() % PER != 0:
		_rows = PackedFloat32Array()   # (an older layout: start over)


static func _save() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f:
		f.store_32(_matches)
		f.store_buffer(_rows.to_byte_array())


static func moments() -> int:
	_load()
	return _rows.size() / PER


## Matches it has watched you play.
static func matches() -> int:
	_load()
	return _matches


## A match's moments (rows of PER numbers): kept (the oldest go past
## MAX_MOMENTS), saved, and trained on, on a worker thread.
static func add_match(rows: PackedFloat32Array, train := true) -> void:
	if rows.is_empty():
		return
	_load()
	_lock.lock()
	_rows.append_array(rows)
	if _rows.size() > MAX_MOMENTS * PER:
		_rows = _rows.slice(_rows.size() - MAX_MOMENTS * PER)
	_matches += 1
	_save()
	_lock.unlock()
	if train:
		train_async()


## Train a new network on everything kept, on a worker thread (one at a time).
static func train_async() -> void:
	if _training >= 0 and not WorkerThreadPool.is_task_completed(_training):
		return
	wait()
	_lock.lock()
	var rows := _rows.slice(maxi(0, _rows.size() - TRAIN_ON * PER))
	_lock.unlock()
	_training = WorkerThreadPool.add_task(func(): _train(rows), false, "Doppelbunny training")


## Wait for a training run to finish (tests; quitting).
static func wait() -> void:
	if _training >= 0:
		WorkerThreadPool.wait_for_task_completion(_training)
		_training = -1


static func _train(rows: PackedFloat32Array) -> void:
	var out := DoppelNet.train(rows, PASSES)
	var f := FileAccess.open(model_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"net": out.net.to_dict(), "likeness": out.likeness, "baseline": out.baseline,
			"flags": out.flags, "moments": out.moments, "matches": _matches}))


## The trained network and how alike it plays: {net, likeness, baseline,
## flags, moments, matches}, or {} if there's none yet.
static func model() -> Dictionary:
	var f := FileAccess.open(model_path(), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or not (d as Dictionary).has("net"):
		return {}
	var net := DoppelNet.from_dict(d.net)
	if net == null:
		return {}
	d["net"] = net
	return d
