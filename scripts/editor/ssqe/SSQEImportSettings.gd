extends Reference

# Import your Sound Space Quantum Editor Plus settings (editor Settings >
# Other > Import SSQE+ settings): a setup file (.ssqes, SSQE+'s EXPORT SETUP:
# {format: "ssqes", settings: {editor, player}, assets, learned}), the desktop
# editor's settings.txt (next to "Sound Space Quantum Editor.exe") or the web
# editor's saved settings (the JSON in its localStorage).
#
# Desktop values (SSQE+ Preferences/SettingsManager.cs): colours [R,G,B,A],
# keybinds ["KeyName", ctrl, shift, alt] with OpenTK key names, sliders
# [value, max, step], lists as their text, gridKeys 9 key names. Web: colours
# [R,G,B], keybinds {key: "KeyA", ctrl, alt, shift} with KeyboardEvent codes.
# The in-game editor keeps keybinds as [scancode, ctrl, alt, shift].
#
# Not imported: what belongs to one map (beat divisor, tempo, export offset,
# the last map's details), paths on that computer, and what the game does its
# own way (VSync, FPS limits, updates, Discord). The playtest settings go to
# the game's own settings (they are the game's), like the Playtest panel's.

const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")

# same name and meaning
const BOOLS := ["waveform", "classicWaveform", "correctOnCopy", "gridNumbers", "approachSquares", "autoplay",
	"numpad", "quantumGridLines", "quantumGridSnap", "metronome", "separateClickTools", "enableQuantum",
	"autoAdvance", "selectTool", "curveBezier", "gridLetters", "reverseScroll", "applyOnPaste", "jumpPaste",
	"pauseScroll", "clampSR", "pasteReversed", "adjustNotes", "monoAudio", "muteSfx", "muteMusic",
	"smoothAutoplay", "gridSquircles", "controlGradients", "oldQuantumSnap", "scaleMetronome", "moveOnGridKey",
	"mode3D", "mode3DHitEffect", "useVSync", "limitPlayerFPS", "lowerBackgroundFPS", "msaa", "skipDownload",
	"checkUpdates", "fullscreenPlayer"]
const NUMBERS := ["editorBGOpacity", "gridOpacity", "trackOpacity", "waveformDetail", "sfxOffset", "musicOffset",
	"bezierDivisor", "gridSquircleDetail", "gridSquircleRadius", "maxPolyphony", "gridZoom", "gridNoteSize",
	"rotateBy", "scaleBy", "grid3DOpacity", "fontScale", "fpsLimit"]
# sliders: [value, max, step] on the desktop, a number on the web
const SLIDERS := ["cursorPos", "approachRate", "quantumSnapping", "quantumXOffset", "quantumYOffset",
	"masterVolume", "sfxVolume"]
const STRINGS := ["modchartGame", "exportType"]
const COLORS := ["color1", "color2", "color3", "color4", "color5"]
# the playtest settings: the game's own (SSQEPanels.PLAYER_KEYS)
const PLAYER := {"noteScale": "note_size", "cursorScale": "cursor_scale", "lockCursor": "lock_mouse",
	"gridGuides": "enable_grid", "sensitivity": "sensitivity", "parallax": "parallax", "fov": "fov",
	"approachDistance": "spawn_distance", "hitWindow": "hitwindow_ms"}

# OpenTK key names (desktop) and KeyboardEvent codes (web) -> Godot scancodes
static func scancode(name: String) -> int:
	var n := name.strip_edges()
	if n == "":
		return 0
	var l := n.to_lower()
	# web codes
	if l.begins_with("key") and n.length() == 4:
		return OS.find_scancode_from_string(n.substr(3).to_upper())
	if l.begins_with("digit") and n.length() == 6:
		return KEY_0 + int(n.substr(5))
	if l.begins_with("numpad") and n.length() == 7 and n.substr(6).is_valid_integer():
		return KEY_KP_0 + int(n.substr(6))
	if l.begins_with("arrow"):
		l = l.substr(5)
	# desktop names
	if n.length() == 1:
		return OS.find_scancode_from_string(n.to_upper())
	if l.begins_with("d") and n.length() == 2 and n.substr(1).is_valid_integer():
		return KEY_0 + int(n.substr(1))
	if l.begins_with("keypad") and n.length() == 7 and n.substr(6).is_valid_integer():
		return KEY_KP_0 + int(n.substr(6))
	if l.begins_with("f") and n.substr(1).is_valid_integer():
		return KEY_F1 + int(n.substr(1)) - 1
	var named := {
		"delete": KEY_DELETE, "backspace": KEY_BACKSPACE, "tab": KEY_TAB, "space": KEY_SPACE,
		"enter": KEY_ENTER, "escape": KEY_ESCAPE, "left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP,
		"down": KEY_DOWN, "home": KEY_HOME, "end": KEY_END, "pageup": KEY_PAGEUP, "pagedown": KEY_PAGEDOWN,
		"insert": KEY_INSERT, "minus": KEY_MINUS, "equal": KEY_EQUAL, "comma": KEY_COMMA, "period": KEY_PERIOD,
		"slash": KEY_SLASH, "semicolon": KEY_SEMICOLON, "apostrophe": KEY_APOSTROPHE, "quote": KEY_APOSTROPHE,
		"leftbracket": KEY_BRACKETLEFT, "bracketleft": KEY_BRACKETLEFT, "rightbracket": KEY_BRACKETRIGHT,
		"bracketright": KEY_BRACKETRIGHT, "backslash": KEY_BACKSLASH, "graveaccent": KEY_QUOTELEFT,
		"backquote": KEY_QUOTELEFT, "keypadenter": KEY_KP_ENTER, "numpadenter": KEY_KP_ENTER,
		"keypadadd": KEY_KP_ADD, "numpadadd": KEY_KP_ADD, "keypadsubtract": KEY_KP_SUBTRACT,
		"numpadsubtract": KEY_KP_SUBTRACT, "keypadmultiply": KEY_KP_MULTIPLY, "numpadmultiply": KEY_KP_MULTIPLY,
		"keypaddivide": KEY_KP_DIVIDE, "numpaddivide": KEY_KP_DIVIDE, "keypaddecimal": KEY_KP_PERIOD,
		"numpaddecimal": KEY_KP_PERIOD,
	}
	if named.has(l):
		return named[l]
	return OS.find_scancode_from_string(n)

static func _num(v):
	if v is Array and v.size() > 0:
		v = v[0]
	if typeof(v) == TYPE_REAL or typeof(v) == TYPE_INT:
		return float(v)
	if v is String and v.is_valid_float():
		return float(v)
	return null

static func _color(v):
	if not (v is Array) or v.size() < 3:
		return null
	var out := []
	for i in 3:
		var n = _num(v[i])
		if n == null:
			return null
		out.append(int(clamp(n, 0, 255)))
	return out

# a keybind -> [scancode, ctrl, alt, shift] or null (Backspace is Delete, as
# in SSQE+ and the in-game editor: compare_keybind)
static func _keybind(v):
	var b = _keybind_raw(v)
	if b != null and int(b[0]) == KEY_BACKSPACE:
		b[0] = KEY_DELETE
	return b

static func _keybind_raw(v):
	if v is Array and v.size() >= 4 and v[0] is String:
		var code := scancode(v[0])
		# desktop order: key, CTRL, SHIFT, ALT
		return [code, bool(v[1]), bool(v[3]), bool(v[2])] if code != 0 else null
	if v is Dictionary and v.get("key") is String:
		var code2 := scancode(v.key)
		return [code2, bool(v.get("ctrl", false)), bool(v.get("alt", false)), bool(v.get("shift", false))] if code2 != 0 else null
	return null

# Reads `text` into the editor settings `s` (and the game's playtest
# settings). -> {ok, count, notes} | {ok: false, error}
static func import_text(text: String, s: Dictionary) -> Dictionary:
	var p := JSON.parse(text.strip_edges().trim_prefix("﻿"))
	if p.error != OK or not (p.result is Dictionary):
		return {"ok": false, "error": "That isn't an SSQE+ settings file (settings.txt is JSON)."}
	var d: Dictionary = p.result
	var notes := []
	# a setup file (.ssqes): the editor's settings with the player's in them
	if String(d.get("format", "")) == "ssqes" and d.get("settings") is Dictionary:
		var st: Dictionary = d.settings
		var merged := {}
		if st.get("player") is Dictionary:
			for k in st.player:
				merged[k] = st.player[k]
		if st.get("editor") is Dictionary:
			for k in st.editor:
				merged[k] = st.editor[k]
			# (the player's own colours / volumes are the map player's, not the editor's)
		if st.get("player") is Dictionary:
			for k in ["noteScale", "cursorScale", "lockCursor", "gridGuides", "sensitivity", "parallax", "fov",
					"approachDistance", "hitWindow", "playerApproachRate", "approachFade", "cameraMode"]:
				if st.player.has(k):
					merged[k] = st.player[k]
		d = merged
	var known := 0
	for k in d:
		if s.has(k) or PLAYER.has(k) or k in ["enableAutosave", "noteColors", "gridKeys", "playerApproachRate", "cameraMode", "approachFade"]:
			known += 1
	if known < 3:
		return {"ok": false, "error": "That doesn't look like SSQE+'s settings (none of its settings are in it)."}
	var count := 0
	for k in BOOLS:
		if d.has(k) and typeof(d[k]) == TYPE_BOOL and s.has(k) and typeof(s[k]) == TYPE_BOOL:
			s[k] = d[k]
			count += 1
	for k in NUMBERS + SLIDERS:
		if d.has(k) and s.has(k) and typeof(s[k]) in [TYPE_INT, TYPE_REAL]:
			var n = _num(d[k])
			if n != null:
				s[k] = int(n) if typeof(s[k]) == TYPE_INT else n
				count += 1
	for k in STRINGS:
		if d.has(k) and d[k] is String and s.has(k):
			s[k] = d[k]
			count += 1
	if d.get("createGame") is String and s.has("createGame"):
		s.createGame = d.createGame
		count += 1
	if d.get("playtestGame") is String and s.has("playtestGame"):
		var g: String = d.playtestGame
		s.playtestGame = "Rhythia" if g.begins_with("Rhythia") else ("Novastra" if g.begins_with("Nova") else "Chromia")
		count += 1
	if d.has("buttonGradients") and typeof(d.buttonGradients) == TYPE_BOOL and not d.has("controlGradients"):
		s.controlGradients = d.buttonGradients
		count += 1
	if d.has("enableAutosave") and typeof(d.enableAutosave) == TYPE_BOOL:
		s.autosave = d.enableAutosave
		count += 1
	elif d.has("autosave") and typeof(d.autosave) == TYPE_BOOL:
		s.autosave = d.autosave
		count += 1
	if d.has("autosaveInterval"):
		var ai = _num(d.autosaveInterval)
		if ai != null:
			s.autosaveInterval = clamp(ai, 0.1, 60.0)
			count += 1
	for k in COLORS:
		var c = _color(d.get(k))
		if c != null:
			s[k] = c
			count += 1
	if d.get("noteColors") is Array and not d.noteColors.empty():
		var cols := []
		for c in d.noteColors:
			var cc = _color(c)
			if cc != null:
				cols.append(cc)
		if not cols.empty() and s.has("noteColors"):
			s.noteColors = cols
			if s.has("customNoteColors"):
				s.customNoteColors = true
			count += 1
	if d.get("patterns") is Array and d.patterns.size() == 10:
		var pats := []
		for x in d.patterns:
			pats.append(String(x) if x != null else "")
		s.patterns = pats
		count += 1
	var kb_n := 0
	for name in s.keybinds:
		if d.has(name):
			var b = _keybind(d[name])
			if b == null and d.get("keybinds") is Dictionary:
				b = _keybind(d.keybinds.get(name))
			if b != null:
				s.keybinds[name] = b
				kb_n += 1
		elif d.get("keybinds") is Dictionary and d.keybinds.has(name):
			var b2 = _keybind(d.keybinds[name])
			if b2 != null:
				s.keybinds[name] = b2
				kb_n += 1
	if kb_n > 0:
		count += kb_n
		notes.append("%d keybinds" % kb_n)
	if d.get("gridKeys") is Array and d.gridKeys.size() == 9:
		var gk := []
		for k in d.gridKeys:
			var code := scancode(String(k)) if k is String else 0
			if code == 0:
				gk = []
				break
			gk.append(code)
		if gk.size() == 9:
			s.gridKeys = gk
			count += 1
			notes.append("grid keys")
	# the playtest settings: the game's
	var played := 0
	for k in PLAYER:
		if not d.has(k):
			continue
		var cur = Rhythia.get(PLAYER[k])
		if typeof(cur) == TYPE_BOOL and typeof(d[k]) == TYPE_BOOL:
			Rhythia.set(PLAYER[k], d[k])
			played += 1
		else:
			var n2 = _num(d[k])
			if n2 != null and typeof(cur) in [TYPE_INT, TYPE_REAL]:
				Rhythia.set(PLAYER[k], n2 if k in ["noteScale", "cursorScale", "sensitivity", "parallax"] else max(n2, 0.0))
				played += 1
	if d.has("playerApproachRate"):
		var ar = _num(d.playerApproachRate)
		if ar != null:
			Rhythia.approach_rate = round(ar) + 1.0
			played += 1
	if d.has("approachFade") and typeof(d.approachFade) == TYPE_BOOL:
		Rhythia.fade_length = 0.5 if d.approachFade else 0.0
		played += 1
	if d.get("cameraMode") is String:
		match String(d.cameraMode).to_lower():
			"spin":
				Rhythia.cam_unlock = true
			"full lock":
				Rhythia.cam_unlock = false
				Rhythia.camera_mode = Globals.CAMERA_FULL_LOCK
			_:
				Rhythia.cam_unlock = false
				Rhythia.camera_mode = Globals.CAMERA_HALF_LOCK
		played += 1
	if played > 0:
		Rhythia.save_settings()
		notes.append("%d playtest settings" % played)
	count += played
	return {"ok": true, "count": count, "notes": notes}

static func import_file(path: String, s: Dictionary) -> Dictionary:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return {"ok": false, "error": "Couldn't open %s." % path.get_file()}
	if f.get_len() > 4 * 1024 * 1024:
		f.close()
		return {"ok": false, "error": "That file is too big to be SSQE+'s settings."}
	var text := f.get_as_text()
	f.close()
	return import_text(text, s)
