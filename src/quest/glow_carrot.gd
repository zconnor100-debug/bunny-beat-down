class_name GlowCarrot
extends LootCrate
## One of the glowing carrots (the Kernel Hunt's Act I, PatchMission): a
## carrot as big as a bunny, stuck in the ground with its leaves up, the
## Touched's gold-green light shining out of it in crawling veins
## (kernel_glow.gdshader) and, while it's the one to find, a beam of that
## light going up so it can be seen across the island. Hold interact by it
## to pull it up (only you: the rangers keep watch); pulled, it comes up out
## of the ground in a burst of light and fades (`used`), and the mission
## lights the next.

const CARROT_MODEL := "res://assets/env/food_carrot/food_carrot.glb"
const LENGTH := 1.7            ## metres, from its root's tip to the top of its leaves
const SUNK := 0.42             ## how much of it is in the ground
const GLOW := Color(0.8, 1.0, 0.34)    ## (the Touched's gold-green)
const BEAM_HEIGHT := 70.0
const GLOW_SHADER := preload("res://src/quest/kernel_glow.gdshader")

signal used(by: Critter)

var lit := false               ## the one to find: its beam up (`light_up`)
var _carrot: Node3D
var _shape: CollisionShape3D
var _glow: ShaderMaterial
var _beam: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _init() -> void:
	open_time = 1.2
	display_name = "the glowing carrot"
	channel_verb = "Pulling up"


func _ready() -> void:
	add_to_group(&"glow_carrots")
	collision_layer = Layers.WORLD
	set_meta(&"surface", &"wood")
	_carrot = AcornShrine._sized(CARROT_MODEL, LENGTH)
	if _carrot == null:
		_carrot = AcornShrine._fallback(CylinderMesh.new(), Color(0.95, 0.5, 0.12), Vector3(0, LENGTH * 0.5, 0))
	var holder := Node3D.new()
	holder.position.y = -LENGTH * SUNK
	holder.rotation = Vector3(randf_range(-0.12, 0.12), randf() * TAU, randf_range(-0.12, 0.12))   # (not quite straight up)
	holder.add_child(_carrot)
	add_child(holder)
	_carrot = holder
	_glow = ShaderMaterial.new()
	_glow.shader = GLOW_SHADER
	for mi in ModelUtil.find_all(holder, "MeshInstance3D"):
		(mi as MeshInstance3D).material_overlay = _glow
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.position.y = 0.6
	_light.shadow_enabled = false
	add_child(_light)
	_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = LENGTH * (1.0 - SUNK)
	_shape.shape = shape
	_shape.position.y = shape.height * 0.5
	add_child(_shape)
	height = shape.height
	reach = 0.3
	_set_lit(lit)


func _process(delta: float) -> void:
	_t += delta
	if _light and not opened:
		_light.light_energy = (2.6 if lit else 1.0) * (0.8 + 0.2 * sin(_t * 3.1))
	if _beam:
		_beam.rotation.y += delta * 0.4


## The one to find now: its beam goes up.
func light_up() -> void:
	_set_lit(true)


func _set_lit(on: bool) -> void:
	lit = on
	if _glow:
		_glow.set_shader_parameter(&"strength", 1.6 if on else 0.55)   # (they all glow: the one to find most)
	if on and _beam == null:
		_beam = _make_beam()
		add_child(_beam)
	if _beam:
		_beam.visible = on
	if on:
		add_to_group(&"objectives")
	elif is_in_group(&"objectives"):
		remove_from_group(&"objectives")


## Only you pull it, and only the lit one.
func channel(by: Critter, delta: float) -> bool:
	if not by.is_player or not lit:
		return false
	return super.channel(by, delta)


func open(by: Node) -> void:
	if opened:
		return
	opened = true
	progress = 1.0
	_set_lit(false)
	_shape.set_deferred(&"disabled", true)   # (nothing left to stand on)
	Audio.play_at(&"crate_open", global_position, 2.0)
	FX.muzzle(global_position + Vector3.UP * 0.6, Vector3.UP, true, Color(GLOW, 0.9))
	BossFX.dust(global_position, 3.0, Color(0.42, 0.33, 0.22, 0.7))
	var tw := create_tween()
	tw.tween_property(_carrot, "position:y", LENGTH * 0.25, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_carrot, "rotation:y", _carrot.rotation.y + TAU, 0.9)
	tw.tween_property(_carrot, "scale", Vector3.ONE * 0.01, 0.4)
	tw.parallel().tween_property(_light, "light_energy", 0.0, 0.5)
	tw.tween_callback(func(): _carrot.visible = false)
	if by is Critter:
		used.emit(by)


func _make_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.35
	cyl.height = BEAM_HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var g := Gradient.new()
	g.set_color(0, Color(GLOW, 0.0))
	g.add_point(0.75, Color(GLOW, 0.35))
	g.set_color(1, Color(GLOW, 0.7))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	mat.albedo_texture = gt
	cyl.material = mat
	beam.mesh = cyl
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = BEAM_HEIGHT * 0.5 + 0.4
	return beam
