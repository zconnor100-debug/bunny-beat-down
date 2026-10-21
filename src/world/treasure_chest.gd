class_name TreasureChest
extends LootCrate
## A banded treasure chest: the best loot on the island, but it takes a few
## seconds of standing still with interact held to unlock — out in the open.
## The rare golden chest takes the full five seconds and never holds less than
## Heirloom gear.

const CHEST_MODEL := "res://assets/props/treasure_chest.glb"
const GOLDEN_MODEL := "res://assets/props/treasure_chest_golden.glb"
const WEIGHTS := [0.0, 0.0, 30.0, 45.0, 25.0]          # Prize / Heirloom / Golden
const GOLDEN_WEIGHTS := [0.0, 0.0, 0.0, 55.0, 45.0]    # Heirloom / Golden

var golden := false


func _init(golden_ := false) -> void:
	golden = golden_
	model_path = GOLDEN_MODEL if golden else CHEST_MODEL
	weights = GOLDEN_WEIGHTS if golden else WEIGHTS
	open_time = 5.0 if golden else 3.5
	extra_weapons = 2 if golden else 1
	display_name = "golden treasure chest" if golden else "treasure chest"


func _ready() -> void:
	super._ready()
	# a faint glint so chests are findable but not neon
	var light := OmniLight3D.new()
	light.light_color = Rarity.COLORS[Rarity.Tier.GOLDEN] if golden else Color(1.0, 0.85, 0.55)
	light.light_energy = 1.2 if golden else 0.6
	light.omni_range = 3.0
	light.position = Vector3(0, 0.9, 0.3)
	light.shadow_enabled = false
	add_child(light)


func open(by: Node) -> void:
	if opened:
		return
	super.open(by)
	for l in find_children("*", "OmniLight3D", false, false):
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 1.5)
