extends Node
## Player-facing settings, persisted to a ConfigFile.
##
## Automated test runs (`godot -s ...` or BBD_TEST=1) read and write a separate
## file so a test can never clobber the settings of someone who is playing.

signal changed(key: StringName)

const REAL_PATH := "user://settings.cfg"
const TEST_PATH := "user://settings_test.cfg"

enum Gore { BLOOD, STUFFING, OFF }
enum CameraMode { THIRD_PERSON, FIRST_PERSON }
enum Difficulty { EASY, NORMAL, HARD }

const DEFAULTS := {
	"mouse_sensitivity": 0.12,      # degrees per pixel
	"aim_sensitivity_scale": 0.6,   # multiplier while aiming down sights
	"invert_y": false,
	"fov": 80.0,
	"camera_mode": CameraMode.THIRD_PERSON,
	"gore": Gore.BLOOD,
	"master_volume": 0.85,
	"music_volume": 0.6,
	"sfx_volume": 0.9,
	"quality": 2,                   # 0 low, 1 medium, 2 high, 3 ultra
	"show_fps": false,
	"opponents": 23,
	"difficulty": Difficulty.NORMAL,
	"seed": 0,                      # 0 = random island every match
}

var path: String = REAL_PATH
var _values: Dictionary = {}


func _init() -> void:
	path = TEST_PATH if is_test_run() else REAL_PATH
	_values = DEFAULTS.duplicate()
	load_settings()


static func is_test_run() -> bool:
	if OS.get_environment("BBD_TEST") == "1":
		return true
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, value: Variant, save := true) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	changed.emit(key)
	if save:
		save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key("settings", key):
			var v: Variant = cfg.get_value("settings", key)
			# ignore values whose type no longer matches (old/hand-edited files)
			if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
				_values[key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value("settings", key, _values[key])
	cfg.save(path)


# --- typed conveniences used all over the codebase -------------------------

var gore: int:
	get:
		return get_value(&"gore")

var difficulty: int:
	get:
		return get_value(&"difficulty")

var fov: float:
	get:
		return get_value(&"fov")
