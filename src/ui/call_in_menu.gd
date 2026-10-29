class_name CallInMenu
extends VBoxContainer
## The pick of your arsenal's guns as you call it in (PlayerController:
## call_menu): each one you've won on a gun badge (its picture, name and
## number), the one picked out glowing and a little bigger; under them, how to
## choose, pick one and back out, on the pad or the keyboard.

const PICKED_SCALE := 1.12

var _row: HBoxContainer
var _badges: Array[GunBadge] = []
var _hint: Label
var _guns: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 12)
	var title := UITheme.label("CALL IN YOUR ARSENAL", 30, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 22)
	add_child(_row)
	_hint = UITheme.label("", 18, UITheme.CREAM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


## Show `guns` (ids; rebuilt when they change), `choice` picked out.
func show_pick(guns: Array, choice: int) -> void:
	if guns != _guns:
		_guns = guns.duplicate()
		for b in _badges:
			b.queue_free()
		_badges.clear()
		for i in guns.size():
			var b := GunBadge.new(i)
			_row.add_child(b)
			_badges.append(b)
	for i in _badges.size():
		var b := _badges[i]
		b.show_gun(WeaponInstance.new(WeaponDB.get_weapon(_guns[i]), Rarity.Tier.PRIZE), i == choice)
		b.pivot_offset = b.size * 0.5
		b.scale = Vector2.ONE * (PICKED_SCALE if i == choice else 1.0)
	if GameInput.using_pad:
		_hint.text = "◄ ►  choose        [A] or [%s]  call it in        [B]  never mind" % GameInput.prompt(&"call_in")
	else:
		_hint.text = "← →  or  1–%d  choose        [ENTER] or [%s]  call it in        [BACKSPACE]  never mind" % [_guns.size(), GameInput.prompt(&"call_in")]


## The gun picked out now (for tests).
func picked() -> int:
	for i in _badges.size():
		if _badges[i].scale.x > 1.0:
			return i
	return -1
