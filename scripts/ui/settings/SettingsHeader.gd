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
	for i in range(titles.size()):
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
		b.connect("pressed", self, "_on_header_tab", [i])
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
	if _side != null and i >= 0 and i < _side.get_child_count():
		_side.get_child(i).pressed = true

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
	var sig := PoolStringArray(titles).join("|")
	_copy_look() # (Sound Space Mode's skin restyles the tabs)
	if sig != _sig:
		_sig = sig
		_syncing = true
		if _side_on:
			_fill_side(titles)
		else:
			while _tabs.get_tab_count() > 0:
				_tabs.remove_tab(_tabs.get_tab_count() - 1)
			for t in titles:
				_tabs.add_tab(t)
			_tabs.current_tab = _tc.current_tab
		_syncing = false
		call_deferred("_fit")
	if _tc.tabs_visible:
		_tc.tabs_visible = false

func _on_header_tab(i: int):
	if _syncing:
		return
	_syncing = true
	_tc.current_tab = i
	_scroll.scroll_vertical = 0 # a new page starts at its top
	_show_side_tab(i)
	_syncing = false

func _on_page_tab(i: int):
	if _syncing:
		return
	_syncing = true
	if i < _tabs.get_tab_count():
		_tabs.current_tab = i
	_show_side_tab(i)
	_syncing = false
