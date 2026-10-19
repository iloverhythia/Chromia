extends Button

# Small star toggle drawn in code (no font glyph / asset needed).
# Used on each colorset tile in the colorset picker.

const FAV_COLOR = Color(1, 0.756863, 0.960784)       # Chromia pink accent
const OFF_COLOR = Color(0.898039, 0.94902, 1, 0.55)
const OFF_HOVER = Color(0.898039, 0.94902, 1, 0.85)

var fav: bool = false setget set_fav
var _pts: PoolVector2Array
var _outline: PoolVector2Array

func set_fav(v: bool):
	fav = v
	hint_tooltip = "Remove from favorites" if fav else "Add to favorites (shown first)"
	update()

func _init():
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rect_min_size = Vector2(22, 22)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_stylebox_override(s, StyleBoxEmpty.new())
	connect("resized", self, "_rebuild")
	connect("mouse_entered", self, "update")
	connect("mouse_exited", self, "update")
	set_fav(false)

func _ready():
	_rebuild()

func _rebuild():
	var c = rect_size / 2.0
	var r_out = min(rect_size.x, rect_size.y) * 0.46
	var r_in = r_out * 0.45
	_pts = PoolVector2Array()
	for i in 10:
		var ang = -PI / 2.0 + i * PI / 5.0
		var r = r_out if i % 2 == 0 else r_in
		_pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	_outline = PoolVector2Array(_pts)
	_outline.append(_pts[0])
	update()

func _draw():
	if _pts.size() < 10:
		return
	var hover = is_hovered()
	if fav:
		draw_colored_polygon(_pts, FAV_COLOR)
		draw_polyline(_outline, Color(0.25, 0.12, 0.25, 0.9), 1.5, true)
	else:
		if hover:
			draw_colored_polygon(_pts, Color(1, 0.756863, 0.960784, 0.25))
		draw_polyline(_outline, Color(0, 0, 0, 0.45), 3.0, true)
		draw_polyline(_outline, OFF_HOVER if hover else OFF_COLOR, 1.5, true)
