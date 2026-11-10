extends Control

# The new Settings look (Settings > Replays & Misc > Experimental > New
# Settings UI, on by default): Settings in the look of the Online and Profile
# pages (OnlineStyle.gd), with a search.
#
#   - one dark panel behind everything, a "Settings" title, and a search box;
#   - the categories as a list down the left (there are 17: as tabs across the
#     top they needed arrows to scroll through);
#   - each group of settings in a card with its name in pink, and the
#     checkboxes, buttons, number boxes, dropdowns and text in the same style
#     as the Online page;
#   - the search lists the settings that match from every category (their
#     name or their hover text); picking one opens its category, scrolls to it
#     and outlines it for a moment.
#
# Nothing is moved or renamed in the pages themselves (they stay at
# Main/Settings/S/F/TabContainer/..., so everything that finds a setting by
# its path still does): the look is put on with overrides and with a
# background drawn behind each group. Turning the setting off loads the menu
# again with the old header (SettingsHeader.gd).
#
# menu2.gd installs this instead of SettingsHeader after the tabs are added.

const PANEL_L := 0.0
const PANEL_T := 0.0
const PANEL_R := 0.0
const PANEL_B := 0.0
const CATS_W := 198.0
const MAX_RESULTS := 60

var S
var settings: Control
var scroll: ScrollContainer
var tc: TabContainer
var header: VBoxContainer
var cats_scroll: ScrollContainer
var cats: VBoxContainer
var cat_btns := []
var search: LineEdit
var results_scroll: ScrollContainer
var results: VBoxContainer
var top_buttons: Control = null
var _bg: Panel = null
var _title: Label = null
var _restyle_timer: Timer = null
var _closed_ticks := 0
var _sig := ""
var _style_next := 0
var _index := []
var _index_sig := ""
var _flash: Panel = null

static func install(settings_page: Control):
	if settings_page == null or settings_page.has_node("NewUI"):
		return
	var s = settings_page.get_node_or_null("S")
	var f = s.get_node_or_null("F") if s != null else null
	var tabs = f.get_node_or_null("TabContainer") if f != null else null
	if tabs == null:
		return
	var ui = load("res://scripts/ui/settings/SettingsNewUI.gd").new()
	ui.name = "NewUI"
	ui.settings = settings_page
	ui.scroll = s
	ui.tc = tabs
	settings_page.add_child(ui)
	settings_page.move_child(ui, 0) # (drawn first: the panel is behind the pages)

func _ready():
	S = load("res://scripts/ui/menu/OnlineStyle.gd").new()
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.name = "Bg"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.margin_left = PANEL_L
	bg.margin_top = PANEL_T
	bg.margin_right = -PANEL_R
	bg.margin_bottom = -PANEL_B
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.add_stylebox_override("panel", S.flat(S.WINDOW_BG, 0, Color(0, 0, 0, 0), 0)) # (the whole screen, edge to edge)
	add_child(bg)
	_bg = bg
	add_to_group("menu_style") # (restyle(): the Menu Customizer's colours, as they change)

	header = VBoxContainer.new()
	header.name = "Header"
	header.anchor_right = 1.0
	header.margin_left = PANEL_L + 22
	header.margin_right = -(PANEL_R + 22)
	header.margin_top = PANEL_T + 12
	header.add_constant_override("separation", 8)
	add_child(header)
	var top := HBoxContainer.new()
	top.add_constant_override("separation", 14)
	header.add_child(top)
	_title = S.title("Settings")
	top.add_child(_title)
	top.add_child(S.spacer())
	search = LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search settings..."
	search.clear_button_enabled = true
	S.field(search)
	search.rect_min_size = Vector2(320, 38)
	search.size_flags_vertical = SIZE_SHRINK_CENTER
	search.connect("text_changed", self, "_on_search")
	top.add_child(search)
	# the buttons that were across the top of the page (Save, profiles, folders...)
	var f = scroll.get_node("F")
	var buttons = f.get_node_or_null("TopButtons")
	if buttons != null:
		f.remove_child(buttons)
		# (in a sideways scroll: on a narrow window the row never pushes the page wider)
		var hs := ScrollContainer.new()
		hs.name = "TopScroll"
		hs.scroll_vertical_enabled = false
		hs.rect_min_size = Vector2(0, 34)
		hs.size_flags_horizontal = SIZE_EXPAND_FILL
		header.add_child(hs)
		hs.add_child(buttons)
		buttons.rect_min_size = Vector2(0, 0)
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			buttons.add_constant_override(k, 0)
		var row = buttons.get_node_or_null("TopButtonsHBox")
		if row != null:
			row.rect_min_size = Vector2(0, 0)
			row.add_constant_override("separation", 6)
		top_buttons = buttons
		buttons.connect("resized", self, "_fit_top", [hs])
		hs.connect("resized", self, "_fit_top", [hs])
	header.add_child(S.rule())

	cats_scroll = S.scroll(ScrollContainer.new())
	cats_scroll.name = "Categories"
	add_child(cats_scroll)
	cats = VBoxContainer.new()
	cats.add_constant_override("separation", 3)
	cats.size_flags_horizontal = SIZE_EXPAND_FILL
	cats_scroll.add_child(cats)

	# the search's list sits where the pages are, over them
	results_scroll = S.scroll(ScrollContainer.new())
	results_scroll.name = "NewUIResults"
	results_scroll.visible = false
	settings.call_deferred("add_child", results_scroll)
	results = VBoxContainer.new()
	results.add_constant_override("separation", 5)
	results.size_flags_horizontal = SIZE_EXPAND_FILL
	results_scroll.add_child(results)

	tc.tabs_visible = false
	tc.add_stylebox_override("panel", StyleBoxEmpty.new())
	tc.connect("tab_changed", self, "_on_page_tab")
	S.scroll(scroll)
	# (the page was made 1150 wide for the old look: here it takes the room next to
	# the categories, and only a page that is wider than that scrolls sideways)
	f.rect_min_size = Vector2(0, 0)
	scroll.scroll_horizontal_enabled = true
	var hb = scroll.get_h_scrollbar()
	hb.add_stylebox_override("scroll", S.flat(Color(1, 1, 1, 0.04), 3))
	hb.add_stylebox_override("scroll_focus", S.flat(Color(1, 1, 1, 0.04), 3))
	hb.add_stylebox_override("grabber", S.flat(Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.45), 3))
	for k in ["grabber_highlight", "grabber_pressed"]:
		hb.add_stylebox_override(k, S.flat(Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.75), 3))
	hb.rect_min_size.y = 8
	header.connect("resized", self, "_fit")
	connect("resized", self, "_fit")
	settings.connect("visibility_changed", self, "_on_shown")
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	t.connect("timeout", self, "_tick")
	add_child(t)
	_tick()
	call_deferred("_fit")

# the list of categories and the pages start under the header
func _fit():
	var top: float = header.margin_top + header.rect_size.y + 10
	cats_scroll.rect_position = Vector2(PANEL_L + 14, top)
	cats_scroll.rect_size = Vector2(CATS_W, max(rect_size.y - top - PANEL_B - 12, 40))
	var left: float = PANEL_L + 14 + CATS_W + 14
	for sc in [scroll, results_scroll]:
		sc.anchor_left = 0
		sc.anchor_top = 0
		sc.anchor_right = 1
		sc.anchor_bottom = 1
		sc.margin_left = left
		sc.margin_top = top
		sc.margin_right = -(PANEL_R + 8)
		sc.margin_bottom = -(PANEL_B + 12)

# --- categories ----------------------------------------------------------------

func _cat_button(title: String, i: int) -> Button:
	var b := Button.new()
	b.text = title
	b.toggle_mode = true
	b.align = Button.ALIGN_LEFT
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	b.hint_tooltip = title
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.rect_min_size = Vector2(0, 32)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_font_override("font", S.f_bold)
	b.add_color_override("font_color", S.DIM)
	b.add_color_override("font_color_hover", S.TEXT)
	b.add_color_override("font_color_pressed", S.TEXT)
	b.add_color_override("font_color_hover_pressed", S.TEXT)
	var none: StyleBoxFlat = S.flat(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, 12, 5)
	var on: StyleBoxFlat = S.flat(Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.2), 4, Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.75), 1, 12, 5)
	b.add_stylebox_override("normal", none)
	b.add_stylebox_override("hover", S.flat(S.BTN_HOVER, 4, Color(0, 0, 0, 0), 0, 12, 5))
	b.add_stylebox_override("pressed", on)
	b.add_stylebox_override("hover_pressed", on)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.connect("pressed", self, "_on_cat", [i])
	return b

func _on_cat(i: int):
	if search.text != "":
		search.text = ""
		_on_search("")
	tc.current_tab = i
	scroll.scroll_vertical = 0 # a new page starts at its top
	_mark_cat()

func _on_page_tab(_i: int):
	_mark_cat()
	# (right away, not at the next tick: no moment of the old look)
	if tc.get_tab_count() > 0:
		_style(tc.get_tab_control(tc.current_tab), true)

# Settings is opened: everything is in the new look before it's drawn
func _on_shown():
	if is_visible_in_tree():
		_tick()
		_fit()

func _mark_cat():
	for i in range(cat_btns.size()):
		cat_btns[i].pressed = i == tc.current_tab

# tabs added, moved or renamed later (VR, Keybinds...): the list follows; and
# what a page shows is styled as it comes (some pages build themselves late)
func _tick():
	var titles := []
	for i in range(tc.get_tab_count()):
		titles.append(tc.get_tab_title(i))
	var sig := PoolStringArray(titles).join("|")
	if sig != _sig:
		_sig = sig
		for b in cat_btns:
			b.queue_free()
		cat_btns = []
		for i in range(titles.size()):
			var b: Button = _cat_button(titles[i], i)
			cats.add_child(b)
			cat_btns.append(b)
		_mark_cat()
	if tc.tabs_visible:
		tc.tabs_visible = false
	var n: int = tc.get_tab_count()
	if n == 0:
		return
	# The page that shows is styled first, the others one at a time (so nothing
	# hitches). This also runs while Settings is closed: by the time it's
	# opened the pages have the new look already, with no moment of the old one.
	# (Closed, once every page has had its turn there's nothing left to do.)
	if not is_visible_in_tree():
		_closed_ticks += 1
		if _closed_ticks > n + 3:
			return
	else:
		_closed_ticks = n # (a few more passes after closing, for pages filled late)
	_style(tc.get_tab_control(tc.current_tab), true)
	_style_next = (_style_next + 1) % n
	_style(tc.get_tab_control(_style_next), true)
	if top_buttons != null and is_instance_valid(top_buttons):
		_style_top(top_buttons)

# the row of buttons: small ones, Save the one that stands out
func _style_top(n: Node):
	for c in n.get_children():
		if c is Button and not c.has_meta("nsu"):
			c.set_meta("nsu", true)
			var theme_was = c.theme
			S.button(c, c.name == "Save", true)
			c.theme = theme_was # (its popup keeps the game's theme)
			c.flat = false
			c.modulate = Color(1, 1, 1, c.modulate.a)
			c.rect_min_size = Vector2(0, 32)
			for k in ["normal", "hover", "pressed", "disabled"]:
				var sb = c.get_stylebox(k)
				if sb is StyleBoxFlat:
					sb.content_margin_left = 11
					sb.content_margin_right = 11
			for k in ["font_color_focus", "font_color_hover_pressed"]:
				c.add_color_override(k, c.get_color("font_color"))
		else:
			_style_top(c)

# (a bar under the row only shows when the buttons don't fit: room for it then)
func _fit_top(hs: ScrollContainer):
	if hs.rect_size.x < 8:
		return # (not laid out yet: no room is made for a bar that may not be needed)
	var over: bool = top_buttons.rect_size.x > hs.rect_size.x + 1
	var h: float = 46.0 if over else 34.0
	if hs.rect_min_size.y != h:
		hs.rect_min_size.y = h

# The Menu Customizer's colours changed (MenuStyle.refresh calls this on the
# "menu_style" group, many times while a colour is dragged): a moment after the
# last change everything is styled again with the new colours.
func restyle():
	if _restyle_timer == null:
		_restyle_timer = Timer.new()
		_restyle_timer.one_shot = true
		_restyle_timer.wait_time = 0.2
		_restyle_timer.connect("timeout", self, "_restyle_now")
		add_child(_restyle_timer)
	_restyle_timer.start()

func _restyle_now():
	S.retint()
	_bg.add_stylebox_override("panel", S.flat(S.WINDOW_BG, 0, Color(0, 0, 0, 0), 0))
	_title.add_color_override("font_color", S.TEXT)
	var keep: Vector2 = search.rect_min_size
	S.field(search)
	search.rect_min_size = keep
	_sig = "" # (the categories are made again)
	if top_buttons != null and is_instance_valid(top_buttons):
		_unmark(top_buttons)
	for i in range(tc.get_tab_count()):
		_unmark(tc.get_tab_control(i))
	_closed_ticks = 0
	_tick()
	if results_scroll.visible:
		_on_search(search.text)

func _unmark(n: Node):
	if n.has_meta("nsu"):
		n.remove_meta("nsu")
	if n is CanvasItem and (n.has_meta("nsu_group") or n.has_meta("nsu_page")):
		n.update() # (its card is drawn with the colours of the moment)
	for c in n.get_children():
		_unmark(c)

# --- the look ---------------------------------------------------------------------

static func _pretty(s: String) -> String:
	# "HitMissSounds" -> "Hit Miss Sounds", "UIColor" -> "UI Color"
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			var prev := s[i - 1]
			var next := s[i + 1] if i + 1 < s.length() else ""
			if prev != " " and (prev != prev.to_upper() or (next != "" and next != next.to_upper())):
				out += " "
		out += c
	return out.replace("_", " ").strip_edges()

func _style(n: Node, page: bool):
	if n == null:
		return
	if page:
		var groups := 0
		for g in n.get_children():
			if g is VBoxContainer and g.has_node("Group"):
				groups += 1
				if not g.has_meta("nsu_group"):
					_card(g)
		# (a page with no groups of its own, like Keybinds: one card behind all of it)
		if groups == 0 and n is Control and not n.has_meta("nsu_page"):
			n.set_meta("nsu_page", true)
			n.connect("draw", self, "_draw_page", [n])
			n.update()
	_style_node(n)

func _card(g: VBoxContainer):
	g.set_meta("nsu_group", true)
	var title := _pretty(g.name)
	var m = g.get_node("Group")
	if m is MarginContainer:
		m.add_constant_override("margin_left", 20)
		m.add_constant_override("margin_right", 18)
		m.add_constant_override("margin_top", 46)
		m.add_constant_override("margin_bottom", 16)
	g.connect("draw", self, "_draw_card", [g, title])
	g.update()

func _draw_page(pg: Control):
	if pg.rect_size.y < 30:
		return
	pg.draw_style_box(S.flat(S.SECTION_BG, 5, Color(1, 1, 1, 0.06), 1), Rect2(Vector2.ZERO, pg.rect_size))

func _draw_card(g: Control, title: String):
	if g.rect_size.y < 50:
		return # (an empty group)
	g.draw_style_box(S.flat(S.SECTION_BG, 5, Color(1, 1, 1, 0.06), 1), Rect2(Vector2.ZERO, g.rect_size))
	g.draw_string(S.f_head, Vector2(20, 12 + S.f_head.get_ascent()), tr(title), S.PINK)

func _style_node(n: Node):
	if n.has_meta("nsu"):
		for c in n.get_children():
			_style_node(c)
		return
	n.set_meta("nsu", true)
	if n is HSeparator:
		# (the cards are apart already: the line between groups goes, its gap stays)
		n.modulate.a = 0.0
		n.rect_min_size.y = 4
		n.add_constant_override("separation", 12)
	elif n is ColorPickerButton:
		pass
	elif n is CheckBox:
		var c: CheckBox = n
		c.focus_mode = FOCUS_NONE
		c.add_font_override("font", S.f_regular)
		for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
			c.add_color_override(k, S.TEXT)
		c.add_color_override("font_color_disabled", S.DIM)
		var none: StyleBoxFlat = S.flat(Color(0, 0, 0, 0), 3, Color(0, 0, 0, 0), 0, 6, 3)
		var over: StyleBoxFlat = S.flat(S.BTN_HOVER, 3, Color(0, 0, 0, 0), 0, 6, 3)
		for k in ["normal", "pressed", "disabled"]:
			c.add_stylebox_override(k, none)
		for k in ["hover", "hover_pressed"]:
			c.add_stylebox_override(k, over)
		c.add_stylebox_override("focus", StyleBoxEmpty.new())
		c.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	elif n is OptionButton or n is MenuButton:
		var d: Button = n
		d.focus_mode = FOCUS_NONE
		d.flat = false
		d.add_font_override("font", S.f_bold)
		for k in ["font_color", "font_color_hover", "font_color_pressed"]:
			d.add_color_override(k, S.TEXT)
		d.add_stylebox_override("normal", S.flat(S.BTN_BG, 3, Color(1, 1, 1, 0.05), 1, 12, 4))
		d.add_stylebox_override("hover", S.flat(S.BTN_HOVER, 3, Color(1, 1, 1, 0.05), 1, 12, 4))
		d.add_stylebox_override("pressed", S.flat(S.BTN_HOVER, 3, S.LILAC, 1, 12, 4))
		d.add_stylebox_override("focus", StyleBoxEmpty.new())
		d.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		d.rect_min_size = Vector2(d.rect_min_size.x, max(d.rect_min_size.y, 30))
	elif n is Button:
		var b: Button = n
		if not (b.text == "" and b.icon != null) and not b.toggle_mode:
			var keep: Vector2 = b.rect_min_size
			var theme_was = b.theme
			# (Save is the one that stands out, as it always did)
			S.button(b, b.name == "Save", true)
			b.theme = theme_was # (its popups and tooltips keep the game's theme)
			b.rect_min_size = Vector2(keep.x, max(keep.y, 30))
	elif n is SpinBox:
		_field(n.get_line_edit())
	elif n is LineEdit:
		if not (n.get_parent() is SpinBox):
			_field(n)
	elif n is Label:
		var l: Label = n
		var f: Font = l.get_font("font")
		var size: int = f.size if f is DynamicFont else 16
		if l.has_meta("nsu_keep"):
			pass # (asked to be left as it is)
		elif not _own_font(f):
			# text shown in a typeface of its own (the samples in Fonts, a
			# preview): that typeface is the point, it stays
			if not l.has_color_override("font_color") or l.has_meta("nsu_fc"):
				l.add_color_override("font_color", S.TEXT)
				l.set_meta("nsu_fc", true)
		elif size >= 21:
			l.add_font_override("font", S.f_head)
			if not l.has_color_override("font_color") or l.has_meta("nsu_fc"):
				l.add_color_override("font_color", S.PINK)
				l.set_meta("nsu_fc", true)
		else:
			l.add_font_override("font", S.f_small if size <= 14 else S.f_regular)
			if not l.has_color_override("font_color") or l.has_meta("nsu_fc"):
				l.add_color_override("font_color", S.TEXT)
				l.set_meta("nsu_fc", true)
		# (one long line made the whole page wider than the screen: it wraps)
		if not l.autowrap and l.get_combined_minimum_size().x > 560:
			l.autowrap = true
			l.size_flags_horizontal |= SIZE_EXPAND_FILL
			var up = l.get_parent()
			for _i in range(6):
				if not (up is Control) or up is GridContainer or up.name == "Group":
					break
				up.size_flags_horizontal |= SIZE_EXPAND_FILL
				up = up.get_parent()
	elif n is ScrollContainer:
		S.scroll(n)
	for c in n.get_children():
		_style_node(c)

# the game's own typeface (Lato), or no particular one: its text takes the
# page's fonts. Anything else was put there to be seen in that typeface.
static func _own_font(f: Font) -> bool:
	if not (f is DynamicFont) or f.font_data == null:
		return true
	return String(f.font_data.font_path).find("/Lato/") != -1

func _field(e: LineEdit):
	if e == null:
		return
	e.add_font_override("font", S.f_regular)
	e.add_color_override("font_color", S.FIELD_TEXT)
	e.add_color_override("font_color_uneditable", Color(S.FIELD_TEXT.r, S.FIELD_TEXT.g, S.FIELD_TEXT.b, 0.6))
	e.add_color_override("cursor_color", S.ACCENT if S.FIELD_BG.v < 0.5 else S.FIELD_TEXT)
	e.add_stylebox_override("normal", S.flat(S.FIELD_BG, 3, Color(1, 1, 1, 0.05), 1, 10, 4))
	e.add_stylebox_override("focus", S.flat(S.FIELD_BG, 3, S.LILAC, 1, 10, 4))
	e.add_stylebox_override("read_only", S.flat(S.FIELD_BG, 3, Color(0, 0, 0, 0), 0, 10, 4))

# Ctrl+F goes to the search box; Esc in it clears it
func _input(event):
	if not (event is InputEventKey) or not event.pressed or event.echo or not is_visible_in_tree():
		return
	if event.scancode == KEY_F and event.control and not event.alt:
		search.grab_focus()
		search.select_all()
		get_tree().set_input_as_handled()
	elif event.scancode == KEY_ESCAPE and search.has_focus():
		if search.text != "":
			search.text = ""
			_on_search("")
		search.release_focus()
		get_tree().set_input_as_handled()

# --- search ------------------------------------------------------------------------

# every setting with a name: [text, hover text, category number, the control]
func _build_index():
	_index = []
	for i in range(tc.get_tab_count()):
		var seen := {}
		_index_node(tc.get_tab_control(i), i, seen, true)
	_index_sig = _sig

func _index_node(n: Node, tab: int, seen: Dictionary, is_page: bool):
	if n is Control and not is_page and not n.visible:
		return # (hidden with what's in it: not for this device, or not unlocked)
	if n is Popup:
		return
	var text := ""
	if n is CheckBox or n is Label or (n is Button and not (n is OptionButton) and not (n is ColorPickerButton)):
		text = String(n.text).strip_edges()
	if text.length() >= 2 and text.length() <= 70 and not seen.has(text) and _has_letter(text):
		seen[text] = true
		var tip := String(n.hint_tooltip) if n is Control else ""
		# (a number box's hover text is often on the box, its name on the label beside it)
		if tip == "" and n is Label and n.get_parent() != null:
			for sib in n.get_parent().get_children():
				if sib is Control and sib != n and String(sib.hint_tooltip) != "":
					tip = String(sib.hint_tooltip)
					break
		_index.append([text, tip, tab, n])
	for c in n.get_children():
		_index_node(c, tab, seen, false)

static func _has_letter(s: String) -> bool:
	for i in range(s.length()):
		var c := s[i]
		if c.to_upper() != c.to_lower():
			return true
	return false

func _on_search(q: String):
	q = q.strip_edges().to_lower()
	var on := q != ""
	var was_on: bool = results_scroll.visible
	results_scroll.visible = on
	scroll.visible = not on
	# (the preview window floats over the pages: out of the way of the list)
	for c in settings.get_children():
		var sc = c.get_script()
		if sc != null and String(sc.resource_path).ends_with("SettingsPreview.gd"):
			c.modulate.a = 0.0 if on else 1.0
	if not on:
		return
	settings.move_child(results_scroll, settings.get_child_count() - 1)
	# (read again each time a search starts: some pages fill in after they open)
	if not was_on or _index.empty() or _index_sig != _sig:
		_build_index()
	for c in results.get_children():
		c.queue_free()
	var words := q.split(" ", false)
	var by_name := []
	var by_tip := []
	for it in _index:
		if not is_instance_valid(it[3]):
			continue
		var name_l: String = String(it[0]).to_lower()
		var all_l: String = name_l + " " + String(it[1]).to_lower() + " " + tc.get_tab_title(it[2]).to_lower()
		var in_name := true
		var in_all := true
		for w in words:
			if name_l.find(w) == -1:
				in_name = false
			if all_l.find(w) == -1:
				in_all = false
		if in_name:
			by_name.append(it)
		elif in_all:
			by_tip.append(it)
	var found: Array = by_name + by_tip
	if found.empty():
		results.add_child(S.label("No setting matches \"%s\"." % q, S.f_regular, S.DIM))
		return
	var head: Label = S.label("%d setting%s" % [found.size(), "" if found.size() == 1 else "s"], S.f_small, S.DIM)
	results.add_child(head)
	for i in range(min(found.size(), MAX_RESULTS)):
		results.add_child(_result_row(found[i]))
	if found.size() > MAX_RESULTS:
		results.add_child(S.label("...and %d more. Type more of its name." % (found.size() - MAX_RESULTS), S.f_small, S.DIM))
	results_scroll.scroll_vertical = 0

func _result_row(it: Array) -> Control:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_stylebox_override("normal", S.flat(S.CARD_BG, 4, Color(1, 1, 1, 0.04), 1, 14, 8))
	b.add_stylebox_override("hover", S.flat(S.CARD_HOVER, 4, Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.6), 1, 14, 8))
	b.add_stylebox_override("pressed", S.flat(S.CARD_HOVER, 4, S.LILAC, 1, 14, 8))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.connect("pressed", self, "_go", [it])
	var h := HBoxContainer.new()
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.margin_left = 14
	h.margin_right = -14
	h.add_constant_override("separation", 12)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(h)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 0)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.size_flags_vertical = SIZE_SHRINK_CENTER
	v.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(S.fit_label(String(it[0]), S.f_bold, S.TEXT))
	var tip := String(it[1]).replace("\n", " ").strip_edges()
	if tip != "":
		v.add_child(S.fit_label(tip, S.f_small, S.DIM))
	var where: Label = S.label(tc.get_tab_title(it[2]), S.f_small, S.PINK)
	where.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(where)
	b.rect_min_size = Vector2(0, 54 if tip != "" else 40)
	return b

# to a setting from the search: its category, scrolled to it, outlined for a moment
func _go(it: Array):
	var n = it[3]
	search.text = ""
	_on_search("")
	if not is_instance_valid(n):
		return
	tc.current_tab = it[2]
	_mark_cat()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if not is_instance_valid(n) or not n.is_visible_in_tree():
		return
	var y: float = n.rect_global_position.y - scroll.rect_global_position.y + scroll.scroll_vertical
	scroll.scroll_vertical = int(max(y - 90, 0))
	yield(get_tree(), "idle_frame")
	if not is_instance_valid(n):
		return
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()
	_flash = Panel.new()
	_flash.mouse_filter = MOUSE_FILTER_IGNORE
	_flash.add_stylebox_override("panel", S.flat(Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.14), 5, S.ACCENT, 2))
	_flash.set_as_toplevel(true)
	# (the whole row when it sits in one: its box and its name together)
	var row: Control = n
	var par = n.get_parent()
	if par is HBoxContainer and par.rect_size.y <= 64:
		row = par
	row.add_child(_flash)
	_flash.rect_global_position = row.rect_global_position - Vector2(6, 4)
	_flash.rect_size = row.rect_size + Vector2(12, 8)
	var tw := Tween.new()
	_flash.add_child(tw)
	tw.interpolate_property(_flash, "modulate:a", 1.0, 0.0, 0.7, Tween.TRANS_SINE, Tween.EASE_IN, 1.3)
	tw.connect("tween_all_completed", _flash, "queue_free")
	tw.start()
