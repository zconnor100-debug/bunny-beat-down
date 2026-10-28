class_name DoppelRecorder
extends Node
## Watches you fight, for the Doppelbunny (DoppelData). A child of your
## critter in a match: every STEP seconds that an enemy is in sight
## (DoppelSense.SIGHT) it notes your situation at the start
## (DoppelSense.features) and what you did through it (DoppelSense.label:
## which way you moved against that enemy, and whether you sprinted,
## crouched, went prone, jumped, fired, healed, threw a grenade or swung the
## club). When the match is over (or you leave it) the moments go to
## DoppelData, which trains on them.

const STEP := 0.2

var match_manager: Node
var rows := PackedFloat32Array()     ## this match's moments so far
var _me: Critter
var _t := 0.0
var _start := PackedFloat32Array()   # the situation at the start of this moment ({} out of a fight)
var _enemy: Critter
var _moved := Vector3.ZERO
var _frames := 0
var _sprint := 0
var _flags := {}
var _hit_at := -100.0
var _clock := 0.0
var _done := false


func _ready() -> void:
	_me = get_parent() as Critter
	_me.damaged.connect(func(_info): _hit_at = _clock)
	Events.clover_eaten.connect(_on_clover)


func _on_clover(c: Node) -> void:
	if c == _me:
		_flags["heal"] = true


func _physics_process(delta: float) -> void:
	if _me == null or not _me.alive or _me.state != Critter.State.GROUND:
		_start = PackedFloat32Array()
		return
	_clock += delta
	if not _start.is_empty():
		# what you're doing this frame (the stick, in the world)
		_moved += Basis(Vector3.UP, _me.look_yaw) * Vector3(_me.move_input.x, 0.0, -_me.move_input.y)
		_frames += 1
		_sprint += 1 if _me.want_sprint else 0
		if _me.want_fire:
			_flags["fire"] = true
		if not _me.is_on_floor() and _me.velocity.y > 0.5:
			_flags["jump"] = true
		if _me.is_throwing():
			_flags["grenade"] = true
		if _me.is_swinging():
			_flags["melee"] = true
	_t += delta
	if _t < STEP:
		return
	_t = 0.0
	if not _start.is_empty() and _frames > 0 and is_instance_valid(_enemy) and _enemy.alive:
		_flags["sprint"] = _sprint * 2 > _frames
		_flags["crouch"] = _me.crouch_amount() > 0.5
		_flags["prone"] = _me.prone_amount() > 0.5
		rows.append_array(_start)
		rows.append_array(DoppelSense.label(_moved / _frames, _enemy.global_position - _me.global_position, _flags))
	# the next moment
	_enemy = DoppelSense.nearest_enemy(_me)
	_start = DoppelSense.features(_me, _enemy, match_manager, _clock - _hit_at) if _enemy else PackedFloat32Array()
	_moved = Vector3.ZERO
	_frames = 0
	_sprint = 0
	_flags = {}


## The match is over for you: what was seen goes to DoppelData (once).
func finish() -> void:
	if _done:
		return
	_done = true
	DoppelData.add_match(rows, not Settings.is_test_run())   # (tests train when they mean to)


func _exit_tree() -> void:
	finish()
