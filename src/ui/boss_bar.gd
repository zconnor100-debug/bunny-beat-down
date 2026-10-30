class_name BossBar
extends VBoxContainer
## A Boss Battle's boss on the HUD (top centre): its name and billing, its
## health (the bar's notch is where it's enraged), and what it's up to:
## counting down to its arrival, ENRAGED, or stunned and VULNERABLE.

const WIDTH := 760.0
const FILL := Color(0.86, 0.12, 0.08)
const FILL_ANGRY := Color(1.0, 0.36, 0.05)

var boss: Boss
var match_manager: MatchManager
var _name: Label
var _status: Label
var _bar: Control
var _shown := 1.0          # (the bar slides down to its health, not jumps)
var _flash := 0.0


func _init(b: Boss, mm: MatchManager) -> void:
	boss = b
	match_manager = mm
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_name = UITheme.label("", 28, UITheme.CREAM, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(WIDTH, 26)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_status = UITheme.label("", 20, UITheme.CARROT_LIGHT, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	if boss:
		boss.health_changed.connect(func(_h, _m): _flash = 0.25)


func _process(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		visible = false
		return
	var waiting := boss.state == Boss.State.WAITING
	_name.text = "%s, %s" % [boss.display_name.to_upper(), boss.title]
	var frac := boss.health / maxf(boss.max_health, 1.0)
	_shown = move_toward(_shown, frac, delta * 0.35) if _shown > frac else frac
	_flash = maxf(0.0, _flash - delta)
	if waiting:
		var left := match_manager.boss_countdown() if match_manager else -1.0
		var t := ceili(left) if left >= 0.0 else -1
		_status.text = "arrives in %d:%02d" % [t / 60, t % 60] if t >= 0 else "is waiting for everyone to land"
		_status.add_theme_color_override("font_color", UITheme.CREAM)
	elif not boss.alive:
		_status.text = "BEATEN!"
		_status.add_theme_color_override("font_color", UITheme.LEAF)
	elif boss.vulnerable():
		var on := int(Time.get_ticks_msec() / 220) % 2 == 0
		_status.text = "STUNNED: VULNERABLE!" if on else ""
		_status.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	elif boss.enraged:
		_status.text = "ENRAGED"
		_status.add_theme_color_override("font_color", FILL_ANGRY)
	else:
		_status.text = "%d%%" % ceili(frac * 100.0)
		_status.add_theme_color_override("font_color", UITheme.CREAM)
	_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.03, 0.03, 0.78)
	back.set_corner_radius_all(13)
	back.border_color = Color(0.0, 0.0, 0.0, 0.9)
	back.set_border_width_all(3)
	_bar.draw_style_box(back, r)
	if boss == null:
		return
	var frac := clampf(boss.health / maxf(boss.max_health, 1.0), 0.0, 1.0)
	var inner := r.grow(-4.0)
	if _shown > frac:   # (what it just lost, fading out)
		var lost := StyleBoxFlat.new()
		lost.bg_color = Color(1.0, 0.85, 0.6, 0.85)
		lost.set_corner_radius_all(10)
		_bar.draw_style_box(lost, Rect2(inner.position, Vector2(inner.size.x * _shown, inner.size.y)))
	if frac > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = (FILL_ANGRY if boss.enraged else FILL).lerp(Color.WHITE, _flash * 1.6)
		fill.set_corner_radius_all(10)
		_bar.draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.x * frac, 20.0), inner.size.y)))
	# the notch where it gets enraged
	var x := inner.position.x + inner.size.x * Boss.ENRAGE_AT
	_bar.draw_line(Vector2(x, inner.position.y - 2.0), Vector2(x, inner.end.y + 2.0), Color(0, 0, 0, 0.8), 3.0)
