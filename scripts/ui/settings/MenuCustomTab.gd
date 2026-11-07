extends VBoxContainer

# Settings > Menu Customizer: your own look for the menu (MenuStyle.gd keeps
# it and puts it on; WaveMenuBG.gd draws the background pattern). Everything
# shows straight away. Each colour has its own reset arrow; "Reset everything"
# gives the game's look back. Skins carry it (Settings > Skins).

const MenuStyle = preload("res://scripts/ui/menu/MenuStyle.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var box: VBoxContainer
var _pickers := {} # key -> ColorPickerButton
var _sliders := {} # key -> HSlider
var _pattern: OptionButton
var _bg_pickers := []
var _speed: HSlider
var _filling := false

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Menu Customizer"):
		return
	var t = load("res://scripts/ui/settings/MenuCustomTab.gd").new()
	t.name = "Menu Customizer"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Skins")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _label(text: String, f: Font, col: Color, wrap := false, parent: Control = null) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.autowrap = wrap
	if wrap:
		l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _ready():
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	var m = MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var t := _label("Menu Customizer", f_title, ACCENT, false, head)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	var reset := Button.new()
	reset.text = "  Reset everything  "
	reset.theme = load("res://uitheme.tres")
	reset.add_font_override("font", f_bold)
	reset.connect("pressed", self, "_reset_all")
	head.add_child(reset)
	_label("Make the menu yours: the background pattern, buttons, text, text boxes and the sidebar. Changes show straight away. Exporting a skin (Settings > Skins) takes your menu with it.", f_body, DIM, true)

	# --- background
	box.add_child(HSeparator.new())
	_label("Background", f_title, ACCENT)
	var row := _row("Pattern")
	_pattern = OptionButton.new()
	_pattern.theme = load("res://uitheme.tres")
	_pattern.add_font_override("font", f_bold)
	_pattern.rect_min_size = Vector2(260, 34)
	for k in MenuStyle.PATTERNS:
		_pattern.add_item(MenuStyle.PATTERN_NAMES[k])
	_pattern.connect("item_selected", self, "_on_pattern")
	row.add_child(_pattern)
	row = _row("Colours")
	for i in 3:
		var cp := ColorPickerButton.new()
		cp.rect_min_size = Vector2(64, 32)
		cp.hint_tooltip = ["Background", "Lines", "Accent"][i]
		cp.connect("color_changed", self, "_on_bg_color")
		row.add_child(cp)
		_bg_pickers.append(cp)
		_label(["background", "lines", "accent"][i], f_body, DIM, false, row)
	var own := Button.new()
	own.text = "  Pattern's own colours  "
	own.theme = load("res://uitheme.tres")
	own.add_font_override("font", f_body)
	own.hint_tooltip = "The pattern's own colours (or your colorset's, with Wave Menu colorset on)"
	own.connect("pressed", self, "_bg_own_colors")
	row.add_child(own)
	row = _row("Speed")
	_speed = HSlider.new()
	_speed.min_value = 0
	_speed.max_value = 3
	_speed.step = 0.1
	_speed.rect_min_size = Vector2(260, 24)
	_speed.size_flags_vertical = SIZE_SHRINK_CENTER
	_speed.connect("value_changed", self, "_on_speed")
	row.add_child(_speed)

	# --- buttons
	box.add_child(HSeparator.new())
	_label("Buttons", f_title, ACCENT)
	_color_row("Button colour", "btn_bg")
	_color_row("When pointed at", "btn_hover")
	_color_row("Button text", "btn_text")
	_slider_row("Roundness", "btn_radius", 0, 20)
	_slider_row("Border width", "btn_border_w", 0, 4)
	_color_row("Border colour", "btn_border")
	_color_row("Highlight (focus)", "focus")

	# --- text
	box.add_child(HSeparator.new())
	_label("Text and text boxes", f_title, ACCENT)
	_color_row("Text", "text")
	_color_row("Headings and highlights (the pink)", "accent")
	_color_row("Text box", "field_bg")
	_color_row("Text box text", "field_text")

	# --- sidebar and menu
	box.add_child(HSeparator.new())
	_label("Sidebar and menu", f_title, ACCENT)
	_color_row("Sidebar", "sidebar_bg")
	_color_row("Sidebar: selected page", "sidebar_sel")
	_color_row("Sidebar icons and names", "sidebar_icon")
	_color_row("Menu tint (over the background)", "menu_tint")

	# --- a preview of the theme
	box.add_child(HSeparator.new())
	_label("Preview", f_title, ACCENT)
	var pv := HBoxContainer.new()
	pv.add_constant_override("separation", 12)
	box.add_child(pv)
	var pb := Button.new()
	pb.text = "  A button  "
	pb.theme = load("res://uitheme.tres")
	pv.add_child(pb)
	var pl := Label.new()
	pl.text = "Some text"
	pl.theme = load("res://uitheme.tres")
	pv.add_child(pl)
	var pe := LineEdit.new()
	pe.text = "A text box"
	pe.rect_min_size = Vector2(200, 0)
	pe.theme = load("res://uitheme.tres")
	pv.add_child(pe)
	_fill()

func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 10)
	box.add_child(h)
	var l := _label(title, f_bold, TEXT, false, h)
	l.rect_min_size.x = 300
	l.valign = Label.VALIGN_CENTER
	return h

func _undo_button(key: String, parent: Control):
	var u := Button.new()
	u.text = "  Reset  "
	u.add_font_override("font", f_body)
	u.theme = load("res://uitheme.tres")
	u.hint_tooltip = "The game's own"
	u.connect("pressed", self, "_reset_key", [key])
	parent.add_child(u)

func _color_row(title: String, key: String):
	var h := _row(title)
	var cp := ColorPickerButton.new()
	cp.rect_min_size = Vector2(90, 32)
	cp.edit_alpha = key in ["menu_tint", "focus", "btn_border"]
	cp.connect("color_changed", self, "_on_color", [key])
	h.add_child(cp)
	_pickers[key] = cp
	_undo_button(key, h)

func _slider_row(title: String, key: String, lo: int, hi: int):
	var h := _row(title)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1
	sl.rect_min_size = Vector2(200, 24)
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.connect("value_changed", self, "_on_slider", [key])
	h.add_child(sl)
	_sliders[key] = sl
	_undo_button(key, h)

# the controls show what's on
func _fill():
	_filling = true
	for k in _pickers:
		_pickers[k].color = MenuStyle.get_value(k)
	for k in _sliders:
		_sliders[k].value = MenuStyle.get_value(k)
	_pattern.select(MenuStyle.PATTERNS.find(MenuStyle.bg_pattern() if Rhythia.wave_menu else "off"))
	var cols := MenuStyle.bg_colors()
	if cols.empty():
		cols = MenuStyle.PATTERN_COLORS
	for i in 3:
		_bg_pickers[i].color = cols[i]
	_speed.value = MenuStyle.bg_speed()
	_filling = false

func _changed():
	MenuStyle.refresh(get_tree())

func _on_color(c: Color, key: String):
	if _filling:
		return
	MenuStyle.set_value(key, c)
	_changed()

func _on_slider(v: float, key: String):
	if _filling:
		return
	MenuStyle.set_value(key, int(v))
	_changed()

func _reset_key(key: String):
	MenuStyle.set_value(key, null)
	_fill()
	_changed()

func _on_pattern(i: int):
	if _filling:
		return
	var k: String = MenuStyle.PATTERNS[i]
	if k == "off":
		Rhythia.wave_menu = false
	else:
		MenuStyle.set_bg("pattern", k)
		if not Rhythia.wave_menu:
			Rhythia.wave_menu = true
	Rhythia.save_settings()
	_changed()

func _on_bg_color(_c = null):
	if _filling:
		return
	MenuStyle.set_bg("colors", [_bg_pickers[0].color, _bg_pickers[1].color, _bg_pickers[2].color])
	_changed()

func _bg_own_colors():
	MenuStyle.set_bg("colors", null)
	_fill()
	_changed()

func _on_speed(v: float):
	if _filling:
		return
	MenuStyle.set_bg("speed", v)
	_changed()

func _reset_all():
	MenuStyle.reset()
	if not Rhythia.wave_menu:
		Rhythia.wave_menu = true
		Rhythia.save_settings()
	_fill()
	_changed()
