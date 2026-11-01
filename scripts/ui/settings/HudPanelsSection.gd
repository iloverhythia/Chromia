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

func _ready():
	_theme = load("res://uitheme.tres")
	add_constant_override("margin_left", 66)
	add_constant_override("margin_right", 66)
	add_constant_override("margin_top", 12)
	add_constant_override("margin_bottom", 12)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 8)
	add_child(v)
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
	connect("visibility_changed", self, "_refresh")
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
	_size_l.text = "%d%%" % int(Rhythia.hud_panel_size)
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
