extends VBoxContainer

# Settings > VR (only while playing in VR / on the Meta Quest app):
#  - Controller grip: the pointer's angle and offset on your hand, like the
#    controller settings of other VR rhythm games. The beam moves as you change
#    it. Set for the right hand; the left hand gets the mirror image.
#  - Controller buttons: which button does what (up to two each).
#
# menu2.gd adds it (add_tab). Saved with the other settings (Savia.gd
# vr_grip_rot / vr_grip_pos / vr_binds).

const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const NONE_ID := 1000 # the "(none)" item (an id of -1 would become 0)

# [label, which value, axis, min, max, step, unit]
const GRIP_ROWS := [
	["Tilt (up / down)", "rot", 0, -90.0, 90.0, 1.0, "°"],
	["Turn (left / right)", "rot", 1, -60.0, 60.0, 1.0, "°"],
	["Roll", "rot", 2, -90.0, 90.0, 1.0, "°"],
	["Move left / right", "pos", 0, -15.0, 15.0, 0.5, " cm"],
	["Move up / down", "pos", 1, -15.0, 15.0, 0.5, " cm"],
	["Move forward / back", "pos", 2, -15.0, 15.0, 0.5, " cm"],
]

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var box: VBoxContainer
var _sliders := [] # [slider, value label, row]
var _pickers := {} # action -> [OptionButton, OptionButton]
var _loading := false

static func wanted() -> bool:
	return Rhythia.vr or OS.has_feature("quest")

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("VR") or not wanted():
		return
	var t = load("res://scripts/ui/settings/VRTab.gd").new()
	t.name = "VR"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Generator")
	if after == null:
		after = tab_container.get_node_or_null("Gameplay")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	_label("Controller grip", f_title, ACCENT)
	_label("Changes the angle and position of the pointer on your hand, so it points where feels natural to you. Watch the beam move while you change it. This is for the right hand; the left hand gets the mirror image.", f_body, DIM, true)
	for row in GRIP_ROWS:
		_grip_row(row)
	_button(box, "Reset grip", "_reset_grip")

	var sep := HSeparator.new()
	box.add_child(sep)
	_label("Controller buttons", f_title, ACCENT)
	_label("Pick which controller button does each thing (both controllers work the same). An action can have two buttons.", f_body, DIM, true)
	for a in Rhythia.VR_ACTIONS:
		_bind_row(a[0], a[1])
	_button(box, "Reset buttons", "_reset_binds")
	_load_values()

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l := Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(180, 36)
	b.size_flags_horizontal = 0
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _grip_row(row: Array):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(row[0], f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var s := HSlider.new()
	s.min_value = row[3]
	s.max_value = row[4]
	s.step = row[5]
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.rect_min_size = Vector2(300, 28)
	s.theme = load("res://uitheme.tres")
	h.add_child(s)
	var val := _label("", f_body, TEXT, false, h)
	val.rect_min_size = Vector2(80, 0)
	val.size_flags_horizontal = 0
	_sliders.append([s, val, row])
	s.connect("value_changed", self, "_on_grip", [_sliders.size() - 1])

func _bind_row(action: String, title: String):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(title, f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var pair := []
	for slot in range(2):
		var o := OptionButton.new()
		o.theme = load("res://uitheme.tres")
		o.add_font_override("font", f_body)
		o.rect_min_size = Vector2(200, 34)
		o.add_item("(none)", NONE_ID)
		for b in Rhythia.VR_BUTTONS:
			o.add_item(b[0], b[1])
		o.connect("item_selected", self, "_on_bind", [action])
		h.add_child(o)
		pair.append(o)
	_pickers[action] = pair

func _load_values():
	_loading = true
	for e in _sliders:
		var row: Array = e[2]
		var v: Vector3 = Rhythia.vr_grip_rot if row[1] == "rot" else Rhythia.vr_grip_pos
		e[0].value = v[row[2]]
		e[1].text = _fmt(v[row[2]], row)
	for action in _pickers:
		var bs: Array = Rhythia.vr_bind(action)
		for slot in range(2):
			var o: OptionButton = _pickers[action][slot]
			o.select(o.get_item_index(bs[slot]) if slot < bs.size() and o.get_item_index(bs[slot]) != -1 else 0)
	_loading = false

static func _fmt(v: float, row: Array) -> String:
	return (("%+.1f" if row[5] < 1.0 else "%+d") % (v if row[5] < 1.0 else int(round(v)))) + row[6]

func _on_grip(v: float, i: int):
	var e: Array = _sliders[i]
	var row: Array = e[2]
	e[1].text = _fmt(v, row)
	if _loading:
		return
	if row[1] == "rot":
		var r: Vector3 = Rhythia.vr_grip_rot
		r[row[2]] = v
		Rhythia.vr_grip_rot = r
	else:
		var p: Vector3 = Rhythia.vr_grip_pos
		p[row[2]] = v
		Rhythia.vr_grip_pos = p
	_save_soon()

func _on_bind(_idx: int, action: String):
	if _loading:
		return
	var out := []
	for o in _pickers[action]:
		var id: int = o.get_selected_id()
		if id != NONE_ID and id >= 0 and not out.has(id):
			out.append(id)
	var binds: Dictionary = Rhythia.vr_binds.duplicate()
	binds[action] = out
	Rhythia.vr_binds = binds
	if Rhythia.vr and not Rhythia.fake_vr:
		Rhythia.apply_vr_binds()
	_save_soon()

func _reset_grip():
	Rhythia.vr_grip_rot = Vector3.ZERO
	Rhythia.vr_grip_pos = Vector3.ZERO
	_load_values()
	_save_soon()

func _reset_binds():
	Rhythia.vr_binds = {}
	if Rhythia.vr and not Rhythia.fake_vr:
		Rhythia.apply_vr_binds()
	_load_values()
	_save_soon()

# sliders send many changes while dragged: save once they stop
var _save_t: SceneTreeTimer = null
func _save_soon():
	_save_t = get_tree().create_timer(0.6)
	_save_t.connect("timeout", self, "_save", [_save_t])

func _save(t):
	if t == _save_t:
		Rhythia.save_settings()
