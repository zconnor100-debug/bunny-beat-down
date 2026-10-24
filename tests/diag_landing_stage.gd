extends Node

var game: Node
var map := "toybox"
var opponents := 49
var seconds := 75.0
var _t := 0.0
var _done := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		map = a[0]
	if a.size() > 1:
		opponents = int(a[1])
	if a.size() > 2:
		seconds = float(a[2])
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"seed", 0, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"opponents", opponents, false)
	settings.set_value(&"quality", 1, false)
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	get_node("/root/Events").critter_died.connect(func(v, info):
		var ground: float = game.island.terrain.height_at(v.global_position.x, v.global_position.z)
		var who: String = info.attacker.display_name if info and info.attacker is Critter else "-"
		if info and info.attacker is Critter:
			who += " %.0fm" % (info.attacker as Critter).global_position.distance_to(v.global_position)
		print("DIED t=%.1f %s kind=%s by %s dmg=%.0f at %s (ground %.1f, %.1f above) vy=%.1f state_before=%s" % [_t, v.display_name,
			DamageInfo.Kind.keys()[info.kind] if info else "?", who, info.amount if info else 0.0, v.global_position.snapped(Vector3.ONE * 0.1), ground,
			v.global_position.y - ground, v.velocity.y, v.state]))


func _physics_process(delta: float) -> void:
	if game == null or game.get("match_manager") == null or (_t == 0.0 and game.match_manager.dropship == null):
		return   # (the plane flies off and is freed after the drop)
	var mm = game.match_manager
	if _t == 0.0:
		print("spawned %d critters (opponents setting %d), map %s" % [mm.critters.size(), opponents, map])
		mm.player_jump()
	_t += delta
	if int(_t / 5.0) != int((_t - delta) / 5.0):
		var states := {}
		for c in mm.critters:
			if is_instance_valid(c):
				states[c.state] = states.get(c.state, 0) + 1
			else:
				states[4] = states.get(4, 0) + 1   # (a corpse, despawned)
		print("t=%.0f wall=%.1fs fps=%d states %s dropship=%.2f" % [_t, Time.get_ticks_msec() / 1000.0, Engine.get_frames_per_second(), states, mm.dropship.progress if is_instance_valid(mm.dropship) else -1.0])
	if _t >= seconds and not _done:
		_done = true
		var states := {}
		var odd := []
		for c in mm.critters:
			var st: int = c.state
			states[st] = states.get(st, 0) + 1
			var ground: float = game.island.terrain.height_at(c.global_position.x, c.global_position.z)
			if st == 1 or st == 2 or st == 0 or c.global_position.y < ground - 2.0:
				odd.append("%s state=%d at %s ground=%.1f vel=%s alive=%s" % [c.display_name, st, c.global_position.snapped(Vector3.ONE * 0.1), ground, c.velocity.snapped(Vector3.ONE * 0.1), c.alive])
		print("after %.0f s: states %s (0 aboard, 1 freefall, 2 gliding, 3 ground, 4 dead), alive %d" % [_t, states, mm.alive_critters().size()])
		for o in odd.slice(0, 30):
			print("  ", o)
		get_tree().quit()
