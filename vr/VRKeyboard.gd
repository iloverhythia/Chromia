extends Control

# On-screen keyboard for VR (on the VR menu screen, vrmenu.gd adds it): it pops
# up whenever a text box gets the focus and goes away when you're done. Keys
# are pressed with the controller pointer and are sent to the text box as real
# key presses, so everything works as with a keyboard (search as you type,
# Enter to confirm...). It sits at the bottom of the screen, or at the top when
# the text box is down there.

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

var panel: Panel
var _keys := [] # [button, base character]
var _shift := false
var _shift_btn: Button
var _target: Control = null
var _font: DynamicFont

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
	var h: float = PAD * 2 + 5 * KEY_H + 4 * GAP
	panel.rect_size = Vector2(w, h)
	for r in range(ROWS.size()):
		for c in range(ROWS[r].size()):
			var ch: String = ROWS[r][c]
			var b := _key(ch, Vector2(PAD + c * (KEY_W + GAP), PAD + r * (KEY_H + GAP)), Vector2(KEY_W, KEY_H))
			b.connect("pressed", self, "_on_char", [ch])
			_keys.append([b, ch])
	# bottom row: shift, space, backspace, enter, done
	var y: float = PAD + 4 * (KEY_H + GAP)
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
