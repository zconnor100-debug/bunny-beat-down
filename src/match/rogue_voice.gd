class_name RogueVoice
extends AudioStreamPlayer3D
## A rogue saying a line out loud, from where it stands, in its own voice.
##
## Every line a rogue can say was spoken ahead of time by tools/voices/
## build_voices.py (Kokoro TTS, a voice of its own for each rogue: two voice
## packs blended, pitched for its kind of critter and paced for its
## personality) and packed into one file per rogue, assets/voices/<rogue>.ogg,
## with assets/voices/voices.json saying where each clip is. A line's `plan`
## there is its parts in order: a clip of its words, the name it calls you
## (`you`: your critter's, "Bun"), a number (`num`: the score so far), another
## rogue's name (`them`), or a pause; each part is a stretch of the rogue's
## file. Lines are looked up by the key they were picked with (Cast.say).

const BANK := "res://assets/voices/voices.json"
const MAX_AT_ONCE := 4          ## voices playing at once (the rest go unsaid)
const NUM_MAX := 60             ## scores past this are read as this (tools/voices NUM_MAX)
const LOUDER_DB := 4.0          ## over the clips' own level (the Voice bus limits the peaks: Audio)
const CARRY := 22.0             ## metres a voice keeps its full loudness to (unit_size; a shot's is 6)
const HEARD_TO := 150.0         ## metres a voice is heard to at all

static var _bank: Dictionary = {}
static var _loaded := false
static var _streams: Dictionary = {}   # file -> AudioStream
static var _active: Array[RogueVoice] = []

var _parts: Array = []   # [start, length] (a clip) or [-1, seconds] (a pause)
var _i := -1
var _end := 0.0
var _wait := 0.0
var _due := 0          # (ticks ms: when the clip should have finished, by the clock)


## Say `said` (Cast.say) out loud from critter `c`, if its line was voiced.
## Stops whatever it was already saying. Returns the voice, or null.
static func speak(c: Critter, said: Dictionary) -> RogueVoice:
	if c == null or not is_instance_valid(c) or c.visual == null or said.is_empty():
		return null
	var parts := plan(c.display_name, String(said.get("key", "")), said.get("fields", {}))
	if parts.is_empty():
		return null
	_active = _active.filter(func(v): return is_instance_valid(v) and not v.is_queued_for_deletion())
	for v in _active.duplicate():
		if v.get_parent() == c.visual:
			v.queue_free()
			_active.erase(v)
	if _active.size() >= MAX_AT_ONCE:
		return null
	var stream := _stream(String(_bank.rogues[c.display_name].file))
	if stream == null:
		return null
	var v := RogueVoice.new()
	v.stream = stream
	v.bus = &"Voice"
	# loud, and carrying: a taunt from across the field still reads over the
	# gunfire, only a little muffled by the distance
	v.volume_db = LOUDER_DB
	v.unit_size = CARRY
	v.max_distance = HEARD_TO
	v.attenuation_filter_cutoff_hz = 12000.0
	v.attenuation_filter_db = -10.0
	v._parts = parts
	c.visual.add_child(v)
	v.position = Vector3(0, c.visual.rig.world_head_top if c.visual.rig else 1.2, 0)
	_active.append(v)
	v._next()
	return v


## A line's parts, as stretches of the rogue's file ([start, length]) and
## pauses ([-1, seconds]); empty if the rogue or the line isn't voiced.
static func plan(rogue: String, key: String, fields: Dictionary) -> Array:
	var r: Dictionary = _load().get("rogues", {}).get(rogue, {})
	var out := []
	for step in steps(rogue, key, fields):
		if step is float:
			out.append([-1.0, step])
		elif r.clips.has(step):
			out.append(r.clips[step])
	# (a line whose words weren't all found isn't said at all)
	return out if out.any(func(p): return float(p[0]) >= 0.0) else []


## The clips a line is made of, in order (clip ids; a float is a pause).
static func steps(rogue: String, key: String, fields: Dictionary) -> Array:
	var bank := _load()
	if not bank.get("rogues", {}).has(rogue) or key == "":
		return []
	var out := []
	for step in [["t", "says"]] if key == "says" else bank.get("plans", {}).get(key, []):
		match String(step[0]):
			"t":
				out.append("says" if key == "says" else "t%d" % int(step[1]))
			"you":
				out.append("you:%s:%s" % [fields.get("you", ""), step[1]])
			"them":
				out.append("them:%s:%s" % [fields.get("them", ""), step[1]])
			"num":
				out.append("num:%d" % clampi(int(fields.get(String(step[1]), 0)), 0, NUM_MAX))
			"pause":
				out.append(float(step[1]))
	return out


## The clips of a line the rogue's file doesn't have (tests: none should be missing).
static func missing(rogue: String, key: String, fields: Dictionary) -> Array:
	var r: Dictionary = _load().get("rogues", {}).get(rogue, {})
	if r.is_empty():
		return ["(no voice for %s)" % rogue]
	var st := steps(rogue, key, fields)
	if st.is_empty():
		return ["(no line %s)" % key]
	return st.filter(func(s): return s is String and not r.clips.has(s))


static func _load() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(BANK):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BANK))
			if data is Dictionary:
				_bank = data
	return _bank


static func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := BANK.get_base_dir().path_join(file)
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


func _next() -> void:
	_i += 1
	if _i >= _parts.size():
		queue_free()
		return
	var p: Array = _parts[_i]
	if float(p[0]) < 0.0:
		stop()
		_wait = float(p[1])
		return
	_end = float(p[0]) + float(p[1])
	# (and by the clock, in case the audio isn't running: no sound device)
	_due = Time.get_ticks_msec() + int((float(p[1]) / maxf(AudioServer.playback_speed_scale, 0.1) + 0.3) * 1000.0)
	play(float(p[0]))


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_next()
	elif not playing or get_playback_position() >= _end or Time.get_ticks_msec() > _due:
		_next()


func _exit_tree() -> void:
	_active.erase(self)
