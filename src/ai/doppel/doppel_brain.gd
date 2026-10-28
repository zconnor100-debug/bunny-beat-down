class_name DoppelBrain
extends AIBrain
## The Doppelbunny's brain. It's an AIBrain (it lands, loots, finds its way
## about, aims and shoots as every bot does) that fights the way you do:
## every DoppelRecorder.STEP of a fight it asks the network trained on your
## fights (DoppelNet, from DoppelData) what you would do now, and does it,
## picking by the network's odds so it isn't a machine: push in, hold, back
## off or circle round; sprint, crouch, go prone, jump; hold its fire, eat a
## clover, throw a grenade, swing the club. It comes in a Mirror Match on the
## Trail (Run), hunting you, and it never says a word. Your Habit Breaker boon
## fools it: just after you do something you rarely do, it can't read you and
## moves at random, with none of your tricks (DoppelRecorder.fooled).

const MOVE_STICK := [Vector2.ZERO, Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]   ## DoppelSense.MOVES, look-relative
const SHADER := preload("res://src/fx/mirror.gdshader")
const TAG_COLOR := Color(0.78, 0.9, 1.0)

var net: DoppelNet
var picked := {}                     ## how often it picked each move and flag (DoppelSense names)
var _move := 0
var _flags := {}
var _decide_t := 0.0
var _hit_at := -100.0
var _rng := RandomNumberGenerator.new()


## "Doppel-Bun": the name it goes by when you're playing `def`.
static func name_for(def: CritterDef) -> String:
	return "Doppel-%s" % def.display_name


## Make `c` look the part: a cracked mirror over everything it wears, and a
## cold silver name tag.
static func look(c: Critter) -> void:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	for mi in c.visual.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = m
	if c.visual.name_tag:
		c.visual.name_tag.text = "◇ %s" % c.display_name
		c.visual.name_tag.modulate = TAG_COLOR


func _ready() -> void:
	super._ready()
	_rng.randomize()
	me.damaged.connect(func(_info): _hit_at = _clock)


func _act(delta: float) -> void:
	me.want_prone = false   # (only while it's fighting the way you would)
	super._act(delta)


func _fight(delta: float) -> void:
	super._fight(delta)   # (finding, aiming and shooting, as any bot)
	if net == null or mode != Mode.FIGHT or target == null or not is_instance_valid(target) or me.current_weapon() == null:
		return
	_decide_t -= delta
	if _decide_t <= 0.0:
		_decide_t = DoppelRecorder.STEP
		_decide()
	if _clock - _last_seen_t < 0.35:   # (in sight; one it lost is chased along the paths, as any bot does)
		_play()


## What you would do now, by the network's odds.
func _decide() -> void:
	if _fooled():
		_move = _rng.randi() % DoppelNet.MOVES
		_flags = {}
		picked["fooled"] = int(picked.get("fooled", 0)) + 1
		return
	var p := net.predict(DoppelSense.features(me, target, match_manager, _clock - _hit_at))
	var roll := _rng.randf()
	_move = DoppelNet.MOVES - 1
	for o in DoppelNet.MOVES:
		roll -= p[o]
		if roll <= 0.0:
			_move = o
			break
	_flags = {}
	for i in DoppelSense.FLAGS.size():
		if _rng.randf() < p[DoppelNet.MOVES + i]:
			_flags[DoppelSense.FLAGS[i]] = true
	for what in [DoppelSense.MOVES[_move]] + _flags.keys():
		picked[what] = int(picked.get(what, 0)) + 1


## Your Habit Breaker boon has it fooled (DoppelRecorder.fooled).
func _fooled() -> bool:
	var you: Critter = target if target and target.is_player else (match_manager.player if match_manager else null)
	var rec := you.get_node_or_null("DoppelRecorder") as DoppelRecorder if you else null
	return rec != null and rec.fooled()


## Do it (the stick and buttons, as you would; the aim stays the bot's).
func _play() -> void:
	me.move_input = MOVE_STICK[_move]
	me.want_sprint = _flags.has("sprint") and _move != 0
	me.want_crouch = _flags.has("crouch")
	me.want_prone = _flags.has("prone")
	if not _flags.has("fire"):
		me.want_fire = false   # (it holds its fire when you would)
	if _flags.has("jump") and me.is_on_floor():
		me.want_jump = true
		_flags.erase("jump")   # (once a moment)
	if _flags.has("heal"):
		_flags.erase("heal")
		if me.inventory.clovers > 0 and me.health < me.max_health * 0.9:
			me.use_clover()
	if _flags.has("grenade"):
		_flags.erase("grenade")
		if me.can_throw() and (not target.is_player or _may_shoot_player()):
			var lob := _lob(me.throw_origin(), target.global_position)
			if lob != Vector3.ZERO:
				me.throw_grenade(lob)
	if _flags.has("melee"):
		var flat := Vector2(target.global_position.x - me.global_position.x, target.global_position.z - me.global_position.z).length()
		if flat < me.melee_reach() * 1.3 and not me.is_swinging():
			me.want_melee = true
			_flags.erase("melee")
