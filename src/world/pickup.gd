class_name Pickup
extends RigidBody3D
## Loot lying in the world. Ammo, clovers and armor are scooped up by walking
## over them; weapons need the interact key (or an AI deciding it wants them).
## Rare loot gets a coloured light beam so it reads from across a clearing;
## lucky clovers are huge (half a critter tall) and glow green, and shield
## acorns are just as big and glow orange.

const MODELS := {
	"ammo_0": "res://assets/props/ammo_light.glb",
	"ammo_1": "res://assets/props/ammo_shells.glb",
	"ammo_2": "res://assets/props/ammo_heavy.glb",
	"ammo_3": "res://assets/props/ammo_rocket.glb",
	"clover": "res://assets/props/pickup_health.glb",
	"armor": "res://assets/props/pickup_armor.glb",
}
const AUTO_RADIUS := 1.1
const CLOVER_HEIGHT := 1.25           ## half the height of a Bun
const CLOVER_GLOW := Color(0.3, 1.0, 0.35)
const CLOVER_SHADER := preload("res://src/fx/clover_glow.gdshader")
static var _clover_glow: ShaderMaterial
static var _acorn_glow: ShaderMaterial

var spec: Dictionary = {}
var _spin: Node3D
var _t := randf() * 10.0
var _sensor: Area3D
var _sense_cd := 0.0
var dropped_by: Node = null      ## who swapped this gun out (AI ignores its own drops)
var dropped_msec := 0


static func weapon_spec(w: WeaponInstance) -> Dictionary:
	return {"type": "weapon", "weapon": w}


static func ammo_spec(ammo_type: int, amount: int) -> Dictionary:
	return {"type": "ammo", "ammo_type": ammo_type, "amount": amount}


static func clover_spec(n: int) -> Dictionary:
	return {"type": "clover", "amount": n}


static func armor_spec(amount: float) -> Dictionary:
	return {"type": "armor", "amount": amount}


static func spawn(parent: Node, spec_: Dictionary, pos: Vector3, vel := Vector3.ZERO) -> Pickup:
	var p := Pickup.new()
	p.spec = spec_
	parent.add_child(p)
	p.global_position = pos
	p.linear_velocity = vel
	return p


func _ready() -> void:
	add_to_group(&"pickups")
	collision_layer = Layers.PICKUPS
	collision_mask = Layers.WORLD
	lock_rotation = true
	mass = 0.5
	linear_damp = 1.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.2
	physics_material_override.friction = 1.0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.18
	cs.shape = sph
	cs.position.y = 0.18
	add_child(cs)
	_spin = Node3D.new()
	_spin.position.y = 0.35
	add_child(_spin)
	var model := _make_model()
	_spin.add_child(model)
	var rarity := rarity_tier()
	if spec.get("type") == "weapon" and rarity >= Rarity.Tier.GARDEN:
		_add_beam(Rarity.COLORS[rarity])
	if spec.get("type") == "clover":
		_glow(model)
	elif spec.get("type") == "armor":
		_glow_acorn(model)
	if not is_weapon():
		_sensor = Area3D.new()
		_sensor.collision_layer = 0
		_sensor.collision_mask = Layers.CRITTERS
		_sensor.monitorable = false
		var scs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = AUTO_RADIUS * (1.4 if spec.get("type") in ["clover", "armor"] else 1.0)
		scs.shape = ss
		_sensor.add_child(scs)
		add_child(_sensor)


func rarity_tier() -> int:
	if spec.get("type") == "weapon":
		return (spec["weapon"] as WeaponInstance).rarity
	return 0


func label() -> String:
	match spec.get("type"):
		"weapon":
			return (spec["weapon"] as WeaponInstance).display_name()
		"ammo":
			return "%d %s" % [spec["amount"], WeaponData.ammo_name(spec["ammo_type"])]
		"clover":
			return "%d Lucky Clover%s" % [spec["amount"], "" if spec["amount"] == 1 else "s"]
		"armor":
			return "Acorn Shield (+%d)" % int(spec["amount"])
	return "?"


func is_weapon() -> bool:
	return spec.get("type") == "weapon"


func _process(delta: float) -> void:
	_t += delta
	_spin.rotation.y += delta * 1.2
	_spin.position.y = 0.35 + sin(_t * 2.0) * 0.05


func _physics_process(delta: float) -> void:
	if is_weapon() or _sensor == null:
		return
	_sense_cd -= delta
	if _sense_cd > 0.0:
		return
	_sense_cd = 0.2
	for body in _sensor.get_overlapping_bodies():
		var critter := body as Critter
		if critter and critter.alive and critter.state == Critter.State.GROUND:
			if try_collect(critter):
				return


## Applies this pickup to `critter`. Returns true if it was consumed.
func try_collect(critter: Critter) -> bool:
	match spec.get("type"):
		"weapon":
			var dropped := critter.give_weapon(spec["weapon"])
			Audio.play_at(&"pickup_weapon", global_position)
			Events.item_picked_up.emit(critter, label())
			if dropped:
				var p := Pickup.spawn(get_parent(), Pickup.weapon_spec(dropped), global_position + Vector3.UP * 0.3, Vector3(0, 2.0, 0))
				p.dropped_by = critter
				p.dropped_msec = Time.get_ticks_msec()
			queue_free()
			return true
		"ammo":
			var left := critter.inventory.add_ammo(spec["ammo_type"], spec["amount"])
			if left == spec["amount"]:
				return false
			Audio.play_at(&"pickup_ammo", global_position, -3.0)
			Events.item_picked_up.emit(critter, label())
			if left > 0:
				spec["amount"] = left
				return false
			queue_free()
			return true
		"clover":
			var left := critter.inventory.add_clovers(spec["amount"])
			if left == spec["amount"]:
				return false
			Audio.play_at(&"pickup_health", global_position, -3.0)
			Events.item_picked_up.emit(critter, label())
			if left > 0:
				spec["amount"] = left
				return false
			queue_free()
			return true
		"armor":
			if critter.armor >= critter.max_armor:
				return false
			critter.armor = minf(critter.max_armor, critter.armor + float(spec["amount"]))
			Audio.play_at(&"pickup_armor", global_position, -3.0)
			Events.item_picked_up.emit(critter, label())
			queue_free()
			return true
	return false


func _make_model() -> Node3D:
	if spec.get("type") == "armor":
		return AcornShield.make()
	var path := ""
	match spec.get("type"):
		"weapon":
			path = (spec["weapon"] as WeaponInstance).data.model_path
		"ammo":
			path = MODELS["ammo_%d" % int(spec["ammo_type"])]
		_:
			path = MODELS.get(spec.get("type"), "")
	var m := ModelUtil.instantiate(path)
	if m:
		if spec.get("type") == "weapon":
			m.rotation = Vector3(0, 0, PI / 2.2)
			m.scale = Vector3.ONE * CritterVisual.WEAPON_SCALE * 1.2   # same size as in the paws
		elif spec.get("type") == "clover":
			m.scale = Vector3.ONE * CLOVER_HEIGHT / maxf(ModelUtil.aabb_of(m).size.y, 0.01)
		return m
	# Fallback only — coloured box until the prop model exists.
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.18, 0.4) if spec.get("type") == "weapon" else Vector3(0.22, 0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = {"weapon": Color(1, 0.55, 0.15), "ammo": Color(0.9, 0.7, 0.3), "clover": Color(0.3, 0.85, 0.3), "armor": Color(0.55, 0.35, 0.2)}.get(spec.get("type"), Color.WHITE)
	box.material = mat
	mi.mesh = box
	return mi


func _glow(model: Node3D) -> void:
	if _clover_glow == null:
		_clover_glow = ShaderMaterial.new()
		_clover_glow.shader = CLOVER_SHADER
		_clover_glow.set_shader_parameter(&"glow", CLOVER_GLOW)
	for gi in ModelUtil.find_all(model, "GeometryInstance3D"):
		(gi as GeometryInstance3D).material_overlay = _clover_glow
	var light := OmniLight3D.new()
	light.light_color = CLOVER_GLOW
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position.y = CLOVER_HEIGHT * 0.6
	add_child(light)


## Shield acorns: the same breathing glow as clovers, in orange, on the nut
## (the cap stays woody), and an orange light on the ground around it.
func _glow_acorn(model: Node3D) -> void:
	if _acorn_glow == null:
		_acorn_glow = ShaderMaterial.new()
		_acorn_glow.shader = CLOVER_SHADER
		_acorn_glow.set_shader_parameter(&"glow", AcornShield.GLOW)
		_acorn_glow.set_shader_parameter(&"strength", 0.9)
	var mi := model as MeshInstance3D
	if mi:
		mi.set_surface_override_material(0, _nut_with_glow())
	var light := OmniLight3D.new()
	light.light_color = AcornShield.GLOW
	light.light_energy = 1.8
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position.y = AcornShield.HEIGHT * 0.5
	add_child(light)


static var _nut_glow_mat: Material


static func _nut_with_glow() -> Material:
	if _nut_glow_mat == null:
		_nut_glow_mat = AcornShield.mesh().surface_get_material(0).duplicate()
		_nut_glow_mat.next_pass = _acorn_glow
	return _nut_glow_mat


func _add_beam(col: Color) -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.12
	cyl.height = 3.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_color(1, Color(col, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	mat.albedo_texture = gt
	cyl.material = mat
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 1.5
	add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.position.y = 0.5
	add_child(light)
