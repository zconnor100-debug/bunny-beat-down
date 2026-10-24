class_name CreditsPanel
extends PanelContainer
## The designated credits page. Built at runtime from assets/credits/*.json —
## the same files tools/gen_credits.py turns into CREDITS.md — so the in-game
## credits and the repository credits can never disagree. Links open in the
## browser.

signal closed

const STICK_SCROLL := 1400.0   # px/s at full stick tilt
const DIR := "res://assets/credits"
const SECTIONS := {
	"characters": "Critters",
	"environment": "Scenery: the island, the cage and the fridge",
	"maps": "Map models (made in Blender)",
	"weapons_props": "Carrot Guns & Props",
	"audio": "Sound & Music",
	"fonts": "Fonts",
}

var _text: RichTextLabel


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1100, 760)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var title := UITheme.label("Credits", 56, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(1000, 560)
	_text.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
	_text.text = build_bbcode()
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.add_child(UITheme.button("Engine licenses", func(): _text.text = _engine_licenses()))
	row.add_child(UITheme.button("Asset credits", func(): _text.text = build_bbcode()))
	var back := UITheme.button("Back", func(): closed.emit())
	row.add_child(back)
	v.add_child(row)
	back.grab_focus.call_deferred()


## Either stick scrolls the list; B / Escape goes back.
func _process(delta: float) -> void:
	var tilt := Input.get_axis(&"look_up", &"look_down") + Input.get_axis(&"move_forward", &"move_back")
	if tilt != 0.0:
		_text.get_v_scroll_bar().value += clampf(tilt, -1.0, 1.0) * STICK_SCROLL * delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


static func load_entries() -> Dictionary:
	var out := {}
	var files: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			files.append(f)
	files.sort_custom(func(a, b): return _order(a) < _order(b))
	for f in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		if data is Array:
			out[f.get_basename()] = data
	return out


static func _order(f: String) -> int:
	var keys := SECTIONS.keys()
	var i := keys.find(f.get_basename())
	return i if i >= 0 else 99


static func build_bbcode() -> String:
	var s := "[center][b]Bunny Beat Down[/b] — created by Zachary Connor with Godot 4.6\n"
	s += "Code, procedural animation, gore and AI: original work (MIT). Everything below belongs to its creators — thank you![/center]\n\n"
	var all := load_entries()
	for key in all:
		s += "[font_size=30][color=#ffb15c]%s[/color][/font_size]\n" % SECTIONS.get(key, key.capitalize())
		for e in all[key]:
			s += "[b]%s[/b]" % _esc(e.get("asset", "?"))
			var author: String = e.get("author", "")
			if author != "":
				var au: String = e.get("author_url", "")
				s += " by " + (("[url=%s]%s[/url]" % [au, _esc(author)]) if au != "" else _esc(author))
			var lic: String = e.get("license", "")
			var lu: String = e.get("license_url", "")
			s += " — " + (("[url=%s]%s[/url]" % [lu, lic]) if lu != "" else lic)
			var src: String = e.get("source_url", "")
			if src != "":
				s += " — [url=%s]source[/url]" % src
			for extra in ["attribution", "note"]:
				var t: String = e.get(extra, "")
				if t != "":
					s += "\n    [i]%s[/i]" % _esc(t)
			var used: String = e.get("used_for", "")
			var changes: String = e.get("changes", "")
			if used != "" or changes != "":
				s += "\n    [color=#d8cdb8]%s%s[/color]" % [("Used for: " + _esc(used)) if used != "" else "", ("   •   Changes: " + _esc(changes)) if changes != "" else ""]
			s += "\n"
		s += "\n"
	return s


static func _engine_licenses() -> String:
	var s := "[center][b]Godot Engine[/b][/center]\n%s\n\n[b]Third-party components bundled with the engine[/b]\n" % _esc(Engine.get_license_text())
	for info in Engine.get_copyright_info():
		s += "\n[b]%s[/b]\n" % _esc(info.get("name", ""))
		for part in info.get("parts", []):
			s += "  %s — %s\n" % [_esc(", ".join(part.get("copyright", []))), _esc(part.get("license", ""))]
	return s


static func _esc(t: String) -> String:
	return t.replace("[", "[lb]")
