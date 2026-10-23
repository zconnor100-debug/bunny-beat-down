class_name Storm
extends Node3D
## The closing "Briar": a ring of thorny purple haze. Outside the safe circle
## critters take damage every second; each stage waits, then shrinks the
## circle toward a new centre inside the old one.

signal changed(stage: int, center: Vector2, radius: float, next_center: Vector2, next_radius: float, time_left: float, shrinking: bool)

## [wait seconds, shrink seconds, radius after shrinking, damage per second]
## Tuned for a match of about eight minutes: no 20-minute losses.
const STAGES := [
	[45.0, 30.0, 150.0, 1.0],
	[35.0, 28.0, 95.0, 2.0],
	[30.0, 24.0, 58.0, 4.0],
	[25.0, 20.0, 32.0, 7.0],
	[20.0, 18.0, 14.0, 10.0],
	[16.0, 16.0, 0.0, 15.0],
]
const MAX_MAP_PACE := 1.35          ## bigger maps get a little longer, not much

## Every match the Briar has a mood, with its own rule (announced at the start).
const VARIANTS := {
	"classic": {"title": "The Briar", "rule": "Stay inside the white circle."},
	"hungry": {"title": "The Hungry Briar", "rule": "Every new circle closes in on YOU."},
	"sticky": {"title": "The Sticky Briar", "rule": "Its thorns slow you to a crawl."},
	"bribable": {"title": "The Bribable Briar", "rule": "Munch a lucky clover in its thorns and it naps for 15 s."},
	"wandering": {"title": "The Wandering Briar", "rule": "The safe circle never stops drifting."},
	"sleepy": {"title": "The Sleepy Briar", "rule": "It waits longer, but its thorns bite twice as hard."},
	"bouncy": {"title": "The Bouncy Briar", "rule": "Its thorns bounce you sky-high."},
}
const STICKY_SLOW := 0.5
const BRIBE_NAP := 15.0
const WANDER_SPEED := 2.5           ## m/s the wandering circle creeps

var variant := "classic"
var player: Critter                 ## the Hungry Briar's favourite
var nap_left := 0.0                 ## the Bribable Briar is asleep for this long
const SHADER := preload("res://src/match/storm.gdshader")

var stage := 0
var center := Vector2.ZERO
var radius := 300.0
var next_center := Vector2.ZERO
var next_radius := 150.0
var dps := 1.0
var shrinking := false
var time_left := 0.0
var pace := 1.0
var active := false
var rng := RandomNumberGenerator.new()
var island: Island

var _from_center := Vector2.ZERO
var _from_radius := 0.0
var _tick := 0.0
var _wall: MeshInstance3D
var _k := 1.0
var _hum: AudioStreamPlayer3D


func start(island_: Island, start_radius: float, pace_ := 1.0, variant_ := "classic") -> void:
	island = island_
	pace = pace_
	variant = variant_ if VARIANTS.has(variant_) else "classic"
	if not Events.clover_eaten.is_connected(_on_clover_eaten):
		Events.clover_eaten.connect(_on_clover_eaten)
	# stages are tuned for a 215 m island: scale circle sizes with the island,
	# and give critters a little longer to cross the bigger map
	_k = island.terrain.island_radius / 215.0
	pace *= minf(sqrt(_k), MAX_MAP_PACE)
	rng.seed = island.seed_value * 31 + 7
	center = Vector2.ZERO
	radius = start_radius
	stage = 0
	_plan_next()
	time_left = _wait_of(0)
	shrinking = false
	active = true
	_build_wall()


## How long a stage waits before it shrinks (the Sleepy Briar dawdles).
func _wait_of(s: int) -> float:
	return float(STAGES[s][0]) * pace * (1.5 if variant == "sleepy" else 1.0)


func _on_clover_eaten(c: Node) -> void:
	var critter := c as Critter
	if active and variant == "bribable" and critter and not is_safe(critter.global_position) and nap_left <= 0.0:
		nap_left = BRIBE_NAP
		if critter.is_player:
			Events.announce.emit("YOU BRIBED THE BRIAR", "It's napping for %d seconds..." % int(BRIBE_NAP))


func _plan_next() -> void:
	var s: Array = STAGES[mini(stage, STAGES.size() - 1)]
	next_radius = s[2] * _k
	dps = s[3] * (2.0 if variant == "sleepy" else 1.0)
	# the Hungry Briar closes in on the player: as close to them as still fits
	if variant == "hungry" and player and is_instance_valid(player) and player.alive:
		var want := Vector2(player.global_position.x, player.global_position.z)
		var c := center + (want - center).limit_length(maxf(radius - next_radius, 0.0) * 0.9)
		if island.terrain.height_at(c.x, c.y) > 2.0 and c.length() <= island.terrain.island_radius * 0.8:
			next_center = c
			return
	# new centre: inside the current circle so the new one fits, nudged onto land
	var best := center
	for i in 30:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * maxf(radius - next_radius, 0.0) * 0.9
		var c := center + Vector2(cos(a), sin(a)) * d
		if c.length() > island.terrain.island_radius * 0.8:
			continue
		if island.terrain.height_at(c.x, c.y) > 2.0:
			best = c
			break
	next_center = best


func _process(delta: float) -> void:
	if not active:
		return
	if nap_left > 0.0:
		# bribed: the Briar naps (the clock stops, the circle holds still)
		nap_left -= delta
		_update_wall()
		changed.emit(stage, center, radius, next_center, next_radius, maxf(time_left, 0.0), shrinking)
		return
	time_left -= delta
	if variant == "wandering" and not shrinking:
		# creep toward where the next circle will be, a little at a time
		center = center.move_toward(next_center, WANDER_SPEED * delta)
	if shrinking:
		var s: Array = STAGES[stage]
		var t := 1.0 - clampf(time_left / (s[1] * pace), 0.0, 1.0)
		center = _from_center.lerp(next_center, t)
		radius = lerpf(_from_radius, next_radius, t)
	if time_left <= 0.0:
		if shrinking:
			shrinking = false
			center = next_center
			radius = next_radius
			stage += 1
			if stage >= STAGES.size():
				stage = STAGES.size() - 1
				time_left = 1e9
			else:
				_plan_next()
				time_left = _wait_of(stage)
		else:
			shrinking = true
			_from_center = center
			_from_radius = radius
			time_left = STAGES[stage][1] * pace
	_update_wall()
	changed.emit(stage, center, radius, next_center, next_radius, maxf(time_left, 0.0), shrinking)


func _physics_process(delta: float) -> void:
	if not active:
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	for c in get_tree().get_nodes_in_group(&"critters"):
		var critter := c as Critter
		if critter == null:
			continue
		var outside := critter.alive and critter.state == Critter.State.GROUND and not is_safe(critter.global_position)
		critter.slow_factor = STICKY_SLOW if outside and variant == "sticky" else 1.0
		if outside:
			var info := DamageInfo.make(dps, DamageInfo.Kind.STORM, null, &"storm")
			info.position = critter.get_chest_position()
			critter.take_damage(info)
			if variant == "bouncy" and critter.alive:
				critter.velocity.y = 11.0
			if critter.is_player:
				Audio.play(&"storm_damage_tick", -4.0, 0.02)


func is_safe(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(center) <= radius


## > 0 when a critter at `pos` should be heading inward now.
func threat(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var outside := p.distance_to(center) - radius
	if outside > -3.0:
		return outside + 3.0
	var next_out := p.distance_to(next_center) - next_radius
	if next_out > 0.0 and (shrinking or time_left < 25.0 * pace):
		return next_out
	return 0.0


func safe_point(pos: Vector3) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	var goal_c := next_center
	var goal_r := next_radius
	var dir := (goal_c - p)
	var d := dir.length()
	var target := goal_c if d < 1.0 else p + dir.normalized() * (d - goal_r * 0.55)
	return Vector3(target.x, island.terrain.height_at(target.x, target.y), target.y)


func _build_wall() -> void:
	_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_wall.mesh = cyl
	var m := ShaderMaterial.new()
	m.shader = SHADER
	_wall.material_override = m
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)


func _update_wall() -> void:
	if _wall == null:
		return
	# the crackle of the Briar comes from the nearest point of the wall
	var cam := get_viewport().get_camera_3d()
	if cam:
		if _hum == null:
			_hum = Audio.make_loop(&"storm_loop", self)
			if _hum:
				_hum.max_distance = 70.0
				_hum.play()
		if _hum:
			var c := Vector2(cam.global_position.x, cam.global_position.z)
			var d := (c - center)
			var edge := center + (d.normalized() if d.length() > 0.01 else Vector2.RIGHT) * radius
			_hum.global_position = Vector3(edge.x, cam.global_position.y, edge.y)
	var r := maxf(radius, 0.5)
	_wall.scale = Vector3(r, 160.0, r)
	_wall.global_position = Vector3(center.x, 60.0, center.y)
	(_wall.material_override as ShaderMaterial).set_shader_parameter(&"radius", r)
