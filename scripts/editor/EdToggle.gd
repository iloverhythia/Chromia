extends Control
# Round toggle + label (Sound Space Quantum Editor's checkbox), Chromia colours.

signal toggled(on)

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)

var text := ""
var pressed := false setget set_pressed
var font: Font

func set_pressed(v: bool):
	pressed = v
	update()

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND

func _gui_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		pressed = not pressed
		update()
		emit_signal("toggled", pressed)
		accept_event()

func _draw():
	var h := rect_size.y
	var r := h * 0.4
	var c := Vector2(r + 1, h / 2)
	draw_circle(c, r, Color(0.08, 0.075, 0.1))
	draw_arc(c, r, 0, TAU, 32, Color(0.35, 0.33, 0.4), 2.0, true)
	if pressed:
		draw_circle(c, r - 3, ACCENT)
	if font:
		draw_string(font, Vector2(r * 2 + 6, (h - font.get_height()) / 2 + font.get_ascent()), text, LILAC)
