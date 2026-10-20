extends Control
# Thin line slider with a round knob (Sound Space Quantum Editor style) in
# Chromia colours. Horizontal, or vertical with `vertical = true`.
# The label (if any) is drawn above, centred: label_format % value.

signal value_changed(value)

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)

var min_value := 0.0
var max_value := 1.0
var step := 0.0
var value := 0.0 setget set_value
var vertical := false
var label_format := "" # e.g. "Beat Divisor: %d"
var label_scale := 1.0 # value shown = value * label_scale
var font: Font
var _drag := false

func set_value(v: float):
	v = clamp(v, min_value, max_value)
	if step > 0:
		v = min_value + round((v - min_value) / step) * step
	value = v
	update()

func _ready():
	mouse_filter = MOUSE_FILTER_STOP

func _track() -> Array:
	# [start, end] points of the line
	if vertical:
		var top := 8.0
		return [Vector2(rect_size.x / 2, rect_size.y - 6), Vector2(rect_size.x / 2, top)]
	var y := rect_size.y - 7
	return [Vector2(7, y), Vector2(rect_size.x - 7, y)]

func _ratio() -> float:
	return 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)

func _set_from(pos: Vector2):
	var t = _track()
	var a: Vector2 = t[0]
	var b: Vector2 = t[1]
	var r := 0.0
	if vertical:
		r = (a.y - pos.y) / max(a.y - b.y, 1)
	else:
		r = (pos.x - a.x) / max(b.x - a.x, 1)
	var old := value
	set_value(min_value + clamp(r, 0, 1) * (max_value - min_value))
	if value != old:
		emit_signal("value_changed", value)

func _gui_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed:
			_set_from(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		_set_from(ev.position)
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
		var d := step if step > 0 else (max_value - min_value) / 20.0
		var old := value
		set_value(value + (d if ev.button_index == BUTTON_WHEEL_UP else -d))
		if value != old:
			emit_signal("value_changed", value)
		accept_event()

func _draw():
	var t = _track()
	var a: Vector2 = t[0]
	var b: Vector2 = t[1]
	draw_line(a, b, ACCENT, 3.0)
	var k: Vector2 = a.linear_interpolate(b, _ratio())
	draw_circle(k, 5.5, LILAC)
	if font and label_format != "" and not vertical:
		var v = value * label_scale
		var s: String = label_format % v
		var w := font.get_string_size(s).x
		draw_string(font, Vector2((rect_size.x - w) / 2, font.get_ascent()), s, LILAC)
