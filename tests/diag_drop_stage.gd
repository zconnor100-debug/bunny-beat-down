extends Node
## Diagnostic: runs real matches headless and logs (1) the player's state and
## height every 0.25 s around the drop and landing, and (2) critters that keep
## trying to move but don't (stuck in rocks/logs).
##   godot --headless --path . -s tests/diag_drop.gd -- <seed> <jump_after_s>

var seed_value := 1234
var jump_after := 3.0
var game: Node
var _t := 0.0
var _jumped := false
var _log_until := 1e9
var _prev_state := -1
var _last_pos: Dictionary = {}
var _reported: Dictionary = {}
var _landed_at := -1.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seed_value = int(a[0])
	if a.size() > 1:
		jump_after = float(a[1])
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"seed", seed_value, false)
	settings.set_value(&"opponents", 23, false)
	settings.set_value(&"quality", 0, false)
	Engine.time_scale = 2.0
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)


func _physics_process(delta: float) -> void:
	if game == null or game.get("match_manager") == null:
		return
	var mm = game.match_manager
	if mm.player == null:
		return
	_t += delta
	var p = mm.player
	if not _jumped and _t > jump_after:
		mm.player_jump()
		_jumped = true
		print("t=%.2f JUMP from y=%.1f" % [_t, p.global_position.y])
	if p.state != _prev_state:
		print("t=%.2f player state %s -> %s at %s (floor=%s)" % [_t, _prev_state, p.state, p.global_position.snapped(Vector3.ONE * 0.1), p.is_on_floor()])
		if p.state == 3 and _landed_at < 0.0:
			_landed_at = _t
			_log_until = _t + 20.0
		_prev_state = p.state
	if _landed_at >= 0.0 and _t < _log_until and int(_t * 4) != int((_t - delta) * 4):
		var ground: float = game.island.terrain.height_at(p.global_position.x, p.global_position.z)
		print("  t=%.2f y=%.2f ground=%.2f vy=%.2f floor=%s state=%d" % [_t, p.global_position.y, ground, p.velocity.y, p.is_on_floor(), p.state])
	# stuck critters: sampled once a second; over the last 6 s they wanted to
	# move most of the time yet ended up less than 1 m from where they started
	if int(_t) != int(_t - delta):
		for c in mm.critters:
			if not is_instance_valid(c) or not c.alive or c.state != 3:
				continue
			var hist: Array = _last_pos.get(c, [])
			hist.append([c.global_position, c.move_input.length() > 0.3])
			if hist.size() > 21:
				hist.pop_front()
			_last_pos[c] = hist
			var wanting := 0
			for hs in hist:
				if hs[1]:
					wanting += 1
			var fighting: bool = c.has_node("AIBrain") and c.get_node("AIBrain").mode == 3
			var spread := 0.0   # a round trip that ends where it started isn't stuck
			for hs in hist:
				spread = maxf(spread, (hs[0] as Vector3).distance_to(hist[0][0]))
			if hist.size() == 21 and wanting >= 18 and not fighting and spread < 5.0 and not _reported.has(c):
				_reported[c] = _t
				var pos: Vector3 = c.global_position
				var near := []
				for n in game.island.scatter.get_children():
					if n is Node3D and n.scene_file_path != "" and pos.distance_to(n.global_position) < 8.0:
						near.append("%s@%.1fm" % [n.scene_file_path.get_file().get_basename(), pos.distance_to(n.global_position)])
				var nrm: Vector3 = game.island.terrain.normal_at(pos.x, pos.z)
				var ground: float = game.island.terrain.height_at(pos.x, pos.z)
				print("STUCK t=%.0f %s at %s ground=%.2f slope=%.0f° swim=%s rescues=%d mode=%s near %s" % [_t, c.display_name, pos.snapped(Vector3.ONE * 0.1),
					ground, rad_to_deg(acos(clampf(nrm.y, -1, 1))), c.swimming, c.rescues,
					c.get_node("AIBrain").mode if c.has_node("AIBrain") else "player", near])
	# follow flagged critters for a while to see what they are doing
	if int(_t) != int(_t - delta):
		for c in _reported:
			if is_instance_valid(c) and c.alive and _t - float(_reported[c]) < 12.0:
				var b = c.get_node_or_null("AIBrain")
				var lg = b.get("_loot_goal") if b else null
				print("   follow %s t=%.0f pos=%s vel=%s input=%.2f floor=%s wall=%s stuck_t=%.1f prog_t=%.1f mode=%s dest=%s goal=%s" % [c.display_name, _t,
					c.global_position.snapped(Vector3.ONE * 0.1), c.get_real_velocity().snapped(Vector3.ONE * 0.1), c.move_input.length(),
					c.is_on_floor(), c.is_on_wall(), c.get("_stuck_t"), b.get("_progress_t") if b else -1.0, b.mode if b else -1,
					(b.get("_dest") as Vector3).snapped(Vector3.ONE * 0.1) if b else "-",
					("%s@%.1fm" % [lg.name, lg.global_position.distance_to(c.global_position)]) if lg and is_instance_valid(lg) else "none"])
	if _t > 240.0:
		var rescued := 0
		for c in mm.critters:
			if is_instance_valid(c):
				rescued += int(c.rescues)
		print("stuck total: %d of %d (rescues %d)" % [_reported.size(), mm.critters.size(), rescued])
		get_tree().quit()
