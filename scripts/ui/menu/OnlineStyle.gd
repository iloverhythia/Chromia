extends Reference

# The Online page's look (menu2.gd builds the page and fills it): the Spectate
# window's colours, cards and buttons, with the Profile page's big title,
# pink section headings and thin rules.

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const ACCENT_HOVER = Color(0.913725, 0.74902, 0.94902)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const PLAYING = Color(0.55, 0.9, 0.65)
const WAITING = Color(1, 0.85, 0.45)
const BAD = Color(1, 0.55, 0.5)
const WINDOW_BG = Color(0.035, 0.03, 0.05, 0.94)
const SECTION_BG = Color(1, 1, 1, 0.025)
const CARD_BG = Color(0.075, 0.068, 0.1, 1)
const CARD_HOVER = Color(0.11, 0.1, 0.145, 1)
const FIELD_BG = Color(0.13, 0.125, 0.165, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const PINK = Color(0.96, 0.6, 0.78)
const RULE = Color(1, 1, 1, 0.16)

var f_regular: DynamicFont
var f_bold: DynamicFont
var f_small: DynamicFont
var f_head: DynamicFont
var f_title: DynamicFont
var f_code: DynamicFont

func _init():
	f_regular = font("res://assets/font/Lato/Lato-Regular.ttf", 16)
	f_bold = font("res://assets/font/Lato/Lato-Bold.ttf", 16)
	f_small = font("res://assets/font/Lato/Lato-Regular.ttf", 14)
	f_head = font("res://assets/font/Lato/Lato-Bold.ttf", 22)
	f_title = font("res://assets/font/Lato/Lato-Black.ttf", 34)
	f_code = font("res://assets/font/Lato/Lato-Black.ttf", 32)

static func font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

static func flat(bg: Color, radius: int = 4, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad_h: float = 0.0, pad_v: float = 0.0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s

func label(text: String, f: Font = null, col: Color = TEXT, wrap: bool = false) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", f if f != null else f_regular)
	l.add_color_override("font_color", col)
	l.autowrap = wrap
	if wrap:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

# the page title, like the Profile page's ("Your Profile")
func title(text: String) -> Label:
	var l = label(text, f_title, TEXT)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	l.add_constant_override("shadow_offset_x", 2)
	l.add_constant_override("shadow_offset_y", 2)
	return l

# a section heading in pink, like "Top Play"
func heading(text: String) -> Label:
	return label(text, f_head, PINK)

func rule() -> ColorRect:
	var r = ColorRect.new()
	r.color = RULE
	r.rect_min_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

# a soft panel holding a section (VBox inside)
func section(parent: Control, ratio: float = 1.0) -> VBoxContainer:
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", flat(SECTION_BG, 4, Color(1, 1, 1, 0.05), 1, 18, 16))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = ratio
	parent.add_child(p)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 10)
	p.add_child(v)
	return v

# a row card (a player, a lobby): returns the HBox inside
func card(parent: Control) -> HBoxContainer:
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", flat(CARD_BG, 4, Color(1, 1, 1, 0.04), 1, 14, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 12)
	p.add_child(h)
	return h

func button(b: Button, accent: bool = false, small: bool = false) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.theme = null
	b.add_font_override("font", f_bold)
	var dark = Color(0.1, 0.07, 0.12)
	for k in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_color_override(k, dark if accent else TEXT)
	b.add_color_override("font_color_disabled", Color(DIM.r, DIM.g, DIM.b, 0.6))
	var ph = 12.0 if small else 18.0
	var pv = 4.0 if small else 8.0
	b.add_stylebox_override("normal", flat(LILAC if accent else BTN_BG, 3, Color(0, 0, 0, 0), 0, ph, pv))
	b.add_stylebox_override("hover", flat(ACCENT_HOVER if accent else BTN_HOVER, 3, Color(0, 0, 0, 0), 0, ph, pv))
	b.add_stylebox_override("pressed", flat(ACCENT if accent else BTN_HOVER, 3, Color(0, 0, 0, 0), 0, ph, pv))
	b.add_stylebox_override("disabled", flat(Color(0.09, 0.085, 0.11, 1), 3, Color(0, 0, 0, 0), 0, ph, pv))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.rect_min_size = Vector2(0, 30 if small else 40)
	return b

# a tab (Lobby / Admin): the active one filled lilac
func tab(b: Button) -> Button:
	button(b)
	b.toggle_mode = true
	b.add_font_override("font", f_head)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed"]:
		b.add_color_override(k, TEXT)
	b.add_color_override("font_color", DIM)
	var on = Color(LILAC.r, LILAC.g, LILAC.b, 0.3)
	b.add_stylebox_override("pressed", flat(on, 3, LILAC, 2, 22, 8))
	b.add_stylebox_override("hover_pressed", flat(Color(LILAC.r, LILAC.g, LILAC.b, 0.38), 3, ACCENT, 2, 22, 8))
	b.add_stylebox_override("normal", flat(BTN_BG, 3, Color(1, 1, 1, 0.06), 1, 22, 8))
	b.add_stylebox_override("hover", flat(BTN_HOVER, 3, Color(1, 1, 1, 0.1), 1, 22, 8))
	b.rect_min_size = Vector2(130, 48)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

# restyles a panel built with the old theme (the admin tools): captions become
# pink headings, separators thin rules, and fields / buttons / checkboxes /
# scrollbars the page's own; rows added later get it too
func restyle_tree(n: Node, top := true):
	if n is HSeparator:
		var r = rule()
		var parent = n.get_parent()
		var i = n.get_index()
		parent.remove_child(n)
		n.queue_free()
		parent.add_child(r)
		parent.move_child(r, i)
		return
	if n.has_meta("ost_done"):
		return
	n.set_meta("ost_done", true)
	if n is Button and not (n is CheckBox) and not (n is OptionButton):
		button(n, false, n.rect_min_size.y > 0 and n.rect_min_size.y <= 30)
	elif n is CheckBox:
		check(n)
	elif n is LineEdit:
		field(n)
	elif n is ScrollContainer:
		scroll(n)
	elif n is Label:
		var l: Label = n
		if l.get_parent() is VBoxContainer and l.get_parent().has_meta("ost_section"):
			l.add_font_override("font", f_head)
			l.add_color_override("font_color", PINK)
		else:
			l.add_font_override("font", f_regular)
			if not l.has_color_override("font_color"):
				l.add_color_override("font_color", TEXT)
	elif n is PanelContainer and top:
		n.add_stylebox_override("panel", flat(SECTION_BG, 4, Color(1, 1, 1, 0.05), 1, 18, 16))
	if n is BoxContainer and not n.is_connected("sort_children", self, "_restyle_new"):
		n.connect("sort_children", self, "_restyle_new", [n])
	for c in n.get_children():
		restyle_tree(c, false)

func _restyle_new(box: Node):
	for c in box.get_children():
		if not c.has_meta("ost_done") or c is HSeparator:
			restyle_tree(c, false)

func make_button(text: String, target: Object, method: String, binds: Array = [], accent: bool = false, small: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	button(b, accent, small)
	b.connect("pressed", target, method, binds)
	return b

func field(e: LineEdit) -> LineEdit:
	e.theme = null
	e.add_font_override("font", f_regular)
	e.add_color_override("font_color", TEXT)
	e.add_color_override("font_color_uneditable", DIM)
	e.add_color_override("cursor_color", ACCENT)
	e.add_stylebox_override("normal", flat(FIELD_BG, 3, Color(0, 0, 0, 0), 0, 14, 8))
	e.add_stylebox_override("focus", flat(FIELD_BG, 3, LILAC, 1, 14, 8))
	e.add_stylebox_override("read_only", flat(FIELD_BG, 3, Color(0, 0, 0, 0), 0, 14, 8))
	e.rect_min_size.y = 40
	return e

func check(c: CheckBox) -> CheckBox:
	c.focus_mode = Control.FOCUS_NONE
	c.add_font_override("font", f_bold)
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed"]:
		c.add_color_override(k, TEXT)
	for k in ["normal", "hover", "pressed", "hover_pressed"]:
		c.add_stylebox_override(k, flat(BTN_BG if k.begins_with("normal") or k == "pressed" else BTN_HOVER, 3, Color(0, 0, 0, 0), 0, 12, 8))
	c.add_stylebox_override("focus", StyleBoxEmpty.new())
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return c

# a thin lilac scrollbar instead of the theme's
func scroll(sc: ScrollContainer) -> ScrollContainer:
	sc.scroll_horizontal_enabled = false
	var bar = sc.get_v_scrollbar()
	var track = flat(Color(1, 1, 1, 0.04), 2)
	track.content_margin_left = 3
	track.content_margin_right = 3
	var grab = flat(Color(LILAC.r, LILAC.g, LILAC.b, 0.45), 2)
	var grab_hi = flat(Color(LILAC.r, LILAC.g, LILAC.b, 0.75), 2)
	bar.add_stylebox_override("scroll", track)
	bar.add_stylebox_override("scroll_focus", track)
	bar.add_stylebox_override("grabber", grab)
	bar.add_stylebox_override("grabber_highlight", grab_hi)
	bar.add_stylebox_override("grabber_pressed", grab_hi)
	bar.rect_min_size.x = 8
	return sc

# a small coloured tag ("HOST", "IN GAME")
func badge(text: String, col: Color) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", flat(Color(col.r, col.g, col.b, 0.16), 3, Color(col.r, col.g, col.b, 0.5), 1, 8, 2))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = label(text, f_small, col)
	p.add_child(l)
	return p

# a round initial (a player without a picture here)
func initial(name: String) -> Control:
	var c = Panel.new()
	var h = 0.0
	for i in name.length():
		h = fmod(h * 31.0 + float(name.ord_at(i)), 997.0)
	var col = Color.from_hsv(fmod(h / 997.0, 1.0), 0.35, 0.55)
	c.add_stylebox_override("panel", flat(col, 18))
	c.rect_min_size = Vector2(36, 36)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = label(name.left(1).to_upper() if name != "" else "?", f_bold, TEXT)
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	c.add_child(l)
	return c

func spacer(expand: bool = true) -> Control:
	var s = Control.new()
	if expand:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
