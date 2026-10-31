class_name BurrowMouth
extends Node3D
## One of Nibbles's burrows (the Kernel Hunt's Act III, FoamMission): the
## mouth of a cardboard tube dug into one of the hamster's heaps of bedding
## (HamsterCage.burrows), and the tunnels behind it run toward the toy room.
## While it's `open` and you're near, the Touched come up out of it every so
## often (`climb_out`: the mission brings them). Nothing you can shoot shuts
## it: a blast does (Events.explosion: a grenade, a rocket, a ranger's
## rocket too), and the heap caves in over it (`caved_in`).

signal climb_out(at: Vector3, out: Vector3)
signal caved_in

const MOUTH := 5.5             ## metres from its mouth a blast has to be to cave it in (and its radius on top)
const EVERY := 16.0            ## seconds between the Touched coming up out of it...
const FIRST := 4.0             ## ...the first, this long after it's open
const NEAR := 130.0            ## metres: only while you're this near
const MOST := 3                ## of its own up at once, at most

var out := Vector3.FORWARD     ## (flat) the way its mouth faces
var tube: Node3D
var open := false              ## sending them up (the mission's step to cave them in)
var caved := false
var climbed: Array[Critter] = []
var _t := FIRST
var _dark: MeshInstance3D


func _init() -> void:
	name = "BurrowMouth"


func _ready() -> void:
	add_to_group(&"burrows")
	Events.explosion.connect(_on_blast)
	# the dark inside of the tube, so the mouth reads as a hole
	_dark = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.05
	disc.radial_segments = 20
	_dark.mesh = disc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.035, 0.02)
	m.roughness = 1.0
	_dark.material_override = m
	_dark.basis = Basis(IKMath.from_to(Vector3.UP, out))   # (its face toward where the mouth looks out)
	_dark.position = Vector3(0.0, 1.2, 0.0) + out * 0.4
	add_child(_dark)


## Open: they start coming up out of it (and it's on your HUD and minimap).
func open_up() -> void:
	if caved:
		return
	open = true
	_t = FIRST
	add_to_group(&"objectives")


func _process(delta: float) -> void:
	if not open or caved:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = EVERY
	climbed = climbed.filter(func(c): return is_instance_valid(c) and c.alive)
	if climbed.size() < MOST and _you_near():
		BossFX.dust(global_position + out * 1.5, 3.0, Color(0.62, 0.5, 0.32, 0.7))
		Audio.play_at(&"burrow_scrabble", global_position, 0.0, 0.1, {"max_distance": 160.0, "unit_size": 12.0})
		climb_out.emit(global_position + out * 3.0, out)


func _you_near() -> bool:
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c and c.is_player:
			return c.alive and c.global_position.distance_to(global_position) < NEAR
	return false


func _on_blast(pos: Vector3, radius: float) -> void:
	if caved or not open or not is_inside_tree():
		return
	if pos.distance_to(global_position + out * 1.0) <= MOUTH + radius * 0.5:
		cave_in()


## The heap comes down over its mouth: dust, the tube crushed under the
## bedding, and nothing more comes up out of it.
func cave_in() -> void:
	if caved:
		return
	caved = true
	open = false
	if is_in_group(&"objectives"):
		remove_from_group(&"objectives")
	Audio.play_at(&"burrow_collapse", global_position, 6.0, 0.05, {"max_distance": 400.0, "unit_size": 25.0})
	Events.explosion.emit(global_position, 6.0)
	BossFX.dust(global_position, 10.0, Color(0.62, 0.5, 0.32, 0.8))
	BossFX.dust_column(global_position + Vector3.UP * 2.0, 1.5, 0.3, Color(0.55, 0.44, 0.28, 0.75))
	var tw := create_tween()
	if tube and is_instance_valid(tube):
		tw.tween_property(tube, "global_position", tube.global_position + Vector3.DOWN * 2.4, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(tube, "scale", Vector3(1.0, 0.45, 1.0), 0.5)
	tw.parallel().tween_property(_dark, "scale", Vector3.ONE * 0.01, 0.4)
	# a heap of bedding slumped over where its mouth was
	var heap := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 4.5
	dome.height = 3.6
	dome.radial_segments = 18
	dome.rings = 8
	heap.mesh = dome
	heap.material_override = CageKit.mat(&"shaving")
	add_child(heap)
	heap.position = out * 1.0
	heap.scale = Vector3(1.0, 0.05, 1.0)
	tw.parallel().tween_property(heap, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	caved_in.emit()
