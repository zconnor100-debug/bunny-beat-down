class_name NutcrackerBoss
extends Boss
## Crackjaw, the Nutcracker General: the Toy Box's other boss (a Boss
## Battle's other choice there, Settings "boss"), a wooden nutcracker as tall
## as the bookcase who was carved to fight the Mouse King and has decided the
## Warren is its army (the Cracxus festivus model, rigged: assets/bosses/
## nutcracker/, his arms, legs, jaw and hat moving on their pegs, rigid, the
## way a wooden toy's do). A bunny's acorn helmet is a nut to him.
##   Quick March: a red lane through whoever he's after, a drum roll, then he
##     marches down it, every stamp of his boots knocking over whoever's near
##     it (and kicking apart any toy fort in the way). Get out of the lane.
##   Sabre Sweep: his sabre swung flat across the floor in front of him, from
##     his right to his left (and back again, enraged): jump it as it comes.
##   Crack!: up close he bows at the waist, jaw wide, and snaps it shut on
##     whatever's in front of him. Missed, he's slow to straighten up, his
##     jaw hanging open: the best place there is to hit him.
##   Walnut Volley: walnuts lobbed high, each cracking open on its own red ring.
##   Timber!: shoot his legs (rockets and grenades most of all) and he
##     wobbles; enough, and he goes over like a felled pine along a red strip,
##     and lies there long enough to go for his head.
## Below half health: Double Time. Quicker marches, the sabre both ways,
## more walnuts.

const MARCH_SPEED := 22.0           ## m/s down the lane
const MARCH_W := 18.0               ## the lane's width
const MARCH_PAST := 25.0            ## metres he marches on past whoever he's after
const MARCH_MAX := 120.0
const STEP_LEN := 9.0               ## metres a stride takes him
const STOMP_R := 8.0                ## a stamp's reach round his boot
const SWEEP_R := 28.0               ## his sabre's reach along the floor
const CRACK_AT := 12.0              ## how far in front of him his jaw comes down
const CRACK_R := 9.0
const NUT_R := 6.5                  ## a walnut's crack
const TOPPLE_AT := 14.0             ## hits on his legs (yours count 1, a bot's 0.15, a blast's 3x) that put him over...
const WOBBLE_DECAY := 1.2           ## ...before they wear off, this many a second
const TOPPLED_FOR := 6.0            ## seconds he lies there
const STEADY_FOR := 20.0            ## seconds after he's back up before he can be put over again
const LEGS := [&"l_upper_leg", &"l_lower_leg", &"l_foot", &"r_upper_leg", &"r_lower_leg", &"r_foot"]
const BROWN := Color(0.42, 0.28, 0.15)
const PAINT := Color(0.78, 0.12, 0.1)

## Flat on his face (Timber!): over from the hips and down onto the floor,
## arms out ahead of him.
const FLAT := {&"hips": Vector3(86, 0, 0), &"root": Vector3(0, -0.29, 0), &"l_upper_arm": Vector3(-150, 0, 0),
	&"r_upper_arm": Vector3(-150, 0, 0), &"head": Vector3(-25, 0, 0), &"jaw": Vector3(20, 0, 0), &"hat": Vector3(-25, 0, 0)}

## (shoulder arms: his right forearm up, the sabre standing up in front of
## his shoulder, whenever he isn't doing something with it. His arms swing
## forward and back on their pegs, like a real nutcracker's, never out to
## the side: that stretched his coat between arm and body.)
const CARRY := {&"r_lower_arm": Vector3(-80, 0, 0), &"r_upper_arm": Vector3(-10, 0, 0)}

var _wobble := 0.0                  # hits on his legs lately (Timber!)
var _steady_until := 0.0
var _jaw_open := false              # (bowed for a Crack!: his jaw counts most of all)
var _floored := false               # (flat on his face after a Timber!, not yet back up)
var _sabre: Node3D
var _nut_mat: StandardMaterial3D


func _init() -> void:
	super()
	id = "nutcracker"
	display_name = "Crackjaw"
	title = "the Nutcracker General"
	land_time = 2.4
	base_health = 32000.0
	walk_speed = 9.0
	turn_speed = 1.4
	armor = 0.9                     # (lacquered wood)
	weak_spots = {&"jaw": 2.5, &"head": 1.8}
	limb_scale = 0.7
	blood = Color(0.66, 0.5, 0.3)   # (sawdust)
	solid_roles = [&"hips", &"spine", &"chest", &"l_upper_leg", &"l_lower_leg", &"r_upper_leg", &"r_lower_leg"]
	blend_from_pose = true   # (a wooden toy's stiff moves, but no snapping from one to the next)
	springs = {&"hat": [2.8, 0.12, 0.05]}   # (his tall hat wobbling on its peg as he stamps)


func stride() -> float:
	return 0.16


func step_sound() -> StringName:
	return &"nut_step"


## His painted eyes, lit: ice blue, red when he's angry.
func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.1, 0.05) if angry else Color(0.5, 0.82, 1.0)


func enrage_line() -> String:
	return "DOUBLE TIME: quicker marches, his sabre both ways. Shoot his legs to put him over."


func attack_name(what: StringName) -> String:
	return {&"march": "Quick March", &"halt": "Halt!", &"sabre": "Sabre Sweep", &"crack": "Crack!", &"walnut": "Walnut",
		&"timber": "Timber!", &"stamp": "Present Arms", &"landing": "Landing"}.get(what, super(what))


## The tall hat soaks up shots (it's mostly hat); his jaw counts most of all
## while he's bowed with it hanging open.
func role_scale(role: StringName) -> float:
	if role == &"hat":
		return 0.75
	if role == &"jaw" and _jaw_open:
		return 3.5
	return super(role)


func _hit_fx(info: DamageInfo) -> void:
	FX.blood_hit(last_hit_pos, -info.direction, clampf(info.amount / 30.0, 0.3, 1.0), blood)
	if info.amount > 60.0:
		BossFX.chips(last_hit_pos, 0.6, PAINT)   # (flakes of his red paint)


func _physics_process(delta: float) -> void:
	_wobble = maxf(0.0, _wobble - WOBBLE_DECAY * delta)
	super(delta)


# ---- the model: his sabre ------------------------------------------------------------------------

## A cavalry sabre in his right fist, made here: a curved steel blade, a
## gold guard and pommel (model units: the model's scale makes it ~10 m).
func _dress() -> void:
	if skeleton == null or not poser.has(&"r_hand"):
		return
	var hand: int = poser.bones[&"r_hand"]
	var att := BoneAttachment3D.new()
	att.name = "Sabre"
	att.bone_idx = hand
	skeleton.add_child(att)
	_sabre = _make_sabre()
	att.add_child(_sabre)
	# (in his fist as he stands, its blade pointing straight ahead: his poses turn it from there)
	var fist := poser.bone_pose(&"r_hand").origin.lerp(poser.bone_tip(&"r_hand"), 0.54)
	_sabre.transform = skeleton.get_bone_global_rest(hand).affine_inverse() * Transform3D(Basis.IDENTITY, fist)


func _make_sabre() -> Node3D:
	var root := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.84)
	steel.metallic = 0.85
	steel.roughness = 0.3
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.92, 0.7, 0.28)
	gold.metallic = 0.9
	gold.roughness = 0.32
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh(0.3, 0.017, 0.004, 0.035)
	blade.material_override = steel
	root.add_child(blade)
	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.012, 0.045, 0.009)
	guard.mesh = gm
	guard.material_override = gold
	root.add_child(guard)
	var grip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0075
	cm.bottom_radius = 0.0075
	cm.height = 0.05
	grip.mesh = cm
	grip.rotation.x = PI * 0.5   # (along the sabre)
	grip.position.z = -0.027
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.08, 0.05)
	dark.roughness = 0.7
	grip.material_override = dark
	root.add_child(grip)
	var pommel := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.01
	sm.height = 0.02
	pommel.mesh = sm
	pommel.material_override = gold
	pommel.position.z = -0.055
	root.add_child(pommel)
	for mi in [blade, guard, grip, pommel]:
		(mi as GeometryInstance3D).layers = CritterVisual.RENDER_LAYER
	return root


## The blade: `length` along +Z from the guard, `width` up and down, curving
## down toward the tip (`curve`) and tapering to a point.
static func _blade_mesh(length: float, width: float, thick: float, curve: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var rows: Array = []   # [top, bottom] centre-plane points per row
	for i in n + 1:
		var u := float(i) / n
		var w := width * (1.0 - pow(u, 4.0)) if i < n else 0.0
		var y := -curve * u * u
		rows.append([Vector3(0, y + w * 0.5, length * u), Vector3(0, y - w * 0.5 * 0.6, length * u)])   # (the back of the blade thicker above the edge)
	for side in [-1.0, 1.0]:
		var x: float = thick * 0.5 * side
		for i in n:
			var a: Array = rows[i]
			var b: Array = rows[i + 1]
			var p := [a[0] + Vector3(x, 0, 0), a[1] + Vector3(x * 0.2, 0, 0), b[0] + Vector3(x, 0, 0), b[1] + Vector3(x * 0.2, 0, 0)]
			if side > 0.0:
				st.add_vertex(p[0]); st.add_vertex(p[1]); st.add_vertex(p[2])
				st.add_vertex(p[2]); st.add_vertex(p[1]); st.add_vertex(p[3])
			else:
				st.add_vertex(p[0]); st.add_vertex(p[2]); st.add_vertex(p[1])
				st.add_vertex(p[2]); st.add_vertex(p[3]); st.add_vertex(p[1])
	st.generate_normals()
	return st.commit()


# ---- choosing ------------------------------------------------------------------------------------

func _choose(t: Critter) -> BossAction:
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	var ahead := forward().dot((t.global_position - global_position).normalized()) > 0.5
	if d < CRACK_AT + 6.0 and ahead and is_ready(&"crack") and t.is_on_floor():
		return _crack()
	if d < SWEEP_R - 2.0 and is_ready(&"sweep"):
		return _sweep(t)
	if d > 30.0 and d < 110.0 and is_ready(&"march"):
		return _march(t)
	if d > 30.0 and d < 140.0 and is_ready(&"walnuts"):
		return _walnuts(t)
	return null


## A wooden toy's walk: stiff legs swinging from the hips, a rock from side
## to side, his free arm swinging, his chin up.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var s := sin(phase)
	return {
		&"l_upper_leg": Vector3(-26.0 * s * amount, 0, 0), &"r_upper_leg": Vector3(26.0 * s * amount, 0, 0),
		&"l_upper_arm": Vector3(18.0 * s * amount, 0, 0), &"hips": Vector3(0, 0, 4.0 * s * amount),
		&"chest": Vector3(0, -4.0 * s * amount, 0), &"root": Vector3(0, absf(sin(phase)) * 0.01 * amount, 0),
	}


## Standing to attention: a slow sway, his jaw working now and then, the
## sabre shouldered (unless what he's doing needs it), and a wobble on his
## pegs once his legs have taken a few hits.
func idle_pose(t: float) -> Dictionary:
	var p := {&"chest": Vector3(1.5 * sin(t * 1.2), 0, 0), &"jaw": Vector3(maxf(0.0, sin(t * 2.3)) * 6.0, 0, 0)}
	var free := 1.0 - (action.weight() if action else 0.0)
	for role in CARRY:
		p[role] = (p.get(role, Vector3.ZERO) as Vector3) + (CARRY[role] as Vector3) * free
	var shaky := clampf(_wobble / TOPPLE_AT, 0.0, 1.0)
	if shaky > 0.3:
		p[&"hips"] = Vector3(sin(t * 9.0) * 4.0 * shaky, 0, sin(t * 7.0) * 6.0 * shaky)
	return p


# ---- Quick March --------------------------------------------------------------------------------

func _march(t: Critter) -> BossAction:
	cooldown(&"march", 11.0)
	var from := global_position
	var dir := Vector3(t.global_position.x - from.x, 0.0, t.global_position.z - from.z).normalized()
	var dist := clampf(Vector2(t.global_position.x - from.x, t.global_position.z - from.z).length() + MARCH_PAST, 40.0, MARCH_MAX)
	var to := _inside(from + dir * dist)
	dist = Vector2(to.x - from.x, to.z - from.z).length()
	var lead := 0.9 if enraged else 1.2
	var speed := MARCH_SPEED * (1.25 if enraged else 1.0)
	var go := dist / speed
	var a := BossAction.new(&"march", lead + go + 0.9)
	var st := {"phase": 0.0, "step": 0}
	var pose := {}
	a.key(0.0, pose)   # (his march's pose: _march_pose, set as he goes)
	a.on(0.0, func():
		warn_strip(from, to, MARCH_W, lead + go)
		Audio.play_at(&"nut_drum", global_position, 6.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
	a.tick = func(time: float, delta: float):
		face_toward(to, delta, 3.0)
		if time < lead:   # (marking time on the spot as the drum rolls)
			_pose_to(pose, _march_pose(time * 9.0, 0.35))
			return
		if time > lead + go:
			pose.clear()
			return
		var u := clampf((time - lead) / go, 0.0, 1.0)
		var p := from.lerp(to, u)
		p.y = lerpf(global_position.y, ground_y(p), 0.3)
		global_position = p
		st.phase = float(st.phase) + delta * speed / STEP_LEN * PI
		var step := int(float(st.phase) / PI)
		if step != int(st.step):
			st.step = step
			_stamp(&"r_foot" if step % 2 == 0 else &"l_foot")
		_pose_to(pose, _march_pose(float(st.phase), 1.0))
	a.on(lead + go, func():   # (Halt! both boots together)
		var at := global_position
		hurt_ring(at, STOMP_R * 1.6, 40.0, 12.0, 12.0, 7.0, &"halt")
		BossFX.shockwave(at, STOMP_R * 1.6)
		Events.explosion.emit(at, STOMP_R * 1.4)
		Audio.play_at(&"nut_step", at, 8.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
	return a


## `pose`, made `to` (in place: a pose an action keeps, changing as it goes).
static func _pose_to(pose: Dictionary, to: Dictionary) -> void:
	pose.clear()
	pose.merge(to)


## A point kept inside the room (a march's end: never out past its walls).
func _inside(p: Vector3) -> Vector3:
	var isl: Island = match_manager.island if match_manager and "island" in match_manager else null
	if isl:
		var r := isl.play_bounds().grow(-25.0)
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.z = clampf(p.z, r.position.y, r.end.y)
	p.y = ground_y(p)
	return p


## Mid-march at `phase` (radians: a stride each PI): stiff legs swung high
## from the hips, the free arm swung against them, chest out, chin up, his
## jaw clacking on every step.
func _march_pose(phase: float, k: float) -> Dictionary:
	var s := sin(phase)
	return {
		&"l_upper_leg": Vector3(-42.0 * s * k, 0, 0), &"r_upper_leg": Vector3(42.0 * s * k, 0, 0),
		&"l_upper_arm": Vector3(34.0 * s * k, 0, 0), &"hips": Vector3(0, 0, 5.0 * s * k),
		&"chest": Vector3(-5.0 * k, -5.0 * s * k, 0), &"head": Vector3(-8.0 * k, 0, 0),
		&"jaw": Vector3(absf(sin(phase)) * 14.0 * k, 0, 0),
		&"root": Vector3(0, absf(s) * 0.018 * k, 0),
		&"r_lower_arm": CARRY[&"r_lower_arm"], &"r_upper_arm": CARRY[&"r_upper_arm"],   # (the sabre shouldered)
	}


## A boot coming down mid-march: whoever's by it knocked flying, and any toy
## fort in the way kicked apart (Events.explosion: BlockPile).
func _stamp(foot: StringName) -> void:
	var at := bone_point(foot, 0.5)
	at.y = ground_y(at)
	hurt_ring(at, STOMP_R, 45.0, 15.0, 12.0, 6.0, &"march")
	BossFX.dust(at, STOMP_R)
	Events.explosion.emit(at, STOMP_R * 1.1)
	Audio.play_at(&"nut_step", at, 4.0, 0.08, {"max_distance": 420.0, "unit_size": 26.0})


# ---- Sabre Sweep --------------------------------------------------------------------------------

## The blade swung flat across the floor in front of him, from his right to
## his left (enraged, and straight back): anyone it reaches on the ground goes
## flying. Jump it. (He swings where the warning showed: no turning after.)
func _sweep(_t: Critter) -> BossAction:
	cooldown(&"sweep", 7.0)
	var wind := 0.85 if enraged else 1.05
	var swing := 0.5
	var back := enraged
	var a := BossAction.new(&"sweep", wind + swing + (0.4 + swing if back else 0.0) + 0.8)
	var centre := global_position
	var fwd := forward()
	# (wound up high on his right, then the blade brought down low on that side
	# and swung flat across to his left: the body twisting and the arm
	# swinging round, the fist turned so the blade runs on along the arm)
	var raised := {&"spine": Vector3(10, 0, 0), &"chest": Vector3(0, -50, 0), &"r_upper_arm": Vector3(-150, 0, 0),
		&"r_lower_arm": Vector3(-25, 0, 0), &"r_hand": Vector3(60, 0, 0), &"l_upper_arm": Vector3(-20, 0, 0), &"head": Vector3(0, -20, 0)}
	var low_right := {&"spine": Vector3(42, 0, 0), &"chest": Vector3(0, -55, 0), &"r_upper_arm": Vector3(-55, -35, 0),
		&"r_hand": Vector3(90, 0, 0), &"l_upper_arm": Vector3(-10, 0, 0), &"head": Vector3(10, -25, 0)}
	var low_left := {&"spine": Vector3(42, 0, 0), &"chest": Vector3(0, 55, 0), &"r_upper_arm": Vector3(-55, 35, 0),
		&"r_hand": Vector3(90, 0, 0), &"l_upper_arm": Vector3(10, 0, 0), &"head": Vector3(10, 25, 0)}
	a.key(0.0, {}).key(wind * 0.7, raised).key(wind, low_right).key(wind + swing, low_left)
	if back:
		a.key(wind + swing + 0.4, low_left).key(wind + swing * 2.0 + 0.4, low_right)
	a.key(a.length, {})
	var hit := {}
	a.on(0.0, func():
		_warn_arc(centre, fwd, SWEEP_R, wind + (swing * 2.0 + 0.4 if back else swing)))
	a.on(wind, func(): Audio.play_at(&"nut_swish", centre + fwd * 12.0, 8.0, 0.05, {"max_distance": 400.0, "unit_size": 30.0}))
	if back:
		a.on(wind + swing + 0.4, func():
			hit.clear()
			Audio.play_at(&"nut_swish", centre + fwd * 12.0, 8.0, 0.05, {"max_distance": 400.0, "unit_size": 30.0}))
	a.tick = func(time: float, _delta: float):
		var u := -1.0
		var dir := 1.0
		if time >= wind and time <= wind + swing:
			u = (time - wind) / swing
		elif back and time >= wind + swing + 0.4 and time <= wind + swing * 2.0 + 0.4:
			u = 1.0 - (time - wind - swing - 0.4) / swing
			dir = -1.0
		if u < 0.0:
			return
		var blade := lerpf(-PI * 0.5, PI * 0.5, u)   # (radians round from his right, through ahead, to his left)
		var left := -global_basis.x
		for c in foes_near(centre, SWEEP_R):
			if hit.has(c):
				continue
			var off := c.global_position - centre
			off.y = 0.0
			if off.length() < 3.0:
				continue
			var ang := atan2(off.dot(left), off.dot(fwd))
			if absf(ang) > PI * 0.5 or (dir > 0.0 and ang > blade) or (dir < 0.0 and ang < blade):
				continue
			hit[c] = true
			if not c.is_on_floor() and c.global_position.y > ground_y(c.global_position) + 1.0:
				continue   # (jumped it)
			var swept := left.rotated(Vector3.UP, ang) * dir   # (along the blade's way)
			hurt(c, 80.0 if enraged else 65.0, (swept + off.normalized() * 0.4).normalized(), 14.0, 6.0, &"sabre",
				DamageInfo.Kind.MELEE, 0.85)
	return a


## The red half-ring on the floor in front of him where his sabre will pass
## (and the danger the bots keep out of: a fan of circles across it).
func _warn_arc(centre: Vector3, fwd: Vector3, radius: float, seconds: float) -> void:
	BossFX.warn_arc(centre, fwd, radius, seconds)
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	for i in 5:
		var ang := deg_to_rad(-72.0 + 36.0 * i)
		var p := centre + (fwd * cos(ang) + left * sin(ang)).normalized() * radius * 0.55
		danger.append([p, radius * 0.48, _clock + seconds + 0.2, _clock])


# ---- Crack! -------------------------------------------------------------------------------------

## He bows at the waist, jaw wide, and snaps it shut on whatever's in front
## of him. Missed, he's slow to straighten up, jaw hanging open.
func _crack() -> BossAction:
	cooldown(&"crack", 6.5)
	var wind := 0.75 if enraged else 0.9
	var stuck := 1.4
	var a := BossAction.new(&"crack", wind + stuck + 0.7)
	var spot := global_position + forward() * CRACK_AT
	spot.y = ground_y(spot)
	var bow := {&"spine": Vector3(42, 0, 0), &"chest": Vector3(22, 0, 0), &"neck": Vector3(8, 0, 0), &"head": Vector3(12, 0, 0),
		&"jaw": Vector3(42, 0, 0), &"l_upper_arm": Vector3(25, 0, 0), &"r_upper_arm": Vector3(25, 0, 0),
		&"l_upper_leg": Vector3(-8, 0, 0), &"r_upper_leg": Vector3(-8, 0, 0), &"root": Vector3(0, -0.015, 0)}
	var bit := bow.duplicate()
	bit[&"jaw"] = Vector3(-4, 0, 0)
	bit[&"spine"] = Vector3(48, 0, 0)
	var hang := bow.duplicate()
	hang[&"jaw"] = Vector3(26, 0, 0)
	a.key(0.0, {}).key(wind * 0.85, bow).key(wind, bit).key(wind + 0.2, hang).key(wind + stuck, hang).key(a.length, {})
	a.on(0.0, func(): warn(spot, CRACK_R, wind))
	a.on(wind, func():
		_jaw_open = true
		for c in hurt_ring(spot, CRACK_R, 90.0 if enraged else 80.0, 35.0, 8.0, 9.0, &"crack", false):
			if not c.alive and gore_ok:
				FX.gore_burst(c.get_chest_position(), 1.2, c.def.fur_color if c.def else Color.WHITE)
		BossFX.chips(spot + Vector3.UP * 2.0, 1.4, BROWN)
		Events.explosion.emit(spot, CRACK_R * 0.8)
		Audio.play_at(&"nut_crack", mouth_position(), 10.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0})
		Audio.play_at(&"nut_clack", mouth_position(), 6.0, 0.05, {"max_distance": 500.0, "unit_size": 40.0}))
	a.on(wind + stuck, func(): _jaw_open = false)
	a.data["cancel"] = func(): _jaw_open = false
	return a


# ---- Walnut Volley ------------------------------------------------------------------------------

func _walnuts(t: Critter) -> BossAction:
	cooldown(&"walnuts", 9.0)
	var n := 11 if enraged else 7
	var gap := 0.22
	var a := BossAction.new(&"walnuts", 0.6 + n * gap + 0.7)
	var toss := {&"l_upper_arm": Vector3(-35, 0, 0), &"l_lower_arm": Vector3(-40, 0, 0), &"chest": Vector3(0, 12, 0), &"head": Vector3(-8, 0, 0)}
	var up := {&"l_upper_arm": Vector3(-140, 0, 0), &"l_lower_arm": Vector3(-10, 0, 0), &"chest": Vector3(-6, 12, 0), &"head": Vector3(-14, 0, 0)}
	a.key(0.0, {}).key(0.45, toss)
	for i in n:
		var at := 0.6 + i * gap
		a.key(at - gap * 0.5, toss).key(at, up)
		a.on(at, func():
			var who := t
			if i % 3 == 2:   # (every third at someone else about)
				var others := foes().filter(func(c): return c != t and c.global_position.distance_to(global_position) < 150.0)
				if not others.is_empty():
					who = others[randi() % others.size()]
			_toss_walnut(who))
	a.key(a.length - 0.4, toss).key(a.length, {})
	a.tick = func(_time: float, delta: float):
		if is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 1.2)
	return a


func _toss_walnut(t: Critter) -> void:
	var from := bone_point(&"l_hand", 0.8) + Vector3.UP * 2.0
	var aim := global_position + forward() * 60.0
	var flight := randf_range(1.6, 2.2)
	if is_instance_valid(t) and t.alive:
		aim = t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * flight * 0.6
	var at := aim + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(0.0, 8.0)
	at.y = ground_y(at)
	warn(at, NUT_R, flight)
	var nut := _walnut()
	get_parent().add_child(nut)
	nut.global_position = from
	var spin := Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	var top := randf_range(45.0, 65.0)
	var fly := func(u: float):
		if is_instance_valid(nut):
			nut.global_position = from.lerp(at, u) + Vector3.UP * sin(u * PI) * top
			nut.rotation = spin * u * flight
	var tw := nut.create_tween()
	tw.tween_method(fly, 0.0, 1.0, flight)
	tw.tween_callback(func():
		hurt_ring(at, NUT_R, 50.0, 15.0, 9.0, 7.0, &"walnut", false)
		BossFX.chips(at + Vector3.UP, 1.2, BROWN)
		BossFX.dust(at, NUT_R)
		var p := Audio.play_at(&"nut_crack", at, 0.0, 0.12, {"max_distance": 260.0, "unit_size": 20.0})
		if p:
			p.pitch_scale = randf_range(1.2, 1.45)
		nut.queue_free())


## A walnut, giant: a wrinkled brown ball with a ridge round its middle.
func _walnut() -> Node3D:
	if _nut_mat == null:
		_nut_mat = StandardMaterial3D.new()
		_nut_mat.albedo_color = Color(0.5, 0.34, 0.19)
		_nut_mat.roughness = 0.85
	var root := Node3D.new()
	root.name = "Walnut"
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.7
	sm.height = 3.2
	shell.mesh = sm
	shell.scale = Vector3(1.0, 1.0, 1.12)
	shell.material_override = _nut_mat
	root.add_child(shell)
	var ridge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.55
	tm.outer_radius = 1.85
	ridge.mesh = tm
	ridge.rotation.z = PI * 0.5
	ridge.material_override = _nut_mat
	root.add_child(ridge)
	return root


# ---- Timber! ------------------------------------------------------------------------------------

## Hits on his legs wobble him (yours count most, and a blast three times
## over); enough of them before they wear off and over he goes.
func take_damage(info: DamageInfo) -> void:
	var before := health
	super(info)
	if not alive or health >= before or info.bone_role not in LEGS:
		return
	var by := info.attacker as Critter
	_wobble += (1.0 if by and by.is_player else 0.15) * (3.0 if info.kind == DamageInfo.Kind.EXPLOSION else 1.0)
	if _wobble >= TOPPLE_AT and _clock >= _steady_until and state == State.FIGHTING and not vulnerable() \
			and (action == null or action.interruptible):
		_topple()


func _topple() -> void:
	_cancel_action()
	start(_timber())


## Over he goes, the way he's facing, along a red strip: whoever's under him
## when he lands is flattened, and then he lies there, his head on the floor,
## taking double, till he pushes himself back up.
func _timber() -> BossAction:
	_wobble = 0.0
	var teeter := 1.1
	var fall := 0.55
	var up := 2.2
	var a := BossAction.new(&"timber", teeter + fall + TOPPLED_FOR + up)
	a.interruptible = false
	var fwd := forward()
	var feet := global_position
	var head := feet + fwd * HEIGHT * 0.62
	_steady_until = _clock + a.length + STEADY_FOR
	var windmill := {&"hips": Vector3(-7, 0, 4), &"l_upper_arm": Vector3(-160, 0, 0), &"r_upper_arm": Vector3(-30, 0, 0),
		&"head": Vector3(-15, 0, 0), &"jaw": Vector3(25, 0, 0)}
	var tipping := {&"hips": Vector3(14, 0, -3), &"l_upper_arm": Vector3(-90, 0, 0), &"r_upper_arm": Vector3(-160, 0, 0),
		&"head": Vector3(-20, 0, 0), &"jaw": Vector3(30, 0, 0)}
	var flat := FLAT
	var push := {&"hips": Vector3(55, 0, 0), &"root": Vector3(0, -0.18, 0), &"l_upper_arm": Vector3(-60, 0, 0),
		&"r_upper_arm": Vector3(-60, 0, 0), &"head": Vector3(-20, 0, 0)}
	a.key(0.0, {}).key(teeter * 0.45, windmill).key(teeter, tipping).key(teeter + fall, flat)
	a.key(teeter + fall + TOPPLED_FOR, flat).key(teeter + fall + TOPPLED_FOR + up * 0.6, push).key(a.length, {})
	Events.announce.emit("CRACKJAW IS GOING OVER!", "TIMBER! Get clear of where he falls, then go for his head.")
	warn_strip(feet - fwd * 6.0, head, 13.0, teeter + fall)
	Audio.play_at(&"nut_clack", mouth_position(), 8.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0})
	a.on(teeter + fall, func():
		_floored = true
		vulnerable_until = _clock + TOPPLED_FOR
		vulnerable_k = VULNERABLE
		var along := head - feet
		for c in foes():
			var cp := c.global_position
			var q := Geometry3D.get_closest_point_to_segment(Vector3(cp.x, feet.y, cp.z), feet, head)
			if Vector2(cp.x - q.x, cp.z - q.z).length() < 7.0:
				var side := Vector3(cp.x - q.x, 0.0, cp.z - q.z)
				hurt(c, 75.0, side.normalized() if side.length() > 0.1 else along.normalized(), 10.0, 7.0, &"timber")
		for k in 4:
			var p := feet.lerp(head, (k + 0.5) / 4.0)
			p.y = ground_y(p)
			BossFX.shockwave(p, 10.0)
			Events.explosion.emit(p, 10.0)
		BossFX.chips(head, 2.0, PAINT)
		Audio.play_at(&"boss_stomp", feet.lerp(head, 0.5), 10.0, 0.0, {"max_distance": 800.0, "unit_size": 50.0})
		Audio.play_at(&"nut_step", head, 8.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
	a.on(teeter + fall + TOPPLED_FOR, func():
		Audio.play_at(&"nut_clack", mouth_position(), 4.0, 0.1, {"max_distance": 400.0, "unit_size": 30.0}))
	a.on(teeter + fall + TOPPLED_FOR + up * 0.5, func(): _floored = false)
	return a


## Whether he's down on the floor (Timber!), for the rogues to yell about.
func toppled() -> bool:
	return action != null and action.name == &"timber" and vulnerable()


# ---- Present Arms (enraged) ----------------------------------------------------------------------

## Double Time: a stamp of his boot that knocks everyone near him back, the
## sabre brought up to his face in salute, a bugle call. (His arrival's
## flourish for the camera, too.)
func _roar_action() -> BossAction:
	var a := BossAction.new(&"present_arms", 2.4)
	var salute := {&"r_upper_arm": Vector3(-55, 0, 0), &"r_lower_arm": Vector3(-105, 0, 0), &"r_hand": Vector3(0, 0, 15),
		&"chest": Vector3(-6, 0, 0), &"head": Vector3(-10, 0, 0), &"l_upper_leg": Vector3(-28, 0, 0)}
	var stamp := salute.duplicate()
	stamp[&"l_upper_leg"] = Vector3(0, 0, 0)
	stamp[&"jaw"] = Vector3(18, 0, 0)
	a.key(0.0, {}).key(0.4, salute).key(0.55, stamp).key(1.9, stamp).key(2.4, {})
	a.on(0.55, func():
		var at := global_position
		hurt_ring(at, 30.0, 12.0, 4.0, 10.0, 5.0, &"stamp", false)
		BossFX.dust(at, 30.0)
		Events.explosion.emit(at, 22.0)
		Audio.play_at(&"nut_step", at, 10.0, 0.0, {"max_distance": 700.0, "unit_size": 50.0})
		Audio.play_at(&"nut_bugle", mouth_position(), 8.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0}))
	return a


# ---- arriving, and going down ---------------------------------------------------------------------

## Dropped into the room like any toy, stiff as a board: he lands with a
## wooden thunk, rocks on his heels, and comes to attention.
func _entrance() -> BossAction:
	var at := global_position
	var drop := land_time
	var a := BossAction.new(&"entrance", drop + 2.4)
	a.interruptible = false
	var rock := {&"hips": Vector3(-7, 0, 0), &"head": Vector3(6, 0, 0), &"jaw": Vector3(20, 0, 0)}
	var rock2 := {&"hips": Vector3(5, 0, 0), &"head": Vector3(-4, 0, 0)}
	a.key(0.0, {&"jaw": Vector3(25, 0, 0)}).key(drop, {}).key(drop + 0.35, rock).key(drop + 0.8, rock2).key(drop + 1.3, {&"hips": Vector3(-2, 0, 0)})
	a.key(drop + 2.4, {})
	a.on(0.0, func(): warn(at, 24.0, drop))
	a.tick = func(time: float, _delta: float):
		if time < drop:
			var u := time / drop
			global_position = at + Vector3.UP * 200.0 * (1.0 - u * u)
	a.on(drop, func():
		global_position = at
		hurt_ring(at, 24.0, 50.0, 10.0, 14.0, 9.0, &"landing")
		BossFX.shockwave(at, 24.0)
		Events.explosion.emit(at, 16.0)
		Audio.play_at(&"nut_step", at, 12.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0})
		Audio.play_at(&"boss_stomp", at, 6.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0}))
	return a


func _after_entrance() -> void:
	cooldown(&"march", 4.0)
	cooldown(&"walnuts", 3.0)
	if foes_near(global_position, 60.0).size() >= 2:
		start(_roar_action())


## Over backwards, stiff as a board, his jaw dropping open and his hat
## tipping off the back of his head. (Beaten while he's already flat on his
## face, he stays there: his jaw drops open and his hat rolls off.)
func _death_action() -> BossAction:
	if _floored:
		var down := BossAction.new(&"death", 1.4)
		down.blend_in = 0.0
		down.blend_out = 0.0
		down.interruptible = false
		var gone := FLAT.duplicate()
		gone[&"jaw"] = Vector3(38, 0, 0)
		gone[&"hat"] = Vector3(-70, 0, 0)
		gone[&"head"] = Vector3(-15, 0, 0)
		down.key(0.0, FLAT).key(0.7, gone).key(1.4, gone)
		down.on(0.2, func():
			BossFX.chips(get_eye_position(), 2.5, PAINT)
			Audio.play_at(&"nut_clack", mouth_position(), 8.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
		return down
	var a := BossAction.new(&"death", 2.6)
	a.blend_out = 0.0
	a.interruptible = false
	var sway := {&"hips": Vector3(6, 0, 0), &"jaw": Vector3(30, 0, 0), &"head": Vector3(10, 0, 0)}
	var flat := {&"hips": Vector3(-86, 0, 0), &"root": Vector3(0, -0.29, 0), &"jaw": Vector3(38, 0, 0), &"hat": Vector3(-55, 0, 0),
		&"l_upper_arm": Vector3(-20, 0, 0), &"r_upper_arm": Vector3(-20, 0, 0), &"head": Vector3(15, 0, 0)}
	a.key(0.0, {}).key(0.6, sway).key(1.6, flat).key(2.6, flat)
	a.on(1.6, func():
		var at := global_position - forward() * HEIGHT * 0.4
		BossFX.shockwave(at, HEIGHT)
		BossFX.chips(get_chest_position(), 3.0, PAINT)
		Events.explosion.emit(at, 20.0)
		Audio.play_at(&"nut_step", at, 12.0, 0.0, {"max_distance": 800.0, "unit_size": 50.0})
		Audio.play_at(&"explosion", at, 4.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
	return a


func _fallen() -> void:
	BossFX.chips(get_chest_position(), 2.5, BROWN)
	BossFX.dust(global_position, 28.0)


# ---- rewind (TimeKeeper) -----------------------------------------------------------------------------

func restore(s: Dictionary) -> void:
	super(s)
	_wobble = 0.0
	_jaw_open = false
	_floored = false
