extends Reference
# The map editor's settings: Sound Space Quantum Editor Plus's editor settings
# (Web Editor/js/settings.js) with Chromia's colours. Saved in
# user://editor/ssqe_settings.json.

const PATH = "user://editor/ssqe_settings.json"

# key: [scancode, ctrl, alt, shift]
const KEYBINDS = {
	"selectAll": [KEY_A, true, false, false],
	"save": [KEY_S, true, false, false],
	"saveAs": [KEY_S, true, false, true],
	"undo": [KEY_Z, true, false, false],
	"redo": [KEY_Y, true, false, false],
	"copy": [KEY_C, true, false, false],
	"paste": [KEY_V, true, false, false],
	"cut": [KEY_X, true, false, false],
	"delete": [KEY_DELETE, false, false, false],
	"hFlip": [KEY_H, false, false, true],
	"vFlip": [KEY_V, false, false, true],
	"switchClickTool": [KEY_TAB, false, false, false],
	"quantum": [KEY_Q, true, false, false],
	"openTimings": [KEY_T, true, false, false],
	"openBookmarks": [KEY_B, true, false, false],
	"storeNodes": [KEY_S, false, false, true],
	"drawBezier": [KEY_D, false, false, true],
	"anchorNode": [KEY_A, false, false, true],
	"exportSSPM": [KEY_E, true, true, false],
	"createBPM": [KEY_B, true, false, true],
}

const KEYBIND_LABELS = {
	"selectAll": "Select All", "save": "Save", "saveAs": "Save As", "undo": "Undo", "redo": "Redo", "copy": "Copy",
	"paste": "Paste", "cut": "Cut", "delete": "Delete", "hFlip": "Horizontal Flip", "vFlip": "Vertical Flip",
	"switchClickTool": "Switch Click Tool", "quantum": "Toggle Quantum", "openTimings": "Open BPM Setup",
	"openBookmarks": "Open Bookmarks", "storeNodes": "Store Bezier Nodes", "drawBezier": "Draw Bezier",
	"anchorNode": "Anchor Node", "exportSSPM": "Export SSPM", "createBPM": "Create BPM From Selection",
}

const GRID_KEYS = [KEY_Q, KEY_W, KEY_E, KEY_A, KEY_S, KEY_D, KEY_Z, KEY_X, KEY_C]
const NUMPAD_KEYS = [KEY_KP_7, KEY_KP_8, KEY_KP_9, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_1, KEY_KP_2, KEY_KP_3]
const PATTERN_KEYS = [KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

static func defaults() -> Dictionary:
	return {
		"waveform": true,
		"classicWaveform": false,
		"correctOnCopy": true,
		"gridNumbers": false,
		"approachSquares": false,
		"autoplay": true,
		"numpad": false,
		"quantumGridLines": true,
		"quantumGridSnap": true,
		"metronome": false,
		"separateClickTools": false,
		"enableQuantum": false,
		"autoAdvance": false,
		"selectTool": false,
		"curveBezier": true,
		"gridLetters": true,
		"reverseScroll": false,
		"applyOnPaste": false,
		"jumpPaste": false,
		"pauseScroll": true,
		"clampSR": true,
		"pasteReversed": false,
		"adjustNotes": false,
		"muteSfx": false,
		"muteMusic": false,
		"smoothAutoplay": true,
		"gridSquircles": true,
		"oldQuantumSnap": false,
		"scaleMetronome": false,
		"moveOnGridKey": false,
		"editorBGOpacity": 170,
		"autoMapDensity": 100,
		"autoMapStars": 5.0,
		"autoMapQuantumPct": 0,
		"autoMapFlow": 70,
		"autoMapFollow": 75,
		"autoMapJump": 100,
		"autoMapPatterns": "mixed",
		"autoMapJumpShare": 50,
		"autoMapDrops": 100,
		"autoMapVariety": 50,
		"autoMapSources": "kick,snare,hat",
		"autoMapSensitivity": 50,
		"autoMapFill": "intense",
		"autoMapCalm": 30,
		"autoMapUseMap": true,
		"autoMapSimilarity": 0,
		"autoMapSetBpm": true,
		"autoMapCount": 0,
		"gridZoom": 100,
		"gridNoteSize": 100,
		"gridOpacity": 255,
		"trackOpacity": 255,
		"sfxOffset": 0.0,
		"musicOffset": 0.0,
		"bezierDivisor": 4.0,
		"maxPolyphony": 1,
		"rotateBy": 90.0,
		"scaleBy": 150.0,
		"cursorPos": 40.0,
		"approachRate": 14.0,
		"masterVolume": 0.25,
		"sfxVolume": 0.25,
		"quantumSnapping": 0.0,
		"quantumXOffset": 1.0,
		"quantumYOffset": 1.0,
		# Chromia's colours (the original's are cyan / magenta / red)
		"color1": [195, 166, 204],
		"color2": [255, 193, 245],
		"color3": [214, 120, 196],
		"color4": [90, 90, 90],
		"color5": [255, 204, 0],
		"keybinds": KEYBINDS.duplicate(true),
		"patterns": ["", "", "", "", "", "", "", "", "", ""],
		"lastLeftNav": "",
		"lastRightNav": "",
		"modchartGame": "Novastra",
		"exportType": "Nightly (SSPM)",
		"mode3D": false,
		"mode3DHitEffect": false,
		"grid3DOpacity": 80.0,
	}

static func load_settings() -> Dictionary:
	var s := defaults()
	var f := File.new()
	if f.open(Globals.p(PATH), File.READ) != OK:
		return s
	var p := JSON.parse(f.get_as_text())
	f.close()
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		return s
	var saved: Dictionary = p.result
	for key in s.keys():
		if not saved.has(key):
			continue
		var v = saved[key]
		if key == "keybinds":
			if v is Dictionary:
				for k in v:
					if s.keybinds.has(k) and v[k] is Array and v[k].size() == 4:
						s.keybinds[k] = [int(v[k][0]), bool(v[k][1]), bool(v[k][2]), bool(v[k][3])]
		elif typeof(v) == typeof(s[key]) or (typeof(s[key]) == TYPE_REAL and typeof(v) == TYPE_INT) or (typeof(s[key]) == TYPE_INT and typeof(v) == TYPE_REAL):
			if typeof(s[key]) == TYPE_INT:
				s[key] = int(v)
			elif typeof(s[key]) == TYPE_REAL:
				s[key] = float(v)
			else:
				s[key] = v
	if not (s.patterns is Array) or s.patterns.size() != 10:
		s.patterns = ["", "", "", "", "", "", "", "", "", ""]
	return s

static func save_settings(s: Dictionary):
	Directory.new().make_dir_recursive(Globals.p("user://editor"))
	var f := File.new()
	if f.open(Globals.p(PATH), File.WRITE) == OK:
		f.store_string(to_json(s))
		f.close()

# names of the keybinds the key press matches (KeybindManager + CompareKeybind)
static func compare_keybind(s: Dictionary, code: int, ctrl: bool, alt: bool, shift: bool) -> Array:
	var result := []
	if code == KEY_BACKSPACE:
		code = KEY_DELETE
	for name in s.keybinds:
		var b: Array = s.keybinds[name]
		if int(b[0]) == code and bool(b[1]) == ctrl and bool(b[2]) == alt and bool(b[3]) == shift:
			result.append(name)
	var pattern := PATTERN_KEYS.find(code)
	if pattern >= 0:
		result.append("pattern%d" % pattern)
	if ctrl or alt or shift:
		return result
	var keys: Array = NUMPAD_KEYS if s.numpad else GRID_KEYS
	var i := keys.find(code)
	if i >= 0:
		result.append("gridKey%d|%d" % [i % 3, i / 3])
	return result

static func key_name(code: int) -> String:
	var n := OS.get_scancode_string(code)
	if n.begins_with("Kp "):
		n = n.substr(3)
	return n

static func keybind_text(b: Array) -> String:
	var parts := []
	if b[1]:
		parts.append("CTRL")
	if b[2]:
		parts.append("ALT")
	if b[3]:
		parts.append("SHIFT")
	parts.append(key_name(int(b[0])).to_upper())
	return PoolStringArray(parts).join("+")

static func color(s: Dictionary, key: String, a := 1.0) -> Color:
	var c: Array = s.get(key, [255, 255, 255])
	return Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, a)
