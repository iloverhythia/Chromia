extends VBoxContainer

# Settings: the top buttons (Save, Presets, folders...) and the tab bar stay
# put; only the page under them scrolls. The buttons are moved out of the
# scrolling page into this header, and the TabContainer's own tab bar is
# hidden behind a copy here (same look, kept in step both ways). The pages
# stay where they were (Main/Settings/S/F/TabContainer/...), so everything
# that finds them by path still does.
#
# menu2.gd installs it after the settings tabs are all added.

var _scroll: ScrollContainer
var _tc: TabContainer
var _tabs := Tabs.new()
var _sig := ""
var _syncing := false

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
	settings.add_child(h)
	var top = f.get_node_or_null("TopButtons")
	if top != null:
		f.remove_child(top)
		h.add_child(top)
		top.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(h._tabs)

func _ready():
	anchor_left = 0
	anchor_right = 1
	anchor_top = 0
	anchor_bottom = 0
	margin_left = _scroll.margin_left
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

# the scrolling page starts under the header
func _fit():
	_scroll.margin_top = rect_size.y

func _copy_look():
	for k in ["tab_fg", "tab_bg", "tab_disabled"]:
		_tabs.add_stylebox_override(k, _tc.get_stylebox(k))
	_tabs.add_font_override("font", _tc.get_font("font"))
	for k in ["font_color_fg", "font_color_bg", "font_color_disabled"]:
		_tabs.add_color_override(k, _tc.get_color(k))
	for k in ["increment", "increment_highlight", "decrement", "decrement_highlight"]:
		_tabs.add_icon_override(k, _tc.get_icon(k))
	_tabs.add_constant_override("hseparation", _tc.get_constant("hseparation"))

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
	_syncing = false

func _on_page_tab(i: int):
	if _syncing:
		return
	_syncing = true
	if i < _tabs.get_tab_count():
		_tabs.current_tab = i
	_syncing = false
