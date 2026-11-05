extends Spatial

# The song's HUD in the Settings preview (SettingsPreviewWorld.gd): the real
# prefabs/game/HUD.tscn panels (timer, accuracy / combo panel, score / misses
# panel, health bar, config), set up from your settings the way HUD.gd sets
# them up in a song: which parts show, their colours, Simple HUD, Faraway
# HUD, the bars attached to the grid, Settings > Fonts, Background Editor >
# HUD panels, rainbow / colorset HUD. HUD.gd itself doesn't run (it needs a
# song); the preview's map fills in the numbers.

const HUD_SCENE := "res://prefabs/game/HUD.tscn"
# scripts that only draw (the combo ring, FPS, the config panel's values)
const KEEP_SCRIPTS := ["res://scripts/game/CircularProgress2.gd", "res://scripts/game/FPS.gd", "res://scripts/game/configDisp.gd"]
# parts a song only shows now and then (or that need a song)
const DROP := ["Mobile", "Stats", "ObnoxiousWarning", "ApproachVP", "ApproachHud", "PauseVP", "PauseHud", "GiveUpVP", "GiveUpHud"]

var hud: Spatial
var _moved: Array = [] # parts moved onto the grid (attach to grid)
var _sig := ""
var _ring := 0.0
var _cs_tint := Color(1, 1, 1)
var _vps: Array = [] # the HUD's viewports, redrawn 20 times a second (like HUD.gd)
var _redraw := 0.0

# the settings that need the HUD made again
static func signature() -> String:
	var keys := ["show_left_panel", "show_right_panel", "show_hp_bar", "show_timer", "show_letter_grade",
		"show_accuracy_bar", "show_config", "attach_hp_to_grid", "attach_timer_to_grid", "simple_hud",
		"faraway_hud", "rainbow_hud", "colorset_hud", "display_true_combo", "show_fc_grade",
		"panel_bg", "panel_text", "score_text_color", "pause_text_color", "miss_text_color",
		"combo_fill_color", "combo_empty_color", "acc_fill_color", "acc_empty_color",
		"energy_fill_color", "energy_empty_color", "timer_fg", "timer_bg", "timer_text",
		"hud_font", "hud_font_size", "hud_panel_style", "hud_panel_size", "hud_brightness", "hud_panel_x", "hud_panel_y", "hud_bars_y", "ss_hud", "sound_space_mode",
		"show_sp_hud"]
	var parts := PoolStringArray()
	for k in keys:
		parts.append(String(Rhythia.get(k)))
	return parts.join("|")

func rebuild(spawn: Spatial):
	_sig = signature()
	for n in _moved:
		if is_instance_valid(n):
			n.queue_free()
	_moved = []
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	hud = null
	var ps = load(HUD_SCENE)
	if not (ps is PackedScene):
		return
	var h: Spatial = ps.instance()
	for n in DROP:
		var c = h.get_node_or_null(n)
		if c != null:
			h.remove_child(c)
			c.free()
	_strip(h)
	add_child(h)
	hud = h
	_apply_settings(spawn)

func _strip(n: Node):
	var s = n.get_script()
	if s != null and not (s.resource_path in KEEP_SCRIPTS):
		n.set_script(null)
	for c in n.get_children():
		_strip(c)

func _each(n: Node, out: Array):
	out.append(n)
	for c in n.get_children():
		_each(c, out)

static func _paint(node, color: Color):
	if node is ColorRect:
		node.color = color
	elif node is Panel:
		var sb = node.get("custom_styles/panel")
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			sb.bg_color = color
			node.set("custom_styles/panel", sb)
	elif node is Label:
		if node.has_color_override("font_color"):
			node.set("custom_colors/font_color", color)
		else:
			node.modulate = color
	elif node is CanvasItem:
		node.modulate = color

static func _bar(bar: ProgressBar, fg: Color, bg: Color):
	if bar == null:
		return
	for k in [["custom_styles/fg", fg], ["custom_styles/bg", bg]]:
		var sb = bar.get(k[0])
		if sb is StyleBoxFlat:
			sb = sb.duplicate()
			sb.bg_color = k[1]
			bar.set(k[0], sb)

# (on the bar's own copy, made by _bar)
static func _bar_set(bar: ProgressBar, fg: Color, bg: Color):
	if bar == null:
		return
	var f = bar.get("custom_styles/fg")
	var b = bar.get("custom_styles/bg")
	if f is StyleBoxFlat:
		f.bg_color = fg
	if b is StyleBoxFlat:
		b.bg_color = bg

static func _grey(c: Color) -> Color:
	var v: float = max(max(c.r, c.g), c.b)
	return Color(v, v, v, c.a)

# what HUD._ready does with your settings
func _apply_settings(spawn: Spatial):
	_vps = []
	var all := []
	_each(hud, all)
	for n in all:
		if n is Viewport:
			n.msaa = Viewport.MSAA_DISABLED
			n.render_target_update_mode = Viewport.UPDATE_ONCE
			_vps.append(n)
		if n.is_in_group("panel_bg"): _paint(n, Rhythia.panel_bg)
		if n.is_in_group("panel_text"): _paint(n, Rhythia.panel_text)
		if n.is_in_group("score_text"): _paint(n, Rhythia.score_text_color)
		if n.is_in_group("pause_text"): _paint(n, Rhythia.pause_text_color)
		if n.is_in_group("miss_text"): _paint(n, Rhythia.miss_text_color)
		if n.is_in_group("timer_text"): _paint(n, Rhythia.timer_text)
	var tinted: bool = Rhythia.rainbow_hud or Rhythia.colorset_hud
	var ring = hud.get_node_or_null("LeftVP/Control/Combo")
	if ring != null:
		ring.fill_color = _grey(Rhythia.combo_fill_color) if tinted else Rhythia.combo_fill_color
		ring.empty_color = _grey(Rhythia.combo_empty_color) if tinted else Rhythia.combo_empty_color
	var acc = hud.get_node_or_null("LeftVP/Control/AccuracyBar")
	_bar(acc, _grey(Rhythia.acc_fill_color) if tinted else Rhythia.acc_fill_color, _grey(Rhythia.acc_empty_color) if tinted else Rhythia.acc_empty_color)
	var energy = hud.get_node_or_null("EnergyVP/Control/Energy")
	_bar(energy, Rhythia.energy_fill_color, Rhythia.energy_empty_color) # (its own copy: tinted below)
	_bar(hud.get_node_or_null("TimerVP/Control/Time"), Rhythia.timer_fg, Rhythia.timer_bg)
	hud.get_node("ConfigHud").visible = Rhythia.show_config
	hud.get_node("ComboHud").visible = Rhythia.display_true_combo
	hud.get_node("LeftHud").visible = Rhythia.show_left_panel
	hud.get_node("RightHud").visible = Rhythia.show_right_panel
	var grade = hud.get_node_or_null("LeftVP/Control/LetterGrade")
	if grade != null:
		grade.visible = Rhythia.show_letter_grade
	if acc != null:
		acc.visible = Rhythia.show_accuracy_bar
	if not Rhythia.show_hp_bar and energy != null:
		energy.visible = false
		hud.get_node("EnergyVP/Control/Modifiers").margin_top -= 30
	hud.get_node("TimerHud").visible = Rhythia.show_timer
	# on the grid: moved under the preview's grid, like the song moves them
	for pair in [["attach_hp_to_grid", "EnergyHud"], ["attach_timer_to_grid", "TimerHud"]]:
		if bool(Rhythia.get(pair[0])) and spawn != null:
			var n = hud.get_node(pair[1])
			hud.remove_child(n)
			spawn.add_child(n)
			n.transform.origin += Vector3(1, -1, 0)
			_moved.append(n)
	if Rhythia.simple_hud:
		for side in ["LeftVP/Control", "RightVP/Control"]:
			var c = hud.get_node(side)
			c.self_modulate = Color(0, 0, 0, 0)
			for n in c.get_children():
				n.visible = n.name in ["SimpleBg", "Pauses", "PausesTitle", "Misses", "MissesTitle"]
				if n.visible:
					n.rect_position.y += 100
	if Rhythia.faraway_hud:
		hud.transform.origin = Vector3(0, 0, -10)
		hud.scale = Vector3(3.7, 3.7, 3.7)
	var name_l = hud.get_node_or_null("TimerVP/Control/SongName")
	if name_l != null:
		name_l.text = String(Rhythia.selected_song.name) if Rhythia.selected_song != null else "Settings preview"
	var mods = hud.get_node_or_null("EnergyVP/Control/Modifiers/Text")
	if mods != null:
		mods.text = ""
	load("res://scripts/HudFont.gd").apply_hud(hud)
	load("res://scripts/HudPanels.gd").apply(hud)

static func _commas(n: int) -> String:
	return Globals.comma_sep(n) if Globals.has_method("comma_sep") else str(n)

# each frame: the preview map's numbers
func frame(delta: float, t: float, loop_s: float, hits: int, total: int, combo: int, last_col: Color, spawn: Spatial):
	if hud == null or not is_instance_valid(hud) or signature() != _sig:
		rebuild(spawn)
		if hud == null:
			return
	_redraw += delta
	if _redraw >= 0.05:
		_redraw = 0.0
		for v in _vps:
			if is_instance_valid(v):
				v.render_target_update_mode = Viewport.UPDATE_ONCE
	# the config panel shows for the first 2.5 s, fading out (HUD.config_time)
	var cfg = hud.get_node_or_null("ConfigHud")
	if cfg != null and Rhythia.show_config:
		var left: float = 2.5 - t
		cfg.visible = left > 0.0
		if left > 0.0:
			cfg.opacity = min(1.0, left)
	var level: int = int(min(8, 1 + combo / 10))
	var score := 0
	for i in combo:
		score += 25 * int(min(8, 1 + i / 10))
	var lc = hud.get_node_or_null("LeftVP/Control/Combo/Label")
	if lc != null:
		lc.text = "%dx" % level
	var ring = hud.get_node_or_null("LeftVP/Control/Combo")
	var target: float = 1.0 if level >= 8 else float(combo % 10) / 10.0
	_ring += (target - _ring) * min(1.0, delta * 6.0)
	if ring != null and ring.get("ready"):
		ring._set_percent(_ring)
	var acc_l = hud.get_node_or_null("LeftVP/Control/Accuracy")
	if acc_l != null:
		acc_l.text = "100%"
	var accb = hud.get_node_or_null("LeftVP/Control/AccuracyBar")
	if accb != null:
		accb.value = 1.0
	var grade = hud.get_node_or_null("LeftVP/Control/LetterGrade")
	if grade != null and grade.visible:
		grade.text = "FC" if Rhythia.show_fc_grade else "SS"
		if not (Rhythia.rainbow_hud or Rhythia.colorset_hud):
			grade.set("custom_colors/font_color", Color("#fa6afa") if Rhythia.show_fc_grade else Color.from_hsv(Rhythia.rainbow_t * 0.1, Rhythia.grade_ss_saturation, Rhythia.grade_ss_value))
	var pl = hud.get_node_or_null("LeftVP/Control/Pauses")
	if pl != null:
		pl.text = "0"
	var nl = hud.get_node_or_null("RightVP/Control/Notes")
	if nl != null:
		nl.text = "%s/%s" % [_commas(hits), _commas(total)]
	var ml = hud.get_node_or_null("RightVP/Control/Misses")
	if ml != null:
		ml.text = "0"
	var sl = hud.get_node_or_null("RightVP/Control/Score")
	if sl != null:
		sl.text = _commas(score)
	var tc = hud.get_node_or_null("ComboVP/Value")
	if tc != null:
		tc.text = str(combo)
	# the timer and health bar (they may be on the grid now)
	var timer_vp = hud.get_node_or_null("TimerVP/Control")
	if timer_vp != null:
		var tb = timer_vp.get_node_or_null("Time")
		if tb != null:
			tb.max_value = 1.0
			tb.value = clamp(t / loop_s, 0.0, 1.0)
		var tl = timer_vp.get_node_or_null("Label")
		if tl != null:
			tl.text = "%d:%02d / %d:%02d" % [int(t) / 60, int(t) % 60, int(loop_s) / 60, int(loop_s) % 60]
	var eb = hud.get_node_or_null("EnergyVP/Control/Energy")
	if eb != null:
		eb.max_value = 1.0
		eb.value = 1.0
	# rainbow / colorset HUD
	if Rhythia.rainbow_hud or Rhythia.colorset_hud:
		var tint: Color
		if Rhythia.colorset_hud:
			var o := Color(last_col.r, last_col.g, last_col.b, 1.0)
			if o.v < 0.75:
				o.v = 0.75
			_cs_tint = _cs_tint.linear_interpolate(o, min(1.0, delta * 10.0))
			tint = _cs_tint
		else:
			tint = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)
		_bar_set(eb, tint, Color(tint.r * 0.2, tint.g * 0.2, tint.b * 0.2, 0.65))
		for n in ["LeftHud", "RightHud", "ComboHud", "TimerHud", "EnergyHud"]:
			var s = hud.get_node_or_null(n)
			if s == null:
				for m in _moved:
					if is_instance_valid(m) and m.name == n:
						s = m
			if s is SpriteBase3D:
				s.modulate = tint
