class_name CritterDef
extends Resource
## One species: which model to load and how it moves, jumps and squeaks.

enum Gait { RUN, HOP }
## The move each species pulls off in the air when it jumps.
enum JumpStyle {
	FLIP,       ## bunnies: front flip / back flip / side flip by travel direction
	SPIN,       ## squirrel: a 360° twirl
	POUNCE,     ## fox: nose up, then a head-first mousing dive
	TUCK_ROLL,  ## raccoon: a tucked cannonball somersault
	FROG_LEAP,  ## frog: streamlined leap, legs fully extended
	TAIL_SLAP,  ## beaver: lean back, land with a tail slap
	BARREL,     ## hamster: a sideways hamster-ball roll
}

@export var id: StringName
@export var display_name := "Critter"
@export_file("*.glb") var model_path := ""
@export_file("*.json") var rig_path := ""
@export var fur_color := Color(0.6, 0.45, 0.3)
## Uniform size multiplier on top of the model's normalised height (models are
## built with the skull top at ~0.85–1.15 m; this makes them read bigger).
@export var body_scale := 1.0
## Extra padding on the per-bone hit capsules (small critters get more).
@export var hitbox_scale := 1.15
@export var max_health := 100.0
@export var move_speed := 6.5
@export var sprint_speed := 9.5
@export var jump_height := 1.6
@export var gait := Gait.RUN
@export var jump_style := JumpStyle.FLIP
@export var voice_pitch := 1.0
@export var wears_acorn_helmet := false
## The species' own club, pulled out to fight with bare paws.
@export var melee_name := "Club"
@export_file("*.glb") var melee_model := ""

const FALLBACK_MODEL := "res://assets/test/test_critter.glb"
const FALLBACK_RIG := "res://assets/test/test_critter.rig.json"


## Skins from assets/characters/<id>/skins.json:
## [{"id": "default", "name": "Classic"}, {"id": "snow", "name": "Snowshoe",
##   "albedo": {"<material name>": "skins/snow_x.jpg"}}, ...]
func skins() -> Array:
	var path := model_path.get_base_dir().path_join("skins.json")
	var list: Array = []
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Array:
			list = data
	if list.is_empty() or list[0].get("id") != "default":
		list.push_front({"id": "default", "name": "Classic"})
	return list


func skin(skin_id: String) -> Dictionary:
	for s in skins():
		if s.get("id") == skin_id:
			return s
	return {"id": "default", "name": "Classic"}


## One-line description of the species' jump trick (for the character picker).
func jump_blurb() -> String:
	return ["Front flip, back flip or side flip — whichever way you're going",
		"A full 360° twirl", "A nose-first mousing pounce", "A tucked cannonball somersault",
		"A long, fully stretched leap", "A lean-back hop with a tail slap landing",
		"A sideways barrel roll"][jump_style]


func resolved_model() -> String:
	return model_path if ResourceLoader.exists(model_path) else FALLBACK_MODEL


func resolved_rig() -> String:
	return rig_path if ResourceLoader.exists(model_path) and FileAccess.file_exists(rig_path) else FALLBACK_RIG
