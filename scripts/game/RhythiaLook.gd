extends Node

# The Rhythia look: a song's HUD as Rhythia draws it, from the settings of an
# imported Rhythia skin (.rhs, content/RhsImporter.gd keeps its whole "config"
# in user://rhythia_look.json). On while Settings > Background Editor > HUD
# panels is "Rhythia" (the import picks it).
#
# Chromia's HUD and Rhythia's come from the same game, so the panels are the
# same size with the same things on them. Places, sizes, fonts and brightness
# are Rhythia's, measured from a picture of it against a render of this (in
# grid units: the border is 3.04 across; they agree to about a pixel of that
# picture): the HUD on the grid's plane at its own size (not Chromia's Faraway
# HUD), the side panels PanelGap outside the grid and turned by PanelAngle (a
# part of a full turn), the name, time and progress bar over the grid, the
# health bar and the modifiers under it. On them, Rhythia's settings:
#   which items show (Left/RightPanel...Enabled), with the right panel's
#     items spread from top to bottom as Rhythia does
#   the combo ring: eight sides, one colour, the combo in it ("41x")
#   Rhythia's fonts: Nunito for the name and time, Montserrat for the titles,
#     Lexend Black for the numbers; values InterfaceValuesFontSize times the
#     size of their titles, in InterfaceTextColor
#   PanelOpacity, PanelBackgroundOpacity and PanelColor, PanelGap, PanelAngle
#   the song's name, time (00:12 / 00:44) and progress bar
#   the health bar's colour and see-through
#   the combo number in the grid (PlayfieldComboText...)
#   the background colour when none of Rhythia's backgrounds is on
# See-through things (the HUD, the border, the notes) are mixed the way
# Rhythia mixes them: see PLAIN_MIX.
# HUD.gd calls apply_hud() after its own font and panel styles.

const FILE := "user://rhythia_look.json"
const STYLE := "rhythia"
# Rhythia's three fonts, told from a picture of it by their letters' shapes and widths
const FONT_INFO := "res://assets/font/Nunito/Nunito-SemiBold.ttf" # the song's name and the time
const FONT_TITLE := "res://assets/font/Montserrat/Montserrat-Regular.ttf" # ACCURACY, POINTS, MISSES
const FONT_VALUE := "res://assets/font/Lexend/Lexend-Black.ttf" # their numbers, the combo in the ring
const FONT_COMBO := "res://assets/font/Nunito/Nunito-Bold.ttf" # the combo in the grid
const VALUE_K := 1.0 # a value's size: its title's, times InterfaceValuesFontSize, times this
const TITLE_PX := 32 # a title's size in a panel's own pixels (the panel is 300 wide)
const PX := 0.0033 # a panel pixel in grid units (the HUD sprites' pixel size)
const BORDER := 1.52 # half the border, in grid units
# a part facing the player squarely (the HUD's sprites lie on their backs: as SoundSpaceMode._place_hud)
const FLAT := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
# where things are, measured from Rhythia (grid units up from the grid's middle)
const NAME_Y := 2.079
const TIME_Y := 1.859
const PROGRESS_Y := 1.726
const PROGRESS_W := 2.869
const PROGRESS_H := 0.043
const HEALTH_Y := -1.665
const HEALTH_W := 2.906
const HEALTH_H := 0.0605
const MODS_Y := -1.791
const TOP_SLOT := 76.0 # the right panel's first title, in panel pixels from the top
const BOTTOM_SLOT := 705.0 # and its last (the left panel's accuracy too)
const COMBO_FONT_K := 0.57 # PlayfieldComboTextFontSize to this game's panel pixels
const PANEL_FROM := 1.49 # the side panels' gap is counted from here (Rhythia's grid is 3 across)
const NAME_PX := 33.0 # the font sizes, in panel pixels
const TIME_PX := 32.0
const TIME_A := 0.75 # the time's text is fainter than the name's
const TITLE_A := 0.63 # and so are the titles (ACCURACY ...), against their values
const RING_TEXT_PX := 56.0
const RING_Y := 147.0 # the ring's middle, in panel pixels from the top
const RING_RX := 90.2 # half its width and height (it is wider than high), to the middle of its line
const RING_RY := 80.0
const RING_W := 15.0 # its line
const STRONGER := 1.1 # the ring and the health bar come out a tenth stronger than their settings say
const TRACK_A := 0.161 # the bars' empty part: white, this see-through
# The HUD's sprites and see-through things, mixed with what is behind them the
# way Rhythia does (and a 2D picture would): straight on the screen's values.
# Chromia's 3D mixes in light (the GLES3 renderer), which makes see-through
# things brighter: 54% white comes out at 76%.
const PLAIN_MIX := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D tex;
uniform float opacity = 1.0;
uniform float behind = 0.0;
float lin(float v) { return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4); }
void fragment() {
	vec4 c = texture(tex, UV);
	float a = clamp(c.a, 0.0, 1.0);
	vec3 col = a > 0.002 ? clamp(c.rgb / a, 0.0, 1.0) : vec3(0.0);
	float top = max(col.r, max(col.g, col.b));
	float A = a * opacity;
	ALBEDO = vec3(lin(col.r), lin(col.g), lin(col.b));
	float span = lin(top) - lin(behind);
	ALPHA = span > 0.004 ? clamp((lin(behind + (top - behind) * A) - lin(behind)) / span, 0.0, 1.0) : A;
}
"""

var hud
var cfg := {}
var _ring: Control
var _ring_label: Label
var _grid_combo: Label
var _combo_shown := -1
var _time_shown := ""
var _bg_done := false
var _bg_tries := 0
var _mixed := [] # [sprite, its material]: the sprites drawn with PLAIN_MIX
var _behind := 0.0 # how bright the background is (0-1)
var _name_col := Color(1, 1, 1)
var _time_col := Color(1, 1, 1)

# --- the kept config: {key: value} (Rhythia writes {key: {"Value": value}}) ---

static func config() -> Dictionary:
	if Engine.has_meta("rhythia_look"):
		return Engine.get_meta("rhythia_look")
	var d := {}
	var f := File.new()
	if f.open(Globals.p(FILE), File.READ) == OK:
		var p = JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and p.result is Dictionary:
			d = flatten(p.result)
	Engine.set_meta("rhythia_look", d)
	return d

static func flatten(raw: Dictionary) -> Dictionary:
	var d := {}
	for k in raw:
		var e = raw[k]
		d[String(k)] = e.get("Value") if e is Dictionary and e.has("Value") else e
	return d

static func save_config(raw: Dictionary):
	var d := flatten(raw)
	Engine.set_meta("rhythia_look", d)
	var f := File.new()
	if f.open(Globals.p(FILE), File.WRITE) == OK:
		f.store_string(JSON.print(d))
		f.close()

static func has_config() -> bool:
	return not config().empty()

static func enabled() -> bool:
	# (not in VR: the HUD there is set out around you, not on a screen)
	return String(Rhythia.get("hud_panel_style")) == STYLE and has_config() and not bool(Rhythia.get("ss_hud")) and not bool(Rhythia.get("sound_space_mode")) and not bool(Rhythia.get("vr"))

static func apply_hud(h):
	if not enabled() or h.has_node("RhythiaLook"):
		return
	var n = load("res://scripts/game/RhythiaLook.gd").new()
	n.name = "RhythiaLook"
	n.hud = h
	n.cfg = config()
	h.add_child(n)
	n._build()

# --- reading it ---

func num(key: String, def: float) -> float:
	var v = cfg.get(key)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_REAL] else def

func on(key: String, def: bool) -> bool:
	var v = cfg.get(key)
	return bool(v) if typeof(v) == TYPE_BOOL else def

# "<prefix>Red" / "Green" / "Blue" (0-255), with an alpha
func rgb(prefix: String, def: Color, alpha: float = 1.0) -> Color:
	if not (cfg.has(prefix + "Red") and cfg.has(prefix + "Green") and cfg.has(prefix + "Blue")):
		return Color(def.r, def.g, def.b, alpha)
	return Color(num(prefix + "Red", 255) / 255.0, num(prefix + "Green", 255) / 255.0, num(prefix + "Blue", 255) / 255.0, alpha)

func _font(size: float, path: String) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = int(round(size))
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _style(l: Label, size: float, font: String, col: Color):
	if l == null:
		return
	l.add_font_override("font", _font(size, font))
	for k in ["font_color", "font_color_shadow"]:
		if k == "font_color":
			l.add_color_override(k, col)
	l.add_constant_override("shadow_offset_x", 0)
	l.add_constant_override("shadow_offset_y", 0)
	l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
	l.modulate = Color(1, 1, 1, 1)
	l.self_modulate = Color(1, 1, 1, 1)
	l.uppercase = false

# a title and its value, the title centred on y (panel pixels from the top)
func _slot(title: Label, value: Label, y: float, title_text: String = ""):
	var vs: float = TITLE_PX * num("InterfaceValuesFontSize", 1.6) * VALUE_K
	for l in [title, value]:
		if l == null:
			continue
		l.visible = true
		l.anchor_top = 0
		l.anchor_bottom = 0
		l.anchor_left = 0
		l.anchor_right = 1
		l.margin_left = 0
		l.margin_right = 0
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
	if title != null:
		if title_text != "":
			title.text = title_text
		title.margin_top = y - 30
		title.margin_bottom = y + 30
	if value != null:
		value.margin_top = y + 62 - 40
		value.margin_bottom = y + 62 + 40

# ---------------------------------------------------------------------------

func _build():
	pause_mode = PAUSE_MODE_PROCESS
	var text_col: Color = rgb("InterfaceTextColor", Color(1, 1, 1))
	var vs: float = TITLE_PX * num("InterfaceValuesFontSize", 1.6) * VALUE_K
	var panel_a: float = clamp(num("PanelOpacity", 1.0), 0.0, 1.0)
	var bg: Color = rgb("PanelColor", Color(1, 1, 1), clamp(num("PanelBackgroundOpacity", 0.0), 0.0, 1.0))
	# (what is behind the HUD: the skin's plain background, or taken as black)
	_behind = 0.0
	if _own_background():
		var bc: Color = rgb("Background", Color(0, 0, 0))
		_behind = (bc.r + bc.g + bc.b) / 3.0

	# --- the side panels: their background, what shows on them, the text
	for side in ["LeftVP", "RightVP"]:
		var c = hud.get_node_or_null(side + "/Control")
		if c is ColorRect:
			c.color = bg
			c.self_modulate = Color(1, 1, 1, 1)
			if c.material != null:
				c.material = null
			for ch in c.get_children():
				# (a panel style's own backing, HudPanels.gd: Rhythia's panel is a plain colour)
				if ch is Panel and ch.name != "SimpleBg":
					ch.visible = false
			var sb = c.get_node_or_null("SimpleBg")
			if sb != null:
				sb.visible = false
	var L = hud.get_node("LeftVP/Control")
	var R = hud.get_node("RightVP/Control")
	for l in [L.get_node("AccuracyTitle"), L.get_node("PausesTitle"), R.get_node("NoteTitle"), R.get_node("MissesTitle"), R.get_node("ScoreTitle")]:
		_style(l, TITLE_PX, FONT_TITLE, Color(text_col.r, text_col.g, text_col.b, TITLE_A))
	for l in [L.get_node("Accuracy"), L.get_node("Pauses"), R.get_node("Notes"), R.get_node("Misses"), R.get_node("Score"), L.get_node("LetterGrade")]:
		_style(l, vs, FONT_VALUE, text_col)
	# left: the ring on top; pauses, the grade and accuracy in their places under it
	L.get_node("AccuracyBar").visible = false
	var ring_on: bool = on("LeftPanelComboRingEnabled", true)
	_set_pair(L.get_node("PausesTitle"), L.get_node("Pauses"), on("LeftPanelPausesEnabled", true), 320)
	L.get_node("LetterGrade").visible = on("LeftPanelGradeEnabled", true)
	_set_pair(L.get_node("AccuracyTitle"), L.get_node("Accuracy"), on("LeftPanelAccuracyEnabled", true), BOTTOM_SLOT)
	# right: what is on, spread from the top to the bottom
	var items := []
	if on("RightPanelScoreEnabled", false):
		items.append([R.get_node("ScoreTitle"), R.get_node("Score"), "SCORE"])
	elif on("RightPanelPointsEnabled", true):
		items.append([R.get_node("ScoreTitle"), R.get_node("Score"), "POINTS"])
	else:
		R.get_node("ScoreTitle").visible = false
		R.get_node("Score").visible = false
	if on("RightPanelMissesEnabled", true):
		items.append([R.get_node("MissesTitle"), R.get_node("Misses"), "MISSES"])
	else:
		R.get_node("MissesTitle").visible = false
		R.get_node("Misses").visible = false
	if on("RightPanelNotesEnabled", true):
		items.append([R.get_node("NoteTitle"), R.get_node("Notes"), "NOTES"])
	else:
		R.get_node("NoteTitle").visible = false
		R.get_node("Notes").visible = false
	for i in items.size():
		var y: float = TOP_SLOT if items.size() == 1 else lerp(TOP_SLOT, BOTTOM_SLOT, float(i) / float(items.size() - 1))
		_slot(items[i][0], items[i][1], y, items[i][2])
	for n in ["FPS", "FPSTitle", "SP"]:
		var x = R.get_node_or_null(n)
		if x != null:
			x.visible = false

	# --- the combo ring: Rhythia's eight-sided ring (a corner up, wider than
	# high), all of it one colour, the combo in it. (Chromia's own ring and its
	# text, the multiplier, are put away: these are this look's own.)
	hud.comboring.visible = false
	hud.combotxt.visible = false
	if ring_on:
		_ring = Octagon.new()
		_ring.name = "RhythiaRing"
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.rx = RING_RX
		_ring.ry = RING_RY
		_ring.width = RING_W
		_ring.rect_position = Vector2(150.0 - RING_RX - 20.0, RING_Y - RING_RY - 20.0)
		_ring.rect_size = Vector2(RING_RX + 20.0, RING_RY + 20.0) * 2.0
		_ring.color = rgb("ComboRingColor", Color(1, 1, 1), clamp(num("ComboRingOpacity", 1.0) * STRONGER, 0.0, 1.0))
		L.add_child(_ring)
		_ring_label = Label.new()
		_ring_label.name = "RhythiaCombo"
		_ring_label.rect_position = Vector2(0, RING_Y - 50.0)
		_ring_label.rect_size = Vector2(300, 100)
		_ring_label.align = Label.ALIGN_CENTER
		_ring_label.valign = Label.VALIGN_CENTER
		_ring_label.text = "0x"
		_style(_ring_label, RING_TEXT_PX, FONT_VALUE, text_col)
		L.add_child(_ring_label)

	# The HUD where the grid is, at its own size. (Chromia's Faraway HUD puts it
	# far behind and bigger, which takes the depth out of it: Rhythia's panels
	# are near, and their turn shows.)
	# (set as a scale and a place: a transform set straight after a scale is
	# overwritten by that scale when Godot next reads it)
	hud.scale = Vector3.ONE
	hud.translation = Vector3.ZERO

	# --- the side panels: flat on the grid's plane, PanelGap outside the border,
	# turned towards you by PanelAngle (a part of a full turn: 0.05 is 18 degrees)
	var gap: float = num("PanelGap", 0.0) * PX
	var turn: float = clamp(num("PanelAngle", 0.05), -0.25, 0.25) * TAU
	for it in [["LeftHud", -1.0], ["RightHud", 1.0]]:
		var s = hud.get_node_or_null(it[0])
		if s is Sprite3D:
			s.opacity = panel_a
			s.modulate = Color(1, 1, 1, 1)
			s.pixel_size = PX
			# (turned about its own middle: the outer edge comes towards you, the inner one goes back)
			s.transform = Transform(Basis(Vector3.UP, -it[1] * turn) * FLAT, Vector3(it[1] * (PANEL_FROM + gap + 150.0 * PX * cos(turn)), 0, 0))
			_plain_mix(s)

	# --- over the grid: the song's name, the time, the progress bar
	var HP = load("res://scripts/HudPanels.gd")
	var info: bool = on("SongInfoEnabled", true)
	_name_col = text_col
	_time_col = Color(text_col.r, text_col.g, text_col.b, TIME_A)
	_style(hud.songnametxt, NAME_PX, FONT_INFO, _name_col)
	_style(hud.timelabel, TIME_PX, FONT_INFO, _time_col)
	hud.songnametxt.visible = info
	hud.timelabel.visible = info
	hud.songnametxt.text = String(Rhythia.selected_song.name) if Rhythia.selected_song != null else hud.songnametxt.text
	var th = HP._part(hud, "TimerHud")
	var t_mid := 1.95 # the panel's middle (it is 300 pixels high: 0.99)
	if th is Sprite3D:
		th.opacity = panel_a
		th.modulate = Color(1, 1, 1, 1)
		th.pixel_size = PX
		th.transform = Transform(FLAT, Vector3(0, t_mid, 0))
		_plain_mix(th)
	_at(hud.songnametxt, _py(t_mid, NAME_Y), 30)
	_at(hud.timelabel, _py(t_mid, TIME_Y), 26)
	var tb: ProgressBar = hud.timebar
	tb.visible = on("SongProgressBarEnabled", true)
	_bar_at(tb, _py(t_mid, PROGRESS_Y), PROGRESS_W / PX, PROGRESS_H / PX)

	# --- under the grid: the health bar, the modifiers under it
	var eb: ProgressBar = hud.energybar
	eb.visible = on("HealthBarEnabled", true) and eb.visible
	var e_mid := -1.95
	var eh = HP._part(hud, "EnergyHud")
	if eh is Sprite3D:
		eh.opacity = panel_a
		eh.modulate = Color(1, 1, 1, 1)
		eh.pixel_size = PX
		eh.transform = Transform(FLAT, Vector3(0, e_mid, 0))
		_plain_mix(eh)
	_bar_at(eb, _py(e_mid, HEALTH_Y), HEALTH_W / PX, HEALTH_H / PX)
	var mods = hud.get_node_or_null("EnergyVP/Control/Modifiers")
	if mods != null:
		# (its icons smaller, as Rhythia's are, their middle at MODS_Y)
		mods.rect_pivot_offset = Vector2(mods.rect_size.x / 2.0, 0)
		mods.rect_scale = Vector2(0.6, 0.6)
		mods.margin_top = _py(e_mid, MODS_Y) - 30
		var mt = mods.get_node_or_null("Text")
		if mt is Label:
			_style(mt, 26, FONT_TITLE, Color(text_col.r, text_col.g, text_col.b, panel_a))
	_bar_colors()

	# --- the combo number in the grid: a label of this look's own, on the
	# grid's plane, PlayfieldComboTextVerticalPositionPercent of the way down
	var ca: float = clamp(num("PlayfieldComboTextOpacity", 0.0), 0.0, 1.0)
	var ch = hud.get_node_or_null("ComboHud")
	if ch is Sprite3D and hud.truecombo != null:
		ch.visible = ca > 0.001
		ch.opacity = 1.0
		ch.modulate = Color(1, 1, 1, 1)
		ch.pixel_size = PX
		hud.truecombo.visible = false
		hud.truecombo.modulate = Color(1, 1, 1, 0) # (Chromia's own number: it's shown again as the combo changes)
		_grid_combo = Label.new()
		_grid_combo.name = "RhythiaGridCombo"
		_grid_combo.anchor_right = 1
		_grid_combo.anchor_bottom = 1
		_grid_combo.align = Label.ALIGN_CENTER
		_grid_combo.valign = Label.VALIGN_CENTER
		_grid_combo.text = "0"
		_style(_grid_combo, num("PlayfieldComboTextFontSize", 122.0) * COMBO_FONT_K, FONT_COMBO, rgb("PlayfieldComboTextColor", Color(1, 1, 1), ca))
		hud.get_node("ComboVP").add_child(_grid_combo)
		var pct: float = clamp(num("PlayfieldComboTextVerticalPositionPercent", 50.0), 0.0, 100.0) / 100.0
		ch.transform = Transform(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0, 1.5 - 3.0 * pct - 0.06, -0.02))
		_plain_mix(ch)
	set_process(true)

# a height over the grid's middle (grid units) as pixels from the top of a 300 high panel whose middle is at `mid`
func _py(mid: float, y: float) -> float:
	return 150.0 - (y - mid) / PX

# a label across its panel, its text centred on y (panel pixels from the top)
func _at(l: Label, y: float, half: float):
	l.anchor_left = 0
	l.anchor_right = 1
	l.anchor_top = 0
	l.anchor_bottom = 0
	l.margin_left = 0
	l.margin_right = 0
	l.margin_top = y - half
	l.margin_bottom = y + half
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.clip_text = false

# a bar w wide and h thick (panel pixels), its middle at y, in the middle of its 900 wide panel
func _bar_at(b: ProgressBar, y: float, w: float, h: float):
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.anchor_top = 0
	b.anchor_bottom = 0
	b.margin_left = -w / 2.0
	b.margin_right = w / 2.0
	b.margin_top = y - h / 2.0
	b.margin_bottom = y + h / 2.0
	b.rect_min_size = Vector2(0, 0)
	for k in ["fg", "bg"]:
		var sb = b.get("custom_styles/" + k)
		if sb is StyleBoxFlat:
			sb.set_corner_radius_all(int(max(1.0, h / 2.0)))

func _set_pair(title: Label, value: Label, show: bool, y: float):
	if show:
		_slot(title, value, y)
	else:
		title.visible = false
		value.visible = false

# the progress and health bars in the skin's colours (HUD.gd paints them again as the song goes)
func _bar_colors():
	var tb: ProgressBar = hud.timebar
	var fg = tb.get("custom_styles/fg")
	var bgs = tb.get("custom_styles/bg")
	if fg is StyleBoxFlat:
		fg.bg_color = rgb("SongProgressBarColor", Color(1, 1, 1), clamp(num("SongProgressBarAlpha", 1.0), 0.0, 1.0))
	if bgs is StyleBoxFlat:
		bgs.bg_color = Color(1, 1, 1, TRACK_A)
	var eb: ProgressBar = hud.energybar
	var efg = eb.get("custom_styles/fg")
	var ebg = eb.get("custom_styles/bg")
	if efg is StyleBoxFlat:
		efg.bg_color = rgb("HealthBarColor", Color(1, 1, 1), clamp(num("HealthBarAlpha", 1.0) * STRONGER, 0.0, 1.0))
	if ebg is StyleBoxFlat:
		ebg.bg_color = Color(1, 1, 1, TRACK_A)

# --- mixed as Rhythia mixes (see PLAIN_MIX) ---

func _light_mix() -> bool:
	return OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

# the see-through to give a thing of brightness `top` so that, mixed in light,
# it comes out as `a` would mixed straight
func _alpha_for(a: float, top: float) -> float:
	if not _light_mix() or a >= 0.999 or a <= 0.001:
		return a
	var span: float = _lin(top) - _lin(_behind)
	if span < 0.004:
		return a
	return clamp((_lin(_behind + (top - _behind) * a) - _lin(_behind)) / span, 0.0, 1.0)

func _plain_mix(s: Sprite3D):
	if not _light_mix() or s == null or s.texture == null:
		return
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PLAIN_MIX
	if s.no_depth_test:
		sh.code = PLAIN_MIX.replace("depth_draw_never;", "depth_draw_never, depth_test_disable;")
	m.shader = sh
	m.render_priority = s.render_priority
	m.set_shader_param("tex", s.texture)
	m.set_shader_param("opacity", s.opacity * s.modulate.a)
	m.set_shader_param("behind", _behind)
	s.material_override = m
	_mixed.append([s, m])

# every frame: the sprites' see-through followed (Chromia fades them), the
# border's set; once: the notes' (NoteManager.alpha_lut)
func _mix_step():
	var game = hud.get_parent()
	var spawn = game.get_node_or_null("Spawn") if game != null else null
	if spawn != null and "alpha_lut" in spawn and spawn.alpha_lut.size() != 65:
		var two: bool = bool(spawn.get("notes_two_layers"))
		var lut := PoolRealArray()
		for i in 65:
			var a: float = _alpha_for(i / 64.0, 0.9)
			lut.append(1.0 - sqrt(max(1.0 - a, 0.0)) if two else a)
		spawn.alpha_lut = lut
	if not _light_mix():
		return
	for it in _mixed:
		if is_instance_valid(it[0]):
			it[1].set_shader_param("opacity", it[0].opacity * it[0].modulate.a)
	var outer = spawn.get_node_or_null("Outer") if spawn != null else null
	var bm = outer.get("material/0") if outer != null else null
	if bm is SpatialMaterial and not bool(Rhythia.get("rainbow_grid")):
		var bc: Color = Rhythia.border_color
		var want := Color(bc.r, bc.g, bc.b, _alpha_for(bc.a, max(bc.r, max(bc.g, bc.b))))
		if bm.albedo_color != want:
			bm.albedo_color = want

# Rhythia's backgrounds are its own drawings; with none of them on it's a
# plain colour, which this puts behind the song
func _own_background() -> bool:
	for k in ["BackgroundTunnelEnabled", "BackgroundSineEnabled", "BackgroundChevronEnabled", "BackgroundRaysEnabled", "BackgroundGridEnabled"]:
		if on(k, false):
			return false
	var imgs = cfg.get("BackgroundImages")
	return not (imgs is Array and not imgs.empty())

func _plain_background() -> bool:
	if not _own_background():
		return true # (one of Rhythia's backgrounds is on: your own background stays)
	var root = hud.get_parent().get_parent() if hud.get_parent() != null else null
	var space = root.get_node_or_null("Space") if root != null else null
	if space == null:
		return false
	var we = null
	for c in space.get_children():
		if c is WorldEnvironment:
			we = c
		elif c is VisualInstance or c is CanvasItem:
			c.visible = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = rgb("Background", Color(0, 0, 0))
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	if we == null:
		we = WorldEnvironment.new()
		space.add_child(we)
	we.environment = env
	return true

func _process(_d):
	if hud == null or not is_instance_valid(hud):
		return
	if not _bg_done and _bg_tries < 240:
		_bg_tries += 1
		_bg_done = _plain_background()
	# the combo in the ring ("41x"), where Chromia shows the multiplier
	var game = hud.Game
	var combo: int = int(hud._spectate_data.combo) if hud.spectating else int(game.combo)
	if combo != _combo_shown:
		_combo_shown = combo
		if _ring_label != null:
			_ring_label.text = "%dx" % combo
		if _grid_combo != null:
			_grid_combo.text = str(combo)
			var vp = _grid_combo.get_parent()
			if vp is Viewport:
				vp.render_target_update_mode = Viewport.UPDATE_ONCE
	if hud.combotxt.visible:
		hud.combotxt.visible = false
	if hud.comboring.visible:
		hud.comboring.visible = false
	if _grid_combo != null and hud.truecombo.visible:
		hud.truecombo.visible = false
	_mix_step()
	# (HUD.gd paints the name and the time in Chromia's timer colours as the song's state changes)
	if hud.songnametxt.get("custom_colors/font_color") != _name_col:
		hud.songnametxt.add_color_override("font_color", _name_col)
	if hud.timelabel.get("custom_colors/font_color") != _time_col:
		hud.timelabel.add_color_override("font_color", _time_col)
	# the time as Rhythia writes it: 00:12 / 00:44
	var t: String = hud.timelabel.text
	if t != _time_shown:
		var parts := t.split(" / ")
		if parts.size() == 2 and parts[0].find(":") != -1 and parts[0].length() <= 5 and parts[1].length() <= 5:
			for i in 2:
				if String(parts[i]).find(":") == 1:
					parts[i] = "0" + String(parts[i])
			t = "%s / %s" % [parts[0], parts[1]]
			hud.timelabel.text = t
		_time_shown = t
	_bar_colors()

# Rhythia's combo ring: eight sides, a corner up, drawn as eight pieces side by
# side (one see-through colour all round, no doubled joins)
class Octagon extends Control:
	var color := Color(1, 1, 1, 0.25)
	var rx := 100.0
	var ry := 80.0
	var width := 15.0
	func _draw():
		var c := rect_size / 2.0
		var k: float = width / 2.0 / cos(PI / 8.0)
		for i in 8:
			var a0: float = i * PI / 4.0
			var a1: float = (i + 1) * PI / 4.0
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			draw_colored_polygon(PoolVector2Array([
				c + Vector2(d0.x * (rx + k), d0.y * (ry + k)), c + Vector2(d1.x * (rx + k), d1.y * (ry + k)),
				c + Vector2(d1.x * (rx - k), d1.y * (ry - k)), c + Vector2(d0.x * (rx - k), d0.y * (ry - k))]), color)
