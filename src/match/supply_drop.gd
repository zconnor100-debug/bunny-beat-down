class_name SupplyDrop
extends Node3D
## A crate drifting down under a dandelion-seed parachute. On touchdown the
## chute floats away and the crate becomes a LootCrate stocked with high-tier
## carrot guns — worth crossing the map (and the line of fire) for. Your
## call-in (Arsenal) is one too: faster, beside you, with your guns in it,
## for you alone.

const MODEL := "res://assets/props/supply_drop.glb"
const FALL_SPEED := 3.5
const WEIGHTS := [0.0, 0.0, 20.0, 45.0, 35.0]   # Prize / Heirloom / Golden only

var landing := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var fall_speed := FALL_SPEED
var contents: Array = []      ## exactly these (LootCrate.contents): a call-in
var player_only := false
var _model: Node3D
var _chute: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group(&"supply_drops")
	_model = ModelUtil.instantiate(MODEL)
	if _model:
		add_child(_model)
		_chute = ModelUtil.find_named(_model, "Chute")
	var light := OmniLight3D.new()
	light.light_color = Rarity.COLORS[Rarity.Tier.GOLDEN]
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position.y = 0.6
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	global_position.y = maxf(landing.y, global_position.y - fall_speed * delta)
	rotation.y += delta * 0.3
	if _model:
		_model.rotation.z = sin(_t * 1.3) * 0.08
	if global_position.y <= landing.y + 0.01:
		_land()


func _land() -> void:
	set_physics_process(false)
	var crate := LootCrate.new()
	crate.weights = WEIGHTS
	crate.model_path = MODEL
	crate.rng.seed = rng.randi()
	crate.supply = contents.is_empty()
	crate.contents = contents
	crate.player_only = player_only
	get_parent().add_child(crate)
	crate.global_position = landing
	crate.rotation.y = rotation.y
	Audio.play_at(&"land", landing, 4.0)
	FX.impact(landing, Vector3.UP, &"dirt")
	queue_free()
