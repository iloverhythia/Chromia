extends VBoxContainer

# Settings: the top buttons (Save, Presets, folders...) and the tab bar stay
# put; only the page under them scrolls. The buttons are moved out of the
# scrolling page into this header, and the TabContainer's own tab bar is
# hidden behind a copy here (same look, kept in step both ways). The pages
# stay where they were (Main/Settings/S/F/TabContainer/...), so everything
# that finds them by path still does.
#
# menu2.gd installs it after the settings tabs are all added.
#
# Side Tabs (Rhythia.settings_side_tabs): the tabs are a list of buttons down
# the left side instead (under the header, scrolling on its own when there
# are more than fit), and the page moves over to make room.
#
# As on the new page (SettingsNewUI.gd), with the same saved settings:
# right-click a tab to hide it (Rhythia.settings_hidden_tabs; the same menu
# shows hidden ones again), and Collapsible Groups (Rhythia.settings_collapsible)
# gives each group a title to click that folds it (Rhythia.settings_collapsed).

var _scroll: ScrollContainer
var _tc: TabContainer
var _tabs := Tabs.new()
var _sig := ""
var _syncing := false
const SIDE_W := 190.0
var _side_on := false
var _left0 := 0.0 # (the page's left edge before the side list moved it over)
var _side_scroll: ScrollContainer = null
var _side: VBoxContainer = null
var _side_group := ButtonGroup.new()
var _map := [] # header tab (or side button) -> page number; hidden pages left out
var _menu: PopupMenu = null
var _menu_tab := -1
var _folds_sig := ""

static func install(settings: Control):
	if settings == null or settings.has_node("Header"):
		return
	var s = settings.get_node_or_null("S")
	var f = s.get_node_or_null("F") if s != null else null
	var tc = f.get_node_or_null("TabContainer") if f != null else null
	if tc == null:
		return
	var h = load("res://scripts/ui/settings/SettingsHeader.gd").new()
	h.name = "Header"
	h._scroll = s
	h._tc = tc
	h.theme = f.theme
	h._side_on = bool(Rhythia.settings_side_tabs)
	# (the side list is made before the header joins the page: its _ready
	# fills the list right away, and filling a list that wasn't there yet
	# crashed the game, in exported builds a null call isn't just an error)
	if h._side_on:
		h._build_side(settings, f.theme)
	settings.add_child(h)
	var top = f.get_node_or_null("TopButtons")
	if top != null:
		f.remove_child(top)
		h.add_child(top)
		top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not h._side_on:
		h.add_child(h._tabs)

func _ready():
	anchor_left = 0
	anchor_right = 1
	anchor_top = 0
	anchor_bottom = 0
	margin_left = _left0 if _side_on else _scroll.margin_left
	margin_right = 0
	margin_top = 0
	add_constant_override("separation", 0)
	mouse_filter = MOUSE_FILTER_PASS
	_tabs.tab_align = Tabs.ALIGN_LEFT
	_tabs.focus_mode = FOCUS_NONE
	_tabs.connect("tab_changed", self, "_on_header_tab")
	_tabs.connect("gui_input", self, "_on_tabs_input")
	_tc.connect("tab_changed", self, "_on_page_tab")
	_tc.tabs_visible = false
	connect("resized", self, "_fit")
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.connect("timeout", self, "_check")
	add_child(t)
	_check()
	call_deferred("_fit")

# the list of tabs: left of the page, under the header
func _build_side(settings: Control, th):
	_left0 = _scroll.margin_left
	_side_scroll = ScrollContainer.new()
	_side_scroll.name = "SideTabs"
	_side_scroll.theme = th
	_side_scroll.scroll_horizontal_enabled = false
	_side_scroll.anchor_left = 0
	_side_scroll.anchor_right = 0
	_side_scroll.anchor_top = 0
	_side_scroll.anchor_bottom = 1
	_side_scroll.margin_left = _scroll.margin_left
	_side_scroll.margin_right = _scroll.margin_left + SIDE_W
	_side_scroll.margin_bottom = _scroll.margin_bottom
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = SIZE_EXPAND_FILL
	_side.add_constant_override("separation", 4)
	_side_scroll.add_child(_side)
	settings.add_child(_side_scroll)
	_scroll.margin_left += SIDE_W + 12 # (the page moves over)

func _fill_side(titles: Array):
	if _side == null:
		return
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	for j in range(_map.size()):
		var i: int = _map[j]
		var b := Button.new()
		b.text = String(titles[i])
		b.toggle_mode = true
		b.group = _side_group
		b.align = Button.ALIGN_LEFT
		b.clip_text = true
		b.focus_mode = FOCUS_NONE
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		_style_side_button(b)
		b.pressed = i == _tc.current_tab
		b.hint_tooltip = "%s (right-click to hide it)" % titles[i]
		b.connect("pressed", self, "_on_header_tab", [j])
		b.connect("gui_input", self, "_on_side_input", [i])
		_side.add_child(b)

# A side tab in the top tabs' own look (the settings page's theme, or Sound
# Space Mode's skin): the chosen one like the open tab, the others like the
# rest, same font and colors. The top tabs are rounded on top only: here all
# four corners are.
var _side_look := []
func _side_box(name: String) -> StyleBox:
	var sb: StyleBox = _tc.get_stylebox(name)
	if sb is StyleBoxFlat:
		var d: StyleBoxFlat = sb.duplicate()
		var r: int = int(max(d.corner_radius_top_left, d.corner_radius_top_right))
		d.corner_radius_top_left = r
		d.corner_radius_top_right = r
		d.corner_radius_bottom_left = r
		d.corner_radius_bottom_right = r
		return d
	return sb

func _style_side_button(b: Button):
	var fg := _side_box("tab_fg")
	var bg := _side_box("tab_bg")
	b.add_stylebox_override("normal", bg)
	b.add_stylebox_override("hover", bg)
	b.add_stylebox_override("pressed", fg)
	b.add_stylebox_override("hover_pressed", fg)
	b.add_stylebox_override("disabled", _side_box("tab_disabled"))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_font_override("font", _tc.get_font("font"))
	var cfg: Color = _tc.get_color("font_color_fg")
	var cbg: Color = _tc.get_color("font_color_bg")
	b.add_color_override("font_color", cbg)
	b.add_color_override("font_color_hover", cfg)
	b.add_color_override("font_color_pressed", cfg)
	b.add_color_override("font_color_hover_pressed", cfg)
	b.add_color_override("font_color_disabled", _tc.get_color("font_color_disabled"))

func _show_side_tab(i: int):
	var j: int = _map.find(i)
	if _side != null and j >= 0 and j < _side.get_child_count():
		_side.get_child(j).pressed = true

# the scrolling page starts under the header
func _fit():
	_scroll.margin_top = rect_size.y
	if _side_scroll != null:
		_side_scroll.margin_top = rect_size.y + 8

func _copy_look():
	# (only when it changed: each copy made the header lay itself out again,
	# twice a second)
	for k in ["tab_fg", "tab_bg", "tab_disabled"]:
		var sb = _tc.get_stylebox(k)
		if _tabs.get_stylebox(k) != sb:
			_tabs.add_stylebox_override(k, sb)
	var f = _tc.get_font("font")
	if _tabs.get_font("font") != f:
		_tabs.add_font_override("font", f)
	for k in ["font_color_fg", "font_color_bg", "font_color_disabled"]:
		_tabs.add_color_override(k, _tc.get_color(k))
	for k in ["increment", "increment_highlight", "decrement", "decrement_highlight"]:
		_tabs.add_icon_override(k, _tc.get_icon(k))
	_tabs.add_constant_override("hseparation", _tc.get_constant("hseparation"))
	# the side tabs follow the look too (when it changed)
	if _side != null:
		var look := [_tc.get_stylebox("tab_fg"), _tc.get_stylebox("tab_bg"), _tc.get_font("font"), _tc.get_color("font_color_fg"), _tc.get_color("font_color_bg")]
		if look != _side_look:
			_side_look = look
			_side.add_constant_override("separation", int(max(2, _tc.get_constant("hseparation"))))
			for b in _side.get_children():
				if b is Button:
					_style_side_button(b)

# tabs added, moved or renamed later: the header copies them again
func _check():
	var titles := []
	for i in range(_tc.get_tab_count()):
		titles.append(_tc.get_tab_title(i))
	var sig := PoolStringArray(titles).join("|") + "#" + PoolStringArray(Rhythia.settings_hidden_tabs).join("|")
	_copy_look() # (Sound Space Mode's skin restyles the tabs)
	if sig != _sig:
		_sig = sig
		_map = []
		for i in range(titles.size()):
			if not _is_hidden(i):
				_map.append(i)
		if _map.empty(): # (every one hidden: all of them, so the page isn't empty)
			for i in range(titles.size()):
				_map.append(i)
		# (the page showing was hidden: the first one in the list)
		if not _map.empty() and not _map.has(_tc.current_tab):
			_tc.current_tab = _map[0]
		_syncing = true
		if _side_on:
			_fill_side(titles)
		else:
			while _tabs.get_tab_count() > 0:
				_tabs.remove_tab(_tabs.get_tab_count() - 1)
			for i in _map:
				_tabs.add_tab(titles[i])
			_tabs.current_tab = max(0, _map.find(_tc.current_tab))
		_syncing = false
		call_deferred("_fit")
	_folds()
	if _tc.tabs_visible:
		_tc.tabs_visible = false

func _on_header_tab(i: int):
	if _syncing:
		return
	if i < 0 or i >= _map.size():
		return
	_syncing = true
	_tc.current_tab = _map[i]
	_scroll.scroll_vertical = 0 # a new page starts at its top
	_show_side_tab(_map[i])
	_syncing = false

func _on_page_tab(i: int):
	if _syncing:
		return
	_syncing = true
	var j: int = _map.find(i)
	if j >= 0 and j < _tabs.get_tab_count():
		_tabs.current_tab = j
	_show_side_tab(i)
	_syncing = false
	_folds()

# --- hiding tabs (right-click) -----------------------------------------------------

func _tab_key(i: int) -> String:
	var c = _tc.get_tab_control(i)
	return String(c.name) if c != null else ""

func _is_hidden(i: int) -> bool:
	return Rhythia.settings_hidden_tabs.has(_tab_key(i))

func _on_tabs_input(ev):
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_RIGHT):
		return
	for j in range(_tabs.get_tab_count()):
		if _tabs.get_tab_rect(j).has_point(ev.position) and j < _map.size():
			_tabs.accept_event()
			_open_menu(_map[j])
			return

func _on_side_input(ev, i: int):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_RIGHT:
		_open_menu(i)

# "Hide <this one>", and "Show <a hidden one>" for each hidden one. (In a layer
# of its own on top: a menu added under the settings page was drawn behind it.)
func _open_menu(i: int):
	if _menu == null or not is_instance_valid(_menu):
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_menu = PopupMenu.new()
		_menu.connect("id_pressed", self, "_on_menu")
		layer.add_child(_menu)
	_menu.clear()
	_menu_tab = i
	if _map.size() > 1 and not _is_hidden(i):
		_menu.add_item("Hide \"%s\"" % _tc.get_tab_title(i), 0)
	var shown_any := false
	for k in range(_tc.get_tab_count()):
		if _is_hidden(k):
			if not shown_any and _menu.get_item_count() > 0:
				_menu.add_separator()
			shown_any = true
			_menu.add_item("Show \"%s\" again" % _tc.get_tab_title(k), 100 + k)
	if _menu.get_item_count() == 0:
		_menu.add_item("Right-click a tab to hide it (at least one stays)", 99)
		_menu.set_item_disabled(0, true)
	_menu.rect_size = Vector2()
	_menu.popup(Rect2(get_viewport().get_mouse_position(), Vector2(1, 1)))

func _on_menu(id: int):
	var list: Array = Rhythia.settings_hidden_tabs.duplicate()
	if id == 0:
		var key := _tab_key(_menu_tab)
		if key != "" and not list.has(key):
			list.append(key)
	elif id >= 100:
		list.erase(_tab_key(id - 100))
	else:
		return
	Rhythia.settings_hidden_tabs = list
	Rhythia.save_settings()
	_check()

# --- Collapsible Groups ---------------------------------------------------------------
# The old page's groups (a VBoxContainer with a "Group" in it) have no title:
# with the setting on, each gets one to click, and a folded group's settings
# are hidden. Off: the titles go and every group is open.

func _folds():
	var on := bool(Rhythia.settings_collapsible)
	var sig := ("on" if on else "off") + "#" + PoolStringArray(Rhythia.settings_collapsed).join("|") + "#" + str(_tc.get_tab_count())
	if sig == _folds_sig:
		return
	_folds_sig = sig
	for k in range(_tc.get_tab_count()):
		var pg = _tc.get_tab_control(k)
		if pg == null:
			continue
		for g in pg.get_children():
			if not (g is VBoxContainer and g.has_node("Group")):
				continue
			var m = g.get_node("Group")
			var t = g.get_node_or_null("FoldTitle")
			if not on:
				if t != null:
					g.remove_child(t)
					t.queue_free()
				if m.has_meta("old_folded"):
					m.remove_meta("old_folded")
					m.visible = true
				continue
			if t == null:
				t = Button.new()
				t.name = "FoldTitle"
				t.flat = true
				t.align = Button.ALIGN_LEFT
				t.focus_mode = FOCUS_NONE
				t.mouse_default_cursor_shape = CURSOR_POINTING_HAND
				t.hint_tooltip = "Click to fold this group shut, or open it again"
				t.connect("pressed", self, "_on_fold", [g])
				g.add_child(t)
				g.move_child(t, 0)
			var key := "%s/%s" % [String(pg.name), String(g.name)]
			var shut: bool = Rhythia.settings_collapsed.has(key)
			var title: String = load("res://scripts/ui/settings/SettingsNewUI.gd")._pretty(String(g.name))
			t.text = ("+   " if shut else "-   ") + tr(title)
			if shut and m.visible:
				m.visible = false
				m.set_meta("old_folded", true)
			elif not shut and m.has_meta("old_folded"):
				m.remove_meta("old_folded")
				m.visible = true

func _on_fold(g: Control):
	var pg = g.get_parent()
	var key := "%s/%s" % [String(pg.name) if pg != null else "", String(g.name)]
	var list: Array = Rhythia.settings_collapsed.duplicate()
	if list.has(key):
		list.erase(key)
	else:
		list.append(key)
	Rhythia.settings_collapsed = list
	Rhythia.save_settings()
	_folds()
