class_name ChewBlock
extends LootCrate
## A wooden chew block to dam Water Bottle Falls with (the Kernel Hunt's
## Act III, FoamMission): hold interact by it to pick it up (only you), and
## you carry it over your head, slowly (CARRY_SPEED), into the Dam. Knocked
## off your feet or beaten down, you drop it where you fell, to be picked up
## again. On the HUD and the minimap while it's lying there to be fetched.

signal picked_up(by: Critter)
signal dropped

const SIZE := 2.6              ## metres across
const CARRY_SPEED := 0.65      ## of your speed, carrying it
const MATS := [&"paint_red", &"paint_blue", &"paint_yellow", &"paint_lime", &"paint_purple"]

var carrier: Critter
var placed := false            ## in the dam now
var _look: Node3D


func _init(tint := 0) -> void:
	open_time = 0.6
	display_name = "the chew block"
	channel_verb = "Lifting"
	name = "ChewBlock"
	set_meta(&"tint", tint)


func _ready() -> void:
	add_to_group(&"glow_carrots")   # (what you pull up or pick up: PlayerController's focus)
	add_to_group(&"objectives")
	collision_layer = 0
	collision_mask = 0
	height = SIZE
	reach = SIZE * 0.6
	var mat: StringName = MATS[int(get_meta(&"tint", 0)) % MATS.size()]
	_look = CageKit.model(ToyProps.made("cage/chew_block"), {"accent": mat})
	if _look == null:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mi.mesh = box
		mi.material_override = CageKit.mat(mat)
		mi.position.y = 0.5
		_look = mi
	var holder := Node3D.new()
	holder.name = "Look"
	holder.add_child(_look)
	_look.scale = Vector3.ONE * SIZE
	add_child(holder)
	_look = holder


## Only you pick it up, and only with your paws free.
func channel(by: Critter, delta: float) -> bool:
	if not by.is_player or carrier != null or placed or ChewBlock.carried_by(by) != null:
		return false
	return super.channel(by, delta)


func open(by: Node) -> void:
	if carrier != null or placed or not (by is Critter):
		return
	progress = 0.0
	_channeler = null
	carrier = by
	opened = true   # (nobody's focus while it's up)
	remove_from_group(&"objectives")
	carrier.speed_scale *= CARRY_SPEED
	carrier.set_meta(&"carrying", self)
	Audio.play_at(&"pickup_armor", carrier.global_position, -2.0, 0.05)
	picked_up.emit(carrier)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if carrier == null:
		return
	if not is_instance_valid(carrier) or not carrier.alive or carrier.is_knocked():
		drop()
		return
	# over its head, held up in both paws
	global_position = carrier.global_position + Vector3.UP * (carrier.chest_height() * 1.9)
	_look.rotation.y = carrier.rotation.y


## Let go of: it falls where its carrier is, to be fetched again.
func drop() -> void:
	if carrier == null:
		return
	var at := carrier.global_position if is_instance_valid(carrier) else global_position
	_let_go()
	opened = false
	add_to_group(&"objectives")
	var floor_y := Island.current.terrain.height_at(at.x, at.z) if Island.current and Island.current.terrain else at.y
	var tw := create_tween()
	tw.tween_property(self, "global_position", Vector3(at.x + 1.5, floor_y, at.z), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Audio.play_at(&"carrot_impact_wood", at, 0.0, 0.1)
	dropped.emit()


## Into the dam: it's stacked there (Dam.take), for good.
func place() -> void:
	_let_go()
	placed = true
	opened = true


func _let_go() -> void:
	if carrier and is_instance_valid(carrier):
		carrier.speed_scale /= CARRY_SPEED
		if carrier.has_meta(&"carrying") and carrier.get_meta(&"carrying") == self:
			carrier.remove_meta(&"carrying")
	carrier = null


## The chew block `c` is carrying (or null).
static func carried_by(c: Critter) -> ChewBlock:
	if not c.has_meta(&"carrying"):
		return null
	var b: Variant = c.get_meta(&"carrying")
	return b as ChewBlock if is_instance_valid(b) else null
