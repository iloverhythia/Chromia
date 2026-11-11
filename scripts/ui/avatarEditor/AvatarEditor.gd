extends Control
# Settings > Player Avatar > Go to editor: your avatar, turning in the middle
# (drag to turn it), with its colours and the items it can wear on the right.
# Saved as you go (Rhythia.avatar, scripts/avatar/AvatarLook.gd).

const AvatarLook = preload("res://scripts/avatar/AvatarLook.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)

var _data: Dictionary
var _avatar: Spatial
var _turn := 0.0
var _dragging := false
var _boxes := {} # item id -> CheckBox
var _pickers := {} # colour key -> ColorPickerButton
var _f: DynamicFont
var _fb: DynamicFont

func _ready():
	_avatar = $VPContainer/VP/Avatar
	$VPContainer/VP/Avatar/Animations.play("Idle")
	$VPContainer/VP/Avatar/Head/Blinking.play("Blink")
	# (the old type-a-name boxes)
	for old in ["Head", "Torso", "Label"]:
		if has_node(old):
			get_node(old).queue_free()
	_data = AvatarLook.normalized(Rhythia.get("avatar"))
	_f = _font("res://assets/font/Lato/Lato-Regular.ttf", 18)
	_fb = _font("res://assets/font/Lato/Lato-Bold.ttf", 20)
	_build_panel()
	_apply()
	$VPContainer.connect("gui_input", self, "_on_view_input")

func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	return f

func _label(t: String, f: Font, col := TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	return l

func _build_panel():
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.065, 0.09, 0.94)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.border_width_left = 1
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_stylebox_override("panel", sb)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.margin_left = -380
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 8)
	scroll.add_child(v)
	v.add_child(_label("Your avatar", _font("res://assets/font/Lato/Lato-Black.ttf", 26), ACCENT))
	var hint := _label("Shown in replays with the alternate camera and when people watch you in 3rd person. Drag the avatar to turn it.", _font("res://assets/font/Lato/Lato-Regular.ttf", 14), DIM)
	hint.autowrap = true
	v.add_child(hint)
	v.add_child(HSeparator.new())
	v.add_child(_label("Colors", _fb))
	for c in [["head", "Head"], ["body", "Body and arms"], ["eyes", "Eyes"]]:
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 10)
		var p := ColorPickerButton.new()
		p.rect_min_size = Vector2(70, 30)
		p.edit_alpha = false
		p.color = Color(_data[c[0]])
		p.connect("color_changed", self, "_on_color", [c[0]])
		row.add_child(p)
		row.add_child(_label(c[1], _f))
		_pickers[c[0]] = p
		v.add_child(row)
	for group in [["head", "On the head"], ["torso", "On the body"]]:
		v.add_child(HSeparator.new())
		v.add_child(_label(group[1], _fb))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_constant_override("hseparation", 16)
		v.add_child(grid)
		for it in AvatarLook.ITEMS:
			if it[2] != group[0]:
				continue
			var cb := CheckBox.new()
			cb.text = it[1]
			cb.add_font_override("font", _f)
			cb.pressed = it[0] in _data["items"]
			cb.rect_min_size = Vector2(150, 30)
			cb.connect("toggled", self, "_on_item", [it[0]])
			grid.add_child(cb)
			_boxes[it[0]] = cb
	v.add_child(HSeparator.new())
	var reset := Button.new()
	reset.text = "Reset to the plain avatar"
	reset.add_font_override("font", _f)
	reset.connect("pressed", self, "_on_reset")
	v.add_child(reset)

func _on_color(col: Color, key: String):
	_data[key] = "#" + col.to_html(false)
	_save()

func _on_item(on: bool, id: String):
	var items: Array = _data["items"]
	if on and not (id in items):
		items.append(id)
	elif not on:
		items.erase(id)
	_save()

func _on_reset():
	_data = AvatarLook.normalized({})
	for id in _boxes:
		_boxes[id].pressed = false
	for k in _pickers:
		_pickers[k].color = Color(_data[k])
	_save()

func _save():
	_data = AvatarLook.normalized(_data)
	Rhythia.avatar = _data.duplicate(true)
	Rhythia.save_settings()
	_apply()

func _apply():
	AvatarLook.apply(_avatar, _data)

# drag to turn
func _on_view_input(ev):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_dragging = ev.pressed
	elif ev is InputEventMouseMotion and _dragging:
		_turn += ev.relative.x * 0.01
		_avatar.rotation.y = _turn
