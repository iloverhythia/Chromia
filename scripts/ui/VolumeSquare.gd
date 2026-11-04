extends Control

# The Alt + scroll volume popup (Savia._change_volume): a small square in the
# bottom right with a speaker, a fill that rises with the volume and the
# percentage under it. Faded in and out by Savia (modulate).

const SIZE := 86.0
var value := 1.0
var _font: DynamicFont

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_left = -SIZE - 20
	margin_top = -SIZE - 20
	margin_right = -20
	margin_bottom = -20
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_font.size = 15

func set_value(v: float):
	value = clamp(v, 0.0, 1.0)
	update()

func _draw():
	var r := Rect2(Vector2.ZERO, rect_size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.08, 0.92)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, r)
	# the fill, from the bottom, behind everything else
	var inner := r.grow(-5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 0.756863, 0.960784, 0.22)
	fill.set_corner_radius_all(8)
	var h: float = inner.size.y * value
	if h > 1:
		draw_style_box(fill, Rect2(inner.position.x, inner.end.y - h, inner.size.x, h))
	# the speaker, with a wave for each third of the volume
	var c := Vector2(rect_size.x * 0.5 - 8, rect_size.y * 0.4)
	var col := Color(0.92, 0.95, 1.0)
	draw_rect(Rect2(c + Vector2(-12, -6), Vector2(7, 12)), col)
	draw_colored_polygon(PoolVector2Array([c + Vector2(-5, -6), c + Vector2(4, -14), c + Vector2(4, 14), c + Vector2(-5, 6)]), col)
	if value <= 0.001:
		draw_line(c + Vector2(10, -7), c + Vector2(22, 7), col, 2.5, true)
		draw_line(c + Vector2(22, -7), c + Vector2(10, 7), col, 2.5, true)
	else:
		for i in range(3):
			if value > i / 3.0:
				draw_arc(c + Vector2(4, 0), 8 + i * 6, -0.9, 0.9, 12, col, 2.0, true)
	var txt := "%d%%" % int(round(value * 100))
	var ts := _font.get_string_size(txt)
	draw_string(_font, Vector2((rect_size.x - ts.x) / 2, rect_size.y - 12), txt, col)
