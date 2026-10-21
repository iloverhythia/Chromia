extends Reference
# The map editor's controls: Sound Space Quantum Editor Plus's editor window
# (Web Editor/js/editorwindow.js, from GuiWindowEditor.Controls.cs) with the
# same positions, sizes and text sizes on the 1920x1080 stage, made of
# Chromia's own buttons, checkboxes, text boxes and drop-downs.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const SSQESlider = preload("res://scripts/editor/ssqe/SSQESlider.gd")
const RM = SSQEMap.RenderMode

const CAMERA_MODES = ["half lock", "full lock", "spin"]
const EXPORT_TYPES = ["Nightly (SSPM)", "Rhythia (RHM)", "Rewrite (PHXM)", "Novastra (NPK)"]
const GAMES = ["Rhythia", "Novastra"]
const LEFT_NAVS = ["OPTIONS", "TIMING", "PATTERNS", "PLAYTEST"]
const RIGHT_NAVS = ["SNAPPING", "GRAPHICS", "EXPORT"]
const TEXT = Color(0.898039, 0.94902, 1)

var ed # SSQEEditor
var items: Array = [] # {node, x, y, w, h, ts, stretch, group, bind, kind}
var theme: Theme
var left_nav := "TIMING"
var right_nav := "SNAPPING"
var nav_buttons := {}
var special_on := false
var special_mode := "" # Beats, Mines, Glides, Lyrics, Fevers, Modify Notes
var special_buttons := {}
var lyric_fade_in := false
var lyric_fade_out := false
var easing_on := false
var easing_style := 0
var easing_direction := 0
var _player_dirty := false

# controls the editor reads or updates
var toast_label: Label
var toast_t := 0.0
var copy_button: Button
var back_button: Button
var click_mode_label: Label
var zoom_value_label: Label
var beat_div_label: Label
var snapping_label: Label
var qx_label: Label
var qy_label: Label
var qx_slider
var qy_slider
var ar_label: Label
var player_ar_label: Label
var cursor_pos_label: Label
var grid3d_label: Label
var grid_zoom_label: Label
var note_size_label: Label
var tempo_label: Label
var music_value_label: Label
var sfx_value_label: Label
var current_time_label: Label
var current_ms_label: Label
var total_time_label: Label
var notes_label: Label
var sr_label: Label
var replace_id_box: LineEdit
var lyric_box: LineEdit
var lyric_create: Button
var lyric_preview: Label
var fever_preview: ColorRect
var background: ColorRect
var touch_bar: Array = []
var am_stars_label: Label
var am_quantum_label: Label
var am_similar_label: Label
var am_stats_label: Label
var play_pause
var music_mute
var sfx_mute

# ================================================================== widgets

func _add(node: Control, x: float, y: float, w: float, h: float, ts: float, group := "", stretch := "XY", kind := "") -> Dictionary:
	ed.add_child(node)
	var it := {"node": node, "x": x, "y": y, "w": w, "h": h, "ts": ts, "stretch": stretch, "group": group, "kind": kind, "bind": {}}
	items.append(it)
	return it

func _btn(x: float, y: float, w: float, h: float, text: String, ts: float, method: String, args: Array = [], group := "") -> Button:
	var b := Button.new()
	b.theme = theme
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	if method != "":
		b.connect("pressed", self, method, args)
	_add(b, x, y, w, h, ts, group)
	return b

func _check(x: float, y: float, text: String, ts: float, key: String, group := "", width := 515.0) -> CheckBox:
	var c := CheckBox.new()
	c.theme = theme
	c.text = text
	c.flat = true
	c.focus_mode = Control.FOCUS_NONE
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
		c.add_color_override(k, TEXT)
	c.connect("toggled", self, "_on_check", [key])
	var it := _add(c, x, y, max(width - x, 120), 30, ts, group, "XY", "check")
	it.bind = {"key": key}
	return c

func _label(x: float, y: float, w: float, h: float, text: String, ts: float, group := "", center := true, color_key := "color1") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = false
	if center:
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
	l.add_color_override("font_color", SSQESettings.color(ed.s, color_key))
	var it := _add(l, x, y, w, h, ts, group, "XY", "label")
	it.color_key = color_key
	return l

func _numeric(x: float, y: float, w: float, h: float, ts: float, key: String, group := "", is_float := false) -> LineEdit:
	var e := LineEdit.new()
	e.theme = theme
	e.align = LineEdit.ALIGN_CENTER
	e.connect("text_entered", self, "_on_numeric_entered", [e, key, is_float])
	e.connect("focus_exited", self, "_on_numeric_left", [e, key, is_float])
	var it := _add(e, x, y, w, h, ts, group, "XY", "numeric")
	it.bind = {"key": key, "float": is_float}
	return e

# GuiNumberBox: a number box with arrows that step it by `increment`
func _number_box(x: float, y: float, w: float, h: float, ts: float, key: String, increment: float, group := "", minv := -1e9, maxv := 1e9) -> LineEdit:
	var aw := h * 0.6
	var e := _numeric(x, y, w - aw, h, ts, key, group, true)
	items[-1].bind.min = minv
	items[-1].bind.max = maxv
	for it in [["\u25b2", increment, 0.0], ["\u25bc", -increment, h / 2]]:
		var b := Button.new()
		b.theme = theme
		b.text = it[0]
		b.focus_mode = Control.FOCUS_NONE
		b.connect("pressed", self, "_bump", [key, it[1], minv, maxv])
		_add(b, x + w - aw, y + it[2], aw, h / 2, ts * 0.45, group)
	return e

func _bump(key: String, d: float, minv: float, maxv: float):
	set_value(key, clamp(float(get_value(key)) + d, minv, maxv))
	refresh_values()

func _slider(x: float, y: float, w: float, h: float, key: String, maxv: float, step: float, def: float, group := "", reverse := false):
	var sl = SSQESlider.new()
	sl.max_value = maxv
	sl.step = step
	sl.default = def
	sl.reverse = reverse
	sl.connect("changed", self, "_on_slider", [key])
	var it := _add(sl, x, y, w, h, 0, group, "XY", "slider")
	it.bind = {"key": key}
	return sl

func _dropdown(x: float, y: float, w: float, h: float, ts: float, options: Array, key: String, group := "", prefix := "") -> OptionButton:
	var o := OptionButton.new()
	o.theme = theme
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	for opt in options:
		o.add_item(prefix + SSQEMap.ss(opt))
	o.connect("item_selected", self, "_on_dropdown", [key, options])
	var it := _add(o, x, y, w, h, ts, group, "XY", "dropdown")
	it.bind = {"key": key, "options": options}
	return o

func _textbox(x: float, y: float, w: float, h: float, ts: float, group := "") -> LineEdit:
	var e := LineEdit.new()
	e.theme = theme
	_add(e, x, y, w, h, ts, group)
	return e

# ================================================================== values (bound keys)
# "s:name" an editor setting, "p:name" a player setting (Chromia's), anything
# else a getter/setter pair here: get_<key> / set_<key>

func get_value(key: String):
	if key.begins_with("s:"):
		return ed.s.get(key.substr(2))
	if key.begins_with("p:"):
		return _player_get(key.substr(2))
	return call("get_" + key)

func set_value(key: String, v):
	if key.begins_with("s:"):
		var k := key.substr(2)
		if typeof(ed.s[k]) == TYPE_INT:
			v = int(round(float(v)))
		ed.s[k] = v
		ed.settings_changed()
		if k == "gridZoom":
			ed._layout()
		return
	if key.begins_with("p:"):
		_player_set(key.substr(2), v)
		return
	call("set_" + key, v)

func _on_check(on: bool, key: String):
	if _refreshing:
		return
	set_value(key, on)

func _on_numeric_entered(_t, e: LineEdit, key: String, is_float: bool):
	_on_numeric_left(e, key, is_float)
	e.release_focus()

func _on_numeric_left(e: LineEdit, key: String, is_float: bool):
	var t := e.text.strip_edges()
	if t.is_valid_float() or t.is_valid_integer():
		var v := float(t)
		for it in items:
			if it.node == e and it.bind.has("min"):
				v = clamp(v, it.bind.min, it.bind.max)
		set_value(key, v if is_float else int(v))

func _on_number_box(v: float, key: String):
	if _refreshing:
		return
	set_value(key, v)

func _on_slider(v: float, key: String):
	set_value(key, v)

func _on_dropdown(i: int, key: String, options: Array):
	if _refreshing:
		return
	set_value(key, options[i])

# --- custom values
func get_exportOffset():
	return int(ed.map.props.exportOffset) if ed.map else 0
func set_exportOffset(v):
	F.set_export_offset(ed.map, int(v))
	ed.on_map_changed()

func get_beatDivisor():
	return ed.map.beat_divisor if ed.map else 3.0
func set_beatDivisor(v):
	ed.map.beat_divisor = float(v)

func get_tempoSlider():
	return ed.map.tempo_slider if ed.map else 0.9
func set_tempoSlider(v):
	ed.set_tempo_slider(float(v))

func get_masterVolume():
	return ed.s.masterVolume
func set_masterVolume(v):
	ed.s.masterVolume = float(v)
	ed.settings_changed()

func get_autoMapStarsSlider():
	return (float(ed.s.autoMapStars) - 1.0) * 10.0
func set_autoMapStarsSlider(v):
	ed.s.autoMapStars = round(10.0 + float(v)) / 10.0
	ed.settings_changed()

func get_gridZoomSlider():
	return float(ed.s.gridZoom) - 50.0
func set_gridZoomSlider(v):
	ed.s.gridZoom = int(round(float(v) / 5.0) * 5 + 50)
	ed.settings_changed()
	ed._layout()

func get_noteSizeSlider():
	return float(ed.s.gridNoteSize) - 25.0
func set_noteSizeSlider(v):
	ed.s.gridNoteSize = int(round(float(v) / 5.0) * 5 + 25)
	ed.settings_changed()

func get_exportType():
	return ed.s.exportType
func set_exportType(v):
	ed.s.exportType = SSQEMap.ss(v)
	ed.settings_changed()

func get_cameraMode():
	if Rhythia.cam_unlock:
		return "spin"
	return CAMERA_MODES[1] if Rhythia.camera_mode == Globals.CAMERA_FULL_LOCK else CAMERA_MODES[0]
func set_cameraMode(v):
	match SSQEMap.ss(v):
		"spin":
			Rhythia.cam_unlock = true
		"full lock":
			Rhythia.cam_unlock = false
			Rhythia.camera_mode = Globals.CAMERA_FULL_LOCK
		_:
			Rhythia.cam_unlock = false
			Rhythia.camera_mode = Globals.CAMERA_HALF_LOCK
	_player_dirty = true

func get_approachFade():
	return float(Rhythia.fade_length) > 0
func set_approachFade(v):
	Rhythia.fade_length = 0.5 if v else 0.0
	_player_dirty = true

func get_playerAR():
	return float(Rhythia.approach_rate) - 1.0
func set_playerAR(v):
	Rhythia.approach_rate = round(float(v)) + 1.0
	_player_dirty = true

const PLAYER_KEYS = {
	"noteScale": "note_size", "cursorScale": "cursor_scale", "lockCursor": "lock_mouse", "gridGuides": "enable_grid",
	"sensitivity": "sensitivity", "parallax": "parallax", "fov": "fov", "approachDistance": "spawn_distance",
	"hitWindow": "hitwindow_ms",
}

func _player_get(k: String):
	return Rhythia.get(PLAYER_KEYS[k])

func _player_set(k: String, v):
	var name: String = PLAYER_KEYS[k]
	var cur = Rhythia.get(name)
	if typeof(cur) == TYPE_BOOL:
		v = bool(v)
	else:
		v = float(v)
		if k != "noteScale" and k != "cursorScale" and k != "sensitivity" and k != "parallax":
			v = max(v, 0.0)
	Rhythia.set(name, v)
	_player_dirty = true

func get_modchartGame():
	return ed.s.modchartGame
func set_modchartGame(v):
	ed.s.modchartGame = SSQEMap.ss(v)
	ed.settings_changed()

func get_lyricFadeIn():
	return lyric_fade_in
func set_lyricFadeIn(v):
	lyric_fade_in = bool(v)
	if lyric_fade_in:
		lyric_fade_out = false

func get_lyricFadeOut():
	return lyric_fade_out
func set_lyricFadeOut(v):
	lyric_fade_out = bool(v)
	if lyric_fade_out:
		lyric_fade_in = false

func get_easingOn():
	return easing_on
func set_easingOn(v):
	easing_on = bool(v)

func get_easingStyle():
	return SSQEMap.EASING_STYLES[easing_style]
func set_easingStyle(v):
	easing_style = max(0, SSQEMap.EASING_STYLES.find(SSQEMap.ss(v)))

func get_easingDirection():
	return ["In", "Out"][min(easing_direction, 1)]
func set_easingDirection(v):
	easing_direction = 0 if SSQEMap.ss(v) == "In" else 1

# ================================================================== build

func build():
	theme = load("res://uitheme.tres")
	var s: Dictionary = ed.s
	# the background: the menu shows through, dimmed (SSQE's editor background)
	background = ColorRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(background, 0, 0, 1920, 1080, 0)
	fever_preview = ColorRect.new()
	fever_preview.color = Color8(255, 0, 0, 23)
	fever_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fever_preview.visible = false
	_add(fever_preview, 0, 0, 1920, 1080, 0, "fever")

	# grid and track (drawn controls, behind the buttons)
	ed.grid = load("res://scripts/editor/ssqe/SSQEGrid.gd").new()
	ed.grid.ed = ed
	ed.add_child(ed.grid)
	ed.track = load("res://scripts/editor/ssqe/SSQETrack.gd").new()
	ed.track.ed = ed
	ed.add_child(ed.track)

	# ------------------------------------------------ nav buttons
	for it in [["OPTIONS", 10, 172, 175], ["TIMING", 195, 172, 175], ["PATTERNS", 380, 172, 175], ["PLAYTEST", 10, 946, 545]]:
		nav_buttons[it[0]] = _btn(it[1], it[2], it[3], 50, it[0], 31, "_on_left_nav", [it[0]], "standard")
	for it in [["SNAPPING", 1365], ["GRAPHICS", 1550], ["EXPORT", 1735]]:
		nav_buttons[it[0]] = _btn(it[1], 172, 175, 50, it[0], 31, "_on_right_nav", [it[0]])
	left_nav = SSQEMap.ss(s.lastLeftNav) if SSQEMap.ss(s.lastLeftNav) in LEFT_NAVS else "TIMING"
	right_nav = SSQEMap.ss(s.lastRightNav) if SSQEMap.ss(s.lastRightNav) in RIGHT_NAVS else "SNAPPING"

	# ------------------------------------------------ Options (10, 222)
	var g := "OPTIONS"
	var X := 10
	var Y := 222
	_check(X + 0, Y + 10, "Use Numpad", 26, "s:numpad", g)
	_check(X + 0, Y + 50, "Separate Click Tools", 26, "s:separateClickTools", g)
	_btn(X + 0, Y + 90, 200, 40, "Swap Click mode", 26, "_kb", ["switchClickTool"], g)
	_check(X + 0, Y + 140, "Jump on Paste", 26, "s:jumpPaste", g)
	_check(X + 0, Y + 180, "Pause on Seek", 26, "s:pauseScroll", g)
	_check(X + 0, Y + 220, "Use Old Quantum Divisor", 26, "s:oldQuantumSnap", g)
	_btn(X + 0, Y + 290, 200, 40, "Edit Extra Objects", 26, "_set_special", [true], g)

	# ------------------------------------------------ Timing
	g = "TIMING"
	_numeric(X + 0, Y + 50, 130, 40, 31, "exportOffset", g)
	_numeric(X + 170, Y + 50, 130, 40, 31, "s:sfxOffset", g, true)
	_numeric(X + 340, Y + 50, 130, 40, 31, "s:musicOffset", g, true)
	_btn(X + 0, Y + 110, 210, 40, "OPEN BPM SETUP", 27, "_kb", ["openTimings"], g)
	_btn(X + 220, Y + 110, 210, 40, "DETECT BPM", 27, "_detect_bpm", [], g)
	_btn(X + 0, Y + 160, 210, 40, "IMPORT INI", 27, "_import_ini", [], g)
	_check(X + 0, Y + 210, "Metronome", 26, "s:metronome", g)
	_check(X + 0, Y + 250, "Scale Metronome With Divisor", 26, "s:scaleMetronome", g)
	_btn(X + 0, Y + 290, 210, 40, "EDIT BOOKMARKS", 27, "_kb", ["openBookmarks"], g)
	_btn(X + 0, Y + 340, 210, 40, "COPY BOOKMARKS", 27, "_copy_bookmarks", [], g)
	_btn(X + 0, Y + 390, 210, 40, "PASTE BOOKMARKS", 27, "_paste_bookmarks", [], g)
	_label(X + 0, Y + 20, 100, 30, "Export Offset:", 30, g, false)
	_label(X + 170, Y + 20, 100, 30, "SFX Offset:", 30, g, false)
	_label(X + 340, Y + 20, 100, 30, "Music Offset:", 30, g, false)

	# ------------------------------------------------ Patterns
	g = "PATTERNS"
	_btn(X + 0, Y + 20, 175, 40, "HORIZONTAL FLIP", 27, "_kb", ["hFlip"], g)
	_btn(X + 185, Y + 20, 175, 40, "VERTICAL FLIP", 27, "_kb", ["vFlip"], g)
	_number_box(X + 0, Y + 110, 100, 40, 31, "s:rotateBy", 5, g)
	_btn(X + 110, Y + 110, 100, 40, "ROTATE", 27, "_rotate", [], g)
	_number_box(X + 0, Y + 190, 100, 40, 31, "s:scaleBy", 5, g)
	_btn(X + 110, Y + 190, 100, 40, "SCALE", 27, "_scale", [], g)
	_check(X + 0, Y + 250, "Apply Rotate/Scale on Paste", 27, "s:applyOnPaste", g, 370)
	_check(X + 0, Y + 290, "Clamp Rotate/Scale in Bounds", 27, "s:clampSR", g, 370)
	_check(X + 0, Y + 330, "Paste Reversed", 27, "s:pasteReversed", g, 370)
	_check(X + 0, Y + 370, "Move Selected on Grid Key Pressed", 27, "s:moveOnGridKey", g, 370)
	_btn(X + 0, Y + 430, 175, 40, "STORE NODES", 27, "_kb", ["storeNodes"], g)
	_btn(X + 185, Y + 430, 175, 40, "CLEAR NODES", 27, "_clear_nodes", [], g)
	_check(X + 0, Y + 490, "Curve Bezier", 27, "s:curveBezier", g, 370)
	_number_box(X + 0, Y + 560, 100, 40, 27, "s:bezierDivisor", 1, g, 1)
	_btn(X + 110, Y + 560, 100, 40, "DRAW", 27, "_kb", ["drawBezier"], g)
	_label(X + 0, Y + 80, 175, 30, "Rotate by Degrees:", 30, g, false)
	_label(X + 0, Y + 160, 100, 30, "Scale by Percent:", 30, g, false)
	_label(X + 0, Y + 530, 100, 30, "Draw Bezier with Divisor:", 30, g, false)
	# auto mapper
	_label(X + 370, Y + 20, 175, 30, "Auto Mapper:", 30, g, false)
	_btn(X + 370, Y + 50, 175, 40, "AUTO MAP", 27, "_auto_map", [], g)
	_label(X + 370, Y + 110, 175, 30, "Density %:", 30, g, false)
	_number_box(X + 370, Y + 140, 120, 40, 27, "s:autoMapDensity", 10, g, 10, 400)
	am_stars_label = _label(X + 370, Y + 200, 175, 30, "", 30, g, false)
	_slider(X + 370, Y + 230, 175, 32, "autoMapStarsSlider", 140, 1, 40, g)
	am_stats_label = _label(X + 370, Y + 280, 175, 90, "", 24, g, false)
	_btn(X + 370, Y + 380, 175, 40, "LEARN FROM MAPS", 27, "_auto_map_learn", [], g)
	_btn(X + 370, Y + 430, 175, 40, "RESET LEARNING", 27, "_auto_map_reset", [], g)
	_label(X + 370, Y + 480, 175, 30, "Notes (0 = Auto):", 26, g, false)
	_number_box(X + 370, Y + 510, 140, 40, 27, "s:autoMapCount", 10, g, 0, 100000)
	am_quantum_label = _label(X + 370, Y + 560, 175, 30, "", 30, g, false)
	_slider(X + 370, Y + 590, 175, 32, "s:autoMapQuantumPct", 100, 1, 0, g)
	_btn(X + 370, Y + 640, 175, 40, "MORE OPTIONS", 27, "_auto_map_options", [], g)
	am_similar_label = _label(X + 0, Y + 630, 175, 30, "", 30, g, false)
	_slider(X + 0, Y + 665, 210, 32, "s:autoMapSimilarity", 100, 1, 0, g)

	# ------------------------------------------------ Playtest (Chromia's own player settings)
	g = "PLAYTEST"
	_dropdown(X + 0, Y + 50, 150, 40, 27, CAMERA_MODES, "cameraMode", g)
	_numeric(X + 175, Y + 50, 100, 40, 31, "p:noteScale", g, true)
	_numeric(X + 300, Y + 50, 100, 40, 31, "p:cursorScale", g, true)
	_check(X + 0, Y + 110, "Lock Cursor Within Grid", 27, "p:lockCursor", g)
	_check(X + 0, Y + 160, "Grid Guides", 27, "p:gridGuides", g)
	_numeric(X + 0, Y + 240, 115, 40, 31, "p:sensitivity", g, true)
	_numeric(X + 135, Y + 240, 115, 40, 31, "p:parallax", g, true)
	_numeric(X + 270, Y + 240, 115, 40, 31, "p:fov", g, true)
	_numeric(X + 0, Y + 325, 150, 40, 31, "p:approachDistance", g, true)
	_numeric(X + 235, Y + 325, 150, 40, 31, "p:hitWindow", g, true)
	_slider(X + 0, Y + 410, 400, 32, "playerAR", 149, 1, 39, g)
	_check(X + 0, Y + 460, "Approach Fade", 27, "approachFade", g)
	_btn(X + 0, Y + 520, 200, 40, "PLAY FROM START", 27, "_playtest", [true], g)
	_btn(X + 210, Y + 520, 200, 40, "PLAY HERE", 27, "_playtest", [false], g)
	_label(X + 0, Y + 20, 100, 30, "Camera Mode:", 30, g, false)
	_label(X + 175, Y + 20, 100, 30, "Note Size:", 30, g, false)
	_label(X + 300, Y + 20, 100, 30, "Cursor Size:", 30, g, false)
	_label(X + 0, Y + 210, 100, 30, "Sensitivity:", 30, g, false)
	_label(X + 135, Y + 210, 100, 30, "Parallax:", 30, g, false)
	_label(X + 270, Y + 210, 100, 30, "FOV:", 30, g, false)
	_label(X + 0, Y + 295, 100, 30, "Approach Distance:", 30, g, false)
	_label(X + 235, Y + 295, 100, 30, "Hit Window:", 30, g, false)
	player_ar_label = _label(X + 0, Y + 380, 400, 32, "", 30, g)

	# ------------------------------------------------ Snapping (1365, 222)
	X = 1365
	g = "SNAPPING"
	_check(X + 245, Y + 10, "Quantum", 27, "s:enableQuantum", g, 545)
	_check(X + 245, Y + 50, "Snap to Grid", 27, "s:quantumGridSnap", g, 545)
	_check(X + 245, Y + 90, "Auto-Advance", 27, "s:autoAdvance", g, 545)
	var bd = _slider(X + 245, Y + 170, 250, 32, "beatDivisor", 31, 0.5, 3, g)
	bd.shift_increment = 0.5
	_slider(X + 245, Y + 240, 250, 32, "s:quantumSnapping", 57, 1, 0, g)
	beat_div_label = _label(X + 245, Y + 140, 250, 32, "", 30, g)
	snapping_label = _label(X + 245, Y + 210, 250, 32, "", 30, g)
	qx_slider = _slider(X + 245, Y + 310, 250, 32, "s:quantumXOffset", 2, 0.05, 1, g)
	qy_slider = _slider(X + 245, Y + 380, 250, 32, "s:quantumYOffset", 2, 0.05, 1, g)
	qx_label = _label(X + 245, Y + 280, 250, 32, "", 30, g)
	qy_label = _label(X + 245, Y + 350, 250, 32, "", 30, g)

	# ------------------------------------------------ Graphics
	g = "GRAPHICS"
	_check(X + 245, Y + 10, "Autoplay", 26, "s:autoplay", g, 545)
	_check(X + 245, Y + 90, "Approach Squares", 26, "s:approachSquares", g, 545)
	_check(X + 245, Y + 130, "Grid Numbers", 26, "s:gridNumbers", g, 545)
	_check(X + 245, Y + 170, "Grid Letters", 26, "s:gridLetters", g, 545)
	_check(X + 245, Y + 210, "Quantum Grid Lines", 26, "s:quantumGridLines", g, 545)
	_slider(X + 245, Y + 290, 250, 32, "s:approachRate", 29, 1, 14, g)
	_slider(X + 245, Y + 370, 250, 32, "s:cursorPos", 100, 1, 40, g)
	ar_label = _label(X + 245, Y + 260, 250, 32, "", 28, g)
	cursor_pos_label = _label(X + 245, Y + 340, 250, 32, "", 28, g)
	_check(X + 245, Y + 50, "Smooth Autoplay Cursor", 26, "s:smoothAutoplay", g, 545)
	_check(X + 0, Y + 10, "3D Mode", 26, "s:mode3D", g, 240)
	_check(X + 0, Y + 50, "3D Hit Effect", 26, "s:mode3DHitEffect", g, 240)
	grid3d_label = _label(X + 0, Y + 100, 230, 32, "", 26, g)
	_slider(X + 0, Y + 130, 230, 32, "s:grid3DOpacity", 255, 1, 80, g)
	grid_zoom_label = _label(X + 0, Y + 180, 230, 32, "", 26, g)
	_slider(X + 0, Y + 210, 230, 32, "gridZoomSlider", 150, 5, 50, g)
	note_size_label = _label(X + 0, Y + 260, 230, 32, "", 26, g)
	_slider(X + 0, Y + 290, 230, 32, "noteSizeSlider", 175, 5, 75, g)

	# ------------------------------------------------ Export
	g = "EXPORT"
	_btn(X + 275, Y + 20, 100, 40, "SAVE", 27, "_kb", ["save"], g)
	_btn(X + 385, Y + 20, 100, 40, "SAVE AS", 27, "_kb", ["saveAs"], g)
	_dropdown(X + 255, Y + 90, 250, 40, 27, EXPORT_TYPES, "exportType", g, "Export: ")
	_btn(X + 275, Y + 140, 210, 40, "EXPORT MAP", 27, "_export_map", [], g)
	replace_id_box = _textbox(X + 275, Y + 230, 210, 40, 27, g)
	_btn(X + 275, Y + 280, 210, 40, "REPLACE", 27, "_replace_id", [], g)
	_btn(X + 275, Y + 350, 210, 40, "CONVERT TO MP3", 27, "_convert_mp3", [], g)
	_label(X + 275, Y + 190, 210, 40, "Replace Audio ID", 30, g)
	_btn(X + 0, Y + 20, 210, 40, "CALCULATE SR/RP", 27, "_calc_sr", [], g)
	sr_label = _label(X + 10, Y + 70, 190, 320, "", 28, g, false)
	sr_label.valign = Label.VALIGN_TOP
	sr_label.autowrap = true

	# ------------------------------------------------ extra objects
	g = "special"
	for it in [["Beats", 0], ["Mines", 40], ["Glides", 80], ["Lyrics", 120], ["Fevers", 160], ["Modify Notes", 668]]:
		special_buttons[it[0]] = _btn(10, 232 + it[1], 150, 30, it[0], 26, "_on_special_mode", [it[0]], "special_nova")
	lyric_box = _textbox(175, 232, 370, 30, 26, "lyric")
	lyric_box.connect("text_entered", self, "_on_lyric_entered")
	_check(175, 232 + 40, "Fade In", 26, "lyricFadeIn", "lyric", 545)
	_check(175, 232 + 80, "Fade Out", 26, "lyricFadeOut", "lyric", 545)
	lyric_create = _btn(175, 232 + 120, 370, 30, "CREATE", 26, "_create_lyric", [], "lyric")
	var info := _label(175, 232 + 160, 370, 400, "Lyric usage:\n> \"-\" prefix: Replace previous line\n> \"-\" suffix: Apply next lyric as a syllable\n    (Without a space in between)\n> Press 'Enter' in the lyric textbox to quickly place a lyric", 20, "lyric", false)
	info.valign = Label.VALIGN_TOP
	_check(175, 232, "Enable Easing", 26, "easingOn", "notenav", 545)
	_dropdown(175, 232 + 80, 370, 30, 26, ["In", "Out"], "easingDirection", "notenav", "Easing Direction: ")
	_dropdown(175, 232 + 40, 370, 30, 26, SSQEMap.EASING_STYLES, "easingStyle", "notenav", "Easing Style: ")
	_btn(175, 232 + 160, 370, 30, "Apply Modifications", 26, "_apply_note_mods", [], "notenav")
	var gs := _btn(10, 946, 545, 50, "", 31, "_cycle_game", [], "special")
	gs.set_meta("game_switch", true)
	_btn(10, 172, 545, 50, "CLOSE EXTRA OBJECTS", 31, "_set_special", [false], "special")
	lyric_preview = _label(0, 860, 1920, 56, "", 48, "lyricpreview", true, "color2")

	# ------------------------------------------------ main controls
	copy_button = _btn(810, 273, 300, 42, "COPY MAP DATA", 27, "_copy_map_data")
	back_button = _btn(810, 774, 300, 42, "BACK TO MENU", 27, "_back")
	var tempo = _slider(1408, 1016, 512, 64, "tempoSlider", 1.4, 0.05, 0.9)
	tempo.set_meta("tempo", true)
	ed.timeline = load("res://scripts/editor/ssqe/SSQETimeline.gd").new()
	ed.timeline.ed = ed
	_add(ed.timeline, 0, 1016, 1344, 64, 0)
	_slider(1856, 760, 40, 256, "masterVolume", 1, 0.01, 0.25, "", true)
	_slider(1792, 760, 40, 256, "s:sfxVolume", 1, 0.01, 0.25, "", true)
	var Icon = load("res://scripts/editor/ssqe/SSQEIcon.gd")
	music_mute = Icon.new()
	music_mute.kind = "mute"
	music_mute.key = "muteMusic"
	music_mute.ed = ed
	_add(music_mute, 1866, 744, 20, 20, 0, "", "")
	sfx_mute = Icon.new()
	sfx_mute.kind = "mute"
	sfx_mute.key = "muteSfx"
	sfx_mute.ed = ed
	_add(sfx_mute, 1802, 744, 20, 20, 0, "", "")
	play_pause = Icon.new()
	play_pause.kind = "play"
	play_pause.ed = ed
	_add(play_pause, 1344, 1016, 64, 64, 0, "", "")

	toast_label = _label(0, 1000, 1920, 64, "", 42)
	toast_label.modulate.a = 0
	_label(565, 172, 80, 30, "Zoom:", 32, "", false)
	zoom_value_label = _label(640, 172, 80, 30, "", 32, "", false, "color2")
	click_mode_label = _label(810, 816, 300, 42, "", 30)
	tempo_label = _label(1408, 1048, 512, 30, "", 30)
	_label(1856, 720, 40, 30, "Music", 24)
	music_value_label = _label(1856, 996, 40, 30, "", 24)
	_label(1792, 720, 40, 30, "SFX", 24)
	sfx_value_label = _label(1792, 996, 40, 30, "", 24)
	current_time_label = _label(0, 1048, 64, 32, "", 26)
	current_ms_label = _label(0, 1012, 32, 32, "", 26)
	total_time_label = _label(1280, 1048, 64, 32, "", 26)
	notes_label = _label(0, 1048, 1344, 32, "", 30)

	# phones: buttons for the shortcuts (the web editor's touch bar)
	if Rhythia.device("mobile"):
		var acts := [["UNDO", "undo"], ["REDO", "redo"], ["SELECT ALL", "selectAll"], ["COPY", "copy"], ["CUT", "cut"],
			["PASTE", "paste"], ["DELETE", "delete"], ["SAVE", "save"]]
		var tw := (790.0 - 6 * (acts.size() - 1)) / acts.size()
		for i in range(acts.size()):
			touch_bar.append(_btn(565 + i * (tw + 6), 946, tw, 50, acts[i][0], 20, "_kb", [acts[i][1]], "touch"))
	_update_nav_text()
	refresh_values()

func on_map_opened():
	if replace_id_box:
		replace_id_box.text = ""
	if special_on:
		_set_special(false)
	refresh_values()

# ================================================================== layout

func layout():
	var mn: float = min(ed.wd, ed.hd)
	for it in items:
		var n: Control = it.node
		var r: Rect2 = ed.stage_rect(it.x, it.y, it.w, it.h, it.stretch)
		n.rect_position = r.position
		n.rect_size = r.size
		if it.ts > 0:
			var f: DynamicFont = ed.text_font(it.ts, mn)
			# (a button's text shrinks to fit, as SSQE's narrower font would)
			if n is Button and not n is CheckBox and not n is OptionButton and n.text != "":
				var avail: float = r.size.x - 6
				var tw: float = f.get_string_size(n.text).x
				if tw > avail and tw > 0:
					f = ed.font(int(max(6, floor(f.size * avail / tw))))
			n.add_font_override("font", f)
			if n is OptionButton:
				n.get_popup().add_font_override("font", f)
			elif n is SpinBox:
				n.get_line_edit().add_font_override("font", f)
	_layout_grid_buttons()
	_apply_visibility()

# Grid Zoom moves the buttons above and below the grid with it
func _layout_grid_buttons():
	var size := 300.0 * clamp(float(ed.s.gridZoom) / 100.0, 0.5, 2.0)
	var top := 540.0 - size / 2
	var bottom := 540.0 + size / 2
	var cy := top - 117
	var by := bottom + 84
	var ly := bottom + 126
	if top - 117 < 175:
		cy = bottom + 16
		by = bottom + 64
		ly = bottom + 108
	for it in items:
		if it.node == copy_button:
			it.y = cy
		elif it.node == back_button:
			it.y = by
		elif it.node == click_mode_label:
			it.y = ly
		else:
			continue
		var r: Rect2 = ed.stage_rect(it.x, it.y, it.w, it.h, it.stretch)
		it.node.rect_position = r.position
		it.node.rect_size = r.size

func _group_visible(g: String) -> bool:
	match g:
		"":
			return true
		"standard":
			return not special_on
		"OPTIONS", "TIMING", "PATTERNS", "PLAYTEST":
			return not special_on and left_nav == g
		"SNAPPING", "GRAPHICS", "EXPORT":
			return right_nav == g
		"special":
			return special_on
		"special_nova":
			return special_on and SSQEMap.ss(ed.s.modchartGame) == "Novastra"
		"lyric":
			return special_on and special_mode == "Lyrics"
		"notenav":
			return special_on and special_mode == "Modify Notes"
		"lyricpreview":
			return special_on and (special_mode == "Lyrics" or special_mode == "")
		"fever":
			return false
		"touch":
			return true
	return true

func _apply_visibility():
	for it in items:
		var vis := _group_visible(it.group)
		if it.node == qx_slider or it.node == qy_slider or it.node == qx_label or it.node == qy_label:
			vis = vis and not ed.s.oldQuantumSnap
		it.node.visible = vis

func _update_nav_text():
	for k in nav_buttons:
		var on: bool = k == left_nav or k == right_nav
		nav_buttons[k].text = ("[%s]" % k) if on else k
	for k in special_buttons:
		special_buttons[k].text = ("[%s]" % k) if k == special_mode else k

# ================================================================== per frame (GuiWindowEditor.Render)

var _refreshing := false
var _refresh_t := 0
func refresh_values():
	if ed.map == null:
		return
	_refreshing = true
	var focus = ed.get_focus_owner()
	for it in items:
		var key: String = it.bind.get("key", "")
		if key == "":
			continue
		var n = it.node
		match it.kind:
			"check":
				var v := bool(get_value(key))
				if n.pressed != v:
					n.pressed = v
			"numeric":
				if n != focus:
					var v2 = get_value(key)
					var t: String = SSQEMap.fmt(float(v2)) if it.bind.get("float", false) else str(int(v2))
					if n.text != t:
						n.text = t
			"numberbox":
				if n.get_line_edit() != focus:
					var v3 := float(get_value(key))
					if n.value != v3:
						n.value = v3
			"slider":
				if not n.dragging:
					var v4 := float(get_value(key))
					if n.value != v4:
						n.value = v4
						n.update()
			"dropdown":
				var v5 := SSQEMap.ss(get_value(key))
				var opts: Array = it.bind.options
				var i := opts.find(v5)
				if i >= 0 and n.selected != i:
					n.select(i)
	_refreshing = false

func update():
	var s: Dictionary = ed.s
	var map = ed.map
	if map == null:
		return
	_refresh_t += 1
	if _refresh_t % 6 == 0:
		refresh_values()
		if _player_dirty:
			_player_dirty = false
			Rhythia.save_settings()
	var t: float = ed.current_time()
	var total: float = ed.total_time()
	zoom_value_label.text = "%d%%" % int(round(map.zoom * 100))
	var mode: String = ed.click_mode()
	click_mode_label.text = "Click: " + ("Select" if mode == "select" else "Place")
	click_mode_label.visible = mode != "both"
	beat_div_label.text = "Beat Divisor: " + SSQEMap.fmt(round(map.beat_divisor * 10) / 10 + 1)
	snapping_label.text = "Quantum Divisor: %d" % int(round(float(s.quantumSnapping) + 3))
	qx_label.text = "Quantum X Offset: " + SSQEMap.fmt(round((float(s.quantumXOffset) - 1) * 100) / 100)
	qy_label.text = "Quantum Y Offset: " + SSQEMap.fmt(round((float(s.quantumYOffset) - 1) * 100) / 100)
	ar_label.text = "Approach Rate: %d" % int(round(float(s.approachRate) + 1))
	player_ar_label.text = "Player Approach Rate: %d" % int(round(float(Rhythia.approach_rate)))
	cursor_pos_label.text = "Cursor Position: %d%%" % int(abs(round(float(s.cursorPos))))
	grid3d_label.text = "3D Grid Opacity: %d%%" % int(round(float(s.grid3DOpacity) / 255.0 * 100))
	grid_zoom_label.text = "Grid Zoom: %d%%" % int(s.gridZoom)
	note_size_label.text = "Note Size: %d%%" % int(s.gridNoteSize)
	tempo_label.text = "PLAYBACK SPEED - %d%%" % int(round(map.tempo() * 100))
	music_value_label.text = str(int(abs(round(float(s.masterVolume) * 100))))
	sfx_value_label.text = str(int(abs(round(float(s.sfxVolume) * 100))))
	am_stars_label.text = "Stars: %.1f" % float(s.autoMapStars)
	am_quantum_label.text = "Quantum: %d%%" % int(round(float(s.autoMapQuantumPct)))
	am_similar_label.text = "Auto Map Like This Map: %d%%" % int(round(float(s.autoMapSimilarity)))
	am_stats_label.text = ed.page.auto_map_stats_text() if ed.page and ed.page.has_method("auto_map_stats_text") else ""
	current_time_label.text = _fmt_time(t)
	total_time_label.text = _fmt_time(total)
	# the ms label follows the timeline's marker
	var tr: Rect2 = ed.stage_rect(0, 1016, 1344, 64)
	var progress := t / total if total > 0 else 0.0
	current_ms_label.text = _comma(int(t)) + "ms"
	var mr: Vector2 = current_ms_label.rect_size
	current_ms_label.rect_position.x = tr.position.x + tr.size.y / 2 + (tr.size.x - tr.size.y) * progress - mr.x / 2
	match map.render_mode:
		RM.NOTES:
			notes_label.text = "%s Notes" % _comma(map.notes.items.size())
		RM.VFX:
			notes_label.text = "%s Objects" % _comma(map.vfx_objects.items.size())
		_:
			notes_label.text = "%s Objects" % _comma(map.special_objects.items.size())
	# game switch text
	for it in items:
		if it.node.has_meta("game_switch"):
			it.node.text = "GAME: " + SSQEMap.ss(s.modchartGame)
	# lyrics / fever previews
	if special_on:
		var lp := _group_visible("lyricpreview")
		lyric_preview.visible = lp
		if lp:
			var sel: Array = map.special_objects.selected
			lyric_create.text = "EDIT" if sel.size() == 1 else "CREATE"
			var r: Array = ed.lyric_preview()
			lyric_preview.text = r[0]
			lyric_preview.modulate.a = r[1]
		var sl = null
		if map.special_objects.selected.size() == 1 and map.special_objects.selected[0].id == 15:
			sl = map.special_objects.selected[0]
		if sl and sl != ed.last_selected_lyric:
			lyric_box.text = sl.text
			lyric_fade_in = sl.fade_in
			lyric_fade_out = sl.fade_out
		ed.last_selected_lyric = sl
		var sn = null
		if map.object_mode == SSQEMap.OBJ_NOTE and not map.notes.selected.empty():
			sn = map.notes.selected[0]
		if sn and sn != ed.last_selected_note:
			easing_on = sn.enable_easing
			easing_style = sn.style
			easing_direction = min(sn.direction, 1)
		ed.last_selected_note = sn
		var fv := false
		if map.object_mode == SSQEMap.OBJ_DISABLED or map.object_mode == SSQEMap.OBJ_FEVER:
			for o in map.special_objects.items:
				if o.id == 16 and t >= o.ms and t <= o.ms + o.duration:
					fv = true
					break
		fever_preview.visible = fv
	else:
		fever_preview.visible = false
	# background
	background.color = Color(30 / 255.0, 30 / 255.0, 30 / 255.0, float(s.editorBGOpacity) / 255.0)
	# toast
	if toast_t > 0:
		toast_t -= ed.get_process_delta_time()
		toast_label.modulate.a = clamp(toast_t / 0.5, 0, 1)

func show_toast(text: String, c: Color):
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.add_color_override("font_color", c)
	toast_t = 2.0
	toast_label.modulate.a = 1

static func _fmt_time(ms: float) -> String:
	var t := int(max(ms, 0))
	return "%d:%02d" % [t / 60000, (t % 60000) / 1000]

static func _comma(n: int) -> String:
	var neg := n < 0
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out

# ================================================================== actions

func _kb(bind: String):
	ed.run_keybind(bind)

func _on_left_nav(name: String):
	left_nav = "" if left_nav == name else name
	ed.s.lastLeftNav = left_nav
	ed.settings_changed()
	_update_nav_text()
	_apply_visibility()

func _on_right_nav(name: String):
	right_nav = "" if right_nav == name else name
	ed.s.lastRightNav = right_nav
	ed.settings_changed()
	_update_nav_text()
	_apply_visibility()

func _set_special(on: bool):
	special_on = on
	special_mode = ""
	ed.set_special(on)

func on_special_changed(on: bool):
	special_on = on
	special_mode = ""
	_update_nav_text()
	_apply_visibility()

const OBJ_MODES = {"Beats": 12, "Mines": 14, "Glides": 13, "Lyrics": 15, "Fevers": 16, "Modify Notes": 1}
func _on_special_mode(name: String):
	special_mode = "" if special_mode == name else name
	ed.map.object_mode = OBJ_MODES.get(special_mode, SSQEMap.OBJ_DISABLED)
	ed.map.clear_selected()
	_update_nav_text()
	_apply_visibility()

func _cycle_game():
	var i := GAMES.find(SSQEMap.ss(ed.s.modchartGame))
	ed.s.modchartGame = GAMES[(i + 1) % GAMES.size()]
	ed.settings_changed()
	_apply_visibility()

func _on_lyric_entered(text: String):
	_create_lyric()
	lyric_box.grab_focus()

func _create_lyric():
	var map = ed.map
	var text := lyric_box.text
	var sel: Array = map.special_objects.selected
	if sel.size() == 1 and sel[0].id == 15:
		map.special_objects.edit("EDIT LYRIC", [sel[0]], self, "_edit_lyric", [text, lyric_fade_in, lyric_fade_out])
	else:
		var ms: float = ed.closest_beat(ed.current_time())
		ms = int(clamp(ms if ms >= 0 else ed.current_time(), 0, ed.total_time()))
		map.special_objects.add_objects("ADD LYRIC", SSQEMap.lyric(int(ms), text, lyric_fade_in, lyric_fade_out))
		if ed.s.autoAdvance:
			ed.advance()
	map.clear_selected()
	lyric_box.text = ""
	lyric_fade_in = false
	lyric_fade_out = false

func _edit_lyric(n, text: String, fi: bool, fo: bool):
	n.text = text
	n.fade_in = fi
	n.fade_out = fo

func _apply_note_mods():
	ed.map.notes.edit("MODIFY NOTE[S]", null, self, "_mod_note", [easing_on, easing_style, easing_direction])

func _mod_note(n, on: bool, st: int, di: int):
	n.enable_easing = on
	n.style = st
	n.direction = di

func _rotate():
	ed.rotate_notes(float(ed.s.rotateBy))

func _scale():
	ed.scale_notes(float(ed.s.scaleBy))

func _clear_nodes():
	ed.clear_nodes()

func _copy_bookmarks():
	var text: String = ed.map.copy_bookmarks_text()
	if text != "":
		OS.clipboard = text
		ed.toast("COPIED TO CLIPBOARD", "other")

func _paste_bookmarks():
	var n: int = ed.map.paste_bookmarks_text(OS.clipboard)
	if n == 0:
		ed.toast("NO BOOKMARKS TO PASTE (\"ms ~ text\" PER LINE)", "warn")

func _copy_map_data():
	OS.clipboard = F.write_txt(ed.map, bool(ed.s.correctOnCopy))
	ed.toast("COPIED TO CLIPBOARD")

func _back():
	if ed.page:
		ed.page.close_project()

func _playtest(from_start: bool):
	if ed.page:
		ed.page.playtest(from_start)

func _detect_bpm():
	if ed.page:
		ed.page.detect_bpm_to_map()

func _import_ini():
	if ed.page:
		ed.page.import_ini()

func _export_map():
	var t := SSQEMap.ss(ed.s.exportType)
	if t == EXPORT_TYPES[0]:
		ed.dialogs.export_sspm("sspm")
	elif t == EXPORT_TYPES[1]:
		ed.dialogs.export_sspm("rhm")
	elif t == EXPORT_TYPES[2]:
		ed.dialogs.export_phxm()
	else:
		ed.dialogs.message("Novastra maps (.npk) can't be made in Chromia. Export to SSPM, Rhythia or Rewrite instead.")

func _replace_id():
	var id := replace_id_box.text.strip_edges()
	if id == "":
		return
	ed.dialogs.confirm("Are you sure you want to replace this ID?\nIf an asset exists with this ID, it will be overwritten.", self, "_do_replace_id", [id])

func _do_replace_id(answer: String, id: String):
	if answer != "yes":
		return
	ed.map.sound_id = id
	ed.on_map_changed()
	ed.toast("REPLACED AUDIO ID WITH " + id)

func _convert_mp3():
	if ed.page:
		ed.page.convert_to_mp3()

func _calc_sr():
	var SR = load("res://scripts/editor/ssqe/SSQEStarRating.gd")
	var notes := []
	for n in ed.map.notes.items:
		notes.append([n.x, n.y, n.ms])
	var sr: float = SR.rate(notes)
	sr_label.text = "SR: %s\n\n(worked out here, with Rhythia's formula; RP needs Rhythia's server)" % SSQEMap.fmt(sr)

func _auto_map():
	if ed.page:
		ed.page.auto_map()

func _auto_map_learn():
	if ed.page:
		ed.page.auto_map_learn()

func _auto_map_reset():
	if ed.page:
		ed.page.auto_map_reset()

func _auto_map_options():
	ed.dialogs.auto_map_options()
