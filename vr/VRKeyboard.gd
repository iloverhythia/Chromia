extends Control

# On-screen keyboard for VR (on the VR menu screen, vrmenu.gd adds it): it pops
# up whenever a text box gets the focus and goes away when you're done. Keys
# are pressed with the controller pointer and are sent to the text box as real
# key presses, so everything works as with a keyboard (search as you type,
# Enter to confirm...). It sits at the bottom of the screen, or at the top when
# the text box is down there, until you move it: drag the bar along its top
# with the pointer and it stays there (Reset in the bar puts it back).
#
# The keys are drawn by one control (Keys, below): every key's background, then
# every label. They used to be fifty Buttons, each drawn by itself, which made
# the menu a hundred draw calls heavier whenever the keyboard was out: on a
# Meta Quest the frame rate sagged with it (the store review's
# VRC.Quest.Performance.1). Now the keyboard costs a handful.

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
var _keys := [] # Key
var _keys_ctl: Control
var _shift := false
var _shift_key: Key

# One key: where it is on the panel, what it shows and what it does.
class Key extends Reference:
	var rect := Rect2()
	var ch := "" # a character key's base character ("" for the others)
	var text := ""
	var method := ""
	var arg = null
	var flash := false

# Draws all the keys and takes a mouse click on one (the VR hands press keys
# through key_at / press_key, MenuPointer.gd).
class Keys extends Control:
	var kb
	const BG := Color(0.764706, 0.65098, 0.8)
	const BG_LOW := Color(0.6, 0.5, 0.65)
	const TXT := Color(0.06, 0.04, 0.08)
	func _draw():
		# every background first, then every label: two batches for the lot
		for k in kb._keys:
			var tint: Color = kb.tint_of(k)
			draw_rect(k.rect, BG_LOW * tint)
			draw_rect(Rect2(k.rect.position, k.rect.size - Vector2(0, 3)), BG * tint)
		var f: Font = kb._font
		for k in kb._keys:
			var sz: Vector2 = f.get_string_size(k.text)
			draw_string(f, (k.rect.position + (k.rect.size - sz) / 2.0 + Vector2(0, f.get_ascent() - 1)).floor(), k.text, TXT)
	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
			var k = kb.key_at(ev.global_position)
			if k != null:
				kb.press_key(k)
				accept_event()
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
	_keys_ctl = Keys.new()
	_keys_ctl.name = "Keys"
	_keys_ctl.kb = self
	_keys_ctl.rect_size = panel.rect_size
	_keys_ctl.focus_mode = FOCUS_NONE # pressing a key must not take the focus from the text box
	_keys_ctl.mouse_filter = MOUSE_FILTER_PASS # (the bar and Reset, over it, keep their clicks)
	panel.add_child(_keys_ctl)
	panel.move_child(_keys_ctl, 0)
	for r in range(ROWS.size()):
		for c in range(ROWS[r].size()):
			var ch: String = ROWS[r][c]
			var k := _key(ch, Vector2(PAD + c * (KEY_W + GAP), BAR + PAD + r * (KEY_H + GAP)), Vector2(KEY_W, KEY_H), "_on_char", ch)
			k.ch = ch
	# bottom row: shift, space, backspace, enter, done
	var y: float = BAR + PAD + 4 * (KEY_H + GAP)
	var x: float = PAD
	_shift_key = _key("Shift", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H), "_on_shift")
	x += KEY_W * 1.5 + GAP
	var space_w: float = w - PAD * 2 - (KEY_W * 1.5 + KEY_W * 1.5 + KEY_W * 1.5 + KEY_W * 1.5) - GAP * 4
	_key("Space", Vector2(x, y), Vector2(space_w, KEY_H), "_on_char", " ")
	x += space_w + GAP
	_key("Delete", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H), "_on_special", KEY_BACKSPACE)
	x += KEY_W * 1.5 + GAP
	_key("Enter", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H), "_on_special", KEY_ENTER)
	x += KEY_W * 1.5 + GAP
	_key("Done", Vector2(x, y), Vector2(KEY_W * 1.5, KEY_H), "_on_done")
	panel.visible = false
	_refresh_labels()

func _key(text: String, pos: Vector2, size: Vector2, method: String, arg = null) -> Key:
	var k := Key.new()
	k.text = text
	k.rect = Rect2(pos, size)
	k.method = method
	k.arg = arg
	_keys.append(k)
	return k

# Typing with the other hand (MenuPointer.gd): the key under a point of the
# screen (layout pixels), or null
func key_at(p: Vector2):
	if not panel.visible:
		return null
	var local: Vector2 = p - _keys_ctl.rect_global_position
	for k in _keys:
		if k.rect.has_point(local):
			return k
	return null

# the key each hand points at (MenuPointer.gd: both hands type), tinted; a key
# flashes when it's pressed
var _lit := [null, null]
func light_hand(hand: int, b):
	if b == _lit[hand]:
		return
	var old = _lit[hand]
	_lit[hand] = b
	_tint(old)
	_tint(b)

func _tint(_b):
	_keys_ctl.update()

# a key's colour: lighter under a hand's pointer, green for a moment when pressed
func tint_of(k) -> Color:
	if k.flash:
		return Color(0.75, 1, 0.85)
	var n := 0
	for h in _lit:
		if h == k:
			n += 1
	return Color(1, 1, 1) if n == 0 else (Color(1, 0.8, 0.97) if n == 1 else Color(1, 0.65, 0.93))

func press_key(k):
	if not (k is Key):
		return
	if k.arg == null:
		call(k.method)
	else:
		call(k.method, k.arg)
	k.flash = true
	_keys_ctl.update()
	yield(get_tree().create_timer(0.09), "timeout")
	k.flash = false
	_keys_ctl.update()

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
	if panel.visible and get_position_in_parent() != get_parent().get_child_count() - 1:
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
		if k.ch != "":
			k.text = (SHIFTED.get(k.ch, k.ch.to_upper()) if _shift else k.ch)
	_shift_key.text = "SHIFT" if _shift else "Shift"
	_keys_ctl.update()

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
