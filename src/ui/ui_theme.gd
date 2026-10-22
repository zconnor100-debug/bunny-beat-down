class_name UITheme
## The game's look in code: garden-shed palette, Fredoka for text, Lilita One
## for titles, chunky rounded buttons.

const CREAM := Color("fff4e0")
const BARK := Color("6b4423")
const BARK_DARK := Color("3d2614")
const CARROT := Color("f28c28")
const CARROT_LIGHT := Color("ffb15c")
const LEAF := Color("5fa83a")
const LEAF_DARK := Color("3c7224")
const BERRY := Color("d9483b")
const INK := Color("2b2118")
const SKY := Color("8ec9ef")
const ACORN := Color("a8743d")

const FONT_TEXT := "res://assets/fonts/Fredoka-Variable.ttf"
const FONT_TITLE := "res://assets/fonts/LilitaOne-Regular.ttf"

static var _theme: Theme
static var _fonts: Dictionary = {}


static func text_font(weight := 500) -> Font:
	var key := "text_%d" % weight
	if not _fonts.has(key):
		var base: FontFile = load(FONT_TEXT) if ResourceLoader.exists(FONT_TEXT) else null
		if base == null:
			_fonts[key] = ThemeDB.fallback_font
		else:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
			_fonts[key] = fv
	return _fonts[key]


static func title_font() -> Font:
	if not _fonts.has("title"):
		_fonts["title"] = load(FONT_TITLE) if ResourceLoader.exists(FONT_TITLE) else ThemeDB.fallback_font
	return _fonts["title"]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = text_font(500)
	t.default_font_size = 22
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(INK, 0.85))
	t.set_constant("outline_size", "Label", 6)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.corner_radius_bottom_left = 18
		sb.corner_radius_bottom_right = 18
		sb.content_margin_left = 26
		sb.content_margin_right = 26
		sb.content_margin_top = 10
		sb.content_margin_bottom = 12
		sb.border_width_bottom = 6
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 6
		match state:
			"normal":
				sb.bg_color = BARK
				sb.border_color = BARK_DARK
			"hover", "focus":
				sb.bg_color = CARROT
				sb.border_color = Color("b65c0e")
			"pressed":
				sb.bg_color = Color("d96f12")
				sb.border_color = Color("8a4209")
				sb.border_width_bottom = 2
				sb.content_margin_top = 14
				sb.content_margin_bottom = 8
			"disabled":
				sb.bg_color = Color(BARK, 0.5)
				sb.border_color = Color(BARK_DARK, 0.5)
		if state == "focus":
			sb.border_width_left = 3
			sb.border_width_right = 3
			sb.border_width_top = 3
			sb.border_color = CREAM
		t.set_stylebox(state, "Button", sb)
	t.set_font("font", "Button", text_font(650))
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(INK, 0.82)
	panel.corner_radius_top_left = 22
	panel.corner_radius_top_right = 22
	panel.corner_radius_bottom_left = 22
	panel.corner_radius_bottom_right = 22
	panel.border_width_bottom = 4
	panel.border_width_top = 4
	panel.border_width_left = 4
	panel.border_width_right = 4
	panel.border_color = Color(BARK, 0.9)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	# sliders / checkboxes / option buttons
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = CARROT
	grabber_area.corner_radius_top_left = 6
	grabber_area.corner_radius_bottom_left = 6
	grabber_area.content_margin_top = 6
	grabber_area.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", grabber_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(CREAM, 0.25)
	slider.corner_radius_top_left = 6
	slider.corner_radius_top_right = 6
	slider.corner_radius_bottom_left = 6
	slider.corner_radius_bottom_right = 6
	slider.content_margin_top = 6
	slider.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider)
	# toggles are just the switch, not a whole button slab
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "OptionButton", 22)
	t.set_font_size("font_size", "CheckButton", 22)
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font("normal_font", "RichTextLabel", text_font(450))
	t.set_font("bold_font", "RichTextLabel", text_font(700))
	t.set_font_size("normal_font_size", "RichTextLabel", 20)
	t.set_font_size("bold_font_size", "RichTextLabel", 22)
	_theme = t
	return t


static func label(text: String, size := 22, color := CREAM, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font())
		l.add_theme_constant_override("outline_size", maxi(8, size / 6))
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		Audio.play(&"ui_click", -6.0)
		on_press.call())
	b.mouse_entered.connect(func(): Audio.play(&"ui_hover", -14.0, 0.0))
	b.focus_mode = Control.FOCUS_ALL
	return b
