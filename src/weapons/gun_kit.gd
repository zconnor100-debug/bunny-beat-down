class_name GunKit
extends RefCounted
## Dresses a carrot-gun model in the player's Workshop kit: a red-dot sight
## on the gun's own Sight marker (a tube around the aiming line with a glowing
## dot on it, so in first person the dot sits right where the carrots go), a
## laser pointer under the muzzle with its beam, and a skin over the gun's
## materials. Used for the gun in your paws and the first-person viewmodel.
## `kit`: {"sight": bool, "laser": bool, "skin": Workshop look id}.

const SKIN_SHADER := preload("res://src/fx/gun_skin.gdshader")
## [pattern, colour a, b, c, strength, metallic, roughness, pattern scale]
const SKINS := {
	"fern_camo": [1, Color(0.2, 0.33, 0.15), Color(0.36, 0.5, 0.22), Color(0.55, 0.49, 0.3), 0.9, 0.0, 0.8, 16.0],
	"candy": [2, Color(0.95, 0.18, 0.24), Color(0.98, 0.95, 0.92), Color.WHITE, 0.85, 0.0, 0.35, 10.0],
	"midnight": [0, Color(0.07, 0.08, 0.17), Color.WHITE, Color.WHITE, 0.85, 0.5, 0.35, 1.0],
	"bubblegum": [0, Color(1.0, 0.55, 0.78), Color.WHITE, Color.WHITE, 0.75, 0.0, 0.25, 1.0],
	"frost": [3, Color(0.72, 0.86, 1.0), Color(0.95, 0.98, 1.0), Color.WHITE, 0.8, 0.1, 0.2, 22.0],
	"gilded": [4, Color(1.0, 0.78, 0.3), Color(0.82, 0.58, 0.18), Color.WHITE, 0.92, 1.0, 0.25, 12.0],
	# earned only, at the top of a Mastery ladder (a hundred beat-downs with a gun, mostly)
	"ruby": [0, Color(0.62, 0.04, 0.1), Color.WHITE, Color.WHITE, 0.88, 0.7, 0.16, 1.0],
	"toxic": [2, Color(0.55, 0.95, 0.15), Color(0.07, 0.09, 0.05), Color.WHITE, 0.88, 0.0, 0.4, 12.0],
	"ember": [1, Color(0.95, 0.36, 0.05), Color(0.55, 0.08, 0.03), Color(0.12, 0.06, 0.04), 0.9, 0.2, 0.5, 14.0],
	"jade": [1, Color(0.1, 0.45, 0.32), Color(0.32, 0.72, 0.52), Color(0.05, 0.25, 0.17), 0.9, 0.35, 0.22, 12.0],
	"obsidian": [1, Color(0.03, 0.025, 0.045), Color(0.09, 0.06, 0.14), Color(0.02, 0.02, 0.03), 0.97, 0.0, 0.32, 9.0],
	"pearl": [3, Color(0.97, 0.84, 0.9), Color(0.8, 0.88, 1.0), Color.WHITE, 0.88, 0.45, 0.12, 9.0],
	"royal": [4, Color(0.42, 0.18, 0.72), Color(0.95, 0.75, 0.3), Color.WHITE, 0.9, 0.9, 0.25, 12.0],
	"zebra": [2, Color(0.05, 0.05, 0.05), Color(0.96, 0.95, 0.92), Color.WHITE, 0.9, 0.0, 0.5, 14.0],
	"carrot_king": [2, Color(1.0, 0.5, 0.08), Color(1.0, 0.82, 0.25), Color.WHITE, 0.9, 0.8, 0.25, 10.0],
	"sapphire": [0, Color(0.07, 0.18, 0.72), Color.WHITE, Color.WHITE, 0.88, 0.75, 0.14, 1.0],
	"diamond": [3, Color(0.93, 0.98, 1.0), Color(0.75, 0.92, 1.0), Color.WHITE, 0.9, 0.2, 0.04, 40.0],
	"looking_glass": [3, Color(0.42, 0.46, 0.52), Color(0.7, 0.74, 0.8), Color.WHITE, 0.9, 1.0, 0.03, 30.0],
	"nemesis": [5, Color(1.0, 0.78, 0.3), Color(0.8, 0.55, 0.16), Color(1.0, 0.1, 0.03), 0.94, 1.0, 0.25, 16.0],
	# earned by beating a boss (Mastery: Unwound)
	"tin_tyrant": [6, Color(0.7, 0.74, 0.8), Color(0.14, 0.15, 0.18), Color(0.82, 0.1, 0.06), 0.95, 0.85, 0.3, 9.0],
}
const DOT_RED := Color(1.0, 0.12, 0.08)
const TUBE_R := 0.03              ## the sight's tube (model units, round the gun's own sight)
const TUBE_LENGTH := 0.09
const BEAM_LENGTH := 7.0          ## metres of laser beam (in the world)

static var _mats: Dictionary = {}


## Dress `model` (a gun, at `world_scale` metres per model unit). Golden guns
## keep their gold (a skin would hide the rarity).
static func dress(model: Node3D, kit: Dictionary, world_scale: float, golden := false) -> void:
	if model == null or kit.is_empty():
		return
	var sight := model.find_child("Sight", true, false) as Node3D
	var muzzle := model.find_child("Muzzle", true, false) as Node3D
	if kit.get("sight", false) and sight:
		model.add_child(_red_dot(sight.position))
	if kit.get("laser", false) and muzzle:
		model.add_child(_laser(muzzle.position, BEAM_LENGTH / maxf(world_scale, 0.001)))
	var skin: String = kit.get("skin", "stock")
	if SKINS.has(skin) and not golden:
		var m := skin_material(skin)
		for gi in model.find_children("*", "GeometryInstance3D", true, false):
			if not (gi as Node).has_meta(&"kit"):
				(gi as GeometryInstance3D).material_overlay = m


static func skin_material(skin: String) -> ShaderMaterial:
	if _mats.has(skin):
		return _mats[skin]
	var s: Array = SKINS[skin]
	var m := ShaderMaterial.new()
	m.shader = SKIN_SHADER
	m.set_shader_parameter(&"pattern", s[0])
	m.set_shader_parameter(&"color_a", s[1])
	m.set_shader_parameter(&"color_b", s[2])
	m.set_shader_parameter(&"color_c", s[3])
	m.set_shader_parameter(&"strength", s[4])
	m.set_shader_parameter(&"metallic_v", s[5])
	m.set_shader_parameter(&"roughness_v", s[6])
	m.set_shader_parameter(&"pattern_scale", s[7])
	_mats[skin] = m
	return m


## A short tube round the aiming line (centred on the Sight marker), on a
## mount, with the dot glowing on the line at its front.
static func _red_dot(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "RedDot"
	root.position = at
	var body := _mat(Color(0.16, 0.16, 0.18), 0.4, 0.5)
	var ring := _mat(Color(1.0, 0.55, 0.12), 0.0, 0.5)
	var tube := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = TUBE_R
	tm.bottom_radius = TUBE_R
	tm.height = TUBE_LENGTH
	tm.radial_segments = 20
	tm.cap_top = false
	tm.cap_bottom = false
	tube.mesh = tm
	tube.rotation.x = PI / 2.0
	tube.material_override = body
	_tag(tube, root)
	var lip := MeshInstance3D.new()
	var lm := TorusMesh.new()
	lm.inner_radius = TUBE_R - 0.002
	lm.outer_radius = TUBE_R + 0.006
	lm.rings = 24
	lip.mesh = lm
	lip.rotation.x = PI / 2.0
	lip.position.z = -TUBE_LENGTH * 0.5
	lip.material_override = ring
	_tag(lip, root)
	var mount := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.024, 0.03, 0.06)
	mount.mesh = mm
	mount.position.y = -TUBE_R - 0.012
	mount.material_override = body
	_tag(mount, root)
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.0028
	dm.height = 0.0056
	dot.mesh = dm
	dot.position.z = -TUBE_LENGTH * 0.45
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = DOT_RED
	glow.emission_enabled = true
	glow.emission = DOT_RED
	glow.emission_energy_multiplier = 3.0
	dot.material_override = glow
	_tag(dot, root)
	return root


## A little box under the barrel and a thin glowing beam out of it.
static func _laser(muzzle: Vector3, length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Laser"
	root.position = muzzle + Vector3(0.0, -0.026, 0.13)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.018, 0.018, 0.055)
	box.mesh = bm
	box.material_override = _mat(Color(0.16, 0.16, 0.18), 0.4, 0.5)
	_tag(box, root)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0025
	cm.bottom_radius = 0.0025
	cm.height = length
	cm.radial_segments = 6
	beam.mesh = cm
	beam.rotation.x = PI / 2.0
	beam.position.z = -0.0275 - length * 0.5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(DOT_RED, 0.45)
	m.emission_enabled = true
	m.emission = DOT_RED
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tag(beam, root)
	return root


static func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _tag(n: Node3D, parent: Node3D) -> void:
	n.set_meta(&"kit", true)   # (skins leave the kit itself alone)
	parent.add_child(n)
