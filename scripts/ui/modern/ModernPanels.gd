extends Control

# The Modern UI's slide-in panel on the left (ModernUI.gd): Settings (the
# categories, each opening that part of the real settings inside the panel)
# and Sort & Filter (the map list's sorts, order, show / hide and ranges).
# The settings themselves are the classic Settings page, shown in the panel:
# ModernUI sits under the classic menu's page area, so the page draws on top
# and works exactly as before.

const MIcon = preload("res://scripts/ui/modern/MIcon.gd")

var ui # ModernUI
var panel: Control
var body: Control
var head_title: Label
var head_sub: Label
var back_btn: Button
var showing := ""
var _classic_rect := Rect2()
var _classic_on := false
var _scroll_top := 0.0
var _tween: Tween

const GENERAL := [["System", "monitor", "Gameplay"], ["Online", "globe", "Online"], ["Interface", "layout", "UI"],
	["Keybinds", "keyboard", "Keybinds"], ["Cursor", "mouse", "World & Cursor"], ["Audio", "volume", "Video & Audio"],
	["Backgrounds", "image", "Background Editor"], ["Favorites", "heart", "Replays & Misc"], ["Streamer", "radio", "Transfer"]]
const SKINNING := [["Notes", "square", "Notes"], ["Hit Effects", "sparkles", "Meshes"], ["Borders", "square", "Background Editor"],
	["Color Sets", "palette", "Colorsets"], ["Fonts", "list", "Fonts"], ["Skins", "folder", "Skins"]]
const MORE := [["Settings Generator", "sparkles", "Generator"], ["VR", "eye", "VR"]]

func _init(owner_ui):
	ui = owner_ui
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false

func _ready():
	# (a click outside the panel closes it)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.35)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.mouse_filter = MOUSE_FILTER_STOP
	dim.connect("gui_input", self, "_on_dim")
	add_child(dim)
	panel = Control.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.connect("draw", self, "_draw_panel")
	add_child(panel)
	var x = ui._button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), 6)
	x.name = "Close"
	x.add_child(MIcon.make("x", 16 * ui.k, ui.TEXT, 2.0))
	x.connect("pressed", self, "close")
	panel.add_child(x)
	back_btn = ui._button(Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), 6)
	back_btn.add_child(MIcon.make("chevron_left", 16 * ui.k, ui.TEXT, 2.0))
	back_btn.connect("pressed", self, "_back")
	panel.add_child(back_btn)
	head_title = ui._label("", ui._font("ExtraBold", 15))
	panel.add_child(head_title)
	head_sub = ui._label("", ui._font("SemiBold", 10), ui.DIM)
	panel.add_child(head_sub)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.scroll_horizontal_enabled = false
	panel.add_child(sc)
	body = VBoxContainer.new()
	body.add_constant_override("separation", int(8 * ui.k))
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	sc.add_child(body)
	_tween = Tween.new()
	add_child(_tween)

func _pw() -> float:
	return clamp(ui.rect_size.x * 0.36, 380 * ui.k, 520 * ui.k)

func layout():
	var k: float = ui.k
	var w := _pw()
	panel.rect_size = Vector2(w, ui.rect_size.y)
	if not _tween.is_active():
		panel.rect_position = Vector2(0, 0) if visible else Vector2(-w, 0)
	var x = panel.get_node("Close")
	x.rect_position = Vector2(w - 40 * k, 12 * k)
	x.rect_size = Vector2(28, 28) * k
	x.get_child(0).rect_position = Vector2(6, 6) * k
	x.get_child(0).rect_size = Vector2(16, 16) * k
	back_btn.rect_position = Vector2(w - 72 * k, 12 * k)
	back_btn.rect_size = Vector2(28, 28) * k
	back_btn.get_child(0).rect_position = Vector2(6, 6) * k
	back_btn.get_child(0).rect_size = Vector2(16, 16) * k
	head_title.rect_position = Vector2(16 * k, 10 * k)
	head_sub.rect_position = Vector2(16 * k, 30 * k)
	var sc = panel.get_node("Scroll")
	sc.rect_position = Vector2(16 * k, 56 * k)
	sc.rect_size = Vector2(w - 32 * k, ui.rect_size.y - 66 * k)
	body.rect_min_size = Vector2(w - 40 * k, 0)
	if _classic_on:
		_place_classic()

func _draw_panel():
	var s := panel.rect_size
	panel.draw_rect(Rect2(Vector2(), s), Color("#100f14"))
	panel.draw_rect(Rect2(s.x - 1, 0, 1, s.y), Color(1, 1, 1, 0.08))
	panel.draw_rect(Rect2(0, 48 * ui.k, s.x, 1), Color(1, 1, 1, 0.06))

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _slide_in():
	var w := _pw()
	visible = true
	layout()
	_tween.stop_all()
	_tween.interpolate_property(panel, "rect_position:x", -w, 0.0, 0.22, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween.start()

func close():
	_hide_classic()
	var w := _pw()
	_tween.stop_all()
	_tween.interpolate_property(panel, "rect_position:x", panel.rect_position.x, -w, 0.18, Tween.TRANS_CUBIC, Tween.EASE_IN)
	_tween.start()
	yield(_tween, "tween_all_completed")
	if panel.rect_position.x <= -w + 1:
		visible = false
		showing = ""
		ui._reload_maps()

func _back():
	if showing.begins_with("settings:"):
		open_settings(false)

func _clear():
	for c in body.get_children():
		c.queue_free()

func _section(t: String):
	var l = ui._label(t, ui._font("ExtraBold", 13))
	body.add_child(l)

# ------------------------------------------------------------------ Settings

func open_settings(slide := true):
	_hide_classic()
	showing = "settings"
	head_title.text = "Settings"
	head_sub.text = "Game Settings and Customizations"
	back_btn.visible = false
	_clear()
	var k: float = ui.k
	# profiles, and the quick buttons
	var row := HBoxContainer.new()
	row.add_constant_override("separation", int(6 * k))
	body.add_child(row)
	for b in [["Export settings", "Skins"], ["Import settings", "Transfer"], ["Profiles", "Gameplay"]]:
		var btn = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
		btn.text = b[0]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.rect_min_size = Vector2(0, 26 * k)
		btn.add_font_override("font", ui._font("Bold", 10))
		btn.add_color_override("font_color", Color("#d3d2d9"))
		btn.connect("pressed", self, "_open_tab", [b[0], b[1]])
		row.add_child(btn)
	var search := LineEdit.new()
	search.placeholder_text = "Search settings"
	search.add_font_override("font", ui._font("SemiBold", 11))
	var ssb = ui._flat(Color(1, 1, 1, 0.05), 5)
	ssb.content_margin_left = 9 * k
	search.add_stylebox_override("normal", ssb)
	search.add_stylebox_override("focus", ui._flat(Color(1, 1, 1, 0.08), 5))
	search.rect_min_size = Vector2(0, 28 * k)
	search.connect("text_changed", self, "_filter_tiles")
	body.add_child(search)
	_tiles("General", GENERAL)
	_tiles("Skinning", SKINNING)
	_tiles("More", MORE)
	if slide:
		_slide_in()
	else:
		layout()

func _tiles(title: String, items: Array):
	var k: float = ui.k
	var tc = Rhythia.menu_node("Main/Settings/S/F/TabContainer")
	_section(title)
	var g := GridContainer.new()
	g.columns = 2
	g.add_constant_override("hseparation", int(8 * k))
	g.add_constant_override("vseparation", int(8 * k))
	g.name = "Tiles_" + title
	body.add_child(g)
	for it in items:
		if tc != null and not tc.has_node(it[2]):
			continue
		var b = ui._button(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 6)
		b.name = it[0]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.rect_min_size = Vector2(0, 38 * k)
		b.connect("pressed", self, "_open_tab", [it[0], it[2]])
		var ic = MIcon.make(it[1], 17 * k, Color("#8fa6ff"), 1.8)
		ic.rect_position = Vector2(10, 10.5) * k
		ic.rect_size = Vector2(17, 17) * k
		b.add_child(ic)
		var l = ui._label(it[0], ui._font("Bold", 12), Color("#e5e4ea"))
		l.rect_position = Vector2(36 * k, 10 * k)
		b.add_child(l)
		var ch = MIcon.make("chevron_right", 12 * k, Color("#77767f"), 2.0)
		ch.anchor_left = 1
		ch.anchor_right = 1
		ch.margin_left = -24 * k
		ch.margin_right = -12 * k
		ch.margin_top = 13 * k
		ch.margin_bottom = 25 * k
		b.add_child(ch)
		g.add_child(b)

func _filter_tiles(t: String):
	t = t.to_lower().strip_edges()
	for g in body.get_children():
		if g is GridContainer:
			for b in g.get_children():
				b.visible = t == "" or String(b.name).to_lower().find(t) != -1

# one part of the real Settings page, in the panel
func _open_tab(title: String, tab: String):
	if title == "Profiles":
		var pr = Rhythia.menu_node("Main/Settings/Header/TopButtons/TopButtonsHBox/Presets")
		if pr == null:
			pr = Rhythia.menu_node("Main/Settings/S/F/TopButtons/TopButtonsHBox/Presets")
		if pr is MenuButton:
			pr.emit_signal("about_to_show")
			pr.get_popup().popup(Rect2(get_global_mouse_position(), Vector2(1, 1)))
			return
	var tc = Rhythia.menu_node("Main/Settings/S/F/TabContainer")
	if tc == null or not tc.has_node(tab):
		return
	showing = "settings:" + tab
	head_title.text = "Settings  >  " + title
	head_sub.text = ""
	back_btn.visible = true
	_clear()
	tc.current_tab = tc.get_node(tab).get_index()
	tc.tabs_visible = false
	_show_classic()
	layout()

func _show_classic():
	var main = Rhythia.menu_node("Main")
	var sb = Rhythia.menu_node("Sidebar")
	var page = Rhythia.menu_node("Main/Settings")
	if main == null or page == null:
		return
	if not _classic_on:
		_classic_rect = Rect2(main.rect_position, main.rect_size)
	_classic_on = true
	if sb != null and sb.has_method("press_page"):
		sb.press_page(page)
	ui._classic(false) # (press_page shows the version labels again)
	main.visible = true
	# the page's own header (buttons and tab bar) is the panel's here
	var h = page.get_node_or_null("Header")
	var sc = page.get_node_or_null("S")
	if h != null and h.visible:
		h.visible = false
		if sc != null:
			_scroll_top = sc.margin_top
			sc.margin_top = 0
	_place_classic()

# (the classic page's header comes back on its own timer: kept away while in the panel)
func _process(_d):
	if not _classic_on:
		return
	var page = Rhythia.menu_node("Main/Settings")
	if page == null:
		return
	var h = page.get_node_or_null("Header")
	var sc = page.get_node_or_null("S")
	if h != null and h.visible:
		h.visible = false
	if sc != null and sc.margin_top != 0:
		sc.margin_top = 0

func _place_classic():
	var main = Rhythia.menu_node("Main")
	if main == null:
		return
	var k: float = ui.k
	main.anchor_right = 0
	main.anchor_bottom = 0
	main.rect_position = Vector2(8 * k, 52 * k)
	main.rect_size = Vector2(_pw() - 14 * k, ui.rect_size.y - 58 * k)

func _hide_classic():
	if not _classic_on:
		return
	_classic_on = false
	var main = Rhythia.menu_node("Main")
	var tc = Rhythia.menu_node("Main/Settings/S/F/TabContainer")
	if tc != null:
		tc.tabs_visible = true
	var page = Rhythia.menu_node("Main/Settings")
	if page != null:
		var h = page.get_node_or_null("Header")
		var sc = page.get_node_or_null("S")
		if h != null and not h.visible:
			h.visible = true
			if sc != null:
				sc.margin_top = _scroll_top
	Rhythia.save_settings()
	if main != null:
		main.anchor_right = 1
		main.anchor_bottom = 1
		main.margin_left = 0
		main.margin_top = 0
		main.margin_right = 0
		main.margin_bottom = 0
		main.visible = false
	var sb = Rhythia.menu_node("Sidebar")
	if sb != null and sb.has_method("press"):
		sb.press(0, true)
	ui._classic(false)

# ------------------------------------------------------------------ Sort & Filter

const SORTS := [["", "Difficulty"], ["stars", "Stars"], ["plays", "Most played"], ["length_short", "Shortest"], ["length_long", "Longest"],
	["sp_high", "Highest SP"], ["sp_low", "Lowest SP"], ["played", "Played"], ["unplayed", "Unplayed"],
	["recent_ranked", "Recently ranked"], ["recent_played", "Recently played"], ["notes_high", "Most notes"], ["notes_low", "Fewest notes"]]

func open_filters():
	_hide_classic()
	showing = "filters"
	head_title.text = "Sort & Filter"
	head_sub.text = "Adjust how maps are sorted and grouped"
	back_btn.visible = false
	_clear()
	_build_filters()
	_slide_in()

func _list():
	return ui.list

func _build_filters():
	var k: float = ui.k
	var L = _list()
	var reset = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
	reset.text = "Reset filters"
	reset.rect_min_size = Vector2(0, 28 * k)
	reset.add_font_override("font", ui._font("Bold", 11))
	reset.add_color_override("font_color", Color("#d3d2d9"))
	reset.connect("pressed", self, "_reset_filters")
	body.add_child(reset)
	# sort by
	_caption("Sort by")
	var ob := OptionButton.new()
	ob.add_font_override("font", ui._font("Bold", 11))
	ob.add_color_override("font_color", Color("#e5e4ea"))
	ob.add_color_override("font_color_hover", Color("#ffffff"))
	ob.add_stylebox_override("normal", ui._flat(Color(1, 1, 1, 0.05), 5))
	ob.add_stylebox_override("hover", ui._flat(Color(1, 1, 1, 0.08), 5))
	ob.add_stylebox_override("pressed", ui._flat(Color(1, 1, 1, 0.08), 5))
	ob.add_stylebox_override("focus", StyleBoxEmpty.new())
	ob.rect_min_size = Vector2(0, 28 * k)
	var cur := _sort_key()
	for i in SORTS.size():
		ob.add_item(SORTS[i][1], i)
		if SORTS[i][0] == cur:
			ob.select(i)
	ob.connect("item_selected", self, "_on_sort")
	body.add_child(ob)
	_toggle("Sort order", "Descending", Rhythia.last_search_flip_sort, "_on_order")
	_toggle("Ranked", "Show", not bool(L.mf.hide_ranked) if L else true, "_on_mf_bool", ["hide_ranked"])
	_toggle("Unranked", "Show", not bool(L.mf.hide_unranked) if L else true, "_on_mf_bool", ["hide_unranked"])
	_toggle("Online maps", "Show", bool(L.show_online_maps) if L else true, "_on_online")
	_toggle("Broken maps", "Show", bool(L.show_broken_maps) if L else false, "_on_broken")
	_toggle("Played maps", "Only played", L != null and int(L.mf.played) == 1, "_on_played")
	_range("Min stars", "min_stars", 0, 15, 0.1)
	_range("Max stars", "max_stars", 0, 15, 0.1)
	_range("Min length", "min_len", 0, 1200, 5)
	_range("Max length", "max_len", 0, 1200, 5)

func _caption(t: String):
	body.add_child(ui._label(t, ui._font("Bold", 11), Color("#c9c8cf")))

func _toggle(title: String, txt: String, on: bool, method: String, binds := []):
	var k: float = ui.k
	_caption(title)
	var cb := CheckButton.new()
	cb.text = txt
	cb.pressed = on
	cb.focus_mode = FOCUS_NONE
	cb.add_font_override("font", ui._font("SemiBold", 10))
	cb.add_color_override("font_color", ui.DIM)
	cb.add_color_override("font_color_pressed", ui.TEXT)
	cb.add_color_override("font_color_hover", ui.TEXT)
	cb.add_color_override("font_color_hover_pressed", ui.TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_stylebox_override(st, ui._flat(Color(1, 1, 1, 0.035 if st != "hover" and st != "hover_pressed" else 0.06), 5))
	cb.connect("toggled", self, method, binds)
	body.add_child(cb)

func _range(title: String, key: String, lo: float, hi: float, step: float):
	var k: float = ui.k
	var L = _list()
	var h := HBoxContainer.new()
	h.add_constant_override("separation", int(8 * k))
	var l = ui._label(title, ui._font("Bold", 11), Color("#c9c8cf"))
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(l)
	var val = ui._label("", ui._font("Bold", 10), ui.DIM)
	h.add_child(val)
	body.add_child(h)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = FOCUS_NONE
	s.add_stylebox_override("slider", ui._bar_style(Color(1, 1, 1, 0.12)))
	s.add_stylebox_override("grabber_area", ui._bar_style(Color(1, 1, 1, 0.85)))
	s.add_stylebox_override("grabber_area_highlight", ui._bar_style(Color(1, 1, 1, 0.95)))
	s.add_icon_override("grabber", ui._dot_tex(int(12 * k)))
	s.add_icon_override("grabber_highlight", ui._dot_tex(int(13 * k)))
	s.value = float(L.mf[key]) if L != null else 0.0
	s.connect("value_changed", self, "_on_range", [key, val])
	body.add_child(s)
	_on_range(s.value, key, val, false)

func _sort_key() -> String:
	if String(Rhythia.map_sort) != "":
		return String(Rhythia.map_sort)
	if Rhythia.sort_by_stars:
		return "stars"
	if Rhythia.sort_by_plays:
		return "plays"
	return ""

func _on_sort(i: int):
	var p = Rhythia.menu_node("Main/Maps/Filters/MapFiltersPage")
	if p != null and p.has_method("_on_sort"):
		p._on_sort(SORTS[i][0])
	ui._reload_maps()

func _on_order(on: bool):
	var L = _list()
	Rhythia.last_search_flip_sort = on
	if L != null:
		L.update_search_flipped(on)
	ui._reload_maps()

func _on_mf_bool(on: bool, key: String):
	var L = _list()
	if L != null:
		L.mf[key] = not on
		ui._reload_maps()

func _on_online(on: bool):
	var L = _list()
	Rhythia.last_search_incl_online = on
	if L != null:
		L.update_search_showonline(on)
		L.show_online_maps = on
	ui._reload_maps()

func _on_broken(on: bool):
	var L = _list()
	Rhythia.last_search_incl_broken = on
	if L != null:
		L.update_search_showbroken(on)
	ui._reload_maps()

func _on_played(on: bool):
	var L = _list()
	if L != null:
		L.mf.played = 1 if on else 0
		ui._reload_maps()

func _on_range(v: float, key: String, val: Label, apply := true):
	var L = _list()
	if key.ends_with("len"):
		val.text = "%02d:%02d" % [int(v) / 60, int(v) % 60] if v > 0 else "Any"
	else:
		val.text = ("%.1f" % v) if v > 0 else "Any"
	if apply and L != null:
		L.mf[key] = v
		ui._reload_maps()

func _reset_filters():
	var L = _list()
	if L != null:
		L.mf = {"min_stars": 0.0, "max_stars": 0.0, "min_len": 0, "max_len": 0, "hide_ranked": false, "hide_unranked": false, "played": 0}
		if L.has_method("reset_filters"):
			L.reset_filters()
	var p = Rhythia.menu_node("Main/Maps/Filters/MapFiltersPage")
	if p != null and p.has_method("_on_sort"):
		p._on_sort("")
	ui._reload_maps()
	open_filters()
