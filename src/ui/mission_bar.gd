class_name MissionBar
extends VBoxContainer
## A Kernel Hunt mission on the HUD (top centre, like a boss's BossBar): its
## title, a bar and what's going on, as the mission's director has them
## (MissionDirector.bar_*). The prologue's: the Big Red Barn, how much of it
## the Touched haven't worn away, and the waves; Act I's: the carrots pulled,
## the Patch catching, the way to Boulder Bluff.

const WIDTH := 640.0
const FILL := Color(0.86, 0.2, 0.12)       ## the Barn's red
const WORN := Color(0.8, 1.0, 0.34)        ## the Touched's gold-green, where it's worn away

var director: MissionDirector
var _name: Label
var _status: Label
var _bar: Control
var _shown := 1.0
var _flash := 0.0
var _last := 1.0


func _init(d: MissionDirector) -> void:
	director = d
	_shown = clampf(d.bar_fill(), 0.0, 1.0) if d else 1.0
	_last = _shown
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_name = UITheme.label(d.bar_title() if d else "", 26, UITheme.CREAM, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(WIDTH, 22)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_status = UITheme.label("", 20, UITheme.CARROT_LIGHT, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)


## What the status line says now (tests read it too).
func status() -> String:
	return director.bar_status()


func _process(delta: float) -> void:
	if director == null or not is_instance_valid(director) or not director.bar_shown():
		visible = false
		return
	visible = true
	_name.text = director.bar_title()
	var frac := clampf(director.bar_fill(), 0.0, 1.0)
	if frac < _last - 0.0001:
		_flash = 0.2
	_last = frac
	_shown = move_toward(_shown, frac, delta * 0.3) if _shown > frac else frac
	_flash = maxf(0.0, _flash - delta)
	_status.text = status()
	var on := int(Time.get_ticks_msec() / 260) % 2 == 0
	_status.add_theme_color_override("font_color", (WORN if on else UITheme.CREAM) if director.bar_warn() \
		else (UITheme.LEAF if director.bar_good() else UITheme.CREAM))
	_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.04, 0.03, 0.78)
	back.set_corner_radius_all(11)
	back.border_color = Color(0.0, 0.0, 0.0, 0.9)
	back.set_border_width_all(3)
	_bar.draw_style_box(back, r)
	if director == null or not is_instance_valid(director):
		return
	var frac := clampf(director.bar_fill(), 0.0, 1.0)
	var inner := r.grow(-4.0)
	if _shown > frac:   # (what was just worn away, in the Touched's colour, fading)
		var lost := StyleBoxFlat.new()
		lost.bg_color = Color(WORN, 0.85)
		lost.set_corner_radius_all(8)
		_bar.draw_style_box(lost, Rect2(inner.position, Vector2(inner.size.x * _shown, inner.size.y)))
	if frac > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = director.bar_color().lerp(Color.WHITE, _flash * 2.0)
		fill.set_corner_radius_all(8)
		_bar.draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.x * frac, 16.0), inner.size.y)))


static func _mmss(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]
