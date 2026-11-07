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
var head_pre: Label # ("Settings  >" before a part's name)
var back_btn: Button
var showing := ""
var _classic_rect := Rect2()
var _classic_on := false
var _scroll_top := 0.0
var _tween: Tween
var _preview # SettingsPreview.gd (modern): beside the panel while Settings is open

const GENERAL := [["System", "gear", "Gameplay"], ["Online", "user", "Online"], ["Interface", "interface", "UI"],
	["Keybinds", "key_f", "Keybinds"], ["Cursor", "mouse", "World & Cursor"], ["Audio", "volume", "Video & Audio"],
	["Backgrounds", "image", "Background Editor"], ["Favorites", "heart", "Replays & Misc"], ["Streamer", "clapper", "Transfer"]]
const SKINNING := [["Notes", "note", "Notes"], ["Hit Effects", "sparkles", "Meshes"], ["Borders", "square_dashed", "Background Editor"],
	["Color Sets", "palette", "Colorsets"], ["Fonts", "type", "Fonts"], ["Skins", "paint", "Skins"]]
const MORE := [["Settings Generator", "wand", "Generator"], ["VR", "vr", "VR"]]
const CARD_BG := Color("#111111")
const CARD_EDGE := Color(1, 1, 1, 0.09)
const TILE_BG := Color("#171717")
const ICON_BG := Color("#191a36")
const ICON_COL := Color("#8584b8")

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
	head_pre = ui._label("", ui._font("ExtraBold", 15), Color("#9d9ca5"))
	panel.add_child(head_pre)
	head_title = ui._label("", ui._font("ExtraBold", 15))
	panel.add_child(head_title)
	head_sub = ui._label("", ui._font("Bold", 12), Color("#b4b3bb"))
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
	if not Rhythia.vr:
		_preview = load("res://scripts/ui/settings/SettingsPreview.gd").new()
		_preview.modern = true
		_preview.k = ui.k
		add_child(_preview)

func _pw() -> float:
	# (the classic Workshop and Multiplayer pages need more room than settings)
	if showing.begins_with("page:"):
		return clamp(ui.rect_size.x * 0.66, 380 * ui.k, ui.rect_size.x - 40 * ui.k)
	return clamp(ui.rect_size.x * 0.36, 380 * ui.k, 520 * ui.k)

# the panel: a header card and a body card, floating over the menu (like the video)
const M := 15.0 # (margin, x k)
const HEAD_Y := 20.0
const HEAD_H := 56.0
const BODY_Y := 85.0

func _body_rect() -> Rect2:
	var k: float = ui.k
	return Rect2(M * k, BODY_Y * k, _pw() - M * k, ui.rect_size.y - BODY_Y * k - 21 * k)

func layout():
	var k: float = ui.k
	var w := _pw()
	panel.rect_size = Vector2(w + 4 * k, ui.rect_size.y)
	if not _tween.is_active():
		panel.rect_position = Vector2(0, 0) if visible else Vector2(-w - 4 * k, 0)
	var hr := Rect2(M * k, HEAD_Y * k, w - M * k, HEAD_H * k)
	var x = panel.get_node("Close")
	x.rect_size = Vector2(30, 30) * k
	x.rect_position = Vector2(hr.end.x - 40 * k, hr.position.y + 13 * k)
	x.get_child(0).rect_position = Vector2(5, 5) * k
	x.get_child(0).rect_size = Vector2(20, 20) * k
	back_btn.rect_size = Vector2(30, 30) * k
	back_btn.rect_position = Vector2(hr.end.x - 72 * k, hr.position.y + 13 * k)
	back_btn.get_child(0).rect_position = Vector2(6, 6) * k
	back_btn.get_child(0).rect_size = Vector2(18, 18) * k
	var tx := hr.position.x + 13 * k
	head_pre.rect_position = Vector2(tx, hr.position.y + 7 * k)
	head_pre.visible = head_pre.text != ""
	if head_pre.visible:
		tx += head_pre.get_font("font").get_string_size(head_pre.text).x
	head_title.rect_position = Vector2(tx, hr.position.y + 7 * k)
	head_sub.rect_position = Vector2(hr.position.x + 13 * k, hr.position.y + 29 * k)
	var br := _body_rect()
	var sc = panel.get_node("Scroll")
	sc.rect_position = br.position + Vector2(12 * k, 12 * k)
	sc.rect_size = br.size - Vector2(18 * k, 22 * k)
	body.rect_min_size = Vector2(br.size.x - 30 * k, 0)
	if _classic_on:
		_place_classic()
	if _preview != null:
		_place_preview()

func _place_preview():
	var k: float = ui.k
	var x := _pw() + 27 * k
	var w: float = ui.rect_size.x - x - 27 * k
	var h: float = min(ui.rect_size.y * 0.585, w * 0.62)
	_preview.rect_position = Vector2(x, max(85 * k, ui.rect_size.y * 0.47 - h / 2))
	_preview.rect_size = Vector2(w, h)

func _draw_panel():
	var k: float = ui.k
	var w := _pw()
	var sb = ui._flat(CARD_BG, 8 * k, CARD_EDGE, 1)
	panel.draw_style_box(sb, Rect2(M * k, HEAD_Y * k, w - M * k, HEAD_H * k))
	panel.draw_style_box(sb, _body_rect())

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
	elif showing.begins_with("profile:"):
		open_profile(false)

func _clear():
	head_pre.text = ""
	for c in body.get_children():
		c.queue_free()

const SUBS := {"System": "Core gameplay settings", "Online": "Your account, chat and spectators", "Interface": "Arrange your HUD and menus",
	"Keybinds": "Keyboard shortcuts and controls", "Cursor": "Cursor behavior and feel", "Audio": "Timing, devices and volume",
	"Backgrounds": "Backgrounds, panels and borders", "Favorites": "Replays and everything else", "Streamer": "Move your settings with a code",
	"Notes": "Choose a note skin", "Hit Effects": "Choose a hit effect", "Borders": "Choose a border skin", "Color Sets": "Choose a color set",
	"Fonts": "The game's fonts", "Skins": "Whole skins", "Settings Generator": "Make settings from a few questions", "VR": "Virtual reality",
	"Export settings": "Save your settings", "Import settings": "Settings from a code"}

# a heading with a line under it
func _section(t: String):
	var k: float = ui.k
	var l = ui._label(t, ui._font("ExtraBold", 14), Color("#e9e8ee"))
	l.rect_min_size = Vector2(0, 30 * k)
	l.valign = Label.VALIGN_CENTER
	l.connect("draw", self, "_draw_rule", [l])
	body.add_child(l)

func _draw_rule(l: Label):
	l.draw_rect(Rect2(0, l.rect_size.y - 1, l.rect_size.x, 1), Color(1, 1, 1, 0.14))

# ------------------------------------------------------------------ Settings

func open_settings(slide := true):
	_hide_classic()
	showing = "settings"
	head_title.text = "Settings"
	head_sub.text = "Game Settings and Customizations"
	back_btn.visible = false
	_clear()
	var k: float = ui.k
	# the settings profile: its name (click for the list), rename, new, delete
	var prow := HBoxContainer.new()
	prow.add_constant_override("separation", int(5 * k))
	body.add_child(prow)
	var pf = ui._button(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.08), 5)
	pf.text = _profile_name()
	pf.align = Button.ALIGN_LEFT
	pf.clip_text = true
	pf.size_flags_horizontal = SIZE_EXPAND_FILL
	pf.rect_min_size = Vector2(0, 24 * k)
	pf.add_font_override("font", ui._font("Bold", 10))
	pf.add_color_override("font_color", ui.TEXT)
	pf.hint_tooltip = "Your settings profiles"
	var psb = pf.get_stylebox("normal")
	if psb is StyleBoxFlat:
		psb.content_margin_left = 8 * k
		pf.get_stylebox("hover").content_margin_left = 8 * k
	pf.connect("pressed", self, "_profile_menu")
	prow.add_child(pf)
	for ib in [["pencil", "Save your settings into this profile", "_profile_save"], ["plus", "New profile from your settings", "_profile_new"], ["minus", "Delete this profile", "_profile_delete"]]:
		var bb = ui._button(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.09), 5)
		bb.rect_min_size = Vector2(24, 24) * k
		bb.hint_tooltip = ib[1]
		var ic = MIcon.make(ib[0], 12 * k, Color("#d9d8de"), 2.0)
		ic.rect_position = Vector2(6, 6) * k
		ic.rect_size = Vector2(12, 12) * k
		bb.add_child(ic)
		bb.connect("pressed", self, ib[2])
		prow.add_child(bb)
	# the quick buttons
	var row := HBoxContainer.new()
	row.add_constant_override("separation", int(5 * k))
	body.add_child(row)
	for b in [["Export settings", "_export"], ["Import settings", "_import_code"], ["Settings code", "_import_code"]]:
		row.add_child(_small_btn(b[0], b[1]))
	var imp = _small_btn("Import files", "_import_files")
	imp.hint_tooltip = "Profiles, color sets and meshes from files"
	body.add_child(imp)
	var search := LineEdit.new()
	search.placeholder_text = "Search settings"
	search.add_font_override("font", ui._font("Bold", 11))
	search.add_color_override("font_color_placeholder", Color("#8d8c95"))
	var ssb = ui._flat(Color(1, 1, 1, 0.045), 5)
	ssb.content_margin_left = 9 * k
	search.add_stylebox_override("normal", ssb)
	var fsb = ui._flat(Color(1, 1, 1, 0.07), 5)
	fsb.content_margin_left = 9 * k
	search.add_stylebox_override("focus", fsb)
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
		var b = ui._button(TILE_BG, Color("#1e1e1e"), 6)
		for st in ["normal", "hover", "pressed"]:
			var sb = b.get_stylebox(st)
			if sb is StyleBoxFlat:
				sb.border_color = Color(1, 1, 1, 0.06 if st == "normal" else 0.12)
				sb.set_border_width_all(1)
		b.name = it[0]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.rect_min_size = Vector2(0, 52 * k)
		b.connect("pressed", self, "_open_tab", [it[0], it[2]])
		var sq := Control.new()
		sq.mouse_filter = MOUSE_FILTER_IGNORE
		sq.rect_position = Vector2(11, 11) * k
		sq.rect_size = Vector2(30, 30) * k
		sq.connect("draw", self, "_draw_icon_sq", [sq])
		b.add_child(sq)
		var ic = MIcon.make(it[1], 19 * k, ICON_COL, 2.0)
		ic.rect_position = Vector2(5.5, 5.5) * k
		ic.rect_size = Vector2(19, 19) * k
		sq.add_child(ic)
		var l = ui._label(it[0], ui._font("ExtraBold", 13), Color("#ecebf0"))
		l.rect_position = Vector2(51 * k, 16 * k)
		b.add_child(l)
		var ch = MIcon.make("chevron_right", 13 * k, Color("#c9c8cf"), 2.0)
		ch.anchor_left = 1
		ch.anchor_right = 1
		ch.margin_left = -28 * k
		ch.margin_right = -15 * k
		ch.margin_top = 19.5 * k
		ch.margin_bottom = 32.5 * k
		b.add_child(ch)
		g.add_child(b)

# the dark blue square behind a tile's icon, with a soft diagonal sheen
func _draw_icon_sq(c: Control):
	var k: float = ui.k
	var r := Rect2(Vector2(), c.rect_size)
	c.draw_style_box(ui._flat(ICON_BG, 3 * k, Color(0, 0, 0, 0.6), 1), r)
	var s := c.rect_size
	c.draw_colored_polygon(PoolVector2Array([Vector2(s.x * 0.45, s.y - 1), Vector2(s.x - 1, s.y * 0.45), Vector2(s.x - 1, s.y * 0.75), Vector2(s.x * 0.75, s.y - 1)]), Color(1, 1, 1, 0.035))

func _small_btn(t: String, method: String) -> Button:
	var k: float = ui.k
	var btn = ui._button(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.09), 4)
	btn.text = t
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.rect_min_size = Vector2(0, 19 * k)
	btn.add_font_override("font", ui._font("Bold", 8))
	btn.add_color_override("font_color", Color("#e2e1e7"))
	btn.connect("pressed", self, method)
	return btn

# --- settings profiles (the classic Presets button, Profiles.gd, does the work)

func _presets():
	var pr = Rhythia.menu_node("Main/Settings/Header/TopButtons/TopButtonsHBox/Presets")
	if pr == null:
		pr = Rhythia.menu_node("Main/Settings/S/F/TopButtons/TopButtonsHBox/Presets")
	if pr == null:
		var l = get_tree().get_nodes_in_group("settings_profiles")
		pr = l[0] if l.size() > 0 else null
	return pr

func _profile_name() -> String:
	var p := String(Rhythia.get_active_profile_path())
	if p == "":
		return "Default"
	return p.get_file().replace(".settings.json", "")

func _profile_menu():
	var pr = _presets()
	if pr is MenuButton:
		pr.emit_signal("about_to_show")
		var pop: PopupMenu = pr.get_popup()
		pop.rect_size = Vector2()
		pop.popup(Rect2(get_global_mouse_position(), Vector2(1, 1)))

func _profile_save():
	var p := String(Rhythia.get_active_profile_path())
	if p == "" or not File.new().file_exists(p):
		_profile_new()
		return
	Rhythia.save_settings(p)
	Globals.notify(Globals.NOTIFY_SUCCEED, "Saved your settings into %s." % _profile_name(), "Settings profile")

func _profile_new():
	var pr = _presets()
	if pr != null and pr.get("profiles") != null:
		pr.on_pressed(pr.profiles.size() + 1)

func _profile_delete():
	var pr = _presets()
	var p := String(Rhythia.get_active_profile_path())
	if pr == null or pr.get("profiles") == null or p == "":
		Globals.notify(Globals.NOTIFY_INFO, "You're on the default settings: there's no profile to delete.", "Settings profile")
		return
	for i in pr.profiles.size():
		if String(pr.profiles[i]).replace("\\", "/").get_file() == p.get_file():
			Globals.confirm_prompt.open("Delete the profile %s?" % _profile_name(), "Delete profile", [{text = "Delete"}, {text = "Cancel", wait = 0}])
			var r = yield(Globals.confirm_prompt, "option_selected")
			Globals.confirm_prompt.close()
			if r == 0:
				pr.delete_profile(i)
				Rhythia.set_active_profile_path("")
				open_settings(false)
			return

func _export():
	var pr = _presets()
	if pr != null and pr.has_method("export_profile"):
		pr.export_profile()

func _import_files():
	var pr = _presets()
	if pr != null and pr.has_method("import_profile"):
		pr.import_profile()

func _import_code():
	_open_tab("Streamer", "Transfer")

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
	head_title.text = title
	head_sub.text = SUBS.get(title, "")
	back_btn.visible = true
	_clear()
	head_pre.text = "Settings  >  "
	tc.current_tab = tc.get_node(tab).get_index()
	tc.tabs_visible = false
	_show_classic()
	layout()

var _page_name := "Settings"
var _main_min := Vector2(1220, 0)
var _f_min = null # (Main/Settings/S/F's own minimum width, given back after)
var _themed := [] # [node, its own theme]: given back after
var _modern_theme: Theme

# the settings controls in the Modern UI's look (dark rounded boxes, slim
# sliders with a white knob, Nunito), for the controls that don't set their own
func _theme() -> Theme:
	if _modern_theme != null:
		return _modern_theme
	var k: float = ui.k
	var th := Theme.new()
	th.default_font = ui._font("Bold", 11)
	var box = ui._flat(Color("#1b1b1b"), 5 * k)
	box.content_margin_left = 8 * k
	box.content_margin_right = 8 * k
	box.content_margin_top = 4 * k
	box.content_margin_bottom = 4 * k
	var box_f = box.duplicate()
	box_f.bg_color = Color("#222222")
	box_f.border_color = Color(1, 1, 1, 0.18)
	box_f.set_border_width_all(1)
	for t in ["LineEdit", "TextEdit"]:
		th.set_stylebox("normal", t, box)
		th.set_stylebox("focus", t, box_f)
		th.set_stylebox("read_only", t, box)
		th.set_color("font_color", t, Color("#ecebf0"))
		th.set_color("cursor_color", t, Color(1, 1, 1))
	var btn = ui._flat(Color("#1d1d1d"), 5 * k, Color(1, 1, 1, 0.07), 1)
	btn.content_margin_left = 10 * k
	btn.content_margin_right = 10 * k
	btn.content_margin_top = 4 * k
	btn.content_margin_bottom = 4 * k
	var btn_h = btn.duplicate()
	btn_h.bg_color = Color("#262626")
	var btn_p = btn.duplicate()
	btn_p.bg_color = Color("#2e2e2e")
	for t in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		th.set_stylebox("normal", t, btn)
		th.set_stylebox("hover", t, btn_h)
		th.set_stylebox("pressed", t, btn_p)
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_stylebox("disabled", t, btn)
		th.set_color("font_color", t, Color("#ecebf0"))
		th.set_color("font_color_hover", t, Color(1, 1, 1))
	for t in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			th.set_stylebox(st, t, StyleBoxEmpty.new())
		th.set_color("font_color", t, Color("#ecebf0"))
		th.set_color("font_color_hover", t, Color(1, 1, 1))
		th.set_color("font_color_pressed", t, Color(1, 1, 1))
	th.set_color("font_color", "Label", Color("#ecebf0"))
	# sliders: a thin grey track, white where it's filled, a round white knob
	var track = ui._flat(Color("#3a3a3a"), 2 * k)
	track.content_margin_top = 2 * k
	track.content_margin_bottom = 2 * k
	var fill = ui._flat(Color("#f2f2f2"), 2 * k)
	fill.content_margin_top = 2 * k
	fill.content_margin_bottom = 2 * k
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _knob(int(round(14 * k)))
	th.set_icon("grabber", "HSlider", knob)
	th.set_icon("grabber_highlight", "HSlider", knob)
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	th.set_constant("separation", "HSeparator", int(18 * k))
	# panels in the page: the video's dark rounded cards
	th.set_stylebox("panel", "PanelContainer", ui._flat(Color("#161616"), 6 * k, Color(1, 1, 1, 0.06), 1))
	var bar = ui._flat(Color(1, 1, 1, 0.22), 2)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(st, "VScrollBar", bar)
	var emp := StyleBoxEmpty.new()
	emp.content_margin_left = 3 * k
	emp.content_margin_right = 3 * k
	th.set_stylebox("scroll", "VScrollBar", emp)
	_modern_theme = th
	return th

# the page and every part of it that has a theme of its own get this one
func _swap_themes(n: Node):
	if n is Control and (n.theme != null or n.name == "Settings"):
		_themed.append([n, n.theme])
		n.theme = _theme()
	# (dark text made for the classic light buttons: light here, on the dark ones)
	if n is Button and n.has_color_override("font_color"):
		var c: Color = n.get_color("font_color")
		if c.v < 0.45:
			_themed.append([n, "font_color", c])
			n.add_color_override("font_color", Color("#ecebf0"))
	for c in n.get_children():
		_swap_themes(c)

func _knob(px: int) -> ImageTexture:
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGBA8)
	img.lock()
	var c := (px - 1) / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(1, 1, 1, clamp(px / 2.0 - d, 0.0, 1.0)))
	img.unlock()
	var t := ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER)
	return t
func _show_classic(page_name := "Settings"):
	_page_name = page_name
	var main = Rhythia.menu_node("Main")
	var sb = Rhythia.menu_node("Sidebar")
	var page = Rhythia.menu_node("Main/" + page_name)
	if main == null or page == null:
		return
	if not _classic_on:
		_classic_rect = Rect2(main.rect_position, main.rect_size)
		_main_min = main.rect_min_size
	_classic_on = true
	main.rect_min_size = Vector2() # (the classic menu wants 1220 wide: here it's the panel's width)
	if page_name == "Settings" and _themed.empty():
		_swap_themes(page)
	if sb != null and sb.has_method("press_page"):
		sb.press_page(page)
	ui._classic(false) # (press_page shows the version labels again)
	main.visible = true
	# the page's own header (buttons and tab bar) is the panel's here
	var h = page.get_node_or_null("Header") if page_name == "Settings" else null
	var sc = page.get_node_or_null("S")
	if h != null and h.visible:
		h.visible = false
		if sc != null:
			_scroll_top = sc.margin_top
			sc.margin_top = 0
	_place_classic()

# (the classic page's header comes back on its own timer: kept away while in the panel)
func _process(_d):
	if _preview != null:
		var on: bool = visible and showing.begins_with("settings") and ui.rect_size.x - _pw() > 360 * ui.k
		if _preview.modern_on != on:
			_preview.modern_on = on
			if on:
				_place_preview()
		_preview.modulate.a = clamp(1.0 + (panel.rect_position.x / max(1.0, _pw())) * 1.5, 0.0, 1.0)
	if _classic_on:
		_place_classic() # (follows the panel as it slides)
	if not _classic_on or _page_name != "Settings":
		return
	var f = Rhythia.menu_node("Main/Settings/S/F")
	if f != null and f.rect_min_size.x > 0:
		if _f_min == null:
			_f_min = f.rect_min_size
		f.rect_min_size = Vector2(0, f.rect_min_size.y)
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
	var br := _body_rect()
	main.rect_position = br.position + Vector2(4, 6) * k + Vector2(panel.rect_position.x, 0)
	main.rect_size = br.size - Vector2(8, 12) * k

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
	for e in _themed:
		if is_instance_valid(e[0]):
			if e[1] is String:
				e[0].add_color_override(e[1], e[2]) # (a button's dark text, given back)
			else:
				e[0].theme = e[1]
	_themed = []
	var f = Rhythia.menu_node("Main/Settings/S/F")
	if f != null and _f_min != null:
		f.rect_min_size = _f_min
		_f_min = null
	if main != null:
		main.rect_min_size = _main_min
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

# ------------------------------------------------------------------ a classic page in the panel

func open_page(title: String, sub: String, page_name: String):
	_hide_classic()
	showing = "page:" + page_name
	head_title.text = title
	head_sub.text = sub
	back_btn.visible = false
	_clear()
	_slide_in()
	_show_classic(page_name)
	layout()

# ------------------------------------------------------------------ Leaderboard

var _lb_req: HTTPRequest
func open_leaderboard():
	_hide_classic()
	showing = "leaderboard"
	head_title.text = "Leaderboard"
	head_sub.text = "Global player rankings"
	back_btn.visible = false
	_clear()
	var k: float = ui.k
	# (the plays on one kind of device, or all: LbModes.gd)
	var dev = load("res://scripts/ui/LbModes.gd").make(self, "open_leaderboard", ui._font("Bold", 11))
	dev.rect_min_size = Vector2(0, 26 * k)
	body.add_child(dev)
	var msg = ui._label("Loading...", ui._font("SemiBold", 11), ui.DIM)
	msg.name = "Msg"
	body.add_child(msg)
	if _lb_req != null and is_instance_valid(_lb_req):
		_lb_req.queue_free()
	_lb_req = HTTPRequest.new()
	_lb_req.timeout = 15
	add_child(_lb_req)
	_lb_req.connect("request_completed", self, "_on_lb", [_lb_req])
	_lb_req.request(ui.SITE + "/savia-public/api/leaderboard/sp?limit=100" + load("res://scripts/ui/LbModes.gd").query())
	if not visible:
		_slide_in()

func _on_lb(result: int, code: int, _h, b: PoolByteArray, r: HTTPRequest):
	r.queue_free()
	if showing != "leaderboard":
		return
	var msg = body.get_node_or_null("Msg")
	var j = parse_json(b.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (j is Dictionary) or not (j.get("entries") is Array):
		if msg: msg.text = "Couldn't load the leaderboard."
		return
	if msg: msg.queue_free()
	for e in j.entries:
		if e is Dictionary:
			body.add_child(_player_row(e))

func _player_row(e: Dictionary) -> Control:
	var k: float = ui.k
	var row := Control.new()
	row.rect_min_size = Vector2(0, 42 * k)
	row.mouse_filter = MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	row.set_meta("e", e)
	row.connect("draw", self, "_draw_player", [row])
	row.connect("gui_input", self, "_on_player_click", [int(e.get("number", -1))])
	if Globals.s(e.get("avatar_url", "")) != "":
		ui._load_pic(Globals.s(e.avatar_url), row)
	return row

func _draw_player(row: Control):
	var k: float = ui.k
	var e: Dictionary = row.get_meta("e")
	var s := row.rect_size
	row.draw_style_box(ui._flat(Color(1, 1, 1, 0.035), 6), Rect2(Vector2(), s))
	var f = ui.f
	var rank := int(e.get("rank", 0))
	var rc: Color = ui.RANK_GOLD if rank == 1 else (Color("#d9d9e0") if rank == 2 else (Color("#d08a4f") if rank == 3 else Color("#c9c8cf")))
	row.draw_string(f.rank, Vector2(10 * k, s.y / 2 + 4 * k), "#%d" % rank, rc)
	var c := Vector2(52 * k, s.y / 2)
	var pic = row.get_meta("pic") if row.has_meta("pic") else null
	if pic != null:
		row.draw_texture_rect(pic, Rect2(c - Vector2(13, 13) * k, Vector2(26, 26) * k), false)
	else:
		row.draw_circle(c, 13 * k, Color(1, 1, 1, 0.12))
	var x := 72 * k
	var tag = e.get("tag")
	if tag is Dictionary and Globals.s(tag.get("text", "")) != "":
		var tt := Globals.s(tag.text).to_upper()
		var tw: float = f.pill.get_string_size(tt).x + 8 * k
		var tc := Color(Globals.s(tag.get("color", "#4b63d8"))) if Globals.s(tag.get("color", "")).is_valid_html_color() else ui.RANKED
		row.draw_style_box(ui._flat(Color(tc.r, tc.g, tc.b, 0.25), 3), Rect2(x, s.y / 2 - 13 * k, tw, 11 * k))
		row.draw_string(f.pill, Vector2(x + 4 * k, s.y / 2 - 4.5 * k), tt, tc.lightened(0.3))
		x += tw + 5 * k
	row.draw_string(f.rowname, Vector2(x, s.y / 2 - 3 * k), Globals.s(e.get("name", "")), ui.TEXT)
	var sub := "RP: %s  •  Plays: %s" % [String(int(round(float(e.get("value", 0))))), String(int(e.get("pass_count", 0)))]
	row.draw_string(f.rowsub, Vector2(72 * k, s.y / 2 + 11 * k), sub, Color("#a9a8b0"))

func _on_player_click(ev, number: int):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT and number > 0:
		open_profile(true, number)

# ------------------------------------------------------------------ Profile

var _prof_n := -1
var _prof_req: HTTPRequest
func open_profile(slide := true, number := -1):
	_hide_classic()
	var lm = get_node_or_null("/root/LobbyManager")
	if number <= 0:
		number = int(lm.my_player_number) if lm != null else -1
	_prof_n = number
	showing = "profile"
	head_title.text = "Profile"
	head_sub.text = "User profile"
	back_btn.visible = false
	_clear()
	var k: float = ui.k
	if number <= 0:
		body.add_child(ui._label("Play online once to have a profile.", ui._font("SemiBold", 11), ui.DIM))
		if slide or not visible: _slide_in()
		return
	var msg = ui._label("Loading...", ui._font("SemiBold", 11), ui.DIM)
	msg.name = "Msg"
	body.add_child(msg)
	_prof_req = HTTPRequest.new()
	_prof_req.timeout = 15
	add_child(_prof_req)
	_prof_req.connect("request_completed", self, "_on_profile", [_prof_req, number])
	_prof_req.request(ui.SITE + "/savia-public/api/player/%d" % number)
	if slide or not visible:
		_slide_in()

func _on_profile(result: int, code: int, _h, b: PoolByteArray, r: HTTPRequest, number: int):
	r.queue_free()
	if showing != "profile" or number != _prof_n:
		return
	var k: float = ui.k
	var p = parse_json(b.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	var msg = body.get_node_or_null("Msg")
	if not (p is Dictionary):
		if msg: msg.text = "Couldn't load the profile."
		return
	if msg: msg.queue_free()
	head_title.text = Globals.s(p.get("name", "Profile"))
	# the card: picture, name, RP
	var card := Control.new()
	card.rect_min_size = Vector2(0, 66 * k)
	card.set_meta("e", p)
	card.connect("draw", self, "_draw_profile_card", [card])
	# their frame round the picture (profile > Frames)
	if p.get("frame") is Dictionary:
		var fv = load("res://scripts/ui/FrameView.gd").new()
		fv.anchor_right = 0
		fv.anchor_bottom = 0
		fv.rect_position = Vector2(14 * k, 13 * k)
		fv.rect_size = Vector2(40 * k, 40 * k)
		fv.set_frame(p.frame)
		card.add_child(fv)
	if Globals.s(p.get("avatar_url", "")) != "":
		ui._load_pic(Globals.s(p.avatar_url), card)
	body.add_child(card)
	# the website's badges
	var bf := DynamicFont.new()
	bf.font_data = load("res://assets/font/Nunito/Nunito-Bold.ttf")
	bf.size = int(11 * k)
	body.add_child(load("res://scripts/ui/BadgeRow.gd").make(p, bf, k))
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null and number == int(lm.my_player_number):
		var row := HBoxContainer.new()
		row.add_constant_override("separation", int(6 * k))
		body.add_child(row)
		for bt in [["Cards", "_open_cards"], ["Frames", "_open_frames"], ["Change profile", "_change_profile"], ["Open on website", "_profile_site"]]:
			var btn = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
			btn.text = bt[0]
			btn.size_flags_horizontal = SIZE_EXPAND_FILL
			btn.rect_min_size = Vector2(0, 26 * k)
			btn.add_font_override("font", ui._font("Bold", 11))
			btn.add_color_override("font_color", Color("#d3d2d9"))
			btn.connect("pressed", self, bt[1])
			row.add_child(btn)
	_section("Top Scores")
	var sr := HTTPRequest.new()
	sr.timeout = 15
	add_child(sr)
	sr.connect("request_completed", self, "_on_scores", [sr, number])
	sr.request(ui.SITE + "/savia-public/api/player/%d/scores" % number)

func _draw_profile_card(c: Control):
	var k: float = ui.k
	var p: Dictionary = c.get_meta("e")
	var s := c.rect_size
	c.draw_style_box(ui._flat(Color(1, 1, 1, 0.035), 8), Rect2(Vector2(), s))
	var pic = c.get_meta("pic") if c.has_meta("pic") else null
	var r := Rect2(14 * k, 13 * k, 40 * k, 40 * k)
	if pic != null:
		c.draw_texture_rect(pic, r, false)
	else:
		c.draw_circle(r.position + r.size / 2, 20 * k, Color(1, 1, 1, 0.12))
	c.draw_string(ui.f.name, Vector2(68 * k, 30 * k), Globals.s(p.get("name", "")), ui.TEXT)
	var rp := float(p.get("sp", 0))
	var sub := "%s RP  •  #%s" % [String(int(round(rp))), String(p.get("sp_rank", "-"))]
	c.draw_string(ui.f.rp, Vector2(68 * k, 48 * k), sub, ui.DIM)

func _on_scores(result: int, code: int, _h, b: PoolByteArray, r: HTTPRequest, number: int):
	r.queue_free()
	if showing != "profile" or number != _prof_n:
		return
	var j = parse_json(b.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	var rows: Array = j.scores if j is Dictionary and j.get("scores") is Array else []
	var best := []
	for e in rows:
		if e is Dictionary and bool(e.get("counts_for_sp", false)):
			best.append(e)
	if best.empty():
		body.add_child(ui._label("No ranked passes yet.", ui._font("SemiBold", 11), ui.DIM))
		return
	for i in min(30, best.size()):
		body.add_child(_score_line(best[i]))

func _score_line(e: Dictionary) -> Control:
	var k: float = ui.k
	var row := Control.new()
	row.rect_min_size = Vector2(0, 30 * k)
	row.set_meta("e", e)
	row.connect("draw", self, "_draw_score_line", [row])
	return row

func _draw_score_line(row: Control):
	var k: float = ui.k
	var e: Dictionary = row.get_meta("e")
	var s := row.rect_size
	row.draw_style_box(ui._flat(Color(1, 1, 1, 0.03), 5), Rect2(Vector2(), s))
	var acc := float(e.get("accuracy", 0.0))
	if acc > 1.0:
		acc /= 100.0
	var g: Array = ui.ScoreHistory.grade_for(acc, false)
	row.draw_rect(Rect2(0, 3 * k, 3 * k, s.y - 6 * k), ui._grade_col(g[0]))
	row.draw_string(ui.f.grade, Vector2(10 * k, s.y / 2 + 6 * k), g[0], ui._grade_col(g[0]))
	var t := "%.2f%%  %s" % [acc * 100.0, Globals.s(e.get("song_name", ""))]
	row.draw_string(ui.f.rowname, Vector2(34 * k, s.y / 2 + 4 * k), ui._fit(t, ui.f.rowname, s.x - 120 * k), ui.TEXT)
	var rt := "%drp  •  %d%%" % [int(round(float(e.get("sp_final", e.get("sp_weighted", 0))))), int(round(float(e.get("sp_weight_pct", 100))))]
	var w: float = ui.f.rowsub.get_string_size(rt).x
	row.draw_string(ui.f.rowsub, Vector2(s.x - 10 * k - w, s.y / 2 + 3 * k), rt, Color("#a9a8b0"))

func _open_cards():
	load("res://scripts/ui/CardsMenu.gd").open_on(self)

func _open_frames():
	load("res://scripts/ui/FramesMenu.gd").open_on(self)

func _change_profile():
	close()
	ui._open_classic_page("Profile")

func _profile_site():
	OS.shell_open(ui.SITE + "/profile?id=%d" % _prof_n)

# ------------------------------------------------------------------ Collections (map folders)

func open_collections():
	_hide_classic()
	showing = "collections"
	head_title.text = "Collections"
	head_sub.text = "Your map folders"
	back_btn.visible = false
	_clear()
	var k: float = ui.k
	var store = load("res://scripts/MapFolders.gd").get_store()
	var newb = ui._button(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.09), 5)
	newb.text = "Manage collections"
	newb.rect_min_size = Vector2(0, 28 * k)
	newb.add_font_override("font", ui._font("Bold", 11))
	newb.add_color_override("font_color", Color("#d3d2d9"))
	newb.connect("pressed", self, "_manage_collections")
	body.add_child(newb)
	var all = _collection_bar("All maps", -1, Color("#3a3a44"), store.active == -1)
	body.add_child(all)
	for i in store.folders.size():
		var fd = store.folders[i]
		body.add_child(_collection_bar(String(fd.name), i, fd.color, store.active == i, fd.maps.size() if fd.get("maps") is Dictionary else -1))
	if store.folders.empty():
		body.add_child(ui._label("No collections yet: make one with Manage collections, or the bookmark button on a map.", ui._font("SemiBold", 11), ui.DIM))
	_slide_in()

func _collection_bar(name: String, i: int, col: Color, active: bool, count := -1) -> Control:
	var k: float = ui.k
	var b := Control.new()
	b.rect_min_size = Vector2(0, 46 * k)
	b.mouse_filter = MOUSE_FILTER_STOP
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.set_meta("c", [name, col, active, count])
	b.connect("draw", self, "_draw_collection", [b])
	b.connect("gui_input", self, "_on_collection", [i])
	return b

func _draw_collection(b: Control):
	var k: float = ui.k
	var c: Array = b.get_meta("c")
	var s := b.rect_size
	var col: Color = c[1]
	var sb = ui._flat(Color(col.r, col.g, col.b, 0.55), 6, Color(1, 1, 1, 0.9) if c[2] else Color(col.r, col.g, col.b, 0.9), int(max(1, round(2 * k))) if c[2] else 1)
	b.draw_style_box(sb, Rect2(Vector2(), s))
	b.draw_string(ui.f.tab, Vector2(12 * k, 22 * k), String(c[0]), Color(1, 1, 1))
	if int(c[3]) >= 0:
		b.draw_string(ui.f.rowsub, Vector2(12 * k, 37 * k), "%d maps" % int(c[3]), Color(1, 1, 1, 0.75))

func _on_collection(ev, i: int):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		var store = load("res://scripts/MapFolders.gd").get_store()
		store.set_active(i)
		close()

func _manage_collections():
	close()
	var b = ui._find_script(Rhythia.menu_node(), "MapFoldersButton.gd")
	if b != null and b.has_method("open_panel"):
		b.open_panel()
