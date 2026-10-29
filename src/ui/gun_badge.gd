class_name GunBadge
extends PanelContainer
## One of your gun slots on the HUD, under the item badges: a long, soft-edged
## badge with the gun's picture side on (assets/ui/gun_<id>.png), its name and
## its slot number, framed in its rarity's colour. The gun in your paws has a
## thicker, glowing frame; an empty slot is dimmed.

const PICTURE := Vector2(176, 58)

## Frames, cached per (rarity, selected) so the HUD allocates nothing per frame.
static var _styles: Dictionary = {}

var _number: Label
var _picture: TextureRect
var _name: Label
var _shown: StringName = &"-"


func _init(slot: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	add_child(h)
	_number = UITheme.label("%d" % (slot + 1), 20, Color(UITheme.CREAM, 0.75), true)
	_number.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	h.add_child(_number)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.custom_minimum_size = PICTURE
	v.add_child(_picture)
	_name = UITheme.label("", 16, UITheme.CREAM)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.custom_minimum_size.x = PICTURE.x
	v.add_child(_name)
	show_gun(null, false)


## The gun in this slot (null: empty), and whether it's the one in your paws.
func show_gun(w: WeaponInstance, selected: bool) -> void:
	var id: StringName = w.data.id if w else &""
	if id != _shown:
		_shown = id
		var path := "res://assets/ui/gun_%s.png" % id
		_picture.texture = load(path) if w and ResourceLoader.exists(path) else null
		_name.text = w.data.display_name.replace("Carrot ", "") if w else "Empty"
	add_theme_stylebox_override("panel", style(w.rarity if w else -1, selected))
	modulate = Color.WHITE if w or selected else Color(1, 1, 1, 0.45)


static func style(rarity: int, selected: bool) -> StyleBoxFlat:
	var key := rarity * 2 + int(selected)
	if not _styles.has(key):
		var sb := StyleBoxFlat.new()
		var edge: Color = Rarity.COLORS[rarity] if rarity >= 0 else Color(UITheme.BARK, 0.9)
		sb.bg_color = Color(UITheme.INK, 0.95 if selected else 0.8)
		sb.border_color = edge
		sb.set_border_width_all(5 if selected else 3)
		sb.set_corner_radius_all(22)
		sb.content_margin_left = 14
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if selected:
			sb.shadow_color = Color(edge, 0.55)
			sb.shadow_size = 9
		_styles[key] = sb
	return _styles[key]
