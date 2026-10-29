class_name AcornShrine
extends LootCrate
## An acorn shrine: a mossy stump with a big golden acorn bobbing over it. Hold
## interact by it for a moment and it offers you a boon (Boons: pick one of
## three). A few on every map, one use each, and only for you: bots walk on by
## (it isn't in the crates or treasure groups they look for).

const STUMP := "res://assets/env/stump_mossy/stump_mossy.glb"
const ACORN := "res://assets/env/acorn/acorn.glb"
## Drawn big, like the guns lying about, so you spot one from across a
## clearing: the stump to a Bun's waist, the acorn a head tall.
const STUMP_HEIGHT := 1.0
const ACORN_HEIGHT := 0.8
const STUMP_RADIUS := 0.75         ## (its collider; the roots splay wider)
const HOVER := 0.05                ## the acorn bobs just over the stump
## Room a shrine needs on the ground (half its size).
const ROOM := Vector3(1.0, 0.9, 1.0)
const GLOW := Color(1.0, 0.8, 0.35)

signal used(by: Critter)

var _acorn: Node3D
var _light: OmniLight3D
var _t := 0.0


func _init() -> void:
	open_time = 1.5
	display_name = "acorn shrine"


func _ready() -> void:
	add_to_group(&"shrines")
	collision_layer = Layers.WORLD
	set_meta(&"surface", &"wood")
	var stump := _sized(STUMP, STUMP_HEIGHT)
	if stump == null:
		stump = _fallback(CylinderMesh.new(), Color(0.42, 0.3, 0.18), Vector3(0, STUMP_HEIGHT * 0.5, 0))
	add_child(stump)
	_acorn = _sized(ACORN, ACORN_HEIGHT)
	if _acorn == null:
		_acorn = _fallback(SphereMesh.new(), Color(0.75, 0.5, 0.2), Vector3.ZERO)
	var holder := Node3D.new()
	holder.position.y = STUMP_HEIGHT + HOVER
	holder.add_child(_acorn)
	add_child(holder)
	_acorn = holder
	var halo := Sprite3D.new()   # (a soft golden glow behind the acorn, always facing you)
	halo.texture = FXTextures.soft_blob()
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.modulate = Color(GLOW, 0.55)
	halo.pixel_size = 2.2 / maxf(halo.texture.get_width(), 1.0)
	halo.shaded = false
	halo.no_depth_test = false
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position.y = ACORN_HEIGHT * 0.5
	holder.add_child(halo)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 2.4
	_light.omni_range = 5.0
	_light.position = Vector3(0, STUMP_HEIGHT + HOVER + ACORN_HEIGHT * 0.5, 0.6)
	_light.shadow_enabled = false
	add_child(_light)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = STUMP_RADIUS
	shape.height = STUMP_HEIGHT
	height = STUMP_HEIGHT + ACORN_HEIGHT
	reach = STUMP_RADIUS
	cs.shape = shape
	cs.position.y = STUMP_HEIGHT * 0.5
	add_child(cs)


func _process(delta: float) -> void:
	if opened or _acorn == null:
		return
	_t += delta
	_acorn.position.y = STUMP_HEIGHT + HOVER + sin(_t * 2.0) * 0.1
	_acorn.rotation.y += delta * 0.8


## Only you can pray here.
func channel(by: Critter, delta: float) -> bool:
	if not by.is_player:
		return false
	return super.channel(by, delta)


func open(by: Node) -> void:
	if opened:
		return
	opened = true
	progress = 1.0
	Audio.play_at(&"crate_open", global_position, 2.0)
	FX.muzzle(global_position + Vector3.UP * (STUMP_HEIGHT + ACORN_HEIGHT * 0.5), Vector3.UP, true, Color(GLOW, 0.9))
	var tw := create_tween()
	tw.tween_property(_acorn, "scale", Vector3.ONE * 1.6, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_acorn, "scale", Vector3.ONE * 0.01, 0.35)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.6)
	if by is Critter:
		used.emit(by)


## The model at `path`, scaled to `height` metres, standing on its base.
static func _sized(path: String, height: float) -> Node3D:
	var m := ModelUtil.instantiate(path)
	if m == null:
		return null
	var box := ModelUtil.aabb_of(m)
	if box.size.y > 0.001:
		var k := height / box.size.y
		var c := box.get_center()
		m.scale = Vector3.ONE * k
		m.position = Vector3(-c.x, -box.position.y, -c.z) * k
	return m


static func _fallback(mesh: PrimitiveMesh, c: Color, at: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mesh.material = mat
	if mesh is CylinderMesh:
		(mesh as CylinderMesh).height = STUMP_HEIGHT
		(mesh as CylinderMesh).top_radius = STUMP_RADIUS
		(mesh as CylinderMesh).bottom_radius = STUMP_RADIUS * 1.1
	elif mesh is SphereMesh:
		(mesh as SphereMesh).radius = ACORN_HEIGHT * 0.4
		(mesh as SphereMesh).height = ACORN_HEIGHT
	mi.mesh = mesh
	mi.position = at
	return mi
