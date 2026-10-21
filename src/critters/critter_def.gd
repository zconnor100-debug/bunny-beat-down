class_name CritterDef
extends Resource
## One species: which model to load and how it moves, jumps and squeaks.

enum Gait { RUN, HOP }

@export var id: StringName
@export var display_name := "Critter"
@export_file("*.glb") var model_path := ""
@export_file("*.json") var rig_path := ""
@export var fur_color := Color(0.6, 0.45, 0.3)
@export var max_health := 100.0
@export var move_speed := 6.5
@export var sprint_speed := 9.5
@export var jump_height := 1.6
@export var gait := Gait.RUN
@export var voice_pitch := 1.0
@export var wears_acorn_helmet := false
@export var spawn_weight := 1.0
## Names the AI critters of this species pick from.
@export var names: PackedStringArray = []

const FALLBACK_MODEL := "res://assets/test/test_critter.glb"
const FALLBACK_RIG := "res://assets/test/test_critter.rig.json"


func resolved_model() -> String:
	return model_path if ResourceLoader.exists(model_path) else FALLBACK_MODEL


func resolved_rig() -> String:
	return rig_path if ResourceLoader.exists(model_path) and FileAccess.file_exists(rig_path) else FALLBACK_RIG
