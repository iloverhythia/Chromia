extends VBoxContainer

# Cursor trail gradient editor ("World & Cursor" settings tab, under the trail options).
# Built in code. Usage (from menu2.gd _ready):
#   load("res://scripts/ui/settings/TrailGradientSettings.gd").attach(self)
#
# Data: Rhythia.trail_gradient_enabled, Rhythia.trail_gradient = [[offset, "rrggbbaa"], ...]
# Bar: click the line to add a point, drag a point to move it, right-click to remove it
# (the endpoints at 0 and 1 always stay).

const TrailGradient = preload("res://scripts/game/TrailGradient.gd")
const H_PATH = "Main/Settings/S/F/TabContainer/World & Cursor/Cursor/Group/H"

const TEXT_COLOR = Color(0.898039, 0.94902, 1, 1)
const ACCENT = Color(1, 0.756863, 0.960784)
const LILAC = Color(0.764706, 0.65098, 0.8)

const HSV_SHADER = """
shader_type canvas_item;
uniform float hue = 0.0;
uniform bool hue_bar = false;
vec3 h2rgb(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
void fragment() {
	if (hue_bar) {
		COLOR = vec4(h2rgb(UV.y), 1.0);
	} else {
		COLOR = vec4(mix(vec3(1.0), h2rgb(hue), UV.x) * (1.0 - UV.y), 1.0);
	}
}
"""

static func attach(menu: Node):
	if menu == null: return
	var h = menu.get_node_or_null(H_PATH)
	if h == null or h.has_node("TrailGradient"): return
	var ui = load("res://scripts/ui/settings/TrailGradientSettings.gd").new()
	ui.name = "TrailGradient"
	ui._h = h
	var after = h.get_node_or_null("TrailOpacity")
	h.add_child(ui)
	if after:
		h.move_child(ui, after.get_index() + 1)

var _h: Node
var pts: Array = []        # [[offset float, Color], ...] sorted
var selected = null        # one entry of pts (arrays are references)
var hue: float = 0.0
var sat: float = 0.0
var val: float = 1.0

var enable_box: CheckBox
var bar: Control
var sv: Control
var sv_overlay: Control
var hue_ctl: Control
var hue_overlay: Control
var sv_mat: ShaderMaterial
var swatch: ColorRect
var hex_edit: LineEdit
var editor: VBoxContainer
var save_timer: Timer
var font: Font

# ---------------------------------------------------------------- building

func _label(text: String, col: Color = TEXT_COLOR) -> Label:
	var l = Label.new()
	l.text = text
	l.valign = Label.VALIGN_CENTER
	if font: l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	return l

func _ready():
	add_constant_override("separation", 4)
	var tmpl_label = _h.get_node_or_null("TrailOpacity/Label") if _h else null
	if tmpl_label: font = tmpl_label.get("custom_fonts/font")
	var theme_res = load("res://uitheme.tres")
	if theme_res: theme = theme_res

	pts = TrailGradient.parse_points(Rhythia.trail_gradient)
	selected = pts[0]

	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.4
	save_timer.connect("timeout", self, "_save_now")
	add_child(save_timer)

	var sep_t = _h.get_node_or_null("SEPARATOR3") if _h else null
	if sep_t: add_child(sep_t.duplicate())

	var cb_t = _h.get_node_or_null("CursorTrail") if _h else null
	if cb_t:
		enable_box = cb_t.duplicate()
		enable_box.set("target", "trail_gradient_enabled")
	else:
		enable_box = CheckBox.new()
	enable_box.name = "EnableGradient"
	enable_box.text = "Enable Gradient"
	enable_box.hint_tooltip = "colors the cursor trail along its length (left = newest, right = oldest)"
	enable_box.pressed = Rhythia.trail_gradient_enabled
	enable_box.connect("toggled", self, "_on_enable_toggled")
	add_child(enable_box)

	editor = VBoxContainer.new()
	editor.add_constant_override("separation", 4)
	add_child(editor)

	var hint = _label("click to add · drag to move · right-click to remove", Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, 0.6))
	hint.autowrap = true
	editor.add_child(hint)

	bar = GradBar.new()
	bar.ui = self
	bar.rect_min_size = Vector2(0, 42)
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	editor.add_child(bar)

	editor.add_child(_label("Point Color", ACCENT))

	var row = HBoxContainer.new()
	row.add_constant_override("separation", 6)
	editor.add_child(row)

	var shader = Shader.new()
	shader.code = HSV_SHADER

	sv = Control.new()
	sv.rect_min_size = Vector2(170, 110)
	sv.mouse_default_cursor_shape = Control.CURSOR_CROSS
	sv.connect("gui_input", self, "_sv_input")
	row.add_child(sv)
	var sv_rect = ColorRect.new()
	sv_mat = ShaderMaterial.new()
	sv_mat.shader = shader
	sv_rect.material = sv_mat
	sv_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	sv.add_child(sv_rect)
	sv_overlay = Control.new()
	sv_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	sv_overlay.connect("draw", self, "_draw_sv_overlay")
	sv.add_child(sv_overlay)

	hue_ctl = Control.new()
	hue_ctl.rect_min_size = Vector2(20, 110)
	hue_ctl.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	hue_ctl.connect("gui_input", self, "_hue_input")
	row.add_child(hue_ctl)
	var hue_rect = ColorRect.new()
	var hue_mat = ShaderMaterial.new()
	hue_mat.shader = shader
	hue_mat.set_shader_param("hue_bar", true)
	hue_rect.material = hue_mat
	hue_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hue_rect.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	hue_ctl.add_child(hue_rect)
	hue_overlay = Control.new()
	hue_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hue_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	hue_overlay.connect("draw", self, "_draw_hue_overlay")
	hue_ctl.add_child(hue_overlay)

	var side = VBoxContainer.new()
	side.add_constant_override("separation", 6)
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(side)
	swatch = ColorRect.new()
	swatch.rect_min_size = Vector2(0, 30)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(swatch)
	hex_edit = LineEdit.new()
	hex_edit.rect_min_size = Vector2(0, 32)
	hex_edit.hint_tooltip = "hex color (press enter)"
	hex_edit.connect("text_entered", self, "_on_hex_entered")
	side.add_child(hex_edit)
	var reset = Button.new()
	reset.text = "Reset"
	reset.hint_tooltip = "reset the trail gradient to the default"
	reset.rect_min_size = Vector2(0, 32)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
		reset.add_color_override(k, Color(0, 0, 0))
	reset.connect("pressed", self, "_on_reset")
	side.add_child(reset)

	_select(selected)
	_update_enabled()

# ---------------------------------------------------------------- state

func _update_enabled():
	if editor:
		editor.modulate = Color(1, 1, 1, 1) if Rhythia.trail_gradient_enabled else Color(1, 1, 1, 0.45)

func _on_enable_toggled(on: bool):
	Rhythia.trail_gradient_enabled = on
	_update_enabled()
	_queue_save()

func _select(p):
	if p == null or not pts.has(p):
		p = pts[0]
	selected = p
	var c: Color = p[1]
	if c.s > 0.001 and c.v > 0.001:
		hue = c.h
	sat = c.s
	val = c.v
	_refresh_color_ui()
	if bar: bar.update()

func _refresh_color_ui():
	if sv_mat: sv_mat.set_shader_param("hue", hue)
	if swatch and selected: swatch.color = selected[1]
	if hex_edit and selected and not hex_edit.has_focus():
		hex_edit.text = (selected[1] as Color).to_html(false)
	if sv_overlay: sv_overlay.update()
	if hue_overlay: hue_overlay.update()

func _apply_hsv():
	if selected == null: return
	var a = (selected[1] as Color).a
	selected[1] = Color.from_hsv(hue, sat, val, a)
	_refresh_color_ui()
	if bar: bar.update()
	_changed()

func _sort_points():
	pts.sort_custom(TrailGradient.PointSorter, "less")

func _changed():
	Rhythia.trail_gradient = TrailGradient.serialize(pts)
	_queue_save()

func _queue_save():
	if save_timer and save_timer.is_inside_tree():
		save_timer.start()
	else:
		_save_now()

func _save_now():
	Rhythia.save_settings()

func _exit_tree():
	if save_timer and not save_timer.is_stopped():
		save_timer.stop()
		_save_now()

func _on_reset():
	pts = TrailGradient.parse_points(TrailGradient.DEFAULT_POINTS)
	_select(pts[0])
	_changed()

func _on_hex_entered(t: String):
	t = t.strip_edges()
	if not t.is_valid_html_color():
		_refresh_color_ui()
		return
	var c = Color(t)
	c.a = 1.0
	if c.s > 0.001 and c.v > 0.001: hue = c.h
	sat = c.s
	val = c.v
	hex_edit.release_focus()
	_apply_hsv()

# bar callbacks
func add_point_at(x: float):
	x = clamp(x, 0.0, 1.0)
	var p = [x, TrailGradient.sample(pts, x)]
	pts.append(p)
	_sort_points()
	_select(p)
	_changed()
	return p

func move_point(p, x: float):
	if p == null or p == pts[0] or p == pts[pts.size() - 1]: return
	p[0] = clamp(x, 0.001, 0.999)
	_sort_points()
	# keep endpoints pinned even if a middle point is dragged past them
	pts[0][0] = 0.0
	pts[pts.size() - 1][0] = 1.0
	bar.update()
	_changed()

func remove_point(p):
	if p == null or pts.size() <= 2 or p == pts[0] or p == pts[pts.size() - 1]: return
	var i = pts.find(p)
	pts.erase(p)
	_select(pts[clamp(i - 1, 0, pts.size() - 1)])
	_changed()

# ---------------------------------------------------------------- SV / hue

func _sv_input(ev):
	if (ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT and ev.pressed) or (ev is InputEventMouseMotion and ev.button_mask & BUTTON_MASK_LEFT):
		var s = sv.rect_size
		sat = clamp(ev.position.x / max(s.x, 1.0), 0.0, 1.0)
		val = clamp(1.0 - ev.position.y / max(s.y, 1.0), 0.0, 1.0)
		_apply_hsv()
		sv.accept_event()

func _hue_input(ev):
	if (ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT and ev.pressed) or (ev is InputEventMouseMotion and ev.button_mask & BUTTON_MASK_LEFT):
		hue = clamp(ev.position.y / max(hue_ctl.rect_size.y, 1.0), 0.0, 0.9999)
		_apply_hsv()
		hue_ctl.accept_event()

func _draw_sv_overlay():
	var s = sv_overlay.rect_size
	sv_overlay.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6), false, 1.0)
	var p = Vector2(sat * s.x, (1.0 - val) * s.y)
	sv_overlay.draw_arc(p, 6, 0, TAU, 20, Color(0, 0, 0, 0.8), 2.5, true)
	sv_overlay.draw_arc(p, 6, 0, TAU, 20, Color(1, 1, 1), 1.5, true)

func _draw_hue_overlay():
	var s = hue_overlay.rect_size
	hue_overlay.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6), false, 1.0)
	var y = hue * s.y
	hue_overlay.draw_rect(Rect2(Vector2(-2, y - 2), Vector2(s.x + 4, 4)), Color(0, 0, 0, 0.8), false, 1.0)
	hue_overlay.draw_rect(Rect2(Vector2(-1, y - 1), Vector2(s.x + 2, 2)), Color(1, 1, 1), true)

# ---------------------------------------------------------------- gradient bar

class GradBar extends Control:
	var ui
	var dragging = null
	var grad_tex: GradientTexture
	const BAR_H = 22.0
	const HANDLE_W = 12.0
	const HANDLE_H = 16.0
	const PAD = 7.0

	func _init():
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		grad_tex = GradientTexture.new()
		grad_tex.width = 256
		grad_tex.gradient = Gradient.new()

	func _x_to_off(x: float) -> float:
		return clamp((x - PAD) / max(rect_size.x - PAD * 2.0, 1.0), 0.0, 1.0)

	func _off_to_x(o: float) -> float:
		return PAD + o * (rect_size.x - PAD * 2.0)

	func _point_at(pos: Vector2):
		var best = null
		var best_d = HANDLE_W * 0.75
		for p in ui.pts:
			var d = abs(_off_to_x(p[0]) - pos.x)
			if d <= best_d:
				best_d = d
				best = p
		return best

	func _gui_input(ev):
		if ev is InputEventMouseButton:
			if ev.button_index == BUTTON_LEFT:
				if ev.pressed:
					var p = _point_at(ev.position)
					if p == null:
						p = ui.add_point_at(_x_to_off(ev.position.x))
					else:
						ui._select(p)
					var is_end = (p == ui.pts[0] or p == ui.pts[ui.pts.size() - 1])
					dragging = null if is_end else p
				else:
					dragging = null
				accept_event()
			elif ev.button_index == BUTTON_RIGHT and ev.pressed:
				var p = _point_at(ev.position)
				if p != null: ui.remove_point(p)
				accept_event()
		elif ev is InputEventMouseMotion and dragging != null:
			if ev.button_mask & BUTTON_MASK_LEFT:
				ui.move_point(dragging, _x_to_off(ev.position.x))
			else:
				dragging = null
			accept_event()

	func _draw():
		if ui == null: return
		var g: Gradient = grad_tex.gradient
		var offs = PoolRealArray()
		var cols = PoolColorArray()
		for p in ui.pts:
			offs.append(p[0])
			cols.append(p[1])
		g.offsets = offs
		g.colors = cols
		var r = Rect2(Vector2(PAD, 2), Vector2(rect_size.x - PAD * 2.0, BAR_H))
		# checker under the gradient so alpha would be visible
		draw_rect(r, Color(0.12, 0.1, 0.14))
		draw_texture_rect(grad_tex, r, false)
		draw_rect(r.grow(1), Color(0.764706, 0.65098, 0.8, 0.8), false, 1.0)
		for p in ui.pts:
			var x = _off_to_x(p[0])
			var top = r.end.y + 1
			var sel = (p == ui.selected)
			var tri = PoolVector2Array([Vector2(x, top), Vector2(x + HANDLE_W / 2, top + 5), Vector2(x + HANDLE_W / 2, top + HANDLE_H), Vector2(x - HANDLE_W / 2, top + HANDLE_H), Vector2(x - HANDLE_W / 2, top + 5)])
			draw_colored_polygon(tri, p[1])
			var outline = PoolVector2Array(tri)
			outline.append(tri[0])
			draw_polyline(outline, Color(1, 0.756863, 0.960784) if sel else Color(0.1, 0.08, 0.12), 2.0 if sel else 1.0, true)
			if sel:
				draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.7), 1.0)
