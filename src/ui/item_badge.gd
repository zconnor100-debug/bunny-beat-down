class_name ItemBadge
extends PanelContainer
## One of the things you carry to use, on the HUD above your gun slots: its
## picture (assets/ui/item_<name>.png), how many you hold (out of how many
## you can), and the button that uses it. Dimmed when you have none.

const SIZE := Vector2(132, 74)

var _count: Label
var _key: Label
var _icon: TextureRect


func _init(picture: String) -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	add_child(h)
	_icon = TextureRect.new()
	_icon.texture = load("res://assets/ui/item_%s.png" % picture) if ResourceLoader.exists("res://assets/ui/item_%s.png" % picture) else null
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(62, 62)
	h.add_child(_icon)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	_count = UITheme.label("", 28, UITheme.CREAM, true)
	v.add_child(_count)
	_key = UITheme.label("", 15, UITheme.CREAM)
	v.add_child(_key)


## `n` of `most`, used with `key` (its on-screen prompt).
func show_count(n: int, most: int, key: String) -> void:
	_count.text = "%d/%d" % [n, most]
	_key.text = "[%s]" % key
	modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.45)
