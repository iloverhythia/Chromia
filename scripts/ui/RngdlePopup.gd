extends PanelContainer

# RNGdle's popup (Rngdle.gd): six reels stopping one after the other, then
# the number's rarity; it closes by itself after a while (or Close / Esc).

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")

var digits := ""
var info := ["Common", "#a1a1aa", "Nothing special", "1.5"] # (Rngdle.RARITY row)
var owner_node
var S
var _reels := []
var _t := 0.0
var _done := false
var _tick := 0.0
var _rarity: Label
var _what: Label
var _close: Button
var _sb: StyleBoxFlat
var _rcol := Color(1, 1, 1)
var _rng := RandomNumberGenerator.new()
const FIRST_STOP := 1.0
const GAP := 0.38

func _init():
	S = OnlineStyle.new()
	_rng.randomize()
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = MOUSE_FILTER_STOP

func _ready():
	_sb = OnlineStyle.flat(OnlineStyle.WINDOW_BG, 10, Color(1, 1, 1, 0.15), 2, 24, 18)
	_sb.shadow_color = Color(0, 0, 0, 0.55)
	_sb.shadow_size = 16
	add_stylebox_override("panel", _sb)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 12)
	add_child(v)
	var title: Label = S.label("RNGdle", OnlineStyle.font("res://assets/font/Nunito/Nunito-Bold.ttf", 26), OnlineStyle.ACCENT)
	title.align = Label.ALIGN_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 8)
	v.add_child(row)
	var big := OnlineStyle.font("res://assets/font/Nunito/Nunito-Bold.ttf", 46)
	for i in 6:
		var box := PanelContainer.new()
		box.rect_min_size = Vector2(58, 78)
		box.add_stylebox_override("panel", OnlineStyle.flat(Color(0.1, 0.095, 0.13), 8, Color(1, 1, 1, 0.12), 1))
		var l: Label = S.label("0", big, OnlineStyle.TEXT)
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
		box.add_child(l)
		row.add_child(box)
		_reels.append({"box": box, "label": l, "stopped": false})
	_rarity = S.label(" ", OnlineStyle.font("res://assets/font/Nunito/Nunito-Bold.ttf", 22), OnlineStyle.TEXT)
	_rarity.align = Label.ALIGN_CENTER
	v.add_child(_rarity)
	_what = S.label("Rolling...", S.f_small, OnlineStyle.DIM)
	_what.align = Label.ALIGN_CENTER
	v.add_child(_what)
	_close = Button.new()
	_close.text = "Close"
	S.button(_close, false, true)
	_close.size_flags_horizontal = SIZE_SHRINK_CENTER
	_close.connect("pressed", self, "close")
	v.add_child(_close)
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place")
	modulate.a = 0.0

func _place():
	var vp := get_viewport_rect().size
	rect_size = get_combined_minimum_size()
	rect_pivot_offset = rect_size / 2.0
	rect_position = ((vp - rect_size) / 2.0).floor()

func _process(delta):
	_t += delta
	modulate.a = min(1.0, _t / 0.2)
	_tick += delta
	var spin := _tick > 0.05
	if spin:
		_tick = 0.0
	var all_stopped := true
	for i in 6:
		var r: Dictionary = _reels[i]
		var stop_at: float = FIRST_STOP + i * GAP
		if not r.stopped:
			if _t >= stop_at:
				r.stopped = true
				r.label.text = digits[i]
				r.label.add_color_override("font_color", Color(1, 1, 1))
				r.box.rect_scale = Vector2(1.12, 1.12)
			else:
				all_stopped = false
				if spin:
					r.label.text = str(_rng.randi() % 10)
					r.label.add_color_override("font_color", Color(1, 1, 1, 0.55))
		# (a little bump as a reel stops)
		r.box.rect_pivot_offset = r.box.rect_size / 2.0
		r.box.rect_scale = r.box.rect_scale.linear_interpolate(Vector2(1, 1), min(1.0, delta * 10.0))
	if all_stopped and not _done:
		_done = true
		_reveal()
	if _done:
		var glow := 0.55 + 0.45 * sin(_t * 4.0)
		var col := _rcol
		var k: Array = info
		if k[0] == "Mythic" or k[0] == "Legendary":
			col = Color.from_hsv(fmod(_t * 0.25, 1.0), 0.55, 1.0) if k[0] == "Mythic" else _rcol.linear_interpolate(Color("#fde047"), 0.5 + 0.5 * sin(_t * 3.0))
			_rarity.add_color_override("font_color", col)
		_sb.border_color = Color(col.r, col.g, col.b, 0.5 + 0.5 * glow)
		_sb.shadow_color = Color(col.r, col.g, col.b, 0.25 * glow)
	if _done and _t > FIRST_STOP + 5 * GAP + 9.0:
		close()

func _reveal():
	var k: Array = info
	_rcol = Color(k[1])
	_rarity.text = k[0].to_upper()
	_rarity.add_color_override("font_color", _rcol)
	_what.text = "%s  ·  1 in %s" % [k[2], k[3]]
	for r in _reels:
		r.box.add_stylebox_override("panel", OnlineStyle.flat(Color(0.1, 0.095, 0.13), 8, Color(_rcol.r, _rcol.g, _rcol.b, 0.8), 2))
	var lm = get_node_or_null("/root/LobbyManager")
	if owner_node != null and is_instance_valid(owner_node):
		owner_node._post(lm, digits)

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func close():
	var layer = get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()
