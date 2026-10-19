extends Control

# Preview of the gameplay screen for the Background Editor. Layers can be
# dragged to move, resized with the corner handles (Shift keeps the aspect
# ratio) and rotated with the top handle (Shift snaps to 15 degrees).
# Right click asks the editor for the context menu.

signal layer_selected(index)
signal layer_changed(index) # after a drag ends
signal context_requested(index, global_pos)
signal delete_requested(index)

const BG = preload("res://scripts/BgLayers.gd")
const HANDLE_R = 7.0
const ROT_DIST = 26.0
const MIN_PX = 8.0

const BG_COL = Color(0.05, 0.045, 0.07)
const GRID_COL = Color(1, 0.756863, 0.960784, 0.55)
const SEL_COL = Color(1, 0.756863, 0.960784)
const HANDLE_FILL = Color(0.764706, 0.65098, 0.8)

var layers: Array = [] # dictionaries owned by the editor
var rects: Array = [] # TextureRect per layer (same order)
var selected: int = -1

var _layer_root: Control
var _overlay: Control

enum { DRAG_NONE, DRAG_MOVE, DRAG_RESIZE, DRAG_ROTATE }
var _drag: int = DRAG_NONE
var _drag_start_mouse := Vector2()
var _drag_start := {}
var _drag_corner := Vector2() # (+-1, +-1)
var _dragged := false

func _init():
	rect_clip_content = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	_layer_root = Control.new()
	_layer_root.name = "Layers"
	_layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_root)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.connect("draw", self, "_draw_overlay")
	connect("resized", self, "_on_resized")

func layer_root() -> Control:
	return _layer_root

func _on_resized():
	_layer_root.rect_size = rect_size
	_overlay.rect_size = rect_size
	relayout()

func relayout():
	for i in rects.size():
		if i < layers.size():
			BG.apply_visual(rects[i], layers[i], rect_size)
	_overlay.update()

func refresh_layer(i: int):
	if i >= 0 and i < rects.size() and i < layers.size():
		BG.apply_visual(rects[i], layers[i], rect_size)
	_overlay.update()

func set_selected(i: int):
	selected = i
	_overlay.update()

# --- geometry -------------------------------------------------------------

func _center(l: Dictionary) -> Vector2:
	return Vector2(l.x * rect_size.x, l.y * rect_size.y)

func _size(l: Dictionary) -> Vector2:
	return Vector2(l.w * rect_size.x, l.h * rect_size.y)

func _corner_pos(l: Dictionary, corner: Vector2) -> Vector2:
	return _center(l) + (corner * _size(l) / 2.0).rotated(deg2rad(l.rot))

func _rot_handle_pos(l: Dictionary) -> Vector2:
	var p = _center(l) + Vector2(0, -_size(l).y / 2.0 - ROT_DIST).rotated(deg2rad(l.rot))
	if Rect2(Vector2(), rect_size).grow(-HANDLE_R).has_point(p):
		return p
	# Off the preview (e.g. a fullscreen layer): put the handle just inside.
	return _center(l) + Vector2(0, -_size(l).y / 2.0 + ROT_DIST).rotated(deg2rad(l.rot))

func _hit_layer(p: Vector2) -> int:
	for i in range(layers.size() - 1, -1, -1):
		var l = layers[i]
		var local = (p - _center(l)).rotated(-deg2rad(l.rot))
		var half = _size(l) / 2.0
		if abs(local.x) <= half.x and abs(local.y) <= half.y:
			return i
	return -1

const CORNERS = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]

# --- input -----------------------------------------------------------------

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position, event.shift)
			else:
				_end_drag()
			accept_event()
		elif event.button_index == BUTTON_RIGHT and event.pressed:
			var i = _hit_layer(event.position)
			if i != -1:
				set_selected(i)
				emit_signal("layer_selected", i)
				emit_signal("context_requested", i, event.global_position)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_DELETE:
		if selected >= 0:
			emit_signal("delete_requested", selected)
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag != DRAG_NONE:
			_update_drag(event.position, event.shift)
			accept_event()
		else:
			_update_cursor(event.position)

func _handle_at(p: Vector2) -> Array:
	if selected < 0 or selected >= layers.size():
		return []
	var l = layers[selected]
	if p.distance_to(_rot_handle_pos(l)) <= HANDLE_R + 3:
		return ["rotate"]
	for c in CORNERS:
		if p.distance_to(_corner_pos(l, c)) <= HANDLE_R + 3:
			return ["resize", c]
	return []

func _update_cursor(p: Vector2):
	var h = _handle_at(p)
	var shape = Control.CURSOR_ARROW
	if h.size() > 0:
		shape = Control.CURSOR_POINTING_HAND if h[0] == "rotate" else Control.CURSOR_FDIAGSIZE
	elif _hit_layer(p) != -1:
		shape = Control.CURSOR_MOVE
	if mouse_default_cursor_shape != shape:
		mouse_default_cursor_shape = shape

func _begin_drag(p: Vector2, _shift: bool):
	grab_focus()
	var h = _handle_at(p)
	if h.size() > 0:
		_drag = DRAG_ROTATE if h[0] == "rotate" else DRAG_RESIZE
		if h[0] == "resize":
			_drag_corner = h[1]
	else:
		var i = _hit_layer(p)
		if i != selected:
			set_selected(i)
			emit_signal("layer_selected", i)
		if i == -1:
			_drag = DRAG_NONE
			return
		_drag = DRAG_MOVE
	_drag_start_mouse = p
	_drag_start = layers[selected].duplicate()
	_dragged = false

func _update_drag(p: Vector2, shift: bool):
	if selected < 0 or selected >= layers.size():
		_drag = DRAG_NONE
		return
	var l: Dictionary = layers[selected]
	var s0 = _drag_start
	var W = max(rect_size.x, 1.0)
	var H = max(rect_size.y, 1.0)
	_dragged = true
	match _drag:
		DRAG_MOVE:
			var d = p - _drag_start_mouse
			l.x = s0.x + d.x / W
			l.y = s0.y + d.y / H
		DRAG_ROTATE:
			var c = Vector2(l.x * W, l.y * H)
			var ang = rad2deg((p - c).angle() + PI / 2.0)
			if shift:
				ang = stepify(ang, 15.0)
			ang = fposmod(ang + 180.0, 360.0) - 180.0
			l.rot = ang
		DRAG_RESIZE:
			var r = deg2rad(s0.rot)
			var size0 = Vector2(s0.w * W, s0.h * H)
			var c0 = Vector2(s0.x * W, s0.y * H)
			var anchor = c0 + (-_drag_corner * size0 / 2.0).rotated(r) # opposite corner stays put
			var local = (p - anchor).rotated(-r)
			var nw = max(MIN_PX, local.x * _drag_corner.x)
			var nh = max(MIN_PX, local.y * _drag_corner.y)
			if shift and size0.x > 0 and size0.y > 0:
				var k = max(nw / size0.x, nh / size0.y)
				nw = max(MIN_PX, size0.x * k)
				nh = max(MIN_PX, size0.y * k)
			var nc = anchor + (_drag_corner * Vector2(nw, nh) / 2.0).rotated(r)
			l.w = nw / W
			l.h = nh / H
			l.x = nc.x / W
			l.y = nc.y / H
	refresh_layer(selected)

func _end_drag():
	if _drag != DRAG_NONE and _dragged and selected >= 0:
		emit_signal("layer_changed", selected)
	_drag = DRAG_NONE
	_dragged = false

# --- drawing ---------------------------------------------------------------

func _draw():
	draw_rect(Rect2(Vector2(), rect_size), BG_COL)

func _draw_overlay():
	# Mock note grid (3x3) in the middle of the screen, drawn on top so it can
	# be seen through the layers.
	var g = rect_size.y * 0.42
	var o = rect_size / 2.0 - Vector2(g, g) / 2.0
	_overlay.draw_rect(Rect2(o, Vector2(g, g)), GRID_COL, false, 2.0)
	for k in [1, 2]:
		var t = g * k / 3.0
		_overlay.draw_line(o + Vector2(t, 0), o + Vector2(t, g), Color(GRID_COL.r, GRID_COL.g, GRID_COL.b, 0.25), 1.0)
		_overlay.draw_line(o + Vector2(0, t), o + Vector2(g, t), Color(GRID_COL.r, GRID_COL.g, GRID_COL.b, 0.25), 1.0)
	_overlay.draw_rect(Rect2(Vector2(), rect_size), Color(1, 1, 1, 0.12), false, 1.0)
	if selected < 0 or selected >= layers.size():
		return
	var l = layers[selected]
	var pts = PoolVector2Array()
	for c in CORNERS:
		pts.append(_corner_pos(l, c))
	pts.append(pts[0])
	_overlay.draw_polyline(pts, SEL_COL, 2.0)
	var top_mid = (pts[0] + pts[1]) / 2.0
	var rh = _rot_handle_pos(l)
	_overlay.draw_line(top_mid, rh, SEL_COL, 2.0)
	_overlay.draw_circle(rh, HANDLE_R, SEL_COL)
	_overlay.draw_circle(rh, HANDLE_R - 2.5, BG_COL)
	for i in 4:
		var cp = pts[i]
		_overlay.draw_rect(Rect2(cp - Vector2(HANDLE_R, HANDLE_R) * 0.8, Vector2(HANDLE_R, HANDLE_R) * 1.6), SEL_COL)
		_overlay.draw_rect(Rect2(cp - Vector2(HANDLE_R, HANDLE_R) * 0.5, Vector2(HANDLE_R, HANDLE_R) * 1.0), HANDLE_FILL)
