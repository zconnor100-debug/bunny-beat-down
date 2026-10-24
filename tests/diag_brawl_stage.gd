extends Node
## Diagnostic: how often bots fight each other. Runs a full 49-bot match
## headless (the player jumps and can't be hurt) and every second counts
## bots fighting bots, and "standoffs": a bot on the ground, after it settled
## in, fighting no one, looking right at another bot within
## AIBrain.BOT_FIGHT_RANGE that it's sure of and that isn't after it either,
## and leaving it be (what reads as bots in factions), split by why (one broke
## off from the other, or nothing). Also logs the death toll over time.

var map := "island"
var seed_value := 1234
var seconds := 240.0
var game: Node
var _t := 0.0
var _next := 1.0
var _deaths := 0
var _bot_kills := 0
var _standoff_s := 0
var _fight_s := 0
var _broke_off_s := 0   # standoff seconds explained by a break-off
var _pairs := {}        # standoff pairs ever seen
var _fought := {}       # pairs that ever fought


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		map = a[0]
	if a.size() > 1:
		seed_value = int(a[1])
	if a.size() > 2:
		seconds = float(a[2])
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"seed", seed_value, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"opponents", 49, false)
	settings.set_value(&"quality", 0, false)
	GameSession.quick = true
	Engine.time_scale = 3.0
	Events.critter_died.connect(_on_died)
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)


func _on_died(_victim: Node, info: DamageInfo) -> void:
	_deaths += 1
	if info and info.attacker is Critter and not (info.attacker as Critter).is_player:
		_bot_kills += 1


func _physics_process(delta: float) -> void:
	if game == null or game.get("match_manager") == null:
		return
	var mm = game.match_manager
	if mm.player == null or mm.phase == MatchManager.Phase.LOADING:
		return
	if mm.phase == MatchManager.Phase.DROPPING and mm.player.state == Critter.State.IN_DROPSHIP:
		mm.player_jump()
	# the player can't die (bots still come for it): the count is about bots
	if mm.player.state == Critter.State.GROUND:
		mm.player.health = mm.player.max_health
	_t += delta
	if _t < _next:
		return
	_next += 1.0
	var bots := []
	for c in mm.critters:
		if is_instance_valid(c) and c.alive and not c.is_player and c.state == Critter.State.GROUND:
			bots.append(c)
	var fighting := 0
	var standoffs := 0
	for b in bots:
		var brain: AIBrain = b.get_node_or_null("AIBrain")
		if brain == null:
			continue
		if brain.target and not brain.target.is_player:
			fighting += 1
			_fought[_pair(b, brain.target)] = true
		if brain.target or brain.settling():
			continue
		var eye: Vector3 = b.get_eye_position()
		var fwd: Vector3 = b.look_direction()
		var space: PhysicsDirectSpaceState3D = b.get_world_3d().direct_space_state
		for o in bots:
			if o == b or b.global_position.distance_to(o.global_position) > AIBrain.BOT_FIGHT_RANGE:
				continue
			if brain.awareness_of(o) < 1.0:
				continue
			var to: Vector3 = o.get_chest_position() - eye
			if to.length() > 10.0 and to.normalized().dot(fwd) < AIBrain.FOV_DOT:
				continue   # (not looking its way right now)
			if brain._visibility_of(o, eye, space, mm.island.scatter) < 0.02:
				continue   # (can't see it right now)
			var their: AIBrain = o.get_node_or_null("AIBrain")
			if their and their.target == b:
				continue
			standoffs += 1
			if (brain._clock < float(brain._avoid.get(o, -1.0)) or (their and their._clock < float(their._avoid.get(b, -1.0)))):
				_broke_off_s += 1
			_pairs[_pair(b, o)] = true
	_standoff_s += standoffs
	_fight_s += fighting
	if int(_t) % 10 == 0:
		print("t=%3ds alive %2d deaths %2d (bots %2d)  fighting bots %2d  standoffs %2d" % [int(_t), mm.alive_critters().size(), _deaths, _bot_kills, fighting, standoffs])
	if _t >= seconds or mm.phase == MatchManager.Phase.ENDED:
		var peaceful := 0
		for p in _pairs:
			if not _fought.has(p):
				peaceful += 1
		print("BRAWL %s seed %d %.0fs: deaths %d (bots %d), bot-fight-seconds %d, standoff-seconds %d (%d after a break-off), pairs that met and never fought %d of %d" % [
			map, seed_value, _t, _deaths, _bot_kills, _fight_s, _standoff_s, _broke_off_s, peaceful, _pairs.size()])
		Engine.time_scale = 1.0
		get_tree().quit()


func _pair(a: Node, b: Node) -> String:
	var x := a.get_instance_id()
	var y := b.get_instance_id()
	return "%d-%d" % [mini(x, y), maxi(x, y)]
