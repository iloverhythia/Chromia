extends MarginContainer
# Settings > Background Editor > HUD panels: the side panels' look
# (scripts/HudPanels.gd) and size. BgEditor.install() adds it to the tab.

const HudPanels = preload("res://scripts/HudPanels.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.898039, 0.94902, 1, 0.6)

var _style: OptionButton
var _size: HSlider
var _size_l: Label
var _img_btn: Button
var _status: Label
var _theme: Theme
var _bright: HSlider
var _bright_l: Label

func _ready():
	_theme = load("res://uitheme.tres")
	add_constant_override("margin_left", 66)
	add_constant_override("margin_right", 66)
	add_constant_override("margin_top", 12)
	add_constant_override("margin_bottom", 12)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 8)
	add_child(v)
	# the background's brightness in songs (scripts/game/BgVeil.gd)
	v.add_child(_text("Background brightness", 20, TEXT, "res://assets/font/Lato/Lato-Bold.ttf"))
	v.add_child(HSeparator.new())
	v.add_child(_text("How bright the background is while you play: lower darkens the world behind the notes. The notes, cursor, grid and HUD stay as they are. People spectating you see it too.", 14, DIM))
	var brow := HBoxContainer.new()
	brow.add_constant_override("separation", 10)
	v.add_child(brow)
	var bl := _text("Brightness", 16, TEXT)
	bl.rect_min_size = Vector2(90, 0)
	brow.add_child(bl)
	_bright = HSlider.new()
	_bright.theme = _theme
	_bright.min_value = 0
	_bright.max_value = 100
	_bright.step = 5
	_bright.rect_min_size = Vector2(320, 28)
	_bright.size_flags_vertical = SIZE_SHRINK_CENTER
	_bright.connect("value_changed", self, "_on_bright")
	brow.add_child(_bright)
	_bright_l = _text("", 16, TEXT)
	_bright_l.rect_min_size = Vector2(60, 0)
	brow.add_child(_bright_l)
	var breset := Button.new()
	breset.theme = _theme
	breset.text = "Reset"
	breset.rect_min_size = Vector2(80, 32)
	breset.connect("pressed", self, "_on_bright", [100.0, true])
	brow.add_child(breset)
	var sp := Control.new()
	sp.rect_min_size = Vector2(0, 14)
	v.add_child(sp)

	v.add_child(_text("HUD panels", 20, TEXT, "res://assets/font/Lato/Lato-Bold.ttf"))
	v.add_child(HSeparator.new())
	v.add_child(_text("How the two side panels look while you play, and how big they are. Sound Space is the Sound Space HUD. People spectating you see your style and size (your own picture stays yours).", 14, DIM))

	var row := HBoxContainer.new()
	row.add_constant_override("separation", 10)
	v.add_child(row)
	var l1 := _text("Style", 16, TEXT)
	l1.rect_min_size = Vector2(90, 0)
	row.add_child(l1)
	_style = OptionButton.new()
	_style.theme = _theme
	_style.rect_min_size = Vector2(240, 32)
	for st in HudPanels.STYLES:
		_style.add_item(st[1])
	_style.connect("item_selected", self, "_on_style")
	row.add_child(_style)
	_img_btn = Button.new()
	_img_btn.theme = _theme
	_img_btn.text = "Choose picture..."
	_img_btn.rect_min_size = Vector2(170, 32)
	_img_btn.connect("pressed", self, "_on_pick")
	row.add_child(_img_btn)
	_status = _text("", 14, DIM)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_status)

	var row2 := HBoxContainer.new()
	row2.add_constant_override("separation", 10)
	v.add_child(row2)
	var l2 := _text("Size", 16, TEXT)
	l2.rect_min_size = Vector2(90, 0)
	row2.add_child(l2)
	_size = HSlider.new()
	_size.theme = _theme
	_size.min_value = 50
	_size.max_value = 200
	_size.step = 5
	_size.rect_min_size = Vector2(320, 28)
	_size.size_flags_vertical = SIZE_SHRINK_CENTER
	_size.connect("value_changed", self, "_on_size")
	row2.add_child(_size)
	_size_l = _text("", 16, TEXT)
	_size_l.rect_min_size = Vector2(60, 0)
	row2.add_child(_size_l)
	var reset := Button.new()
	reset.theme = _theme
	reset.text = "Reset size"
	reset.rect_min_size = Vector2(110, 32)
	reset.connect("pressed", self, "_on_size", [100.0])
	row2.add_child(reset)
	# brightness and where the parts are (HudPanels.gd _place / _brighten)
	var sp2 := Control.new()
	sp2.rect_min_size = Vector2(0, 6)
	v.add_child(sp2)
	v.add_child(_text("Brightness and position of the HUD in songs. Left / right moves the side panels away from the grid or closer, up / down moves them up or down, and Timer & health bar moves those away from the grid or closer. Spectators see it too.", 14, DIM))
	_slider_row(v, "Brightness", "hud_brightness", 10, 200, 5, 100.0, "%d%%")
	_slider_row(v, "Left / right", "hud_panel_x", -2.0, 2.0, 0.05, 0.0, "%+.2f")
	_slider_row(v, "Up / down", "hud_panel_y", -2.0, 2.0, 0.05, 0.0, "%+.2f")
	_slider_row(v, "Timer & health bar", "hud_bars_y", -2.0, 2.0, 0.05, 0.0, "%+.2f")
	connect("visibility_changed", self, "_refresh")
	_refresh()

var _rows := {} # setting -> [slider, value label, format]
func _slider_row(v: Control, label: String, key: String, lo: float, hi: float, step: float, def: float, fmt: String):
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 10)
	v.add_child(row)
	var l := _text(label, 16, TEXT)
	l.rect_min_size = Vector2(90, 0) # (a long name wraps, so the sliders line up)
	row.add_child(l)
	var sl := HSlider.new()
	sl.theme = _theme
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.rect_min_size = Vector2(320, 28)
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.connect("value_changed", self, "_on_row", [key])
	row.add_child(sl)
	var val := _text("", 16, TEXT)
	val.rect_min_size = Vector2(60, 0)
	row.add_child(val)
	var b := Button.new()
	b.theme = _theme
	b.text = "Reset"
	b.rect_min_size = Vector2(80, 32)
	b.connect("pressed", self, "_reset_row", [key, def])
	row.add_child(b)
	_rows[key] = [sl, val, fmt]

func _on_row(x: float, key: String):
	if _refreshing:
		return
	Rhythia.set(key, x)
	Rhythia.save_settings()
	_refresh()

func _reset_row(key: String, def: float):
	Rhythia.set(key, def)
	Rhythia.save_settings()
	_refresh()

func _text(t: String, size: int, col: Color, font_path := "res://assets/font/Lato/Lato-Regular.ttf") -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap = true
	l.valign = Label.VALIGN_CENTER
	var f := DynamicFont.new()
	f.font_data = load(font_path)
	f.size = size
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	return l

var _refreshing := false
func _refresh():
	_refreshing = true
	_style.select(max(0, HudPanels.ids().find(HudPanels.current())))
	_size.value = float(Rhythia.hud_panel_size)
	_bright.value = float(Rhythia.bg_brightness)
	_bright_l.text = "%d%%" % int(Rhythia.bg_brightness)
	_size_l.text = "%d%%" % int(Rhythia.hud_panel_size)
	for key in _rows:
		var r: Array = _rows[key]
		var x := float(Rhythia.get(key))
		r[0].value = x
		r[1].text = (r[2] % int(x)) if r[2] == "%d%%" else (r[2] % x)
	var img := HudPanels.image_file()
	_img_btn.visible = HudPanels.current() == "image"
	_status.text = (img.get_file() if img != "" else "No picture yet") if _img_btn.visible else ""
	_refreshing = false

func _on_style(i: int):
	if _refreshing:
		return
	var id: String = HudPanels.ids()[i]
	HudPanels.set_style(id)
	Rhythia.save_settings()
	_refresh()
	if id == "image" and HudPanels.image_file() == "":
		_on_pick()

func _on_size(v: float):
	if _refreshing and v != 100.0:
		return
	Rhythia.hud_panel_size = clamp(v, 50.0, 200.0)
	Rhythia.save_settings()
	_refresh()

func _on_pick():
	Globals.file_sel.open_file(self, "_on_picked", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"]), false, OS.get_system_dir(OS.SYSTEM_DIR_PICTURES))

func _on_picked(files):
	if files == null or files.size() == 0:
		return
	var src := String(files[0])
	var ext := src.get_extension().to_lower()
	var img := Image.new()
	if not (ext in HudPanels.IMAGE_EXTS) or img.load(src) != OK:
		Globals.notify(Globals.NOTIFY_WARN, "That picture couldn't be read.", "HUD panels")
		return
	for e in HudPanels.IMAGE_EXTS:
		var old: String = Globals.p("%s.%s" % [HudPanels.IMAGE_BASE, e])
		if File.new().file_exists(old):
			Directory.new().remove(old)
	# (kept as a PNG, at most 1024 px on its longer side)
	var m: int = int(max(img.get_width(), img.get_height()))
	if m > 1024:
		img.resize(int(img.get_width() * 1024 / m), int(img.get_height() * 1024 / m), Image.INTERPOLATE_BILINEAR)
	img.save_png(Globals.p(HudPanels.IMAGE_BASE + ".png"))
	HudPanels.set_style("image")
	Rhythia.save_settings()
	_refresh()

func _on_bright(v: float, force := false):
	if _refreshing and not force:
		return
	Rhythia.bg_brightness = clamp(v, 0.0, 100.0)
	Rhythia.save_settings()
	_refresh()
