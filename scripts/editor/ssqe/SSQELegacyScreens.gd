extends Control

# Legacy UI (editor setting "legacyUI"): the editor's own screens as Sound
# Space Quantum Editor Plus has them, instead of Chromia's start page and
# Settings window. Ported from SSQE+'s NewGUI/Windows (GuiWindowMenu, Create,
# Settings, Keybinds .Controls.cs) and the web editor's screens.js: the same
# controls at the same places on its 1920x1080 stage, scaled to the page,
# in SSQELegacy.gd's look.
#
#   menu      SOUND SPACE+ / QUANTUM EDITOR PLUS, the changelog, CREATE NEW MAP,
#             LOAD MAP, PASTE MAP, SETTINGS, COLLABORATE, EDIT LAST MAP, and the
#             open-maps bar along the bottom (your editor maps, newest first)
#   create    the game (Sound Space / Rhythia / Novastra...), Audio ID (a
#             Roblox audio), Import Audio, CREATE MAP
#   settings  COLORS, GRAPHICS, MAPPING, PLAYER, AUDIO, OTHER; SAVE AND
#             RETURN, RESET TO DEFAULT, OPEN EDITOR FOLDER, CHANGE KEYBINDS
#   keybinds  every keybind with RESET, the grid keys, the static keybinds,
#             CTRL / ALT / SHIFT Held
#
# EditorPage.gd shows this instead of its start page while Legacy UI is on;
# the editor's SETTINGS button opens the settings screen over the editor.

const L = preload("res://scripts/editor/ssqe/SSQELegacy.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const SSQESlider = preload("res://scripts/editor/ssqe/SSQESlider.gd")
const EditorProject = preload("res://scripts/editor/EditorProject.gd")

const W0 := 1920.0
const H0 := 1080.0
const TEXT_K := 0.78
const CHANGELOG_URL := "https://raw.githubusercontent.com/iloverhythia/Sound-Space-Quantum-Editor-Plus/master/changelog"
const FEEDBACK_URL := "https://forms.gle/Rh4RXKT9KyttJ9Dc6"
const LOGO := "res://assets/images/editor/ssqe_logo.png"
const UNC_CHECK := Color8(75, 75, 75) # Checkbox_Uncolored's check
const GAMES_CREATE := ["Sound Space", "Rhythia", "Novastra/Phoenyx/Other"]
const GAMES_PLAYTEST := ["Chromia", "Rhythia", "Novastra"]
const SETTINGS_TABS := ["COLORS", "GRAPHICS", "MAPPING", "PLAYER", "AUDIO", "OTHER"]
const STATIC_KEYBINDS := "Static keybinds:\n\n> Zoom: CTRL + SCROLL\n\n> Beat Divisor: SHIFT + SCROLL\n>> Hold CTRL to increment by 0.5\n\n> Seek: SCROLL/LEFT/RIGHT\n> Play/Pause: SPACE\n\n> Select all: CTRL + A\n> Deselect all: ESCAPE\n\n> Delete: DELETE/BACKSPACE\n> Copy: CTRL + C\n> Paste: CTRL + V\n> Cut: CTRL + X\n> Undo: CTRL + Z\n> Redo: CTRL + Y\n\n> Fullscreen: F11\n> Save: CTRL + S\n> Save as: CTRL + SHIFT + S\n\n> Place stored patterns: 0-9\n>> Hold SHIFT to store selected notes as the key's pattern\n>> Hold CTRL to clear the key's pattern"

var page # EditorPage
var s: Dictionary
var screen := ""
var items := [] # {node, x, y, w, h, ts, screen, tab, font}
var from_editor := false # the settings screen was opened over the editor
var settings_tab := "COLORS"
var create_game := 0
var audio_file := ""
var map_index := 0
var _theme: Theme
var _fonts := {}
var _icons := {}
var _capture = null # the keybind box waiting for a key: {kind: "bind" / "grid", key}
var _reset_armed := false
var _changelog: Label
var _changelog_text := ""
var _bar_selects := []
var _bar_closes := []
var _nav_left: Button
var _nav_right: Button
var _last_btn: Button
var _selected_btn: Button
var _held := {}
var _fps_label: Label
var _create_panels := []
var _create_checks := []
var _settings_buttons := {}
var _game_checks := []
var _id_box: LineEdit
var _picker: PopupPanel
var _picker_cp: ColorPicker
var _picker_key := ""
var _note_strip: Control

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_STOP
	connect("resized", self, "_layout")
	set_process(true)
	set_process_input(true)

# ================================================================== setup

func setup(p):
	page = p
	s = page.ed.s if page.ed != null and page.ed.s is Dictionary else SSQESettings.load_settings()
	_theme = L.make_theme(s)
	_build()
	show_screen("menu")

func _font(px: int, path: String = L.FONT_MAIN) -> DynamicFont:
	px = int(clamp(px, 6, 220))
	var key := "%s|%d" % [path, px]
	if not _fonts.has(key):
		_fonts[key] = L.font(path, px)
	return _fonts[key]

func _k() -> float:
	return min(rect_size.x / W0, rect_size.y / H0)

func _add(scr: String, node: Control, x: float, y: float, w: float, h: float, ts: float, font := L.FONT_MAIN, tab := "") -> Control:
	add_child(node)
	if node is Control and node.get("theme") != null or node is Button or node is LineEdit:
		node.theme = _theme
	items.append({"node": node, "x": x, "y": y, "w": w, "h": h, "ts": ts, "screen": scr, "font": font, "tab": tab})
	return node

func _sq(scr: String, x, y, w, h, c: Color, tab := "") -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = MOUSE_FILTER_IGNORE
	_add(scr, r, x, y, w, h, 0, L.FONT_MAIN, tab)
	return r

func _btn(scr: String, x, y, w, h, text: String, ts: float, method: String, args := [], tab := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	if method != "":
		b.connect("pressed", self, method, args)
	_add(scr, b, x, y, w, h, ts, L.FONT_MAIN, tab)
	return b

func _lbl(scr: String, x, y, w, h, text: String, ts: float, font := L.FONT_MAIN, tab := "", center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.add_color_override("font_color", Color(1, 1, 1))
	if center:
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
	_add(scr, l, x, y, w, h, ts, font, tab)
	return l

# GuiCheckbox (Checkbox_Uncolored): a round box, white text; `key` a setting or
# "m:<method>" (get_/set_ here)
func _check(scr: String, x, y, size, text: String, ts: float, key: String, tab := "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = FOCUS_NONE
	c.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
		c.add_color_override(k, Color(1, 1, 1))
	c.set_meta("key", key)
	c.connect("toggled", self, "_on_check", [c])
	_add(scr, c, x, y, max(size, 600), size, ts, L.FONT_MAIN, tab)
	items[-1].box = size
	return c

# GuiNumberBox: a box with two arrows; Textbox_Uncolored (white text)
func _num(scr: String, x, y, w, h, key: String, inc: float, mn: float, mx: float, is_float: bool, ts := 34.0, tab := "") -> LineEdit:
	var e := LineEdit.new()
	e.align = LineEdit.ALIGN_LEFT
	e.add_color_override("font_color", Color(1, 1, 1))
	e.add_color_override("cursor_color", Color(1, 1, 1))
	e.set_meta("key", key)
	e.set_meta("range", [mn, mx, is_float])
	e.connect("text_entered", self, "_on_num_entered", [e])
	e.connect("focus_exited", self, "_on_num_left", [e])
	_add(scr, e, x, y, w - w / 8.0 - 2, h, ts, L.FONT_MAIN, tab)
	for a in [[true, 0.0, inc], [false, h / 2.0, -inc]]:
		var b := _btn(scr, x + w - w / 8.0, y + a[1], w / 8.0, h / 2.0, "", 0, "_bump", [key, a[2], mn, mx, is_float], tab)
		b.icon = _arrow(a[0])
		b.expand_icon = true
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = L.box(L.FILL if st == "normal" else Color8(38, 38, 38), L.OUTLINE, 1, 2)
			sb.content_margin_left = 1
			sb.content_margin_right = 1
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			b.add_stylebox_override(st, sb)
	return e

# the path boxes (CHOOSE | file name): a button and the chosen path beside it
func _pathbox(scr: String, x, y, w, h, text: String, ts: float, method: String, label_method: String, tab := "") -> Label:
	_btn(scr, x, y, w / 4.0, h, text, ts, method, [], tab)
	_sq(scr, x + w / 4.0, y, w * 3 / 4.0, h, L.FILL, tab)
	var l := _lbl(scr, x + w / 4.0 + 8, y, w * 3 / 4.0 - 8, h, "", ts, L.FONT_MAIN, tab)
	l.valign = Label.VALIGN_CENTER
	l.clip_text = true
	l.set_meta("label_method", label_method)
	return l

# ================================================================== screens

func _build():
	# ---------------------------------------------------------------- menu
	_sq("menu", 0, 0, 1920, 1080, L.BG)
	_sq("menu", 35, 180, 950, 790, Color8(0, 0, 0, 40))
	_sq("menu", 55, 230, 900, 715, Color8(0, 0, 0, 50))
	_sq("menu", 0, 1040, 1920, 40, Color8(0, 0, 0, 50))
	var logo := TextureRect.new()
	logo.expand = true
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	logo.texture = _logo_texture()
	_add("menu", logo, 35, 4, 212, 172, 0)
	_lbl("menu", 262, 26, 900, 90, "QUANTUM EDITOR PLUS", 84, L.FONT_SQUARE)
	_btn("menu", 262, 132, 100, 40, "Feedback?", 20, "_on_feedback")
	_lbl("menu", 60, 195, 200, 40, "CHANGELOG", 42)
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	_add("menu", sc, 60, 230, 890, 715, 0)
	_changelog = Label.new()
	_changelog.autowrap = true
	_changelog.add_color_override("font_color", Color(1, 1, 1))
	_changelog.text = "Loading..."
	sc.add_child(_changelog)
	_btn("menu", 1190, 180, 600, 100, "CREATE NEW MAP", 54, "show_screen", ["create"])
	_btn("menu", 1190, 295, 600, 100, "LOAD MAP", 54, "_on_load")
	_btn("menu", 1190, 410, 600, 100, "PASTE MAP", 54, "_on_paste")
	_btn("menu", 1190, 525, 600, 100, "SETTINGS", 54, "open_settings", [false])
	_btn("menu", 1190, 640, 600, 100, "COLLABORATE", 54, "_on_collab")
	_last_btn = _btn("menu", 1190, 755, 600, 100, "EDIT LAST MAP", 54, "_on_edit_last")
	_selected_btn = _btn("menu", 1190, 870, 600, 100, "EDIT SELECTED MAP", 46, "_on_edit_selected")
	_nav_left = _btn("menu", 0, 1040, 40, 40, "<", 34, "_on_map_nav", [-1])
	_nav_right = _btn("menu", 1880, 1040, 40, 40, ">", 34, "_on_map_nav", [1])
	for i in 5:
		var x: float = 40 + 368 * i
		var sel := _btn("menu", x, 1040, 368, 40, "", 20, "_on_map_select", [i])
		_bar_selects.append(sel)
		var cl := _btn("menu", x, 1040, 40, 40, "X", 26, "_on_map_close", [i])
		cl.visible = false
		_bar_closes.append(cl)

	# ---------------------------------------------------------------- create
	_sq("create", 0, 0, 1920, 1080, L.BG)
	_btn("create", 750, 705, 420, 50, "CREATE MAP", 38, "_on_create")
	_btn("create", 690, 920, 540, 75, "BACK TO MENU", 48, "show_screen", ["menu"])
	create_game = max(0, GAMES_CREATE.find(String(s.get("createGame", "Sound Space"))))
	for i in GAMES_CREATE.size():
		_create_checks.append(_check("create", 320, 415 + i * 100, 50, GAMES_CREATE[i], 30, "m:create_game_%d" % i))
	# (each game's panel: at the game buttons' container, 320,415)
	var gx := 320 + 370
	var gy := 415
	_create_panels = [[], [], []]
	_create_panels[0].append(_lbl("create", gx, gy - 45, 540, 50, "Audio ID", 36))
	_id_box = LineEdit.new()
	_id_box.add_color_override("font_color", Color(1, 1, 1))
	_create_panels[0].append(_add("create", _id_box, gx + 100, gy + 5, 340, 50, 36))
	_create_panels[0].append(_lbl("create", gx, gy + 55, 540, 50, "Import Audio", 36))
	var n0 := items.size()
	_pathbox("create", gx, gy + 105, 540, 50, "CHOOSE", 28, "_choose_audio", "_audio_label")
	for it in items.slice(n0, items.size() - 1):
		_create_panels[0].append(it.node)
	_create_panels[1].append(_lbl("create", gx, gy - 45, 540, 50, "Import Audio", 36))
	n0 = items.size()
	_pathbox("create", gx, gy + 5, 540, 50, "CHOOSE", 28, "_choose_audio", "_audio_label")
	for it in items.slice(n0, items.size() - 1):
		_create_panels[1].append(it.node)
	_create_panels[1].append(_lbl("create", gx, gy + 85, 540, 100, "Rhythia Online is no longer supported for importing\nand should not be used for new work.\n\ndiscord.gg/rhythia -> #Announcements", 20))
	_create_panels[2].append(_lbl("create", gx, gy - 45, 540, 50, "Import Audio", 36))
	n0 = items.size()
	_pathbox("create", gx, gy + 5, 540, 50, "CHOOSE", 28, "_choose_audio", "_audio_label")
	for it in items.slice(n0, items.size() - 1):
		_create_panels[2].append(it.node)

	# ---------------------------------------------------------------- settings
	_sq("settings", 0, 0, 1920, 1080, L.BG)
	for i in SETTINGS_TABS.size():
		_settings_buttons[SETTINGS_TABS[i]] = _btn("settings", 180, 80 + i * 100, 200, 50, SETTINGS_TABS[i], 30, "_settings_tab", [SETTINGS_TABS[i]])
	var X := 500
	var Y := 80
	# COLORS
	var t := "COLORS"
	var names := ["Color 1 (1/X BPM + Primary):", "Color 2 (1/1 BPM + Secondary):", "Color 3 (1/2 BPM):", "Color 4 (Waveform):", "Color 5 (Special Objects):"]
	for i in 5:
		var y: float = i * 100
		_btn("settings", X, Y + y, 200, 50, "PICK COLOR", 30, "_pick_color", ["color%d" % (i + 1)], t)
		_lbl("settings", X, Y + y - 30, 400, 26, names[i], 30, L.FONT_MAIN, t)
		var sw := _sq("settings", X + 210, Y + y, 75, 50, Color.white, t)
		sw.set_meta("color_key", "color%d" % (i + 1))
	_btn("settings", X, Y + 500, 200, 50, "ADD COLOR", 30, "_pick_color", ["+note"], t)
	_lbl("settings", X, Y + 470, 200, 26, "Note Colors:", 30, L.FONT_MAIN, t)
	_lbl("settings", X, Y + 555, 195, 26, "LMB: Remove\nRMB: Move left", 30, L.FONT_MAIN, t)
	_note_strip = Control.new()
	_note_strip.connect("draw", self, "_draw_note_strip")
	_note_strip.connect("gui_input", self, "_on_note_strip", [_note_strip])
	_note_strip.mouse_filter = MOUSE_FILTER_STOP
	_add("settings", _note_strip, X + 210, Y + 500, 75, 50, 0, L.FONT_MAIN, t)
	_check("settings", X + 310, Y + 502, 45, "Use Note Colors", 34, "customNoteColors", t)
	# (Chromia: the preview and stored nodes have their own colours)
	for it3 in [[300, "color6", "Color 6 (Preview):"], [400, "color7", "Color 7 (Stored Nodes):"]]:
		_btn("settings", X + 650, Y + it3[0], 200, 50, "PICK COLOR", 30, "_pick_color", [it3[1]], t)
		_lbl("settings", X + 650, Y + it3[0] - 30, 400, 26, it3[2], 30, L.FONT_MAIN, t)
		var sw2 := _sq("settings", X + 860, Y + it3[0], 75, 50, Color.white, t)
		sw2.set_meta("color_key", it3[1])
	for it2 in [[0, "editorBGOpacity", "Editor Background Opacity:"], [100, "gridOpacity", "Grid Opacity:"], [200, "trackOpacity", "Track Opacity:"]]:
		_num("settings", X + 650, Y + it2[0], 200, 50, it2[1], 5, 0, 255, false, 34, t)
		_lbl("settings", X + 650, Y + it2[0] - 30, 400, 26, it2[2], 30, L.FONT_MAIN, t)
		var pv := _sq("settings", X + 860, Y + it2[0], 75, 50, Color.white, t)
		pv.set_meta("alpha_key", it2[1])
	# GRAPHICS
	t = "GRAPHICS"
	_check("settings", X, Y + 0, 45, "Enable Waveform", 34, "waveform", t)
	_check("settings", X, Y + 60, 45, "Use Classic Waveform", 34, "classicWaveform", t)
	_num("settings", X, Y + 150, 200, 50, "waveformDetail", 1, 1, 250, false, 30, t)
	_lbl("settings", X, Y + 120, 400, 26, "Waveform Level of Detail:", 30, L.FONT_MAIN, t)
	_check("settings", X, Y + 300, 45, "Enable VSync", 34, "useVSync", t)
	_check("settings", X, Y + 360, 45, "Limit Player FPS", 34, "limitPlayerFPS", t)
	var fs := SSQESlider.new()
	fs.max_value = 305
	fs.step = 5
	fs.default = 60
	fs.line_color = L.UNCOLORED
	fs.dot_color = Color(1, 1, 1)
	fs.connect("changed", self, "_on_fps_slider")
	_add("settings", fs, X, Y + 410, 400, 55, 0, L.FONT_MAIN, t)
	fs.set_meta("key", "fpsLimit")
	_fps_label = _lbl("settings", X, Y + 460, 400, 55, "", 34, L.FONT_MAIN, t)
	_check("settings", X, Y + 510, 45, "Lower FPS in Background", 34, "lowerBackgroundFPS", t)
	_check("settings", X + 700, Y + 0, 45, "Use Anti-Aliasing", 34, "msaa", t)
	_check("settings", X + 700, Y + 60, 45, "Show Control Gradients", 34, "controlGradients", t)
	_lbl("settings", X + 700, Y + 120, 200, 26, "Font Scale:", 30, L.FONT_MAIN, t)
	_num("settings", X + 700, Y + 150, 200, 50, "fontScale", 0.05, 0.25, 2.5, true, 30, t)
	_check("settings", X + 700, Y + 300, 45, "Grid Squircles", 34, "gridSquircles", t)
	_num("settings", X + 700, Y + 390, 200, 50, "gridSquircleDetail", 1, 1, 16, false, 30, t)
	_lbl("settings", X + 700, Y + 360, 400, 26, "Grid Squircle Corner Detail:", 30, L.FONT_MAIN, t)
	_num("settings", X + 700, Y + 485, 200, 50, "gridSquircleRadius", 0.025, 0, 0.5, true, 30, t)
	_lbl("settings", X + 700, Y + 455, 400, 26, "Grid Squircle Corner Radius:", 30, L.FONT_MAIN, t)
	var sqp := Panel.new()
	sqp.mouse_filter = MOUSE_FILTER_IGNORE
	sqp.set_meta("squircle", true)
	_add("settings", sqp, X + 955, Y + 395, 40, 40, 0, L.FONT_MAIN, t)
	# MAPPING
	t = "MAPPING"
	_check("settings", X, Y + 0, 45, "Enable Autosave", 34, "autosave", t)
	_num("settings", X, Y + 90, 200, 50, "autosaveInterval", 1, 0.1, 60, true, 34, t)
	_lbl("settings", X, Y + 60, 400, 26, "Autosave Interval (min):", 30, L.FONT_MAIN, t)
	_check("settings", X, Y + 215, 45, "Correct Errors on Copy", 34, "correctOnCopy", t)
	_check("settings", X, Y + 275, 45, "Reverse Scroll Direction", 34, "reverseScroll", t)
	_check("settings", X, Y + 335, 45, "Adjust Notes With Timing", 34, "adjustNotes", t)
	# PLAYER
	t = "PLAYER"
	for i in GAMES_PLAYTEST.size():
		_game_checks.append(_check("settings", X, Y + i * 60, 45, GAMES_PLAYTEST[i], 34, "m:playtest_game_%d" % i, t))
	_pathbox("settings", X + 300, Y + 60, 750, 50, "RHYTHIA PATH", 30, "_choose_rhythia", "_rhythia_label", t)
	_pathbox("settings", X + 300, Y + 120, 750, 50, "NOVASTRA PATH", 30, "_choose_nova", "_nova_label", t)
	_check("settings", X, Y + 200, 45, "Open Player in Fullscreen", 34, "fullscreenPlayer", t)
	_lbl("settings", X, Y + 270, 1100, 80, "Chromia playtests in the game itself (the SSQE Player). Rhythia and Novastra open the game you\npick with its path, on a computer (the map is exported for it first).", 24, L.FONT_SEMIBOLD, t)
	# AUDIO
	t = "AUDIO"
	_check("settings", X, Y + 0, 45, "Mono Audio", 34, "monoAudio", t)
	_num("settings", X, Y + 90, 200, 50, "maxPolyphony", 1, 1, 16, false, 34, t)
	_lbl("settings", X, Y + 60, 400, 26, "Maximum Polyphony:", 30, L.FONT_MAIN, t)
	# OTHER
	t = "OTHER"
	_check("settings", X, Y + 0, 45, "Skip Download From Roblox", 34, "skipDownload", t)
	_check("settings", X, Y + 60, 45, "Check For Updates", 34, "checkUpdates", t)
	_check("settings", X, Y + 120, 45, "Invites To Map Together", 34, "allowCollabInvites", t)
	_check("settings", X, Y + 180, 45, "Legacy UI (SSQE+'s look)", 34, "legacyUI", t)
	_btn("settings", X, Y + 260, 500, 50, "IMPORT SSQE+ SETTINGS", 30, "_import_settings", [], t)
	_lbl("settings", X, Y + 320, 1100, 60, "Your SSQE+ setup (.ssqes, from SSQE+'s EXPORT SETUP in Settings) or settings.txt from its folder.", 24, L.FONT_SEMIBOLD, t)
	# bottom
	_btn("settings", 660, 930, 600, 100, "SAVE AND RETURN", 54, "_save_and_return")
	_btn("settings", 700, 865, 500, 50, "RESET TO DEFAULT", 30, "_on_reset")
	_btn("settings", 700, 810, 500, 50, "OPEN EDITOR FOLDER", 30, "_open_folder")
	_btn("settings", 700, 755, 500, 50, "CHANGE KEYBINDS", 30, "show_screen", ["keybinds"])

	# ---------------------------------------------------------------- keybinds
	_sq("keybinds", 0, 0, 1920, 1080, L.BG)
	for kb in [[1366, 100, "Horizontal Flip", "hFlip"], [1366, 180, "Vertical Flip", "vFlip"], [1366, 260, "Store Bezier Nodes", "storeNodes"],
			[1366, 340, "Anchor Bezier Node", "anchorNode"], [1366, 420, "Draw Bezier Curve", "drawBezier"],
			[150, 100, "Switch Click Function", "switchClickTool"], [150, 180, "Toggle Quantum", "quantum"],
			[150, 300, "Open Timings", "openTimings"], [150, 380, "Open Bookmarks", "openBookmarks"],
			[150, 540, "Export SSPM", "exportSSPM"], [150, 620, "Create Timing Point", "createBPM"],
			[1366, 540, "Open Directory", "openDirectory"], [1366, 620, "Undo", "undo"], [1366, 700, "Redo", "redo"]]:
		_keybind_row(kb[0], kb[1], kb[2], kb[3])
	_lbl("keybinds", 778, 49, 128, 26, "Grid", 28)
	for i in 9:
		var x2: float = 778 + (i % 3) * 138
		var y2: float = 75 + (i / 3) * 94
		var box := _btn("keybinds", x2, y2, 128, 40, "", 28, "_capture_key", ["grid", i])
		box.set_meta("grid", i)
		_btn("keybinds", x2, y2 + 44, 128, 40, "RESET", 36, "_reset_grid", [i])
	var help := _lbl("keybinds", 480, 330, 960, 580, STATIC_KEYBINDS, 20, L.FONT_MAIN, "", true) # (centred in its box, as SSQE's labels are)
	help.add_constant_override("line_spacing", -4)
	_btn("keybinds", 655, 930, 600, 100, "RETURN TO SETTINGS", 52, "open_settings", [null])
	for h in [["ctrl", 828, "CTRL Held"], ["alt", 912, "ALT Held"], ["shift", 996, "SHIFT Held"]]:
		var c := _check("keybinds", 64, h[1], 64, h[2], 36, "m:held_" + h[0])
		c.mouse_filter = MOUSE_FILTER_IGNORE
		_held[h[0]] = c

	_picker = PopupPanel.new()
	_picker_cp = ColorPicker.new()
	_picker_cp.edit_alpha = false
	_picker_cp.connect("color_changed", self, "_on_picked_color")
	_picker.add_child(_picker_cp)
	add_child(_picker)
	_fetch_changelog()

func _keybind_row(x: float, y: float, label: String, key: String):
	_lbl("keybinds", x, y, 300, 26, label, 28)
	var cas := _lbl("keybinds", x + 276, y + 30, 256, 40, "", 28)
	cas.set_meta("cas", key)
	cas.valign = Label.VALIGN_CENTER
	var box := _btn("keybinds", x, y + 30, 128, 40, "", 28, "_capture_key", ["bind", key])
	box.set_meta("bind", key)
	_btn("keybinds", x + 138, y + 30, 128, 40, "RESET", 28, "_reset_bind", [key])

# the number boxes' arrows (SSQE's Arrows.png): a small white triangle
var _arrows := {}
func _arrow(up: bool) -> Texture:
	if _arrows.has(up):
		return _arrows[up]
	var n := 32
	var img := Image.new()
	img.create(n, n, false, Image.FORMAT_RGBA8)
	img.lock()
	for y in n:
		for x in n:
			var fy: float = (y + 0.5) / n
			var dx: float = abs(x + 0.5 - n / 2.0) / (n / 2.0)
			# (a triangle most of the button's height, its point up or down)
			var t: float = (fy - 0.15) / 0.7 if up else (0.85 - fy) / 0.7
			var inside: bool = fy >= 0.15 and fy <= 0.85 and dx <= t * 0.9
			img.set_pixel(x, y, Color(1, 1, 1, 0.9) if inside else Color(1, 1, 1, 0))
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	_arrows[up] = tex
	return tex

static func _logo_texture():
	if ResourceLoader.exists(LOGO):
		return load(LOGO)
	var img := Image.new()
	if img.load(LOGO) == OK: # (not imported yet: the file as it is)
		var t := ImageTexture.new()
		t.create_from_image(img)
		return t
	return null

# ================================================================== showing

func show_screen(name: String):
	screen = name
	visible = true
	_capture = null
	_reset_armed = false
	for it in items:
		var on: bool = it.screen == name and (it.tab == "" or it.tab == settings_tab)
		it.node.visible = on
	if name == "create":
		_show_create_panel()
	elif name == "menu":
		_refresh_menu()
	_refresh_values()
	_layout()

func open_settings(over_editor = null):
	if over_editor != null:
		from_editor = bool(over_editor)
	s = page.ed.s if page.ed != null and page.ed.s is Dictionary else s
	settings_tab = String(s.get("lastSettingsTab", "COLORS"))
	if not settings_tab in SETTINGS_TABS:
		settings_tab = "COLORS"
	show_screen("settings")

func _settings_tab(t: String):
	settings_tab = t
	s.lastSettingsTab = t
	show_screen("settings")

func _layout():
	if rect_size.x <= 0:
		return
	var k := _k()
	var fs: float = clamp(float(s.get("fontScale", 1.0)), 0.25, 2.5)
	for it in items:
		var n: Control = it.node
		n.rect_position = Vector2(it.x * rect_size.x / W0, it.y * rect_size.y / H0)
		n.rect_size = Vector2(it.w * rect_size.x / W0, it.h * rect_size.y / H0)
		if it.ts > 0:
			var f: DynamicFont = _font(int(round(it.ts * TEXT_K * k * fs)), it.font)
			n.add_font_override("font", f)
		if n is CheckBox:
			var px: int = int(round(float(it.get("box", 45)) * rect_size.y / H0))
			_check_icons(n, px)
	if _changelog:
		_changelog.add_font_override("font", _font(int(round(20 * TEXT_K * k * fs)), L.FONT_SEMIBOLD))
		_changelog.rect_min_size.x = 870 * rect_size.x / W0

func _check_icons(c: CheckBox, px: int):
	var key: int = px
	if not _icons.has(key):
		_icons[key] = L.checkbox_icons(px, UNC_CHECK)
	c.add_icon_override("unchecked", _icons[key][0])
	c.add_icon_override("checked", _icons[key][1])
	c.add_constant_override("hseparation", int(px * 0.15))

# ================================================================== values

var _refreshing := false
func _refresh_values():
	_refreshing = true
	for it in items:
		var n = it.node
		if not n.visible:
			continue
		if n is CheckBox and n.has_meta("key"):
			var v: bool = bool(_get(String(n.get_meta("key"))))
			if n.pressed != v:
				n.pressed = v
		elif n is LineEdit and n.has_meta("key") and n != get_focus_owner():
			n.text = _fmt(s.get(n.get_meta("key"), 0))
		elif n is SSQESlider and n.has_meta("key"):
			n.value = float(s.get(n.get_meta("key"), 60))
			n.update()
		elif n is ColorRect and n.has_meta("color_key"):
			n.color = SSQESettings.color(s, String(n.get_meta("color_key")))
		elif n is ColorRect and n.has_meta("alpha_key"):
			n.color = Color(1, 1, 1, clamp(float(s.get(n.get_meta("alpha_key"), 255)), 0, 255) / 255.0)
		elif n is Label and n.has_meta("label_method"):
			n.text = call(String(n.get_meta("label_method")))
		elif n is Label and n.has_meta("cas"):
			var b: Array = s.keybinds.get(n.get_meta("cas"), [0, false, false, false])
			var parts := []
			if b[1]: parts.append("CTRL")
			if b[2]: parts.append("ALT")
			if b[3]: parts.append("SHIFT")
			n.text = PoolStringArray(parts).join(" + ")
		elif n is Button and n.has_meta("bind"):
			var bk: String = n.get_meta("bind")
			n.text = "..." if _capture != null and _capture.kind == "bind" and _capture.key == bk else SSQESettings.key_name(int(s.keybinds[bk][0])).to_upper()
		elif n is Button and n.has_meta("grid"):
			var gi: int = n.get_meta("grid")
			n.text = "..." if _capture != null and _capture.kind == "grid" and _capture.key == gi else SSQESettings.key_name(int(SSQESettings.grid_keys({"gridKeys": s.gridKeys})[gi])).to_upper()
		elif n is Panel and n.has_meta("squircle"):
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(1, 1, 1)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(int(float(s.get("gridSquircleRadius", 0.25)) * n.rect_size.x))
			sb.anti_aliasing = true
			n.add_stylebox_override("panel", sb)
	if _note_strip:
		_note_strip.update()
	if _fps_label:
		var v2: float = float(s.get("fpsLimit", 60))
		_fps_label.text = "FPS Limit: %s" % ("Unlimited" if int(round(v2)) >= 305 else str(int(round(v2 + 60))))
	for t in _settings_buttons:
		_settings_buttons[t].text = ("[%s]" % t) if t == settings_tab else t
	_refreshing = false

static func _fmt(v) -> String:
	if typeof(v) == TYPE_REAL:
		return str(stepify(v, 0.001))
	return str(v)

func _get(key: String):
	if key.begins_with("m:"):
		return call("get_" + key.substr(2))
	return s.get(key, false)

func _on_check(on: bool, c: CheckBox):
	if _refreshing:
		return
	var key: String = c.get_meta("key")
	if key.begins_with("m:"):
		call("set_" + key.substr(2), on)
	else:
		s[key] = on
		_changed(key)
	_refresh_values()

func _on_num_entered(_t, e: LineEdit):
	_on_num_left(e)
	e.release_focus()

func _on_num_left(e: LineEdit):
	var key: String = e.get_meta("key")
	var r: Array = e.get_meta("range")
	if e.text.is_valid_float():
		var v: float = clamp(float(e.text), float(r[0]), float(r[1]))
		s[key] = v if r[2] else int(round(v))
		_changed(key)
	_refresh_values()

func _bump(key: String, d: float, mn: float, mx: float, is_float: bool):
	var v: float = clamp(float(s.get(key, 0)) + d, mn, mx)
	s[key] = stepify(v, 0.001) if is_float else int(round(v))
	_changed(key)
	_refresh_values()

func _on_fps_slider(v: float):
	s.fpsLimit = v
	_changed("fpsLimit")
	_refresh_values()

# a setting changed: saved, and the open editor (and the game) follow
func _changed(key: String):
	if page != null and page.ed != null:
		page.ed.s = s
		page.ed.settings_changed()
	else:
		SSQESettings.save_settings(s)
	match key:
		"useVSync":
			OS.vsync_enabled = bool(s.useVSync)
		"fontScale":
			_layout()
		"legacyUI":
			if not bool(s.legacyUI) and page != null:
				page.legacy_ui_changed()

# the games (radio buttons)
func get_create_game_0(): return create_game == 0
func get_create_game_1(): return create_game == 1
func get_create_game_2(): return create_game == 2
func set_create_game_0(_v): _set_create_game(0)
func set_create_game_1(_v): _set_create_game(1)
func set_create_game_2(_v): _set_create_game(2)
func _set_create_game(i: int):
	create_game = i
	s.createGame = GAMES_CREATE[i]
	_changed("createGame")
	_show_create_panel()

func _show_create_panel():
	for i in _create_panels.size():
		for n in _create_panels[i]:
			n.visible = screen == "create" and i == create_game

func get_playtest_game_0(): return String(s.get("playtestGame", "Chromia")) == GAMES_PLAYTEST[0]
func get_playtest_game_1(): return String(s.get("playtestGame", "Chromia")) == GAMES_PLAYTEST[1]
func get_playtest_game_2(): return String(s.get("playtestGame", "Chromia")) == GAMES_PLAYTEST[2]
func set_playtest_game_0(_v): _set_playtest(0)
func set_playtest_game_1(_v): _set_playtest(1)
func set_playtest_game_2(_v): _set_playtest(2)
func _set_playtest(i: int):
	s.playtestGame = GAMES_PLAYTEST[i]
	_changed("playtestGame")
	if i == 1 and String(s.get("rhythiaPath", "")) == "":
		_choose_rhythia()
	elif i == 2 and String(s.get("novaPath", "")) == "":
		_choose_nova()

func get_held_ctrl(): return Input.is_key_pressed(KEY_CONTROL)
func get_held_alt(): return Input.is_key_pressed(KEY_ALT)
func get_held_shift(): return Input.is_key_pressed(KEY_SHIFT)
func set_held_ctrl(_v): pass
func set_held_alt(_v): pass
func set_held_shift(_v): pass

func _process(_d):
	if not visible:
		return
	if screen == "keybinds":
		for k in _held:
			var on: bool = call("get_held_" + k)
			if _held[k].pressed != on:
				_refreshing = true
				_held[k].pressed = on
				_refreshing = false
	elif screen == "menu":
		for i in 5:
			var sel: Button = _bar_selects[i]
			_bar_closes[i].visible = sel.visible and sel.is_hovered() or (_bar_closes[i].visible and _bar_closes[i].is_hovered())
			if _bar_closes[i].visible:
				sel.text = "Open Map"
			elif sel.has_meta("title"):
				sel.text = sel.get_meta("title")

# ================================================================== menu

func _maps() -> Array:
	var hidden: Array = s.get("legacyClosedMaps", [])
	var out := []
	for p in EditorProject.list_projects():
		if not hidden.has(String(p.pid)):
			out.append(p)
	return out

func _refresh_menu():
	var list := _maps()
	map_index = int(clamp(map_index, 0, max(list.size() - 5, 0)))
	_nav_left.visible = map_index > 0
	_nav_right.visible = map_index < list.size() - 5
	for i in 5:
		var sel: Button = _bar_selects[i]
		var p = list[map_index + i] if map_index + i < list.size() else null
		sel.visible = p != null
		_bar_closes[i].visible = false
		if p != null:
			var title := Globals.s(p.title)
			sel.set_meta("title", title)
			sel.set_meta("pid", String(p.pid))
			sel.text = title
	var all: Array = EditorProject.list_projects()
	_last_btn.visible = not all.empty()
	var song = Rhythia.selected_song
	_selected_btn.visible = song is Song
	if song is Song:
		_selected_btn.text = "EDIT: " + Globals.s(song.name).to_upper()

func _on_map_nav(d: int):
	map_index += d
	_refresh_menu()

func _on_map_select(i: int):
	var sel: Button = _bar_selects[i]
	if sel.has_meta("pid"):
		hide_for_editor()
		page.open_project(String(sel.get_meta("pid")))

# X: off the bar (the map stays in your editor maps)
func _on_map_close(i: int):
	var sel: Button = _bar_selects[i]
	if not sel.has_meta("pid"):
		return
	var hidden: Array = s.get("legacyClosedMaps", []).duplicate()
	hidden.append(String(sel.get_meta("pid")))
	s.legacyClosedMaps = hidden
	_changed("legacyClosedMaps")
	_refresh_menu()

func _gui_input(ev):
	if screen == "menu" and ev is InputEventMouseButton and ev.pressed and ev.position.y > rect_size.y * 1040.0 / H0:
		if ev.button_index == BUTTON_WHEEL_UP:
			_on_map_nav(1)
		elif ev.button_index == BUTTON_WHEEL_DOWN:
			_on_map_nav(-1)

func hide_for_editor():
	visible = false

func _on_load():
	page._on_load_map()

func _on_paste():
	page._on_paste_new()

func _on_collab():
	page._on_collaborate()

func _on_edit_last():
	hide_for_editor()
	page._on_edit_last()

func _on_edit_selected():
	hide_for_editor()
	page._on_edit_selected()

func _on_feedback():
	OS.shell_open(FEEDBACK_URL)

func _fetch_changelog():
	var r := HTTPRequest.new()
	r.timeout = 15
	add_child(r)
	r.connect("request_completed", self, "_on_changelog", [r])
	if r.request(CHANGELOG_URL) != OK:
		r.queue_free()
		_changelog.text = "Couldn't load the changelog."

func _on_changelog(result, code, _h, body: PoolByteArray, r: HTTPRequest):
	r.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_changelog_text = body.get_string_from_utf8().replace("\r", "")
	else:
		_changelog_text = "Couldn't load the changelog (no connection)."
	_changelog.text = _changelog_text

# ================================================================== create

func _audio_label() -> String:
	return audio_file.get_file()

func _choose_audio():
	if Globals.file_sel == null:
		return
	Globals.file_sel.open_file(self, "_on_audio_chosen", PoolStringArray(["*.mp3, *.ogg, *.wav ; Songs (mp3, ogg, wav)"]), false, OS.get_system_dir(OS.SYSTEM_DIR_MUSIC))

func _on_audio_chosen(files):
	audio_file = page._first(files)
	_refresh_values()

func _on_create():
	var id := _id_box.text.strip_edges()
	if create_game == 0 and id != "" and audio_file == "":
		_download_roblox(id)
		return
	if audio_file == "":
		Globals.notify(Globals.NOTIFY_WARN, "Choose an audio file first.", "Create Map")
		return
	hide_for_editor()
	page._on_new_song_picked([audio_file])

# a Roblox audio by its ID (Sound Space's songs): downloaded, then mapped
func _download_roblox(id: String):
	if not id.is_valid_integer():
		Globals.notify(Globals.NOTIFY_WARN, "An Audio ID is the number of a Roblox audio.", "Create Map")
		return
	var dir: String = Globals.p("user://editor/roblox_audio")
	Directory.new().make_dir_recursive(dir)
	var out := dir.plus_file(id + ".ogg")
	if bool(s.get("skipDownload", true)) and File.new().file_exists(out):
		audio_file = out
		_on_create()
		return
	var r := HTTPRequest.new()
	r.timeout = 60
	r.download_file = out
	add_child(r)
	r.connect("request_completed", self, "_on_roblox", [r, out, id])
	Globals.notify(Globals.NOTIFY_INFO, "Downloading Roblox audio %s..." % id, "Create Map")
	if r.request("https://assetdelivery.roblox.com/v1/asset/?id=" + id) != OK:
		r.queue_free()

func _on_roblox(result, code, _h, _b, r: HTTPRequest, out: String, id: String):
	r.queue_free()
	var f := File.new()
	var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200 and f.file_exists(out)
	if ok and f.open(out, File.READ) == OK:
		var head := f.get_buffer(4)
		f.close()
		ok = head.size() == 4 and (head.get_string_from_ascii() == "OggS" or head.get_string_from_ascii().begins_with("ID3") or (head[0] == 0xFF and (head[1] & 0xE0) == 0xE0))
	if not ok:
		Directory.new().remove(out)
		Globals.notify(Globals.NOTIFY_WARN, "Roblox didn't send audio %s (it may be private, or need signing in). Download it and use CHOOSE instead." % id, "Create Map")
		return
	audio_file = out
	_on_create()

# ================================================================== settings

func _save_and_return():
	SSQESettings.save_settings(s)
	if page and page.ed:
		page.ed.settings_changed()
	if from_editor:
		from_editor = false
		visible = false
	else:
		show_screen("menu")

func _on_reset():
	if not _reset_armed:
		_reset_armed = true
		for it in items:
			if it.node is Button and it.node.text == "RESET TO DEFAULT":
				it.node.text = "ARE YOU SURE?"
		yield(get_tree().create_timer(5.0), "timeout")
		if _reset_armed:
			_reset_armed = false
			for it in items:
				if it.node is Button and it.node.text == "ARE YOU SURE?":
					it.node.text = "RESET TO DEFAULT"
		return
	_reset_armed = false
	var keep := {}
	for k in ["patterns", "legacyUI", "lastLeftNav", "lastRightNav", "rhythiaPath", "novaPath", "playtestGame", "createGame", "legacyClosedMaps"]:
		if s.has(k):
			keep[k] = s[k]
	var fresh := SSQESettings.defaults()
	for k in fresh:
		s[k] = fresh[k]
	for k in keep:
		s[k] = keep[k]
	_changed("reset")
	for it in items:
		if it.node is Button and it.node.text == "ARE YOU SURE?":
			it.node.text = "RESET TO DEFAULT"
	_refresh_values()

func _open_folder():
	var p: String = ProjectSettings.globalize_path(Globals.p("user://editor"))
	Directory.new().make_dir_recursive(p)
	OS.shell_open(p)

func _import_settings():
	if Globals.file_sel == null:
		return
	Globals.file_sel.open_file(self, "_on_import_picked", PoolStringArray(["*.ssqes, *.txt, *.json ; SSQE+ settings (.ssqes setup or settings.txt)"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))

func _on_import_picked(files):
	var path: String = page._first(files)
	if path == "":
		return
	var r: Dictionary = load("res://scripts/editor/ssqe/SSQEImportSettings.gd").import_file(path, s)
	if not r.ok:
		Globals.notify(Globals.NOTIFY_WARN, String(r.error), "Import SSQE+ settings")
		return
	_changed("import")
	_layout()
	_refresh_values()
	Globals.notify(Globals.NOTIFY_SUCCEED, "Imported %d settings from SSQE+." % r.count, "Import SSQE+ settings")

func _rhythia_label() -> String:
	return String(s.get("rhythiaPath", ""))

func _nova_label() -> String:
	return String(s.get("novaPath", ""))

func _choose_rhythia():
	_choose_game("rhythiaPath")

func _choose_nova():
	_choose_game("novaPath")

var _choosing_path := ""
func _choose_game(key: String):
	if Globals.file_sel == null or OS.has_feature("mobile") or OS.get_name() == "HTML5":
		Globals.notify(Globals.NOTIFY_INFO, "Playtesting in another game needs a computer.", "Settings")
		return
	_choosing_path = key
	Globals.file_sel.open_file(self, "_on_game_chosen", PoolStringArray(["* ; The game"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP))

func _on_game_chosen(files):
	var path: String = page._first(files)
	if path == "" or _choosing_path == "":
		return
	s[_choosing_path] = path
	_changed(_choosing_path)
	_refresh_values()

# the colours
func _pick_color(key: String):
	_picker_key = key
	if key == "+note":
		_picker_cp.color = Color(1, 1, 1)
	else:
		_picker_cp.color = SSQESettings.color(s, key)
	_picker.popup_centered(Vector2(320, 420))

func _on_picked_color(c: Color):
	var v: Array = [int(c.r8), int(c.g8), int(c.b8)]
	if _picker_key == "+note":
		var cols: Array = s.noteColors.duplicate(true)
		if cols.size() < 32:
			cols.append(v)
		s.noteColors = cols
		s.customNoteColors = true
		_picker_key = "note%d" % (cols.size() - 1)
	elif _picker_key.begins_with("note"):
		var cols2: Array = s.noteColors.duplicate(true)
		var i: int = int(_picker_key.substr(4))
		if i >= 0 and i < cols2.size():
			cols2[i] = v
		s.noteColors = cols2
	else:
		s[_picker_key] = v
	_changed(_picker_key)
	_refresh_values()

func _draw_note_strip():
	var cols: Array = s.get("noteColors", [])
	if cols.empty():
		return
	var w: float = _note_strip.rect_size.x / cols.size()
	for i in cols.size():
		var c: Array = cols[i]
		_note_strip.draw_rect(Rect2(w * i, 0, w, _note_strip.rect_size.y), Color8(int(c[0]), int(c[1]), int(c[2])))
	var hi: int = _note_strip.get_meta("hover") if _note_strip.has_meta("hover") else -1
	if hi >= 0 and hi < cols.size():
		_note_strip.draw_rect(Rect2(w * hi, 0, w, _note_strip.rect_size.y), Color8(0, 127, 255), false, 2)

# LMB: remove, RMB: move left (GuiWindowSettings' note colours)
func _on_note_strip(ev, strip: Control):
	var cols: Array = s.get("noteColors", [])
	if cols.empty():
		return
	if ev is InputEventMouseMotion:
		strip.set_meta("hover", int(clamp(floor(ev.position.x / (strip.rect_size.x / cols.size())), 0, cols.size() - 1)))
		strip.update()
	elif ev is InputEventMouseButton and not ev.pressed:
		var i: int = int(clamp(floor(ev.position.x / (strip.rect_size.x / cols.size())), 0, cols.size() - 1))
		var c2: Array = cols.duplicate(true)
		if ev.button_index == BUTTON_LEFT and c2.size() > 1:
			c2.remove(i)
		elif ev.button_index == BUTTON_RIGHT and i > 0:
			var t = c2[i]
			c2[i] = c2[i - 1]
			c2[i - 1] = t
		else:
			return
		s.noteColors = c2
		s.customNoteColors = true
		_changed("noteColors")
		strip.update()

# ================================================================== keybinds

func _capture_key(kind: String, key):
	_capture = {"kind": kind, "key": key}
	_refresh_values()

func _input(ev):
	if _capture == null or not visible or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.scancode in [KEY_CONTROL, KEY_ALT, KEY_SHIFT, KEY_META]:
		return
	var code: int = ev.scancode
	if code == KEY_BACKSPACE:
		code = KEY_DELETE
	if _capture.kind == "bind":
		s.keybinds[_capture.key] = [code, ev.control, ev.alt, ev.shift]
	else:
		var gk: Array = SSQESettings.grid_keys({"gridKeys": s.gridKeys}).duplicate()
		gk[int(_capture.key)] = code
		s.gridKeys = gk
	_capture = null
	_changed("keybinds")
	_refresh_values()
	get_tree().set_input_as_handled()

func _reset_bind(key: String):
	s.keybinds[key] = SSQESettings.KEYBINDS[key].duplicate()
	_changed("keybinds")
	_refresh_values()

func _reset_grid(i: int):
	var gk: Array = SSQESettings.grid_keys({"gridKeys": s.gridKeys}).duplicate()
	gk[i] = SSQESettings.GRID_KEYS[i]
	s.gridKeys = gk
	_changed("gridKeys")
	_refresh_values()
