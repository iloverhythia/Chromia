extends MarginContainer
# Settings > Fonts: pick the font of the song HUD from the ones the game comes
# with, or use your own .ttf / .otf. Spectators see it too (scripts/HudFont.gd).

const HudFont = preload("res://scripts/HudFont.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.898039, 0.94902, 1, 0.6)
const ACCENT := Color(1, 0.756863, 0.960784)
const SAMPLE := "0:42 / 2:13   x4   1,234,567   98.76%   MISSES 3"

var _rows := {} # id -> PanelContainer
var _status: Label
var _custom_name: Label
var _remove_btn: Button
var _list: VBoxContainer
var _ui_theme

static func add_tab(tabs: Node):
	if tabs == null or tabs.has_node("Fonts"):
		return
	var t = load("res://scripts/ui/settings/FontsTab.gd").new()
	t.name = "Fonts"
	tabs.add_child(t)

func _ready():
	_ui_theme = load("res://uitheme.tres")
	# (no scrolling of its own: the settings page scrolls and sizes each tab by
	# what's in it, so a tab that scrolls itself came out 0 px tall)
	size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		add_constant_override("margin_" + side, 66)
	add_constant_override("margin_top", 16)
	add_constant_override("margin_bottom", 24)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_constant_override("separation", 8)
	add_child(_list)

	_list.add_child(_text("The font of the HUD while you play: the side panels, the timer, combo and score. People who spectate you see it too.", DIM, 15))

	# the size of all of it
	var size_row := HBoxContainer.new()
	size_row.add_constant_override("separation", 10)
	_list.add_child(size_row)
	var sl := _text("Size", TEXT, 16)
	sl.rect_min_size = Vector2(60, 0)
	size_row.add_child(sl)
	_size = HSlider.new()
	_size.theme = _ui_theme
	_size.min_value = 50
	_size.max_value = 200
	_size.step = 5
	_size.value = float(Rhythia.hud_font_size)
	_size.rect_min_size = Vector2(320, 28)
	_size.size_flags_vertical = SIZE_SHRINK_CENTER
	_size.connect("value_changed", self, "_on_size")
	size_row.add_child(_size)
	_size_l = _text("%d%%" % int(Rhythia.hud_font_size), TEXT, 16)
	_size_l.rect_min_size = Vector2(60, 0)
	size_row.add_child(_size_l)
	var size_reset := Button.new()
	size_reset.text = "Reset size"
	size_reset.theme = _ui_theme
	size_reset.rect_min_size = Vector2(110, 30)
	size_reset.connect("pressed", self, "_on_size", [100.0])
	size_row.add_child(size_reset)

	var group := ""
	for f in HudFont.FONTS:
		var g: String = f[3] if f.size() > 3 else ""
		if g != group and g != "":
			group = g
			var h := _text(g, ACCENT, 17)
			h.rect_min_size = Vector2(0, 30)
			h.valign = Label.VALIGN_BOTTOM
			_list.add_child(h)
		elif g == "" and group != "":
			group = ""
			var sp := Control.new()
			sp.rect_min_size = Vector2(0, 10)
			_list.add_child(sp)
		_list.add_child(_font_row(f[0], f[1]))

	# your own font
	var own := HBoxContainer.new()
	own.add_constant_override("separation", 10)
	_list.add_child(own)
	var pick := Button.new()
	pick.text = "Choose a font file (.ttf / .otf)"
	pick.theme = _ui_theme
	pick.rect_min_size = Vector2(300, 34)
	pick.connect("pressed", self, "_on_pick")
	own.add_child(pick)
	_remove_btn = Button.new()
	_remove_btn.text = "Remove"
	_remove_btn.theme = _ui_theme
	_remove_btn.rect_min_size = Vector2(110, 34)
	_remove_btn.connect("pressed", self, "_on_remove")
	own.add_child(_remove_btn)
	_status = _text("", DIM, 14)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.valign = Label.VALIGN_CENTER
	own.add_child(_status)
	_list.add_child(_text("Your own font is sent to the people watching you (4 MB at most). Letters it doesn't have use Chromia's font.", DIM, 13))
	_refresh()

func _text(t: String, col: Color, size: int) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap = true
	l.theme = _ui_theme
	l.add_color_override("font_color", col)
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Regular.ttf")
	f.size = size
	f.use_filter = true
	l.add_font_override("font", f)
	return l

func _font_row(id: String, title: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	row.connect("gui_input", self, "_on_row_input", [id])
	var v := VBoxContainer.new()
	v.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_constant_override("separation", 2)
	row.add_child(v)
	var name_l := _text(title, TEXT, 15)
	name_l.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var sample := Label.new()
	sample.mouse_filter = MOUSE_FILTER_IGNORE
	sample.clip_text = true
	sample.add_color_override("font_color", TEXT)
	sample.name = "Sample"
	sample.rect_min_size = Vector2(0, 30) # (same height before its font is in)
	v.add_child(sample)
	_rows[id] = row
	sample.text = SAMPLE
	_pending.append(id)
	set_process(true)
	return row

# each sample in its own font, a few per frame (40+ fonts at once made the tab
# slow to open)
var _pending := []
func _process(_d):
	var n := 0
	while not _pending.empty() and n < 4:
		var id: String = _pending.pop_front()
		if _rows.has(id):
			_set_sample_font(id)
		n += 1
	if _pending.empty():
		set_process(false)

func _set_sample_font(id: String):
	var sample: Label = _rows[id].get_child(0).get_node("Sample")
	var d: DynamicFontData = null
	if id == HudFont.CUSTOM:
		d = HudFont.load_data(HudFont.custom_file())
	else:
		d = HudFont.data_for(id, "", "regular", {})
	if d == null:
		d = load("res://assets/font/Lato/Lato-Regular.ttf")
	var f := DynamicFont.new()
	f.font_data = d
	f.size = 22
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Lato/Lato-Regular.ttf"))
	sample.add_font_override("font", f)
	sample.text = SAMPLE if (id != HudFont.CUSTOM or HudFont.custom_file() != "") else "(no font chosen yet: choose a font file below)"

func _style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.07) if on else Color(1, 1, 1, 0.025)
	sb.border_color = ACCENT if on else Color(1, 1, 1, 0.08)
	sb.border_width_left = 3
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb

func _refresh():
	var cur := String(Rhythia.hud_font)
	for id in _rows:
		_rows[id].add_stylebox_override("panel", _style(id == cur))
	var cf := HudFont.custom_file()
	_remove_btn.disabled = cf == ""
	_status.text = ("Your own font is saved (.%s)." % cf.get_extension()) if cf != "" else "No font file chosen yet."

func _on_row_input(ev, id: String):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if id == HudFont.CUSTOM and HudFont.custom_file() == "":
			_on_pick()
			return
		_choose(id)

var _size: HSlider
var _size_l: Label
func _on_size(v: float):
	Rhythia.hud_font_size = clamp(v, 50.0, 200.0)
	_size_l.text = "%d%%" % int(Rhythia.hud_font_size)
	if _size.value != Rhythia.hud_font_size:
		_size.value = Rhythia.hud_font_size
	Rhythia.save_settings()

func _choose(id: String):
	Rhythia.hud_font = id
	Rhythia.save_settings()
	_refresh()

func _on_pick():
	Globals.file_sel.open_file(self, "_on_font_picked", PoolStringArray(["*.ttf, *.otf ; Fonts"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _on_font_picked(files):
	if files == null or files.size() == 0:
		return
	var err := HudFont.set_custom(String(files[0]))
	if err != "":
		Globals.notify(Globals.NOTIFY_WARN, err, "Fonts")
		return
	_set_sample_font(HudFont.CUSTOM)
	_choose(HudFont.CUSTOM)
	Globals.notify(Globals.NOTIFY_INFO, "Your font is used in songs now.", "Fonts")

func _on_remove():
	HudFont.remove_custom()
	if String(Rhythia.hud_font) == HudFont.CUSTOM:
		Rhythia.hud_font = HudFont.DEFAULT
		Rhythia.save_settings()
	_set_sample_font(HudFont.CUSTOM)
	_refresh()
