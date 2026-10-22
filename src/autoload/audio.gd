extends Node
## Sound effects and music, addressed by logical keys from
## res://assets/audio/manifest.json (e.g. "shotgun_fire" -> several variants).
## Missing keys are silently ignored so gameplay never depends on audio assets.

const MANIFEST := "res://assets/audio/manifest.json"
const POOL_3D := 48
const POOL_2D := 12
const MUSIC_TRIM_DB := {"victory": -4.0}   # the victory reel is mastered hotter than the rest

var _variants: Dictionary = {}       # key -> Array[AudioStream]
var _music_slots: Dictionary = {}    # "menu"/"victory" -> path, "match" -> Array
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d := 0
var _next2d := 0
var _music: AudioStreamPlayer
var _music_fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_manifest()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 6.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	Settings.changed.connect(func(_k): _apply_volumes())
	_apply_volumes()


func _setup_buses() -> void:
	for bus_name in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	# sounds behind the listener go through a low-pass, so front/back is audible
	# (stereo panning alone can't tell them apart)
	if AudioServer.get_bus_index(&"SFXBehind") == -1:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, &"SFXBehind")
		AudioServer.set_bus_send(b, &"SFX")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 1700.0
		AudioServer.add_bus_effect(b, lp)


func _apply_volumes() -> void:
	_set_bus_linear(&"Master", Settings.get_value(&"master_volume"))
	_set_bus_linear(&"Music", Settings.get_value(&"music_volume"))
	_set_bus_linear(&"SFX", Settings.get_value(&"sfx_volume"))


func _set_bus_linear(bus_name: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("audio manifest is not a dictionary")
		return
	for key in data:
		if key == "music":
			_music_slots = data[key]
			continue
		var streams: Array[AudioStream] = []
		var files: Variant = data[key]
		if files is String:
			files = [files]
		for f in files:
			var res_path := "res://assets/audio/" + String(f)
			if ResourceLoader.exists(res_path):
				streams.append(load(res_path))
		if not streams.is_empty():
			_variants[StringName(key)] = streams


func has_sound(key: StringName) -> bool:
	return _variants.has(key)


func _pick(key: StringName) -> AudioStream:
	var list: Array = _variants.get(key, [])
	return null if list.is_empty() else list[randi() % list.size()]


## Positional one-shot. Returns the player so loops can be stopped by the caller.
## opts (all optional): unit_size, max_distance, panning (panning_strength),
## directional (true: muffle it when it's behind the listener).
func play_at(key: StringName, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.08, opts := {}) -> AudioStreamPlayer3D:
	var stream := _pick(key)
	if stream == null:
		return null
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.unit_size = opts.get("unit_size", 6.0)
	p.max_distance = opts.get("max_distance", 140.0)
	p.panning_strength = opts.get("panning", 1.0)
	p.bus = &"SFXBehind" if opts.get("directional", false) and is_behind_listener(pos) else &"SFX"
	p.play()
	return p


## Where the player hears from (CameraRig keeps this at the critter's head,
## facing where they look). Falls back to the active camera.
var listener: Node3D


func listener_transform() -> Transform3D:
	if listener and is_instance_valid(listener) and listener.is_inside_tree():
		return listener.global_transform
	var cam := get_viewport().get_camera_3d()
	return cam.global_transform if cam else Transform3D.IDENTITY


func is_behind_listener(pos: Vector3) -> bool:
	var xf := listener_transform()
	var to := pos - xf.origin
	to.y = 0.0
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if to.length_squared() < 1.0 or fwd.length_squared() < 1e-6:
		return false
	return to.normalized().dot(fwd.normalized()) < -0.35


## Non-positional one-shot (UI, the local player's own gun, pickups).
func play(key: StringName, volume_db := 0.0, pitch_jitter := 0.05) -> AudioStreamPlayer:
	var stream := _pick(key)
	if stream == null:
		return null
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
	return p


## A looping player owned by the caller (storm, wind, rocket whoosh).
func make_loop(key: StringName, parent: Node, positional := true) -> Node:
	var stream := _pick(key)
	if stream == null:
		return null
	stream = stream.duplicate()
	if "loop" in stream:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p: Node
	if positional:
		p = AudioStreamPlayer3D.new()
		p.unit_size = 8.0
	else:
		p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"SFX"
	parent.add_child(p)
	return p


func play_music(slot: String, fade := 1.5) -> void:
	var entry: Variant = _music_slots.get(slot)
	if entry is Array:
		entry = entry.pick_random() if not entry.is_empty() else null
	if entry == null:
		stop_music(fade)
		return
	var res_path := "res://assets/audio/" + String(entry)
	if not ResourceLoader.exists(res_path):
		return
	var stream: AudioStream = load(res_path)
	if _music.stream == stream and _music.playing:
		return
	if _music_fade:
		_music_fade.kill()
	_music.stream = stream
	if "loop" in stream:
		stream.loop = slot != "victory"
	_music.volume_db = -30.0
	_music.play()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", MUSIC_TRIM_DB.get(slot, 0.0), fade)


func stop_music(fade := 1.0) -> void:
	if not _music.playing:
		return
	if _music_fade:
		_music_fade.kill()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", -40.0, fade)
	_music_fade.tween_callback(_music.stop)
