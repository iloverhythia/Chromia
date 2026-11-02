extends Control
# The editor's Settings window, opened from the editor's start screen (before
# any map is open). The window (SSQEDialogs.settings) only needs the settings,
# fonts and the screen's scale from the editor, so this stands in for it; the
# settings are the same file, and an editor that's already been opened gets
# the changes straight away.

const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const H0 := 1080.0

var page # EditorPage
var s: Dictionary
var hd := 1.0
var map = null # (no map: the windows that need one don't open from here)
var dialogs
var _fonts := {}

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	dialogs = load("res://scripts/editor/ssqe/SSQEDialogs.gd").new()
	dialogs.ed = self
	add_child(dialogs)
	connect("resized", self, "_on_resized")
	_on_resized()

func _on_resized():
	hd = max(rect_size.y, 1.0) / H0

func open():
	# the open editor's own settings when there is one, so both stay the same
	s = page.ed.s if page and page.ed else SSQESettings.load_settings()
	_on_resized()
	dialogs.settings()

func is_open() -> bool:
	return dialogs != null and dialogs.windows.has("settings")

func settings_changed():
	SSQESettings.save_settings(s)
	SSQESettings.show_gradients(get_tree(), bool(s.get("controlGradients", true)))
	if page and page.ed:
		page.ed.s = s
		page.ed.settings_changed()

func font(px: int, bold := false) -> DynamicFont:
	px = int(clamp(px, 6, 160))
	var legacy: bool = bool(s.get("legacyUI", false)) if s is Dictionary else false
	var key := px * 4 + (1 if bold else 0) + (2 if legacy else 0)
	if _fonts.has(key):
		return _fonts[key]
	var f := DynamicFont.new()
	if legacy:
		f.font_data = load("res://assets/font/SSQE/main.ttf") # (SSQE: Source Sans Pro Bold for everything)
	else:
		f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf" if bold else "res://assets/font/Lato/Lato-Regular.ttf")
	f.size = px
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	_fonts[key] = f
	return f
