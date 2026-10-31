class_name KeyPull
extends LootCrate
## The key in a Wound rogue's back once it's wound down (the Kernel Hunt's
## Act II, ClockworkMission): hold interact by it to pull the key out (only
## you: the rangers keep the Wound off you). It goes where the rogue goes, and
## it's on the HUD and the minimap while it's there to pull. `used` when it's
## out; the mission frees the rogue.

signal used(by: Critter)

var rogue: Critter
var key: WindKey


func _init(c: Critter = null, k: WindKey = null) -> void:
	rogue = c
	key = k
	open_time = 1.4
	display_name = "%s's key" % (c.display_name if c else "the")
	channel_verb = "Pulling out"
	name = "KeyPull"


func _ready() -> void:
	add_to_group(&"glow_carrots")   # (what you pull: PlayerController's focus)
	add_to_group(&"objectives")
	collision_layer = 0
	collision_mask = 0
	height = 1.0
	reach = 0.6
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if rogue == null or not is_instance_valid(rogue) or not rogue.alive:
		if not opened:
			queue_free()
		return
	global_position = rogue.global_position + Vector3.UP * 0.4


## Only you pull it.
func channel(by: Critter, delta: float) -> bool:
	if not by.is_player:
		return false
	if key and is_instance_valid(key):
		key.speed = lerpf(40.0, -900.0, progress)   # (it fights you, then backs out)
	return super.channel(by, delta)


func open(by: Node) -> void:
	if opened:
		return
	opened = true
	progress = 1.0
	remove_from_group(&"objectives")
	if key and is_instance_valid(key):
		var at := key.global_position
		Audio.play_at(&"key_pull", at, 2.0, 0.05)
		BossFX.sparks(at, (at - rogue.get_chest_position()).normalized(), 0.5)
		key.reparent(rogue.get_parent())
		var out := (at - rogue.get_chest_position()).normalized()
		var tw := key.create_tween()
		tw.tween_property(key, "global_position", at + out * 1.2 + Vector3.UP * 0.8, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(key, "global_position", Vector3(at.x, rogue.global_position.y + 0.1, at.z) + out * 2.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(key, "rotation:x", key.rotation.x + TAU * 1.5, 0.8)
		key.speed = 0.0
		Despawner.schedule(key, 20.0, 1.0)
	if by is Critter:
		used.emit(by)
	queue_free()
