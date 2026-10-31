class_name StarfallMission
extends MissionDirector
## The Kernel Hunt's Finale, "The Starfall" (KernelHunt), on Wildwood Island
## by night. The Briar came up through the bedding in the hamster cage and
## took the three Kernels, down through its roots, under the lake, home to
## where the Acorn fell: Boulder Bluff, glowing gold-green over the island
## all night. The Barn Rangers start at the Big Red Barn. In parts, one
## after another (`step`):
##
## ROOTS: three of the Briar's taproots have broken up out of the island
##   round the Barn's side of the Bluff (BriarRoot), carrying the Kernels'
##   light up to it. Break the knot of each, where it came up (a blast does it
##   the most harm; you start with grenades, and a crate brings more and a
##   rocket launcher), while the Touched grow up out of the ground round it.
## BRIAR: the roots cut, it calls up the Briar: its wall comes up round the
##   Bluff (Storm.close_on) and closes in, the Touched pouring down off the
##   Bluff to stop you, and the Warren answers (the rogues of Acts I and II,
##   gliding down to fight with you). Get inside before it shuts.
## WAKE: the ring shut round you, Boulder Bluff heaves, and the Briar Heart
##   comes up out of it (BriarHeart: its arrival, BossIntro). Break its pods,
##   its Kernels fly free; split open, it closes the Briar in tighter. Beat it
##   and the ending (StarfallOutro): the Starfall Acorn whole again, going home.
##
## Go down yourself, or lose everyone on your side, and it's over.

enum Step { ROOTS, BRIAR, WAKE, BOSS, DONE }

const ROOTS := 3
const ROOT_OUT := 100.0        ## metres from the Heart its roots' knots come up...
const ROOT_SPREAD := 70.0      ## ...this many degrees apart, round the Barn's side of the Bluff
const ROOT_END := 20.0         ## metres from the Heart they go under the Bluff
const GUARDS := 3              ## Touched round each knot to start with (Scrappy; COUNT_SCALE)
const SPROUT_GUNS := [&"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_pistol"]
const RUSH_GUNS := [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun", &"carrot_lmg"]
const RUSH := 7                ## the Touched pouring off the Bluff as the Briar closes (Scrappy)
const BRIAR_FROM := 45.0       ## metres outside the furthest of you its wall comes up
const ARENA := 62.0            ## its ring round the Heart, closed: the fight's...
const ARENA_LAST := 44.0       ## ...and tighter once it's split open
const CLOSE_FOR := 42.0        ## seconds the Briar takes to close
const BRIAR_DPS := 5.0
const WAKE_ANYWAY := 14.0      ## seconds after it's shut that the Heart comes up, inside or not
const HEAVE := 3.0
const SPROUT_EVERY := 22.0     ## the Touched growing up inside the ring while it fights...
const SPROUT := 2              ## ...this many at a time (Scrappy; COUNT_SCALE)...
const SPROUT_MOST := 6         ## ...this many of them up at once, at most
const ANSWER_AFTER := 5.0      ## seconds into the Briar closing that the Warren answers
const OUTRO_AFTER := 4.6       ## seconds after the Heart's down that the ending starts
const GRENADES := 3
const BEAM_HEIGHT := 150.0

var step := Step.ROOTS
var roots: Array[BriarRoot] = []
var heart_pos := Vector3.ZERO  ## where the Briar Heart comes up: the top of Boulder Bluff
var answered: Array[Critter] = []
var lighting: WorldLighting
var _start := Vector3.ZERO
var _shut_t := -1.0
var _heave_t := -1.0
var _down_t := -1.0
var _sprout_t := 12.0
var _sprouts: Array[Critter] = []
var _beam: MeshInstance3D
var _glow: OmniLight3D
var _said_pods := 0


func _init() -> void:
	super._init()
	mission = "starfall"


## The island by night: the Barn (where you start), Boulder Bluff (cleared
## where the Heart comes up), the three roots; the rangers, and the Heart,
## waiting under the Bluff.
func setup(mm: MatchManager) -> void:
	match_manager = mm
	island = mm.island
	_rng.seed = mm.rng.seed * 11 + 43
	var barn_poi := _poi("Big Red Barn", "barn")
	barn_pos = _ground(barn_poi.get("center", Vector2(260, -130)))
	if not barn_poi.is_empty() and not (barn_poi.buildings as Array).is_empty():
		barn_building = barn_poi.buildings[0]
		barn_pos = barn_building.global_position
	var bluff := _poi("Boulder Bluff", "boulders")
	bluff_pos = _ground(bluff.get("center", Vector2(145, 10)))
	heart_pos = bluff_pos
	var patch := _poi("Carrot Patch", "carrot_patch")
	patch_pos = _ground(patch.center) if not patch.is_empty() else heart_pos
	for n in KernelHunt.RANGERS:
		_spawn_ranger(n)
	_clear_bluff()
	_lay_roots()
	mm._make_boss()
	_beam_up()


func wants_boss() -> bool:
	return true


func boss_script() -> String:
	return "res://src/bosses/briar_heart.gd"


func tune_lighting(l: WorldLighting) -> void:
	lighting = l
	l.make_night()


## The woods by night: crickets.
func ambience() -> StringName:
	return &"night_loop"


## Where the camera looks as it starts: the Bluff, glowing.
func facing() -> Vector3:
	return heart_pos + Vector3.UP * 30.0


## The rocks and trees on top of Boulder Bluff round where the Heart's to come
## up (it would come up through them, and they'd hide it going home): gone.
func _clear_bluff() -> void:
	if island == null or island.scatter == null:
		return
	for n in island.scatter.get_children():
		var prop := n as Node3D
		if prop and _flat(prop.global_position - heart_pos).length() < 21.0:
			prop.queue_free()


## The three roots: their knots round the Barn's side of the Bluff, each
## root running from its knot to the foot of the Bluff.
func _lay_roots() -> void:
	var toward := _flat(barn_pos - heart_pos).normalized()
	if toward.length() < 0.5:
		toward = Vector3.FORWARD
	for i in ROOTS:
		var dir := toward.rotated(Vector3.UP, deg_to_rad(ROOT_SPREAD * (i - 1)))
		var want := heart_pos + dir * ROOT_OUT
		var at := want
		if island:
			var spot := island.clear_loot_spot(_ground(Vector2(want.x, want.z)), Vector3(BriarRoot.KNOT_R, BriarRoot.KNOT_R, BriarRoot.KNOT_R))
			if spot == Vector3.INF:
				spot = island.random_land_point(2.0, Vector2(want.x, want.z), 14.0)
			at = spot if spot != Vector3.INF else want
		at = _ground(Vector2(at.x, at.z))
		var end := heart_pos + _flat(at - heart_pos).normalized() * ROOT_END
		var path := VineMesh.wandering(at, end, _rng, 2.0, 7.0, 2.5)
		for k in path.size():
			path[k] = _ground(Vector2(path[k].x, path[k].z))
		var root := BriarRoot.new(match_manager._difficulty, _rng.randi())
		root.path = path
		root.position = at
		match_manager.world_root.add_child(root)
		root.global_position = at
		root.sprouted.connect(_sprouted.bind(root))
		root.cut.connect(_on_cut)
		roots.append(root)


## The Bluff's light, going up into the night (it's seen from all over the
## island), and lighting the Bluff.
func _beam_up() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "BluffGlow"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 9.0
	cyl.bottom_radius = 4.0
	cyl.height = BEAM_HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(StarfallKernel.GLOW, 0.0))
	g.add_point(0.8, Color(StarfallKernel.GLOW, 0.12))
	g.set_color(1, Color(StarfallKernel.GLOW, 0.3))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	mat.albedo_texture = gt
	cyl.material = mat
	_beam.mesh = cyl
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match_manager.world_root.add_child(_beam)
	_beam.global_position = heart_pos + Vector3.UP * (BEAM_HEIGHT * 0.5 - 2.0)
	_glow = OmniLight3D.new()
	_glow.light_color = StarfallKernel.GLOW
	_glow.omni_range = 60.0
	_glow.light_energy = 2.2
	_glow.shadow_enabled = false
	match_manager.world_root.add_child(_glow)
	_glow.global_position = heart_pos + Vector3.UP * 8.0


## You and the rangers out of the Barn's yard, facing the Bluff; Touched
## round every knot.
func begin() -> void:
	var fwd := _flat(heart_pos - barn_pos).normalized()
	_start = _ground_at(barn_pos + fwd * 24.0)
	var side := fwd.cross(Vector3.UP)
	for i in rangers.size():
		var r := rangers[i]
		r.place_at(_ground_at(_start - fwd * 4.5 + side * ((i - (rangers.size() - 1) * 0.5) * 2.6)), atan2(-fwd.x, -fwd.z))
		_follow(r)
	_arm_player(_start, atan2(-fwd.x, -fwd.z))
	var p := match_manager.player
	if p:
		p.inventory.grenades = maxi(p.inventory.grenades, GRENADES)
	stage = Stage.WAVE
	step = Step.ROOTS
	_t = 0.0
	var n := maxi(1, roundi(GUARDS * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	for root in roots:
		for k in n:
			var a := TAU * k / n + _rng.randf_range(-0.4, 0.4)
			var post := _ground_at(root.global_position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(7.0, 14.0))
			root.sprouts.append(_spawn_touched(post, SPROUT_GUNS[_rng.randi() % SPROUT_GUNS.size()], false, post, _start + Vector3.UP))
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	match_manager._set_phase(MatchManager.Phase.PLAYING)
	get_tree().create_timer(4.0, false).timeout.connect(func(): _shout("st", 0, _keeper()))
	get_tree().create_timer(9.5, false).timeout.connect(func(): _shout("sr", 0))
	get_tree().create_timer(14.0, false).timeout.connect(func(): _shout("sr", 1, _keeper()))
	get_tree().create_timer(16.0, false).timeout.connect(_drop_crate_by_you)


func _process(delta: float) -> void:
	_tend_glow()
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING:
		return
	_clock += delta
	_t += delta
	match step:
		Step.BRIAR:
			_tend_briar(delta)
		Step.WAKE:
			_heave(delta)
		Step.BOSS:
			_tend_sprouts(delta)
		Step.DONE:
			if _down_t >= 0.0:
				_down_t += delta
				if _down_t >= OUTRO_AFTER and stage != Stage.OUTRO:
					stage = Stage.OUTRO
					_play_outro()


## The night sky glows over the Bluff, wherever you look from.
func _tend_glow() -> void:
	if lighting == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to := heart_pos - cam.global_position
		lighting.glow_toward(to, 0.0 if step == Step.DONE else clampf(1.2 - _flat(to).length() / 600.0, 0.3, 1.0))


# ---- the roots ---------------------------------------------------------------------------------

## A crate down by you: grenades, and a launcher (a blast does the knots the
## most harm).
func _drop_crate_by_you() -> void:
	if step != Step.ROOTS:
		return
	var p := match_manager.player
	var by := p.global_position if p and p.alive else _start
	var out := _flat(heart_pos - by).normalized()
	var at := island.random_land_point(2.0, Vector2(by.x + out.x * 12.0, by.z + out.z * 12.0), 8.0) if island else by
	var spot := at if at != Vector3.INF else by
	var drop := SupplyDrop.new()
	drop.landing = spot
	drop.rng.seed = _rng.randi()
	var rockets := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), Rarity.Tier.PRIZE)
	drop.contents = [Pickup.grenade_spec(4), Pickup.weapon_spec(rockets),
		Pickup.ammo_spec(rockets.data.ammo_type, Inventory.AMMO_PICKUP[rockets.data.ammo_type] * 3)]
	match_manager.world_root.add_child(drop)
	drop.global_position = spot + Vector3.UP * 70.0
	Events.supply_drop_incoming.emit(spot)
	Events.headline.emit("A crate's coming down: grenades, and a rocket launcher. Blasts do the knots the most harm.")


## One of the Touched grows up out of the ground by a root's knot.
func _sprouted(at: Vector3, root: BriarRoot) -> void:
	if step != Step.ROOTS or root.broken:
		return
	var c := _grow_touched(_ground_at(at), _ground_at(root.global_position + _flat(at - root.global_position).normalized() * 9.0))
	if c:
		root.sprouts.append(c)
	if _say_ok("ss"):
		_shout("ss", 0)


## One of the Touched, growing up out of the ground at `at` (thorny shoots,
## dirt thrown up), to hold `post`.
func _grow_touched(at: Vector3, post: Vector3) -> Critter:
	BossFX.dust(at, 3.0, Color(0.3, 0.24, 0.22, 0.7))
	FX.burst(at + Vector3.UP * 0.6, Vector3.UP, {"amount": 14, "lifetime": 1.4, "speed": Vector2(1.0, 4.0), "spread": 50.0,
		"gravity": -0.3, "size": 0.25, "scale": Vector2(0.6, 1.4), "color": Color(StarfallKernel.GLOW, 0.8), "fade": true,
		"additive": true, "damping": 1.5, "aabb": 10.0})
	Audio.play_at(&"root_burst", at, -6.0, 0.15, {"max_distance": 160.0, "unit_size": 12.0})
	var p := match_manager.player
	var watch := p.global_position + Vector3.UP if p and p.alive else heart_pos
	var c := _spawn_touched(at, SPROUT_GUNS[_rng.randi() % SPROUT_GUNS.size()], false, post, watch)
	if c:
		Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	return c


func _on_cut(_by: Node) -> void:
	var left := roots.filter(func(r): return not r.broken).size()
	if left > 0:
		Events.announce.emit("%d OF %d ROOTS CUT" % [roots.size() - left, roots.size()], "The light's stopped in that one. %s." % ("One to go" if left == 1 else "%d to go" % left))
		_shout("sc", 0)
		return
	Events.announce.emit("ALL THREE ROOTS CUT", "It's starving. And the ground's shaking...")
	_shout("sc", 0)
	get_tree().create_timer(3.0, false).timeout.connect(_start_briar)


# ---- the Briar ---------------------------------------------------------------------------------

## The Briar comes up round the Bluff and closes in; the Touched come down
## off it at you, and the Warren answers.
func _start_briar() -> void:
	if step != Step.ROOTS:
		return
	step = Step.BRIAR
	_t = 0.0
	var far := ARENA + 60.0
	for c in [match_manager.player] + rangers:
		if is_instance_valid(c) and (c as Critter).alive:
			far = maxf(far, _flat((c as Critter).global_position - heart_pos).length())
	match_manager.storm.close_on(island, Vector2(heart_pos.x, heart_pos.z), far + BRIAR_FROM, ARENA, CLOSE_FOR, BRIAR_DPS)
	match_manager.storm.dim(0.5)   # (by night)
	Events.announce.emit("THE BRIAR IS CLOSING IN", "Get inside it before it shuts: onto Boulder Bluff.")
	Audio.play_at(&"root_burst", heart_pos, 12.0, 0.0, {"max_distance": 3000.0, "unit_size": 120.0})
	var p := match_manager.player
	if p:
		Events.explosion.emit(p.global_position + _flat(heart_pos - p.global_position).normalized() * 30.0, 8.0)
	_shout("sb", 0, _keeper())
	get_tree().create_timer(6.0, false).timeout.connect(func(): _shout("sb", 1))
	_rush()
	get_tree().create_timer(ANSWER_AFTER, false).timeout.connect(_answer)


## The Touched pour down off the Bluff, between you and it.
func _rush() -> void:
	var p := match_manager.player
	var you := p.global_position if p and p.alive else _start
	var to_you := _flat(you - heart_pos).normalized()
	var n := maxi(3, roundi(RUSH * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	for k in n:
		var a := _rng.randf_range(-0.9, 0.9)
		var from := _ground_at(heart_pos + to_you.rotated(Vector3.UP, a) * _rng.randf_range(24.0, 34.0))
		var post := _ground_at(heart_pos + to_you.rotated(Vector3.UP, a * 0.8) * _rng.randf_range(38.0, 54.0))
		_spawn_touched(from, RUSH_GUNS[_rng.randi() % RUSH_GUNS.size()], false, post, you + Vector3.UP)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)


## The Warren answers: the rogues who came for Brutus, and the ones you
## unwound in the toy room, gliding down round you.
func _answer() -> void:
	if step != Step.BRIAR and step != Step.WAKE:
		return
	var p := match_manager.player
	var round_ := p.global_position if p and p.alive else _start
	var names: Array = KernelHunt.ANSWER + KernelHunt.WOUND
	for i in names.size():
		var a := TAU * i / names.size() + _rng.randf_range(-0.3, 0.3)
		var land := _ground_at(round_ + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(12.0, 24.0))
		var c := _spawn_ranger(String(names[i]))
		rangers.erase(c)   # (they aren't the Barn's: the report counts the rangers)
		answered.append(c)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.drop_spot = land
		c.begin_freefall(land + Vector3(cos(a), 0.0, sin(a)) * 25.0 + Vector3.UP * 70.0, Vector3.ZERO)
	Events.announce.emit("THE WARREN ANSWERS", "%d rogues saw the Bluff's light from across the island, and came." % names.size())
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	get_tree().create_timer(3.0, false).timeout.connect(func():
		if not answered.is_empty() and is_instance_valid(answered[0]) and answered[0].alive:
			_shout("sw", 0, answered[0]))


## The Briar shut round you: the Bluff heaves (or, inside or out, it comes
## up anyway a while later).
func _tend_briar(delta: float) -> void:
	var storm := match_manager.storm
	if storm.shrinking:
		return
	_shut_t = 0.0 if _shut_t < 0.0 else _shut_t + delta
	var p := match_manager.player
	var inside := p != null and p.alive and storm.is_safe(p.global_position)
	if inside or _shut_t >= WAKE_ANYWAY:
		step = Step.WAKE
		_t = 0.0
		_heave_t = 0.0
		Events.announce.emit("THE BRIAR HAS SHUT", "Nobody's getting out now. And Boulder Bluff is moving...")


func _heave(delta: float) -> void:
	if _heave_t < 0.0:
		return
	_heave_t += delta
	if fmod(_heave_t, 0.45) < delta:
		BossFX.dust(heart_pos + Vector3(_rng.randf_range(-9, 9), 0.0, _rng.randf_range(-9, 9)), 6.0, Color(0.32, 0.27, 0.24, 0.7))
		Events.explosion.emit(heart_pos, 4.0)
	if _heave_t >= HEAVE:
		_heave_t = -1.0
		_wake()


## It comes up out of the Bluff.
func _wake() -> void:
	step = Step.BOSS
	_t = 0.0
	_sprout_t = SPROUT_EVERY * 0.6
	for r in rangers + answered:
		if is_instance_valid(r) and r.alive:
			var brain := r.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.release()
	var heart := match_manager.boss as BriarHeart
	if heart:
		heart.pod_opened.connect(_on_pod_opened)
		heart.pod_broken.connect(_on_pod_broken)
		heart.opened.connect(_on_heart_opened)
	if _beam:
		var tw := create_tween()
		tw.tween_property(_beam, "scale", Vector3(0.2, 1.0, 0.2), 2.0)
		tw.tween_callback(_beam.hide)
	match_manager.release_boss(heart_pos)


func _on_pod_opened(_i: int) -> void:
	if _said_pods < 2 or _say_ok("sq"):
		_said_pods += 1
		_shout("sq", 0)


func _on_pod_broken(_i: int) -> void:
	get_tree().create_timer(0.8, false).timeout.connect(func(): _shout("sp", 0))


## Split open: the Briar closes in tighter round it.
func _on_heart_opened() -> void:
	get_tree().create_timer(1.6, false).timeout.connect(func(): _shout("so", 0, _keeper()))
	match_manager.storm.close_on(island, Vector2(heart_pos.x, heart_pos.z), ARENA, ARENA_LAST, 20.0, BRIAR_DPS * 1.6)


## The Touched keep growing up inside the ring while it fights (never right
## by you).
func _tend_sprouts(delta: float) -> void:
	_sprout_t -= delta
	if _sprout_t > 0.0:
		return
	_sprout_t = SPROUT_EVERY
	_sprouts = _sprouts.filter(func(c): return is_instance_valid(c) and c.alive)
	var n := mini(SPROUT_MOST - _sprouts.size(), maxi(1, roundi(SPROUT * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)]))))
	var p := match_manager.player
	for k in n:
		for tries in 8:
			var a := _rng.randf() * TAU
			var at := _ground_at(heart_pos + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(24.0, ARENA - 8.0))
			if p and p.alive and _flat(at - p.global_position).length() < 14.0:
				continue
			var c := _grow_touched(at, at)
			if c:
				_sprouts.append(c)
			break


# ---- the end ------------------------------------------------------------------------------------------

func critter_down(c: Critter, info: DamageInfo) -> void:
	super.critter_down(c, info)
	if c == match_manager.player and stage != Stage.OVER and stage != Stage.OUTRO:
		end(false)


## Its heart's stopped: the Briar withers where it stands.
func boss_down(_by: Node) -> void:
	if step == Step.DONE:
		return
	step = Step.DONE
	_down_t = 0.0
	match_manager.storm.wither(5.0)


func play_outro(rig: CameraRig = null, hud: CanvasLayer = null, pc: PlayerController = null) -> MissionCinematic:
	_outro = StarfallOutro.new(self, rig, hud, pc)
	_outro.finished.connect(func(): end(true))
	add_child(_outro)
	return _outro


# ---- the bar on the HUD, the report -----------------------------------------------------------------

func bar_title() -> String:
	match step:
		Step.ROOTS:
			return "THE BRIAR'S ROOTS"
		Step.WAKE:
			return "BOULDER BLUFF"
	return "THE BRIAR"


func bar_fill() -> float:
	match step:
		Step.ROOTS:
			return float(roots.filter(func(r): return r.broken).size()) / maxf(1.0, roots.size())
		Step.BRIAR:
			var s := match_manager.storm
			return clampf(1.0 - s.time_left / CLOSE_FOR, 0.0, 1.0) if s.shrinking else 1.0
	return 1.0


func bar_color() -> Color:
	return StarfallKernel.GLOW if step == Step.ROOTS else Color(0.62, 0.3, 0.85)


func bar_status() -> String:
	var p := match_manager.player
	match step:
		Step.ROOTS:
			var left := roots.filter(func(r): return not r.broken)
			var near := INF
			for r in left:
				near = minf(near, _flat((r as Node3D).global_position - p.global_position).length() if p else INF)
			var cut := roots.size() - left.size()
			return "%d of %d cut  ·  break the knots  ·  %d m" % [cut, roots.size(), roundi(near)] if near < INF \
				else "%d of %d cut" % [cut, roots.size()]
		Step.BRIAR:
			var s := match_manager.storm
			if p == null:
				return ""
			if not s.shrinking:
				return "It's shut round the Bluff" if s.is_safe(p.global_position) else "IT'S SHUT  ·  GET INSIDE!"
			return "Get inside before it shuts  ·  %s  ·  %d m to the Bluff" % [MissionBar._mmss(s.time_left), roundi(_flat(heart_pos - p.global_position).length())]
		Step.WAKE:
			return "THE BLUFF IS MOVING!"
	return "THE BRIAR HEART IS DOWN!" if step == Step.DONE else ""


func bar_warn() -> bool:
	var p := match_manager.player
	return step == Step.WAKE or (step == Step.BRIAR and p != null and not match_manager.storm.is_safe(p.global_position))


func bar_good() -> bool:
	return step == Step.DONE


func bar_shown() -> bool:
	return step in [Step.ROOTS, Step.BRIAR, Step.WAKE]


func report() -> Dictionary:
	var r := super.report()
	r.erase("barn")
	r.erase("wave")
	r["cut"] = roots.filter(func(x): return x.broken).size()
	r["roots"] = roots.size()
	r["step"] = Step.keys()[step].to_lower()
	r["answered"] = answered.size()
	var heart := match_manager.boss as BriarHeart
	if heart:
		r["boss_time"] = heart.fight_time()
		r["kernels"] = heart.kernels.size()
		r["pods_left"] = heart.pods_left()
	return r


func news(r: Dictionary) -> Array:
	return WarrenSim.starfall_news(r)


func lost_text() -> String:
	return "There's nobody left to stop the Briar."


func opening() -> Array:
	return ["CUT THE BRIAR'S ROOTS", "Three of them, carrying the Kernels' light up to Boulder Bluff. Break the knot where each one comes up (%s throws a grenade)." % GameInput.prompt(&"grenade")]


func you_down_text(who: String, _left: int) -> String:
	return "Taken out by %s. Without you, the rangers can't stop the Briar." % who


func result(won: bool, r: Dictionary) -> Array:
	if won:
		return ["THE KERNEL HUNT IS COMPLETE!", "The Starfall: the Acorn's gone home, and the Briar's just a briar. %d Touched beaten down, %d of %d rangers home." % [
			int(r.get("touched", 0)), int(r.get("rangers", 0)), KernelHunt.RANGERS.size()]]
	match step:
		Step.ROOTS:
			return ["THE ROOTS HOLD", "%d of %d roots cut before the Touched stopped you." % [int(r.get("cut", 0)), int(r.get("roots", 0))]]
		Step.BRIAR, Step.WAKE:
			return ["THE BRIAR CLOSES", "It shut round Boulder Bluff, and you didn't make it."]
	return ["THE BRIAR HEART BEATS ON", "It still has %d of the three Kernels." % int(r.get("pods_left", 3))]


# ---- helpers -------------------------------------------------------------------------------------------

func _follow(r: Critter) -> void:
	var brain := r.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.release()
		brain.escort = match_manager.player


## Buck Toothington, if he's standing.
func _keeper() -> Critter:
	for r in rangers:
		if is_instance_valid(r) and r.alive and r.display_name == KernelHunt.RANGERS[0]:
			return r
	return null
