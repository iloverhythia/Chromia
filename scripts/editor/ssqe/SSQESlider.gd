extends Control
# SSQE's GuiSlider in Chromia's colours: a thin line with a dot, a hexagon
# around it while hovered. Values go from 0 to max_value in steps of `step`
# (with Shift, step * shift_increment); right-click resets to `default`.
# Vertical when taller than wide (`reverse` puts 0 at the bottom).

signal changed(value)

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)

var max_value := 1.0
var step := 0.01
var shift_increment := 1.0
var default := 0.0
var value := 0.0
var reverse := false
var can_reset := true
var line_color := ACCENT
var dot_color := LILAC
var dragging := false
var _hover := 0.0
var _hovering := false

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	connect("mouse_entered", self, "_on_enter")
	connect("mouse_exited", self, "_on_exit")

func _on_enter():
	_hovering = true

func _on_exit():
	_hovering = false

func horizontal() -> bool:
	return rect_size.x > rect_size.y

func line_rect() -> Rect2:
	var r := Rect2(Vector2(), rect_size)
	if horizontal():
		return Rect2(r.size.y / 2, r.size.y / 2 - 1.5, r.size.x - r.size.y, 3)
	return Rect2(r.size.x / 2 - 1.5, r.size.x / 2, 3, r.size.y - r.size.x)

func progress() -> float:
	var p := 0.5 if max_value == 0 else value / max_value
	if reverse:
		p = 1.0 - p
	return p

func marker_pos() -> Vector2:
	var l := line_rect()
	var p := progress()
	if horizontal():
		return Vector2(l.position.x + l.size.x * p, l.position.y + l.size.y / 2)
	return Vector2(l.position.x + l.size.x / 2, l.position.y + l.size.y * p)

func _set_from(pos: Vector2):
	var h := horizontal()
	var width := (rect_size.y - rect_size.x) * (-1.0 if h else 1.0)
	var st := step / max(max_value, 0.000001)
	if not Input.is_key_pressed(KEY_SHIFT):
		st /= shift_increment
	var start := rect_size.y / 2 if h else rect_size.x / 2
	var m := pos.x if h else pos.y
	var raw := m - start if h else ((width - m + start) if reverse else m - start)
	var prog := round(raw / width / st) * st if st > 0 else raw / width
	var v: float = clamp(max_value * prog, 0, max_value)
	if v != value:
		value = v
		emit_signal("changed", value)
	update()

func _gui_input(ev):
	if ev is InputEventMouseButton:
		if ev.button_index == BUTTON_LEFT:
			dragging = ev.pressed
			if ev.pressed:
				_set_from(ev.position)
			accept_event()
		elif ev.button_index == BUTTON_RIGHT and ev.pressed:
			if can_reset:
				value = default
				emit_signal("changed", value)
				update()
			accept_event()
		elif ev.pressed and (ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN):
			var d := step / (1.0 if Input.is_key_pressed(KEY_SHIFT) else shift_increment)
			if d <= 0:
				d = max_value / 20.0
			var up: bool = ev.button_index == BUTTON_WHEEL_UP
			if reverse and not horizontal():
				pass
			var v: float = clamp(value + (d if up else -d), 0, max_value)
			if v != value:
				value = v
				emit_signal("changed", value)
				update()
			accept_event()
	elif ev is InputEventMouseMotion and dragging:
		_set_from(ev.position)
		accept_event()

func _process(delta):
	var target := 1.0 if (_hovering or dragging) else 0.0
	if _hover != target:
		_hover = move_toward(_hover, target, delta * 10.0)
		update()

func _draw():
	var l := line_rect()
	draw_rect(l, line_color)
	var c := marker_pos()
	draw_circle(c, 4.0, dot_color)
	if _hover > 0:
		var radius := 12.0 * _hover
		var rot := deg2rad(90.0 * _hover)
		var pts := PoolVector2Array()
		for k in range(7):
			var a := rot + k * PI / 3.0
			pts.append(c + Vector2(cos(a), sin(a)) * radius)
		draw_polyline(pts, dot_color, 2.0, true)
