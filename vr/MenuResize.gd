extends Control

# The resize icon in the bottom right corner of the VR menu screen
# (MenuPointer.gd adds it to the screen's viewport):
#  - point at it, hold the trigger and drag: the screen grows or shrinks with
#    the pointer, like resizing a window by its corner
#  - tap it: buttons for the screen size and the size of the text and buttons
# Saved as Settings > VR > Menu screen (Rhythia.vr_menu_size / vr_menu_ui).
#
# A plain Control over the whole menu, not a CanvasLayer: in the menu screen's
# viewport (drawn bigger than it is laid out) a CanvasLayer's controls get the
# pointer at the wrong spot.

const ICON := 52.0
const BG := Color(0.11, 0.09, 0.16, 0.86)
const FG := Color(1, 0.756863, 0.960784)
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)

var screen # MenuPointer.gd
var _icon: Control
var _panel: PanelContainer
var _screen_val: Label
var _ui_val: Label
var _f: DynamicFont
var _fb: DynamicFont

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_f = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	_fb = _font("res://assets/font/Lato/Lato-Bold.ttf", 19)
	_icon = Icon.new()
	_icon.anchor_left = 1.0
	_icon.anchor_right = 1.0
	_icon.anchor_top = 1.0
	_icon.anchor_bottom = 1.0
	_icon.margin_left = -ICON - 6
	_icon.margin_right = -6
	_icon.margin_top = -ICON - 6
	_icon.margin_bottom = -6
	_icon.hint_tooltip = "Drag to resize the screen, tap for sizes"
	_icon.connect("gui_input", self, "_on_icon_input")
	add_child(_icon)
	_build_panel()

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _on_icon_input(e: InputEvent):
	if e is InputEventMouseButton and e.button_index == BUTTON_LEFT and e.pressed:
		_icon.accept_event()
		if screen != null and is_instance_valid(screen):
			screen.begin_resize(self)

func toggle_panel():
	_panel.visible = not _panel.visible
	_refresh()

func _build_panel():
	_panel = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.97)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	_panel.add_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.margin_right = -6
	_panel.margin_bottom = -ICON - 14
	_panel.margin_left = -440
	_panel.margin_top = -ICON - 14
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.visible = false
	add_child(_panel)
	var col = VBoxContainer.new()
	col.add_constant_override("separation", 10)
	_panel.add_child(col)
	var t = _label("Menu screen size", _fb, FG)
	col.add_child(t)
	_screen_val = _row(col, "Screen", "_screen_step")
	_ui_val = _row(col, "Text and buttons", "_ui_step")
	var hint = _label("Or point at the corner icon, hold the trigger and drag to resize the screen.", _f, DIM)
	hint.autowrap = true
	col.add_child(hint)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	col.add_child(h)
	_button(h, "Reset", "_reset")
	_button(h, "Close", "toggle_panel")

func _label(text: String, f: Font, c: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", c)
	return l

func _button(parent: Node, text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", _fb)
	b.rect_min_size = Vector2(56, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, method, args)
	parent.add_child(b)
	return b

func _row(col: Node, title: String, method: String) -> Label:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	col.add_child(h)
	var l = _label(title, _fb, TEXT)
	l.rect_min_size = Vector2(170, 0)
	l.valign = Label.VALIGN_CENTER
	h.add_child(l)
	_button(h, "-", method, [-1])
	var v = _label("", _f, TEXT)
	v.rect_min_size = Vector2(70, 0)
	v.align = Label.ALIGN_CENTER
	v.valign = Label.VALIGN_CENTER
	h.add_child(v)
	_button(h, "+", method, [1])
	return v

func _refresh():
	_screen_val.text = "%d°" % int(round(Rhythia.vr_menu_size))
	_ui_val.text = "%d %%" % int(round(Rhythia.vr_menu_ui))

func _screen_step(d: int):
	Rhythia.vr_menu_size = clamp(round((Rhythia.vr_menu_size + d * 10.0) / 5.0) * 5.0, 40.0, 160.0)
	_apply()

func _ui_step(d: int):
	Rhythia.vr_menu_ui = clamp(Rhythia.vr_menu_ui + d * 10.0, 60.0, 140.0)
	_apply()

func _reset():
	Rhythia.vr_menu_size = 100.0
	Rhythia.vr_menu_ui = 100.0
	_apply()

func _apply():
	_refresh()
	if screen != null and is_instance_valid(screen):
		screen.rebuild()
	Rhythia.save_settings()

func _process(_d):
	if _panel.visible:
		_refresh()

# the corner grip: a rounded box with a two-way diagonal arrow
class Icon extends Control:
	var hover = false
	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		connect("mouse_entered", self, "_set_hover", [true])
		connect("mouse_exited", self, "_set_hover", [false])
	func _set_hover(on: bool):
		hover = on
		update()
	func _draw():
		var r = Rect2(Vector2.ZERO, rect_size)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.16, 0.3, 0.95) if hover else Color(0.11, 0.09, 0.16, 0.8)
		sb.border_color = Color(1, 0.756863, 0.960784, 0.95 if hover else 0.6)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, r)
		var c = Color(1, 0.86, 0.98)
		var a = rect_size * 0.27
		var b = rect_size * 0.73
		draw_line(a, b, c, 3.0, true)
		var k = rect_size.x * 0.17
		for p in [[a, 1.0], [b, -1.0]]:
			var o: Vector2 = p[0]
			var s: float = p[1]
			draw_line(o, o + Vector2(k * s, 0), c, 3.0, true)
			draw_line(o, o + Vector2(0, k * s), c, 3.0, true)
