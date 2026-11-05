extends Control

# On-screen keyboard for VR (on the VR menu screen, vrmenu.gd adds it): it pops
# up whenever a text box gets the focus and goes away when you're done. Keys
# are pressed with the controller pointer and are sent to the text box as real
# key presses, so everything works as with a keyboard (search as you type,
# Enter to confirm...). It sits at the bottom of the screen, or at the top when
# the text box is down there, until you move it: drag the bar along its top
# with the pointer and it stays there (Reset in the bar puts it back).

const ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "/"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "'", ":"],
	["z", "x", "c", "v", "b", "n", "m", ",", ".", "?", "!"],
]
const SHIFTED := {
	"1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
	"-": "_", "/": "\\", "'": "\"", ":": ";", ",": "<", ".": ">", "?": "=", "!": "+",
}
const KEY_W := 82.0
const KEY_H := 52.0
const GAP := 6.0
const PAD := 12.0
const BAR := 40.0 # the grab bar along the top
const POS_FILE := "user://vr_keyboard.cfg"

var panel: Panel
var _keys := [] # [button, base character]
var _shift := false
var _shift_btn: Button
var _target: Control = null
var _font: DynamicFont
var _dragging := false
var _drag_from := Vector2() # pointer minus panel position when the drag began
var _saved_pos = null # Vector2 where you put it, or null: the usual place

func _ready():
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_WIDE)
	pause_mode = PAUSE_MODE_PROCESS
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_font.size = 24
	panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.08, 0.96)
	sb.border_color = Color(1, 0.756863, 0.960784)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	panel.add_stylebox_override("panel", sb)
	add_child(panel)
	var cols: int = ROWS[0].size()
	var w: float = PAD * 2 + cols * KEY_W + (cols - 1) * GAP
	var h: float = BAR + PAD * 2 + 5 * KEY_H + 4 * GAP
	panel.rect_size = Vector2(w, h)
	_add_bar(w)
	_load_pos()
	for r in range(ROWS.size()):
		for c in range(ROWS[r].size()):
			var ch: String = ROWS[r][c]
			var b := _key(ch, Vector2(PAD + c * (KEY_W + GAP), BAR + PAD + r * (KEY_H + GAP)), Vector2(KEY_W, KEY_H))
			b.connect("pressed", self, "_on_char", [ch])
			_keys.append([b, ch])
	# bottom row: shift, space, backspace, enter, done
	var y: float = BAR + PAD + 4 * (KEY_H + GAP)
	var x: float = PAD
	_shift_btn = _key("Shift", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H))
	_shift_btn.connect("pressed", self, "_on_shift")
	x += KEY_W * 1.5 + GAP
	var space_w: float = w - PAD * 2 - (KEY_W * 1.5 + KEY_W * 1.5 + KEY_W * 1.5 + KEY_W * 1.5) - GAP * 4
	var sp := _key("Space", Vector2(x, y), Vector2(space_w, KEY_H))
	sp.connect("pressed", self, "_on_char", [" "])
	x += space_w + GAP
	var bs := _key("Delete", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H))
	bs.connect("pressed", self, "_on_special", [KEY_BACKSPACE])
	x += KEY_W * 1.5 + GAP
	var en := _key("Enter", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H))
	en.connect("pressed", self, "_on_special", [KEY_ENTER])
	x += KEY_W * 1.5 + GAP
	var done := _key("Done", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H))
	done.connect("pressed", self, "_on_done")
	panel.visible = false
	_refresh_labels()

func _key(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", _font)
	b.focus_mode = FOCUS_NONE # pressing a key must not take the focus from the text box
	b.rect_position = pos
	b.rect_size = size
	b.rect_min_size = size
	panel.add_child(b)
	return b

# Typing with the other hand (MenuPointer.gd): the key under a point of the
# screen (layout pixels), or null
func key_at(p: Vector2):
	if not panel.visible:
		return null
	for b in panel.get_children():
		if b is Button and b.visible and b.get_global_rect().has_point(p):
			return b
	return null

var _off_lit = null
func light_off_hand(b):
	if b == _off_lit:
		return
	if _off_lit != null and is_instance_valid(_off_lit):
		_off_lit.self_modulate = Color(1, 1, 1)
	_off_lit = b
	if b != null:
		b.self_modulate = Color(1, 0.8, 0.97) # (the key the other hand is on)

func _is_text_box(c) -> bool:
	if c is LineEdit:
		return c.editable and c.is_visible_in_tree()
	if c is TextEdit:
		return not c.readonly and c.is_visible_in_tree()
	return false

func _process(_d):
	var f = get_focus_owner()
	if _is_text_box(f):
		if f != _target or not panel.visible:
			_target = f
			_show_for(f)
	elif panel.visible:
		panel.visible = false
		_target = null
	if panel.visible:
		raise() # over boxes opened after it

func _show_for(c: Control):
	var vs: Vector2 = get_viewport_rect().size
	var r: Rect2 = c.get_global_rect()
	var x: float = (vs.x - panel.rect_size.x) / 2.0
	var y: float = vs.y - panel.rect_size.y - 8.0
	if r.end.y > y - 4.0:
		y = 8.0 # the text box is down there: keyboard at the top
	panel.rect_position = Vector2(x, y).floor()
	if _saved_pos is Vector2:
		panel.rect_position = _clamped(_saved_pos)
	panel.visible = true
	Rhythia.trail("VR keyboard for %s" % c.name)

func _refresh_labels():
	for k in _keys:
		var ch: String = k[1]
		k[0].text = (SHIFTED.get(ch, ch.to_upper()) if _shift else ch)
	_shift_btn.text = "SHIFT" if _shift else "Shift"

func _on_shift():
	_shift = not _shift
	_refresh_labels()

func _on_char(ch: String):
	var out := ch
	if _shift and ch != " ":
		out = SHIFTED.get(ch, ch.to_upper())
		_shift = false
		_refresh_labels()
	_send(ord(out), _scancode_for(out))

func _on_special(code: int):
	_send(0, code)

func _on_done():
	if is_instance_valid(_target):
		_target.release_focus()
	panel.visible = false
	_target = null

static func _scancode_for(ch: String) -> int:
	var u := ch.to_upper()
	if u.length() == 1:
		var c := ord(u)
		if (c >= ord("A") and c <= ord("Z")) or (c >= ord("0") and c <= ord("9")) or c == ord(" "):
			return c
	return 0

# A real key press (down + up) into this screen: the focused text box gets it.
func _send(unicode: int, scancode: int):
	if not is_instance_valid(_target):
		return
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.pressed = pressed
		ev.scancode = scancode
		ev.unicode = unicode if pressed else 0
		get_viewport().input(ev)

# --- moving it -------------------------------------------------------------------------
func _add_bar(w: float):
	var bar := Panel.new()
	bar.name = "Bar"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.756863, 0.960784, 0.16)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	bar.add_stylebox_override("panel", sb)
	bar.rect_position = Vector2(2, 2)
	bar.rect_size = Vector2(w - 4, BAR - 4)
	bar.mouse_default_cursor_shape = CURSOR_MOVE
	bar.connect("gui_input", self, "_on_bar_input")
	panel.add_child(bar)
	var l := Label.new()
	l.text = ":::  Drag here to move the keyboard  :::"
	l.add_font_override("font", _font)
	l.add_color_override("font_color", Color(1, 0.86, 0.98, 0.85))
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.rect_size = bar.rect_size
	l.mouse_filter = MOUSE_FILTER_IGNORE
	bar.add_child(l)
	var reset := Button.new()
	reset.text = "Reset"
	reset.theme = load("res://uitheme.tres")
	reset.add_font_override("font", _font)
	reset.focus_mode = FOCUS_NONE
	reset.rect_size = Vector2(KEY_W * 1.2, BAR - 10)
	reset.rect_position = Vector2(bar.rect_size.x - reset.rect_size.x - 4, 3)
	reset.connect("pressed", self, "_on_reset")
	bar.add_child(reset)

func _on_bar_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_dragging = ev.pressed
		if ev.pressed:
			_drag_from = ev.global_position - panel.rect_position
		else:
			_saved_pos = panel.rect_position
			_save_pos()
	elif ev is InputEventMouseMotion and _dragging:
		panel.rect_position = _clamped(ev.global_position - _drag_from)

# kept on the screen
func _clamped(p: Vector2) -> Vector2:
	var vs: Vector2 = get_viewport_rect().size
	return Vector2(clamp(p.x, 0, max(0.0, vs.x - panel.rect_size.x)), clamp(p.y, 0, max(0.0, vs.y - panel.rect_size.y))).floor()

func _on_reset():
	_saved_pos = null
	_save_pos()
	if is_instance_valid(_target):
		_show_for(_target)

func _load_pos():
	var cfg := ConfigFile.new()
	if cfg.load(POS_FILE) == OK and cfg.has_section_key("keyboard", "pos"):
		var p = cfg.get_value("keyboard", "pos")
		_saved_pos = p if p is Vector2 else null

func _save_pos():
	var cfg := ConfigFile.new()
	cfg.set_value("keyboard", "pos", _saved_pos)
	cfg.save(POS_FILE)
