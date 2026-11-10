extends Spatial

onready var Game: SongPlayerManager = get_parent()
onready var Spawn: NoteManager = get_parent().get_node("Spawn")


onready var timebar: ProgressBar = get_node("TimerVP/Control/Time")
onready var timelabel: Label = get_node("TimerVP/Control/Label")
onready var songnametxt: Label = get_node("TimerVP/Control/SongName")
onready var acclabel: Label = get_node("LeftVP/Control/Accuracy")
onready var accbar: ProgressBar = get_node("LeftVP/Control/AccuracyBar")
onready var pauselabel: Label = get_node("LeftVP/Control/Pauses")
onready var noteslabel: Label = get_node("RightVP/Control/Notes")
onready var misseslabel: Label = get_node("RightVP/Control/Misses")
onready var scorelabel: Label = get_node("RightVP/Control/Score")
onready var energybar: ProgressBar = get_node("EnergyVP/Control/Energy")
onready var modicons: HBoxContainer = get_node("EnergyVP/Control/Modifiers/Icons/H")
onready var modtxt: Label = get_node("EnergyVP/Control/Modifiers/Text")

onready var comboring: Control = get_node("LeftVP/Control/Combo")
onready var combotxt: Label = get_node("LeftVP/Control/Combo/Label")
onready var truecombo: Label = get_node("ComboVP/Value")

onready var lettergrade: Label = get_node("LeftVP/Control/LetterGrade")

onready var friend: MeshInstance = Spawn.get_node("Friend")

onready var cur_pos = $"../Spawn/Cursor".transform.origin
onready var pcur_pos = cur_pos


var panel_bg: Color = Rhythia.panel_bg
var panel_text: Color = Rhythia.panel_text

var unpause_fill_color: Color = Rhythia.unpause_fill_color
var unpause_empty_color: Color = Rhythia.unpause_empty_color
var how_to_quit: Color = Rhythia.how_to_quit

var combo_fill_color: Color = Rhythia.combo_fill_color
var combo_empty_color: Color = Rhythia.combo_empty_color

var acc_fill_color: Color = Rhythia.acc_fill_color
var acc_empty_color: Color = Rhythia.acc_empty_color

var energy_fill_color: Color = Rhythia.energy_fill_color
var energy_empty_color: Color = Rhythia.energy_empty_color

var giveup_text: Color = Rhythia.giveup_text
var giveup_fill_color: Color = Rhythia.giveup_fill_color
var giveup_fill_color_end_skip: Color = Rhythia.giveup_fill_color_end_skip

var timer_text: Color = Rhythia.timer_text
var timer_text_done: Color = Rhythia.timer_text_done
var timer_text_canskip: Color = Rhythia.timer_text_canskip

var timer_fg: Color = Rhythia.timer_fg
var timer_bg: Color = Rhythia.timer_bg
var timer_fg_done: Color = Rhythia.timer_fg_done
var timer_bg_done: Color = Rhythia.timer_bg_done
var timer_fg_canskip: Color = Rhythia.timer_fg_canskip
var timer_bg_canskip: Color = Rhythia.timer_bg_canskip

var miss_flash_color: Color = Rhythia.miss_flash_color
var pause_used_color: Color = Rhythia.pause_used_color

var miss_text_color: Color = Rhythia.miss_text_color
var pause_text_color: Color = Rhythia.pause_text_color
var score_text_color: Color = Rhythia.score_text_color

var pause_ui_opacity: float = Rhythia.pause_ui_opacity

var grade_ss_saturation: float = Rhythia.grade_ss_saturation
var grade_ss_value: float = Rhythia.grade_ss_value
var grade_ss_shine: float = Rhythia.grade_ss_shine

var grade_s_color: Color = Rhythia.grade_s_color
var grade_s_shine: float = Rhythia.grade_s_shine

var grade_a_color: Color = Rhythia.grade_a_color
var grade_b_color: Color = Rhythia.grade_b_color
var grade_c_color: Color = Rhythia.grade_c_color
var grade_d_color: Color = Rhythia.grade_d_color
var grade_f_color: Color = Rhythia.grade_f_color



var last_combo: int = 0
var rainbow_letter_grade: bool = false



var elapsed: float = 0
var gtimer: float = 0
var s_curspd: float = 0
var s_tcurspd: float = 0
var calculating: bool = false


func set_song_name(name: String = Rhythia.selected_song.name):
	songnametxt.text = name

func song_end(end_type: int):
	if end_type == Globals.END_GIVEUP and Rhythia.record_replays and not Rhythia.replaying:
		Rhythia.replay.store_sig(Spawn.rms, Globals.RS_GIVEUP)
	if end_type != Globals.END_PASS:
		friend.failed = true
		Rhythia.fail_asp.play()
	friend.upd()

var combo_ring_target: float = 0
var combo_ring_value: float = 0

# a mod's icon in the row with the speed ones (assets/images/modifiers/64)
func _mod_icon(name: String):
	var tex = load("res://assets/images/modifiers/64/%s_colored.png" % name)
	if tex == null or modicons.has_node("Mod_" + name):
		return
	var r := TextureRect.new()
	r.name = "Mod_" + name
	r.texture = tex
	r.rect_min_size = Vector2(64, 64)
	r.expand = true
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modicons.add_child(r)
	return r

# the custom speed's icon says how fast: "137%" in its lower half, under the dial
func _speed_custom_icon():
	var r = _mod_icon("speed_custom")
	if r == null:
		return
	var pct := int(round(float(Globals.speed_multi[Globals.SPEED_CUSTOM]) * 100.0))
	var l := Label.new()
	l.name = "Pct"
	l.text = "%d%%" % pct
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Black.ttf")
	f.size = 17 if pct < 1000 else 13
	f.outline_size = 2
	f.outline_color = Color(0.12, 0.05, 0.25)
	f.use_filter = true
	l.add_font_override("font", f)
	l.add_color_override("font_color", Color(1, 1, 1))
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.anchor_right = 1
	l.anchor_bottom = 1
	l.margin_top = 30 # (the dial is in the top half)
	l.margin_bottom = -10
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(l)

var _grade_shine = null
func update_static_values():
	var src_hits = _spectate_data.hits if spectating else Game.hits
	var src_total = _spectate_data.total_notes if spectating else Game.total_notes
	var src_misses = _spectate_data.misses if spectating else Game.misses
	var src_score = _spectate_data.score if spectating else Game.score
	var src_combo = _spectate_data.combo if spectating else Game.combo
	var src_combo_level = _spectate_data.combo_level if spectating else Game.combo_level

	if src_hits == src_total: acclabel.text = "100%"
	elif src_hits == 0: acclabel.text = "0%"
	else: acclabel.text = "%.3f%%" % ((src_hits / float(src_total)) * 100) if src_total > 0 else "0%"
	Rhythia.song_end_accuracy_str = acclabel.text
	if not src_total == 0:
		accbar.value = src_hits / float(src_total)
	noteslabel.text = "%s/%s" % [Globals.comma_sep(src_hits), Globals.comma_sep(src_total)]
	misseslabel.text = "%s" % Globals.comma_sep(src_misses)
	_update_sp(src_hits, src_total)

	if not spectating:
		energybar.max_value = Game.max_energy
		energybar.value = Game.energy
	else:
		energybar.max_value = 1.0
		energybar.value = _spectate_data.energy_pct

	combotxt.text = String(src_combo_level) + "x"
	combo_ring_target = (float(Game.lvl_progress) / 10.0) if not spectating else _spectate_data.lvl_progress_pct

	if src_combo != last_combo:
		truecombo.text = String(src_combo)
		truecombo.rect_position.y = 100
		last_combo = src_combo

	pauselabel.text = Globals.comma_sep(Rhythia.song_end_pause_count)

	for n in get_tree().get_nodes_in_group("pause_text"):
		paint(
			n,
			pause_text_color if (Rhythia.song_end_pause_count == 0)
			else pause_used_color
		)

	scorelabel.text = Globals.comma_sep(src_score)

	var grade: String = "--"
	var gcol: Color = Color(1, 0, 1)
	var shine: float = 0
	var acc = 100
	if src_total > 0:
		acc = src_hits / float(src_total)
	rainbow_letter_grade = (acc >= 0.99)
	if acc == 1 and Rhythia.show_fc_grade:
		grade = "FC"
		gcol = Color("#fa6afa")
	elif acc >= 0.99:
		grade = "SS"
		gcol = Color.from_hsv(Rhythia.rainbow_t * 0.1, grade_ss_saturation, grade_ss_value)
		shine = grade_ss_shine
	elif acc >= 0.98:
		grade = "S"; gcol = grade_s_color; shine = grade_s_shine
	elif acc >= 0.95:
		grade = "A"; gcol = grade_a_color
	elif acc >= 0.9:
		grade = "B"; gcol = grade_b_color
	elif acc >= 0.85:
		grade = "C"; gcol = grade_c_color
	elif acc >= 0.8:
		grade = "D"; gcol = grade_d_color
	else:
		grade = "F"; gcol = grade_f_color

	lettergrade.text = grade
	# (kept here: reading the material's value back waits for the renderer on
	# PC, and this runs on every hit)
	if shine != _grade_shine:
		_grade_shine = shine
		lettergrade.material.set_shader_param("amount", shine)

	if not _tinted_hud():
		lettergrade.set("custom_colors/font_color", gcol)

# ── SP readout (Settings > UI > Show SP) ──
# The SP passing now would give, at the accuracy so far, worked out like the
# server does (Savia.sp_for_accuracy). "- SP" when the play can't give SP (map
# not ranked, No Fail, other hit window...). At the top of the right panel,
# above the score.
var _sp_label: Label = null
var _sp_hits = 0
var _sp_total = 0

func _make_sp_label():
	if not Rhythia.show_sp_hud or Rhythia.selected_song == null:
		return
	_sp_label = noteslabel.duplicate()
	_sp_label.name = "SP"
	# (the score's font: it sits right above the score, and Notes' regular
	# weight looked out of place there; Settings > Fonts still applies)
	_sp_label.add_font_override("font", scorelabel.get_font("font"))
	_sp_label.visible = true
	_sp_label.margin_top = -890.0
	_sp_label.margin_bottom = -815.0
	get_node("RightVP/Control").add_child(_sp_label)
	# (the map's value comes from the server a moment after the start)
	var lm = _get_lobby_manager()
	if lm != null and not lm.is_connected("map_rank_info_received", self, "_on_sp_rank_info"):
		lm.connect("map_rank_info_received", self, "_on_sp_rank_info")
	_update_sp(0, 0)

func _on_sp_rank_info(_id, _ranked, _xp, _hash):
	call_deferred("_update_sp", _sp_hits, _sp_total) # (after Savia keeps the value)

func _update_sp(hits, total):
	if _sp_label == null:
		return
	_sp_hits = hits
	_sp_total = total
	# (watching someone: their settings aren't known here)
	_sp_label.visible = not spectating
	var acc: float = 1.0 if total <= 0 else float(hits) / float(total)
	var sp: int = Rhythia.sp_for_accuracy(acc)
	_sp_label.text = "- SP" if sp < 0 else "%s SP" % Globals.comma_sep(sp)

var miss_flash: float = 0

var _timer_state: int = -1
var _timer_shown_s: int = -1
var _timer_shown_ls: int = -1
var _timer_was_skip: bool = false
var _timer_end_s: int = -1
func update_timer(ms: float, canSkip: bool = false):
	var qms = ms + Spawn.ms_offset
	var lms = Game.last_ms

	if Rhythia.queue_active:
		lms = Rhythia.queue_end_length + (3000 * (Rhythia.song_queue.size() - 1))

	var s = clamp(floor(qms / 1000), 0, lms / 1000)
	var m = floor(s / 60)
	var rs = fmod(s, 60)

	var ls = floor(lms / 1000)
	var lm = floor(ls / 60)
	var lrs = fmod(ls, 60)

	# Runs every frame: colors are only repainted when the timer's state
	# changes, and text/bar only when they'd look different.
	var tstate: int = 1 if canSkip else (2 if (not Rhythia.queue_active and Spawn.ms > Game.last_ms) else 0)
	if not _tinted_hud() and tstate != _timer_state:
		_timer_state = tstate
		if canSkip:
			timebar.get("custom_styles/fg").bg_color = timer_fg_canskip
			timebar.get("custom_styles/bg").bg_color = timer_bg_canskip
			for n in get_tree().get_nodes_in_group("timer_text"):
				paint(n, timer_text_canskip)

		elif not Rhythia.queue_active and Spawn.ms > Game.last_ms:
			timebar.get("custom_styles/fg").bg_color = timer_fg_done
			timebar.get("custom_styles/bg").bg_color = timer_bg_done
			for n in get_tree().get_nodes_in_group("timer_text"):
				paint(n, timer_text_done)

		else:
			timebar.get("custom_styles/fg").bg_color = timer_fg
			timebar.get("custom_styles/bg").bg_color = timer_bg
			for n in get_tree().get_nodes_in_group("timer_text"):
				paint(n, timer_text)

	var tval: float = clamp(qms / lms, 0, 1)
	if abs(timebar.value - tval) > 0.0005 or (tval == 1.0 and timebar.value != 1.0):
		timebar.value = tval

	if canSkip:
		var expire_threshold_ms = ms + (3000 * Spawn.speed_multi)
		var skip_expires_sec = max(0.0, (Spawn.next_ms - expire_threshold_ms) / 1000.0)

		var action_text = "TAP" if Rhythia.device("mobile") else "PRESS SPACE"

		var skip_txt = "%s TO SKIP, Expires in  %.1fs" % [action_text, skip_expires_sec]
		if timelabel.text != skip_txt:
			timelabel.text = skip_txt
		var mcol = Color(1, 0.1, 0.1, 1) if skip_expires_sec < 1 else Color(1, 1, 1, 1)
		if timelabel.modulate != mcol:
			timelabel.set_modulate(mcol)
	else:
		if int(s) != _timer_shown_s or int(ls) != _timer_shown_ls or _timer_was_skip:
			_timer_shown_s = int(s)
			_timer_shown_ls = int(ls)
			timelabel.text = "%d:%02d / %d:%02d" % [m, rs, lm, lrs]
	_timer_was_skip = canSkip
	if int(s) != _timer_end_s:
		_timer_end_s = int(s)
		Rhythia.song_end_time_str = "%d:%02d" % [m, rs]

	if Rhythia.queue_active:
		if ms >= Game.last_ms + Rhythia.hitwindow_ms:
			songnametxt.text = "(Intermission)"
		else:
			songnametxt.text = Rhythia.selected_song.name

func on_miss(color: Color):
	if spectating:
		return
	miss_flash = 1

func paint(node: Control, color: Color):
	if node is ColorRect:
		node.color = color

	elif node is Panel:
		node.get("custom_styles/panel").bg_color = color

	elif node is Label:
		if node.has_color_override("font_color"):
			node.set("custom_colors/font_color", color)
		else:
			node.modulate = color

	else:
		node.modulate = color

var config_time: float = 2.5


const ReplayControlsScene = preload("res://prefabs/game/ReplayControls.tscn")
var replay_controls: CanvasLayer

func _build_replay_controls():
	if not Rhythia.replaying or Rhythia.replay.autoplayer or Rhythia.replay.sv == 1: return
	replay_controls = ReplayControlsScene.instance()
	add_child(replay_controls)
	replay_controls.setup(Spawn)

# The HUD panels are drawn into off-screen viewports. Redrawing all of them
# every frame is a big cost at high FPS, so they refresh at most
# HUD_REFRESH_HZ times a second (looks identical; monitors don't go higher).
const HUD_REFRESH_HZ = 240.0
var _hud_vps: Array = []
var _hud_shown_by: Array = []
var _hud_refresh_t: float = 0.0
var _stats_t: float = 0.0

func _setup_hud_viewports():
	for c in get_children():
		if c is Viewport:
			c.msaa = Viewport.MSAA_DISABLED # 2D-only, anti-aliasing does nothing here
			c.render_target_update_mode = Viewport.UPDATE_ONCE
			_hud_vps.append(c)
			# The 3D sprite showing this viewport (TimerVP -> TimerHud).
			_hud_shown_by.append(get_node_or_null(c.name.trim_suffix("VP") + "Hud"))

func _refresh_hud_viewports(delta: float):
	_hud_refresh_t += delta
	if _hud_refresh_t < 1.0 / HUD_REFRESH_HZ:
		return
	_hud_refresh_t = 0.0
	# Panels that aren't on screen (pause, give up, config...) aren't redrawn.
	for i in range(_hud_vps.size()):
		var shown = _hud_shown_by[i]
		if shown != null and not shown.is_visible_in_tree():
			continue
		_hud_vps[i].render_target_update_mode = Viewport.UPDATE_ONCE

var _timer_hud = null

# --- Rainbow HUD / Colorset HUD: the whole HUD (text, numbers, bars) tinted ---
func _tinted_hud() -> bool:
	return Rhythia.rainbow_hud or Rhythia.colorset_hud

# Colorset HUD: the colour of the last note you hit, blended in quickly
var _cs_tint: Color = Color(1, 1, 1)
var _cs_tint_target: Color = Color(1, 1, 1)

func _on_hit_for_colorset_hud(col):
	if typeof(col) == TYPE_COLOR:
		_cs_tint_target = _readable(col)

# (dark colours would make the text hard to read)
static func _readable(c: Color) -> Color:
	var o := Color(c.r, c.g, c.b, 1.0)
	if o.v < 0.75:
		o.v = 0.75
	return o

func _hud_tint(delta: float) -> Color:
	if Rhythia.colorset_hud:
		_cs_tint = _cs_tint.linear_interpolate(_cs_tint_target, min(1.0, delta * 10.0))
		return _cs_tint
	return Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)

func _process(delta: float):
	gtimer += delta
	_refresh_hud_viewports(delta)
	_update_spectate_render(delta)
	_update_replay_vr()
	if spectating and _real_cursor != null and is_instance_valid(_real_cursor):
		_real_cursor.check_debug_mouse_toggle()
	if Rhythia.show_config:
		config_time = max(config_time - delta, 0)
		if config_time <= 0: $ConfigHud.visible = false
		else: $ConfigHud.opacity = min(1, config_time)

	if combo_ring_value > combo_ring_target:
		combo_ring_value = max(combo_ring_value + (
			((combo_ring_target - combo_ring_value) * delta * 6)
		), combo_ring_target)
	elif combo_ring_value < combo_ring_target:
		combo_ring_value = min(combo_ring_value + (
			((combo_ring_target - combo_ring_value) * delta * 6)
		), combo_ring_target)

	if comboring.percent != combo_ring_value:
		comboring._set_percent(combo_ring_value)

	if Input.is_action_pressed("give_up"):
		get_node("GiveUpHud").visible = true
		get_node("GiveUpVP/Control/Label").visible = not $PauseHud.visible
		if Spawn.ms > Game.last_ms:
			get_node("GiveUpVP/Control/Label").text = "Skipping..."
			get_node("GiveUpVP/Control").fill_color = giveup_fill_color_end_skip

		get_node("GiveUpVP/Control").percent = Game.giving_up
		get_node("GiveUpHud").opacity = min(Game.giving_up * 2, 1)
	else:
		get_node("GiveUpHud").visible = false
		get_node("GiveUpHud").opacity = 0

	if rainbow_letter_grade and not _tinted_hud():
		lettergrade.set("custom_colors/font_color", Color.from_hsv(Rhythia.rainbow_t * 0.1, grade_ss_saturation, grade_ss_value))

	if miss_flash != 0:
		var miss_col = lerp(miss_text_color, miss_flash_color, miss_flash)
		for n in get_tree().get_nodes_in_group("miss_text"):
			paint(n, miss_col)
		miss_flash = max(0, miss_flash - (delta * 3))

	if _tinted_hud():
		var tint: Color = _hud_tint(delta)
		energybar.get("custom_styles/fg").bg_color = tint
		energybar.get("custom_styles/bg").bg_color = Color(tint.r * 0.2, tint.g * 0.2, tint.b * 0.2, 0.65)
		# The timer may have been moved onto the grid (attach_timer_to_grid), so it
		# is kept in a variable instead of being looked up under the HUD.
		if is_instance_valid(_timer_hud):
			_timer_hud.modulate = tint
		$ComboHud.modulate = tint
		$LeftHud.modulate = tint
		$RightHud.modulate = tint

	if Spawn.pause_state != 0:
		$PauseHud.visible = not Input.is_key_pressed(KEY_C)
		$PauseVP/Control.percent = clamp(
			1 - (Spawn.pause_state),
			0,
			float(Spawn.pause_state != -1)
		)
		$PauseHud.modulate = Color(1, 1, 1, abs(Spawn.pause_state) * pause_ui_opacity)
	else:
		$PauseHud.visible = false


	elapsed += delta
	if elapsed >= 0.1 and calculating:
		pcur_pos = cur_pos
		cur_pos = $"../Spawn/Cursor".transform.origin
		var dist = cur_pos.distance_to(pcur_pos)
		s_curspd = dist / elapsed
		if s_curspd > s_tcurspd:
			s_tcurspd = s_curspd
		elapsed = 0
	if gtimer >= 2:
		calculating = true

	# Debug stats panel: only rebuild its text when shown, 10x a second.
	_stats_t += delta
	if _stats_t < 0.1 or not $Stats/Label.visible:
		return
	_stats_t = 0.0
	var fstr = "cursor speed\n{current} m/sec/{frames}fr\n\ntop speed\n{top} m/sec/{frames}fr\n\nrec interval\n{rec}"
	$Stats/Label.text = fstr.format(
		{
			"current": stepify(s_curspd, 0.1),
			"frames": Engine.get_frames_per_second(),
			"top": stepify(s_tcurspd, 0.1),
			"rec": round(Spawn.rec_interval)
		}
	)









var spectating: bool = false
var spectate_peer_id: int = -1
var _spectate_data: Dictionary = {
	"score": 0, "hits": 0, "misses": 0, "total_notes": 0, "combo": 0, "combo_level": 1,
	"energy_pct": 1.0, "lvl_progress_pct": 0.0,
}
var ghost_cursor: MeshInstance = null

# Playback: the watched player sends where they are up to 60 times a second,
# with their map time (ms). Playback runs on a steady clock: your own clock
# plus a fixed offset to their map time, taken from the messages that arrived
# quickest (late ones don't pull it around), a little behind so the next
# position is usually already here. The cursor follows a smooth curve through
# the positions. So notes and music move at an even speed whatever the network
# does, and the cursor doesn't cut corners.
const SPEC_KEEP_MS := 6000.0
const SPEC_WINDOW_SEC := 3.0      # how far back the quickest arrival is looked for
const SPEC_MIN_DELAY_SEC := 0.08
const SPEC_MAX_DELAY_SEC := 0.4
var _spec_samples: Array = []
var _spec_ms: float = 0.0
var _spec_clock_set: bool = false
var _spec_offsets: Array = []     # [arrival time, their ms - your clock]
var _spec_offset: float = 0.0
var _spec_delay: float = 0.12     # follows how uneven the arrivals are
var _spec_delay_target: float = 0.12
var _spec_reloading: bool = false

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func _spec_settings():
	return load("res://scripts/SpectateSettings.gd")

func enter_spectate_mode(peer_id: int):
	spectating = true
	call_deferred("_spectate_discord_status", peer_id)
	process_priority = -10 # the watched time is set before the notes move this frame
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		if not lobby_manager.is_connected("live_state_received", self, "_on_spectate_live_state"):
			lobby_manager.connect("live_state_received", self, "_on_spectate_live_state")
		if not lobby_manager.is_connected("lobby_state_changed", self, "_on_spectate_lobby_state_changed"):
			lobby_manager.connect("lobby_state_changed", self, "_on_spectate_lobby_state_changed")
		if not lobby_manager.is_connected("player_failed", self, "_on_spectate_target_failed"):
			lobby_manager.connect("player_failed", self, "_on_spectate_target_failed")
		if not lobby_manager.is_connected("player_settings_received", self, "_on_spectate_settings_received"):
			lobby_manager.connect("player_settings_received", self, "_on_spectate_settings_received")
	_create_ghost_cursor()
	_create_spectate_banner()
	if not Rhythia.vr and _spec_page_layer == null:
		# the Spectate window (eye button, bottom right): who's online and the
		# global chat, the same as in the menu
		_spec_page_layer = CanvasLayer.new()
		_spec_page_layer.layer = 95
		add_child(_spec_page_layer)
		_spec_page = Control.new()
		_spec_page.name = "Spectate"
		_spec_page.set_script(load("res://scripts/ui/menu/SpectatePage.gd"))
		_spec_page_layer.add_child(_spec_page)
	if not Rhythia.vr:
		# the switch button and the scoreboard are clicked with the mouse
		Input.set_custom_mouse_cursor(null)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_set_spectate_target(peer_id)

# Watch peer_id (the server sends their settings back).
func _set_spectate_target(peer_id: int):
	spectate_peer_id = peer_id
	_spec_reset_clock()
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.report_spectate_target(peer_id)
	_update_spectate_target_name()
	_check_view_settings()

func spectate_specific_player(peer_id: int):
	if not spectating or peer_id == spectate_peer_id or _spec_reloading:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or peer_id == lobby_manager.local_peer_id:
		return
	for p in lobby_manager.players:
		if int(p.get("peer_id", -1)) == peer_id:
			_set_spectate_target(peer_id)
			return

func _on_spectate_target_failed(peer_id):
	if spectating and peer_id == spectate_peer_id:
		_pick_next_target()

func _on_spectate_lobby_state_changed():
	if not spectating:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	for p in lobby_manager.players:
		if int(p.get("peer_id", -1)) == spectate_peer_id:
			if bool(p.get("failed", false)):
				break
			_update_spectate_target_name()
			return
	_pick_next_target() # they failed or left

func _pick_next_target():
	if _spec_reloading:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var next = lobby_manager.get_first_place_peer_id()
	if next == -1 and lobby_manager.watch_mode:
		return # (Spectate tab: the server says when it's over, with why)
	if next == -1:
		_end_spectate_and_return_to_lobby()
	elif next != spectate_peer_id:
		_set_spectate_target(next)

# Discord: Spectating <their name>
func _spectate_discord_status(peer_id: int):
	var lm = _get_lobby_manager()
	var who := ""
	if lm != null:
		for p in lm.players:
			if p is Dictionary and int(p.get("peer_id", -1)) == peer_id:
				who = Globals.s(p.get("name", ""))
		if who == "":
			who = Globals.s(lm.get("watch_target_name"))
	Rhythia.update_rpc_spectating(who)

func exit_spectate_mode():
	spectating = false
	spectate_peer_id = -1
	_set_spec_paused(false)
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.report_spectate_target(-1)
	_spec_reset_clock()
	_spec_vr_head = null
	_spec_hand_sig = ""
	if _spec_vr_holder != null:
		_spec_vr_holder.queue_free()
		_spec_vr_holder = null
		_spec_vr_hands = []
	if spectate_cursor != null:
		spectate_cursor.queue_free()
		spectate_cursor = null
	if _spectate_ui != null:
		_spectate_ui.queue_free()
		_spectate_ui = null
		_spectate_banner = null
		_spectate_view_button = null
	if _spec_vr_sprite != null:
		_spec_vr_sprite.visible = false
	if _spec_page_layer != null:
		_spec_page_layer.queue_free()
		_spec_page_layer = null
		_spec_page = null
	if _real_cursor != null and is_instance_valid(_real_cursor):
		_real_cursor.visible = true
		_real_cursor.set_process(true)
		_real_cursor.set_process_input(true)
	_real_cursor = null

func _end_spectate_and_return_to_lobby():
	var lm = _get_lobby_manager()
	if lm != null and lm.watch_mode:
		exit_spectate_mode()
		get_parent().leave_watching()
		return
	exit_spectate_mode()
	var game = get_parent()
	if game != null and game.has_method("show_round_results"):
		game.show_round_results()
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.reset_lobby_round()
	get_tree().paused = false
	get_parent().black_fade_target = true
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

# The watched player paused (or is counting back in): their position stays
# put, Paused shows, the music waits. When they go on, the clock starts over
# from their new positions (before, it kept timing off the ones from before
# the pause and the notes and music stuttered for seconds).
var spec_paused: bool = false
var _spec_paused_label: Label = null

func _set_spec_paused(p: bool):
	if p == spec_paused:
		return
	spec_paused = p
	if p and _spec_paused_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_spec_paused_label = Label.new()
		var f = DynamicFont.new()
		f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
		f.size = 42
		_spec_paused_label.add_font_override("font", f)
		_spec_paused_label.add_color_override("font_color", Color(1, 1, 1, 0.92))
		_spec_paused_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.7))
		_spec_paused_label.add_constant_override("shadow_offset_x", 3)
		_spec_paused_label.add_constant_override("shadow_offset_y", 3)
		_spec_paused_label.text = "Paused"
		_spec_paused_label.align = Label.ALIGN_CENTER
		_spec_paused_label.valign = Label.VALIGN_CENTER
		_spec_paused_label.anchor_right = 1.0
		_spec_paused_label.anchor_bottom = 1.0
		_spec_paused_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_spec_paused_label)
	if _spec_paused_label != null:
		_spec_paused_label.visible = p
	if not p:
		_spec_reset_clock() # (their time jumped by the pause)

func _on_spectate_live_state(peer_id, x, y, combo, combo_level, score, hits, misses, total_notes, energy_pct, lvl_progress_pct, chart_ms):
	if not spectating or peer_id != spectate_peer_id:
		return
	var lm_p = _get_lobby_manager()
	var paused_now: bool = lm_p != null and bool(lm_p._live_state_cache.get(peer_id, {}).get("paused", false))
	_set_spec_paused(paused_now)
	if paused_now:
		return
	if not _spec_samples.empty():
		var last_ms: float = _spec_samples[_spec_samples.size() - 1].ms
		if chart_ms < last_ms - 1000.0:
			_spec_reset_clock() # their map time went back: start over
		elif chart_ms <= last_ms:
			return # late or repeated
	var now: float = OS.get_ticks_usec() / 1000000.0
	var vr_pose = null
	var dx := 0.0
	var dy := 0.0
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		var cached: Dictionary = lobby_manager._live_state_cache.get(peer_id, {})
		var raw = cached.get("vr", null)
		if raw is Array and raw.size() == 22:
			vr_pose = raw
		dx = float(cached.get("dx", 0.0))
		dy = float(cached.get("dy", 0.0))
	_spec_samples.append({
		"vr": vr_pose, "dx": dx, "dy": dy,
		"t": now, "ms": chart_ms, "x": x, "y": y,
		"combo": combo, "combo_level": combo_level, "score": score,
		"hits": hits, "misses": misses, "total_notes": total_notes,
		"energy_pct": energy_pct, "lvl_progress_pct": lvl_progress_pct,
	})
	while _spec_samples.size() > 4 and _spec_samples[0].ms < chart_ms - SPEC_KEEP_MS:
		_spec_samples.pop_front()
	# their map time against your clock (map ms run at the song speed)
	_spec_offsets.append([now, chart_ms - now * 1000.0 * _spec_speed()])
	while _spec_offsets.size() > 1 and _spec_offsets[0][0] < now - SPEC_WINDOW_SEC:
		_spec_offsets.pop_front()
	if _spec_offsets.size() % 8 == 0:
		_spec_update_delay()

func _spec_speed() -> float:
	return max(Spawn.speed_multi, 0.05) if Spawn != null else 1.0

var _spec_stats_ms := -INF # (the update whose numbers are on the HUD)
func _spec_reset_clock():
	_spec_stats_ms = -INF
	_spec_samples.clear()
	_spec_offsets.clear()
	_spec_clock_set = false

func _spec_best_offset() -> float:
	var best: float = -INF
	for o in _spec_offsets:
		best = max(best, o[1])
	return best

# How late messages come compared with the quickest ones: the delay covers
# the latest of the last few seconds (plus a little), so the next position is
# here in time and playback never has to wait.
func _spec_update_delay():
	var best := _spec_best_offset()
	var lates := []
	for o in _spec_offsets:
		lates.append((best - o[1]) / (1000.0 * _spec_speed()))
	lates.sort()
	var latest: float = lates[lates.size() - 1] if lates.size() > 0 else 0.1
	_spec_delay_target = clamp(latest + 0.05, SPEC_MIN_DELAY_SEC, SPEC_MAX_DELAY_SEC)

func _update_spectate_render(delta: float):
	if not spectating or spectate_cursor == null or _spec_samples.empty() or Spawn == null:
		return
	var spd := _spec_speed()
	var now: float = OS.get_ticks_usec() / 1000000.0
	var best := _spec_best_offset()
	if not _spec_clock_set or abs(best - _spec_offset) > 400.0 * spd:
		_spec_offset = best # start, a skip, or far off: jump
		_spec_delay = _spec_delay_target
		_spec_clock_set = true
	else:
		# small changes are taken in slowly so the speed stays even
		_spec_offset += (best - _spec_offset) * min(1.0, delta * 0.5)
		_spec_delay += (_spec_delay_target - _spec_delay) * min(1.0, delta * 0.5)
	var play: float = now * 1000.0 * spd + _spec_offset - _spec_delay * 1000.0 * spd
	if play < _spec_ms and _spec_ms - play < 400.0 * spd:
		play = _spec_ms # never a little backwards
	var newest: Dictionary = _spec_samples[_spec_samples.size() - 1]
	_spec_ms = min(play, newest.ms) # no newer position yet: wait on the last one
	spectate_cursor.transform.origin = _spec_cursor_at(_spec_ms)
	_update_spectate_drift(_spec_ms)
	_update_spectate_vr(_spec_ms)
	# (the numbers only when a newer update of theirs is reached: redone every
	# frame, the HUD's texts were laid out again each frame)
	var sample: Dictionary = _spec_sample_before(_spec_ms)
	if float(sample.ms) != _spec_stats_ms:
		_spec_stats_ms = float(sample.ms)
		_apply_spectate_stats(sample)
		update_static_values()
	Spawn.ms = _spec_ms # NoteManager moves the notes and keeps the music with it

# --- watching someone in VR: their hands, beam and (with their settings) view ---
# Their head and hands come with each position, placed next to the game, so
# they land in the same spot in your scene. The hands and beam are the game's
# own (vr/VRPlayer.tscn); the beam ends on their cursor.
var _spec_vr_holder: Spatial = null
var _spec_vr_hands: Array = [] # [left, right]
var _spec_vr_head = null # Transform next to the game, or null

func vr_view_on() -> bool:
	return spectating and typeof(_spec_vr_head) == TYPE_TRANSFORM and not Rhythia.vr \
		and _spec_settings().applied_for() == spectate_peer_id

func apply_vr_view(cam: Camera):
	if typeof(_spec_vr_head) == TYPE_TRANSFORM:
		cam.global_transform = get_parent().global_transform * _spec_vr_head

func _pose_at(arr: Array, o: int) -> Transform:
	var q := Quat(arr[o + 3], arr[o + 4], arr[o + 5], arr[o + 6]).normalized()
	return Transform(Basis(q), Vector3(arr[o], arr[o + 1], arr[o + 2]))

func _spec_make_hands():
	if _spec_vr_holder != null:
		return
	_spec_vr_holder = Spatial.new()
	_spec_vr_holder.name = "SpectatedVRHands"
	get_parent().add_child(_spec_vr_holder)
	var scene = load("res://vr/VRPlayer.tscn")
	if not (scene is PackedScene):
		return
	# only the plain hands (FakeOrigin) are taken; the rest never enters the tree
	var vrp = scene.instance()
	var fake = vrp.get_node_or_null("FakeOrigin")
	for n in ["LeftHand", "RightHand"]:
		var h = fake.get_node_or_null(n) if fake != null else null
		if h == null:
			continue
		fake.remove_child(h)
		h.owner = null
		for c in h.get_children():
			c.owner = null
		_spec_vr_holder.add_child(h)
		_spec_vr_hands.append(h)
	vrp.free()

func _update_spectate_vr(ms: float):
	_spec_vr_head = null
	var n: int = _spec_samples.size()
	var i: int = _spec_index_before(ms)
	var a: Dictionary = _spec_samples[i]
	if not (a.get("vr") is Array):
		if _spec_vr_holder != null:
			_spec_vr_holder.visible = false
		return
	var b: Dictionary = _spec_samples[i + 1] if i + 1 < n and _spec_samples[i + 1].get("vr") is Array else a
	var alpha: float = 0.0
	if b.ms > a.ms:
		alpha = clamp((ms - a.ms) / (b.ms - a.ms), 0.0, 1.0)
	var pa: Array = a.vr
	var pb: Array = b.vr
	_spec_vr_head = _pose_at(pa, 1).interpolate_with(_pose_at(pb, 1), alpha)
	_spec_make_hands()
	if _spec_vr_hands.size() < 2:
		return
	_spec_vr_holder.visible = true
	_spec_hand_look()
	var pointing: int = 0 if pa[0] > 0.5 else 1 # left : right
	for k in range(2):
		var o: int = 8 + k * 7
		var hand: Spatial = _spec_vr_hands[k]
		hand.transform = _pose_at(pa, o).interpolate_with(_pose_at(pb, o), alpha)
		var ray = hand.get_node_or_null("Ray")
		if ray == null:
			continue
		ray.enabled = k == pointing
		if k == pointing and ray.has_method("update_beam") and spectate_cursor != null:
			ray.set_target(spectate_cursor.global_transform.origin)
			ray.update_beam()

# --- a VR play's replay: their head is the camera, their hands and beam show ---
# (Replay.vr_samples, recorded at about 20 a second; the same pose as spectators get)
var _replay_vr_i := 0
func replay_vr_on() -> bool:
	return Rhythia.replaying and not Rhythia.vr and not spectating and Rhythia.replay != null and not Rhythia.replay.vr_samples.empty() and typeof(_spec_vr_head) == TYPE_TRANSFORM

func _update_replay_vr():
	if not Rhythia.replaying or spectating or Rhythia.vr or Rhythia.replay == null or Rhythia.replay.vr_samples.empty():
		return
	var spawn = get_node_or_null("../Spawn")
	if spawn == null:
		return
	var rms: float = float(spawn.get("rms"))
	var smp: Array = Rhythia.replay.vr_samples
	var i: int = clamp(_replay_vr_i, 0, smp.size() - 1)
	while i > 0 and float(smp[i][0]) > rms:
		i -= 1
	while i + 1 < smp.size() and float(smp[i + 1][0]) <= rms:
		i += 1
	_replay_vr_i = i
	var pa: Array = smp[i][1]
	var pb: Array = smp[i + 1][1] if i + 1 < smp.size() else pa
	var alpha := 0.0
	if i + 1 < smp.size() and float(smp[i + 1][0]) > float(smp[i][0]):
		alpha = clamp((rms - float(smp[i][0])) / (float(smp[i + 1][0]) - float(smp[i][0])), 0.0, 1.0)
	_spec_vr_head = _pose_at(pa, 1).interpolate_with(_pose_at(pb, 1), alpha)
	_spec_make_hands()
	if _spec_vr_hands.size() < 2:
		return
	_spec_vr_holder.visible = true
	var cursor = spawn.get("_n_cursor")
	var pointing: int = 0 if pa[0] > 0.5 else 1 # left : right
	for k in range(2):
		var hand: Spatial = _spec_vr_hands[k]
		hand.transform = _pose_at(pa, 8 + k * 7).interpolate_with(_pose_at(pb, 8 + k * 7), alpha)
		var ray = hand.get_node_or_null("Ray")
		if ray == null:
			continue
		ray.enabled = k == pointing
		if k == pointing and ray.has_method("update_beam") and cursor is Spatial:
			ray.set_target(cursor.global_transform.origin)
			ray.update_beam()

# Their hands as they see them (Settings > VR > Hands): the furry paws, or
# their own vr_hand.obj once downloaded (LobbyManager.fetch_spectate_assets);
# checked about once a second until it's there.
var _spec_hand_sig := ""
var _spec_hand_check_at := 0
func _spec_hand_look():
	var now := OS.get_ticks_msec()
	if now < _spec_hand_check_at:
		return
	_spec_hand_check_at = now + 1000
	var lm = _get_lobby_manager()
	var s = lm.player_view_settings.get(spectate_peer_id, {}) if lm != null else {}
	if not (s is Dictionary):
		s = {}
	var kind: String = String(s.get("vr_hand", "default"))
	var spec = _spec_settings()
	var rpath: String = spec.cached_asset(String(s.get("vr_hand_file", "")).to_lower(), "obj") if kind == "custom" else ""
	var lpath: String = spec.cached_asset(String(s.get("vr_hand_left_file", "")).to_lower(), "obj") if kind == "custom" else ""
	var sig := "%s|%s|%s" % [kind, rpath, lpath]
	if sig == _spec_hand_sig:
		return
	_spec_hand_sig = sig
	var VRP = load("res://vr/VRPlayer.gd")
	var meshes = null # [left, right]
	if kind == "paw":
		var r = load("res://vr/PawHand.gd").build()
		meshes = [VRP._mirrored(r), r]
	elif kind == "ball":
		var b = load("res://vr/BallHand.gd").build()
		meshes = [b, b]
	elif load("res://vr/ExtraHands.gd").has(kind):
		meshes = load("res://vr/ExtraHands.gd").pair(kind)
	elif kind == "custom" and rpath != "":
		var ObjParse = load("res://scripts/content/resources/ObjParse.gd")
		var r = ObjParse.load_obj(rpath)
		if r != null and r.get_surface_count() > 0:
			var l = ObjParse.load_obj(lpath) if lpath != "" else null
			if l == null or l.get_surface_count() == 0:
				l = VRP._mirrored(r)
			meshes = [l, r]
	for k in range(_spec_vr_hands.size()):
		var hand: Spatial = _spec_vr_hands[k]
		var mi = hand.get_node_or_null("Mesh")
		if not (mi is MeshInstance):
			continue
		if not mi.has_meta("hand_default"):
			mi.set_meta("hand_default", [mi.mesh, mi.transform, mi.get_surface_material(0)])
		var d: Array = mi.get_meta("hand_default")
		var outline = mi.get_node_or_null("Outline")
		var trail = mi.get_node_or_null("HandTrail")
		var ray = hand.get_node_or_null("Ray")
		if ray != null and "start_gap" in ray:
			ray.start_gap = 0.0
			var XH = load("res://vr/ExtraHands.gd")
			if (kind == "paw" or kind == "ball" or XH.has(kind)) and meshes != null:
				var tip: float = load("res://vr/PawHand.gd").TIP if kind == "paw" else (load("res://vr/BallHand.gd").TIP if kind == "ball" else XH.tip(kind))
				ray.start_gap = max(0.0, ray.transform.origin.z + tip * VRP.UNITS_PER_M)
		if meshes == null:
			mi.mesh = d[0]
			mi.transform = d[1]
			mi.set_surface_material(0, d[2])
			if outline:
				outline.visible = true
			if trail:
				trail.transform = Transform()
			continue
		var mesh: Mesh = meshes[k]
		mi.mesh = mesh
		mi.transform = Transform(Basis().scaled(Vector3(VRP.UNITS_PER_M, VRP.UNITS_PER_M, VRP.UNITS_PER_M)), Vector3.ZERO)
		for j in range(mesh.get_surface_count()):
			mi.set_surface_material(j, null if mesh.surface_get_material(j) != null else d[2])
		if outline:
			outline.visible = false
		if trail:
			trail.transform = Transform(Basis().scaled(Vector3(0.02, 0.02, 0.06)), Vector3.ZERO)

func _spec_index_before(ms: float) -> int:
	var i: int = _spec_samples.size() - 1
	while i > 0 and _spec_samples[i].ms > ms:
		i -= 1
	return i

func _spec_sample_before(ms: float) -> Dictionary:
	return _spec_samples[_spec_index_before(ms)]

# A smooth curve through the positions (Catmull-Rom on their map times).
# their buffer (drift) cursor: its offset comes with each position. Shown
# with their settings on (Buffer Cursor), and camera parallax follows it with
# their Follow Buffer Cursor (NoteManager.do_half_lock)
var spectate_drift := Vector3.ZERO
func _update_spectate_drift(ms: float):
	var i: int = _spec_index_before(ms)
	var p1: Dictionary = _spec_samples[i]
	var d := Vector2(float(p1.get("dx", 0.0)), float(p1.get("dy", 0.0)))
	if i + 1 < _spec_samples.size() and ms > p1.ms:
		var p2: Dictionary = _spec_samples[i + 1]
		var u: float = clamp((ms - p1.ms) / max(p2.ms - p1.ms, 0.001), 0.0, 1.0)
		d = d.linear_interpolate(Vector2(float(p2.get("dx", 0.0)), float(p2.get("dy", 0.0))), u)
	spectate_drift = Vector3(d.x, d.y, 0)
	var m2 = spectate_cursor.get_node_or_null("Mesh2")
	if m2 != null:
		var on: bool = Rhythia.enable_drift_cursor and d.length() > 0.0005
		m2.visible = on
		if on:
			m2.transform.origin.x = d.x
			m2.transform.origin.y = d.y

func _spec_cursor_at(ms: float) -> Vector3:
	var n: int = _spec_samples.size()
	var z: float = spectate_cursor.transform.origin.z
	var i: int = _spec_index_before(ms)
	var p1: Dictionary = _spec_samples[i]
	if i >= n - 1 or ms <= p1.ms:
		return Vector3(p1.x, p1.y, z)
	var p2: Dictionary = _spec_samples[i + 1]
	var p0: Dictionary = _spec_samples[i - 1] if i > 0 else p1
	var p3: Dictionary = _spec_samples[i + 2] if i + 2 < n else p2
	var h: float = max(p2.ms - p1.ms, 0.001)
	var u: float = clamp((ms - p1.ms) / h, 0.0, 1.0)
	var a := Vector2(p1.x, p1.y)
	var b := Vector2(p2.x, p2.y)
	var m1: Vector2 = (b - Vector2(p0.x, p0.y)) / max(p2.ms - p0.ms, 0.001) * h
	var m2: Vector2 = (Vector2(p3.x, p3.y) - a) / max(p3.ms - p1.ms, 0.001) * h
	var u2 := u * u
	var u3 := u2 * u
	var pos: Vector2 = a * (2.0 * u3 - 3.0 * u2 + 1.0) + m1 * (u3 - 2.0 * u2 + u) + b * (-2.0 * u3 + 3.0 * u2) + m2 * (u3 - u2)
	return Vector3(pos.x, pos.y, z)

func _apply_spectate_stats(sample: Dictionary):
	_spectate_hit_sounds(int(sample.hits) - int(_spectate_data.hits), int(sample.misses) - int(_spectate_data.misses))
	_spectate_data.score = sample.score
	_spectate_data.hits = sample.hits
	_spectate_data.misses = sample.misses
	_spectate_data.total_notes = sample.total_notes
	_spectate_data.combo = sample.combo
	_spectate_data.combo_level = sample.combo_level
	_spectate_data.energy_pct = sample.energy_pct
	_spectate_data.lvl_progress_pct = sample.lvl_progress_pct

# Watching someone: their hits and misses as sounds. The notes aren't judged
# here while spectating (NoteManager skips its sounds then), so a spectator
# heard nothing: the counts going up are the hits / misses. A big jump (the
# first sample, joining late, switching player) isn't played.
const SPEC_SOUND_JUMP := 6
func _spectate_hit_sounds(dh: int, dm: int):
	if not spectating or get_tree().paused:
		return
	if dh > 0 and dh <= SPEC_SOUND_JUMP and Rhythia.play_hit_snd:
		var at: Transform = spectate_cursor.global_transform if is_instance_valid(spectate_cursor) else Transform()
		for _k in range(min(dh, 3)):
			SFXManager.play_hitsfx(at)
	if dm > 0 and dm <= SPEC_SOUND_JUMP and Rhythia.play_miss_snd:
		if Rhythia.sfx_2d:
			var m2 = Spawn.get_node_or_null("Miss2D")
			if m2 != null: m2.play()
		else:
			var m3 = Spawn.get_node_or_null("Miss")
			if m3 != null:
				if is_instance_valid(spectate_cursor):
					m3.global_transform = spectate_cursor.global_transform
				m3.play()

# --- their settings or yours ----------------------------------------------------
# Most settings are read when the song scene is built, so switching reloads it
# straight into spectating the same player (LobbyManager.reload_into_spectate).

func _on_spectate_settings_received(peer_id):
	if spectating and peer_id == spectate_peer_id:
		_check_view_settings()

func _check_view_settings():
	_update_view_button()
	_spectate_cursor_picture()
	if not spectating or _spec_reloading:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var spec = _spec_settings()
	var on_for: int = spec.applied_for() # -1: yours
	if spec.prefer_theirs():
		if on_for == spectate_peer_id or not lobby_manager.player_view_settings.has(spectate_peer_id):
			return # already on, or not here yet
		if lobby_manager.has_player_settings(spectate_peer_id):
			_reload_spectate(true)
		elif on_for != -1:
			_reload_spectate(false) # they sent none (an older game): yours
	elif on_for != -1:
		_reload_spectate(false)

func _reload_spectate(theirs: bool):
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or not lobby_manager.lobby_active or not bool(lobby_manager.lobby_state.get("started", false)):
		return
	_spec_reloading = true
	var spec = _spec_settings()
	if theirs:
		spec.apply(lobby_manager.player_view_settings[spectate_peer_id], spectate_peer_id)
	else:
		spec.restore()
	_update_view_button()
	lobby_manager.reload_into_spectate(spectate_peer_id)

func toggle_spectate_view():
	if not spectating or _spec_reloading:
		return
	var spec = _spec_settings()
	spec.set_prefer_theirs(not spec.prefer_theirs())
	var lobby_manager = _get_lobby_manager()
	if spec.prefer_theirs() and lobby_manager != null and not lobby_manager.player_view_settings.has(spectate_peer_id):
		lobby_manager.request_player_settings(spectate_peer_id)
	if Rhythia.vr:
		Globals.notify(Globals.NOTIFY_INFO, "Spectating with %s settings" % ("their" if spec.prefer_theirs() else "your"))
	_check_view_settings()

func _input(event):
	if not spectating:
		return
	if _spec_page != null and is_instance_valid(_spec_page) and _spec_page.is_open():
		# the Spectate window is open (typing in its chat...): the keys stay
		# away from the game (R gives up, Space / Esc skip or pause, Tab switches)
		if event is InputEventKey:
			for a in ["give_up", "pause"]:
				if event.is_action(a):
					Input.action_release(a)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_TAB:
		toggle_spectate_view()
		get_tree().set_input_as_handled()
	elif Rhythia.vr and event.is_action_pressed("vr_click"):
		toggle_spectate_view() # VR: the trigger switches (it does nothing else while watching)
	elif Rhythia.vr and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_VR_THIRD:
		toggle_third_person() # VR: B / Y (Pause does nothing while watching)
		get_tree().set_input_as_handled()
	elif not Rhythia.vr and event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_3:
		toggle_third_person()
		get_tree().set_input_as_handled()

# 3rd person while watching: you see the player's avatar (Settings > Player
# Avatar: theirs, sent with their settings) playing, from behind and to the
# side, like the alternate replay camera. VR: B / Y moves you there (VRPlayer
# reads vr_third_person); desktop: 3 switches to the alternate camera.
const JOY_VR_THIRD := 1 # B / Y
var third_person := false

func toggle_third_person():
	if not spectating:
		return
	third_person = not third_person
	var look = null
	var lm = _get_lobby_manager()
	if lm != null and lm.player_view_settings.has(spectate_peer_id):
		look = lm.player_view_settings[spectate_peer_id].get("avatar")
	var root = get_tree().current_scene
	if Rhythia.vr:
		Rhythia.set_meta("vr_third_person", third_person)
		var av = root.get_node_or_null("Game/Avatar") if root else null
		if av is Spatial:
			av.visible = third_person
			if third_person:
				av.get_node("Animations").play("Idle")
				av.get_node("Head/Blinking").play("Blink")
				load("res://scripts/avatar/AvatarLook.gd").apply(av, look)
		Globals.notify(Globals.NOTIFY_INFO, "3rd person view" if third_person else "Your own view")
	elif root != null and root.has_method("set_third_person"):
		root.set_third_person(third_person, look)
	_update_spectate_target_name()

var _spectate_ui: Control = null
var _spec_page_layer: CanvasLayer = null # the Spectate window while watching
var _spec_page: Control = null # (SpectatePage.gd)
var _spectate_banner: Label = null
var _spectate_view_button: Button = null

func _create_spectate_banner():
	if _spectate_ui != null:
		return
	# (in the top-left column, above the Spectators list; exit_spectate_mode frees it)
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 6)
	_top_left().add_child(box)
	_top_left().move_child(box, 0)
	_spectate_ui = box

	_spectate_banner = Label.new()
	var spectate_font = DynamicFont.new()
	spectate_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	spectate_font.size = 20
	_spectate_banner.add_font_override("font", spectate_font)
	_spectate_banner.add_color_override("font_color", Color(1, 0.85, 0.2))
	_spectate_banner.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	_spectate_banner.add_constant_override("shadow_offset_x", 2)
	_spectate_banner.add_constant_override("shadow_offset_y", 2)
	box.add_child(_spectate_banner)

	_spectate_view_button = Button.new()
	_spectate_view_button.focus_mode = Control.FOCUS_NONE # Space / Enter don't press it
	var button_font = DynamicFont.new()
	button_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	button_font.size = 16
	_spectate_view_button.add_font_override("font", button_font)
	_spectate_view_button.connect("pressed", self, "toggle_spectate_view")
	box.add_child(_spectate_view_button)
	_update_view_button()
	var lm = _get_lobby_manager()
	if lm != null and lm.watch_mode:
		# from the Spectate tab: a way back (or hold the give up key)
		var stop := Button.new()
		stop.focus_mode = Control.FOCUS_NONE
		stop.add_font_override("font", button_font)
		stop.text = "Stop watching" if Rhythia.vr else "Stop watching (hold %s)" % _give_up_key_name()
		stop.connect("pressed", get_parent(), "leave_watching")
		box.add_child(stop)
	elif lm != null and lm.lobby_active:
		# out of a lobby match: leave the lobby (or hold the give up key)
		var leave := Button.new()
		leave.focus_mode = Control.FOCUS_NONE
		leave.add_font_override("font", button_font)
		leave.text = "Leave lobby" if Rhythia.vr else "Leave lobby (hold %s)" % _give_up_key_name()
		leave.connect("pressed", get_parent(), "leave_lobby_match")
		box.add_child(leave)
	# a small Report button: skin, chat or other, with a screenshot (SpectateReport.gd)
	if not Rhythia.vr:
		var report := Button.new()
		report.focus_mode = Control.FOCUS_NONE
		var small_font = DynamicFont.new()
		small_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
		small_font.size = 13
		report.add_font_override("font", small_font)
		report.text = "Report"
		report.hint_tooltip = "Report this player (skin, chat, other)"
		report.size_flags_horizontal = 0 # (as small as its text)
		report.modulate = Color(1, 1, 1, 0.75)
		report.connect("pressed", self, "_open_report")
		box.add_child(report)

func _open_report():
	var lm = _get_lobby_manager()
	if lm == null or not spectating:
		return
	var number := 0
	var pname := ""
	for p in lm.players:
		if p is Dictionary and int(p.get("peer_id", -1)) == spectate_peer_id:
			number = int(p.get("player_number", 0)) if p.get("player_number") != null else 0
			pname = Globals.s(p.get("name", ""))
	if number <= 0:
		Globals.notify(Globals.NOTIFY_WARN, "This player can't be reported from here (no player number). Report them on Discord.", "Report")
		return
	var s = lm.player_view_settings.get(spectate_peer_id, {})
	load("res://scripts/game/SpectateReport.gd").open_for(self, number, pname, s if s is Dictionary else {}, Globals.s(lm.lobby_state.get("song_name", "")))

static func _give_up_key_name() -> String:
	for e in InputMap.get_action_list("give_up"):
		if e is InputEventKey:
			return OS.get_scancode_string(e.scancode)
	return "give up"

func _update_view_button():
	if _spectate_view_button == null:
		return
	var key: String = "trigger" if Rhythia.vr else "Tab"
	var lobby_manager = _get_lobby_manager()
	var spec = _spec_settings()
	var text := ""
	if _spec_reloading:
		text = "Loading %s settings..." % ("their" if spec.prefer_theirs() else "your")
	elif not spec.prefer_theirs():
		text = "Your settings  |  Use theirs (%s)" % key
	elif spec.applied_for() == spectate_peer_id:
		text = "Their settings  |  Use yours (%s)" % key
	elif lobby_manager != null and lobby_manager.player_view_settings.has(spectate_peer_id):
		text = "Their settings aren't available  |  Use yours (%s)" % key
	else:
		text = "Getting their settings...  |  Use yours (%s)" % key
	_spectate_view_button.text = text
	_spectate_view_button.disabled = _spec_reloading

func _update_spectate_target_name():
	if _spectate_banner == null:
		return
	var lobby_manager = _get_lobby_manager()
	var name_text = "Player"
	if lobby_manager != null:
		for p in lobby_manager.players:
			if int(p.get("peer_id", -1)) == spectate_peer_id:
				name_text = Globals.s(p.get("name", "Player"))
	var spins: bool = lobby_manager != null and lobby_manager.has_method("watched_player_spins") and lobby_manager.watched_player_spins()
	_spectate_banner.text = "👁 SPECTATING: %s%s" % [name_text, "  ·  SPIN" if spins else ""]
	_update_spectate_vr_panel(name_text)

# VR, watching someone: the top-left banner and its Stop button are on the
# flat screen, which the headset doesn't show. A panel above the right HUD
# panel says who it is and how to switch view / stop (the trigger switches
# view while watching, so the buttons can't be clicked: holding give up stops).
var _spec_vr_vp: Viewport = null
var _spec_vr_label: Label = null
var _spec_vr_sprite: Sprite3D = null

func _vr_button_names(action: String) -> String:
	var names := PoolStringArray()
	for b in Rhythia.vr_bind(action):
		for nb in Rhythia.VR_BUTTONS:
			if int(nb[1]) == int(b):
				names.append(String(nb[0]))
	return names.join(" or ") if names.size() > 0 else ""

func _update_spectate_vr_panel(name_text: String):
	if not Rhythia.vr:
		return
	if _spec_vr_sprite == null:
		var right = get_node_or_null("RightHud")
		if right == null:
			return
		_spec_vr_vp = Viewport.new()
		_spec_vr_vp.size = Vector2(300, 220)
		_spec_vr_vp.transparent_bg = true
		_spec_vr_vp.hdr = false
		_spec_vr_vp.usage = Viewport.USAGE_2D
		_spec_vr_vp.msaa = Viewport.MSAA_DISABLED
		_spec_vr_vp.render_target_update_mode = Viewport.UPDATE_ONCE
		add_child(_spec_vr_vp)
		_spec_vr_label = Label.new()
		var f := DynamicFont.new()
		f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
		f.size = 24
		_spec_vr_label.add_font_override("font", f)
		_spec_vr_label.add_color_override("font_color", Color(1, 0.85, 0.2))
		_spec_vr_label.anchor_right = 1.0
		_spec_vr_label.anchor_bottom = 1.0
		_spec_vr_label.margin_left = 8
		_spec_vr_label.margin_right = -8
		_spec_vr_label.autowrap = true
		_spec_vr_label.valign = Label.VALIGN_BOTTOM # (grows upward from the panel)
		_spec_vr_vp.add_child(_spec_vr_label)
		_spec_vr_sprite = right.duplicate(0)
		_spec_vr_sprite.name = "SpectateVR"
		_spec_vr_sprite.texture = _spec_vr_vp.get_texture()
		var h: float = _spec_vr_vp.size.y * _spec_vr_sprite.pixel_size
		var panel_h: float = 900.0 * right.pixel_size
		_spec_vr_sprite.transform.origin = right.transform.origin + Vector3(0, panel_h / 2.0 + h / 2.0 + 0.03, 0)
		add_child(_spec_vr_sprite)
	var stop_keys := _vr_button_names("give_up")
	var lm0 = _get_lobby_manager()
	var on_spin: bool = lm0 != null and lm0.has_method("watched_player_spins") and lm0.watched_player_spins()
	var lines := PoolStringArray(["Watching %s%s" % [name_text, " (on Spin)" if on_spin else ""], "Trigger: switch view", "B / Y: %s" % ("your own view" if third_person else "3rd person view")])
	var lm = _get_lobby_manager()
	if lm != null and lm.watch_mode:
		lines.append("Hold %s: stop watching" % (stop_keys if stop_keys != "" else "give up"))
	elif lm != null and lm.lobby_active:
		lines.append("Hold %s: leave the lobby" % (stop_keys if stop_keys != "" else "give up"))
	_spec_vr_label.text = lines.join("\n")
	_spec_vr_sprite.visible = true
	_spec_vr_vp.render_target_update_mode = Viewport.UPDATE_ONCE # (redrawn when it changes)

var spectate_cursor: Spatial = null
var _real_cursor: Spatial = null

# Watching with their settings: the cursor shows their cursor picture (from
# the server, kept in user://spectate_cursors/). With yours: your own.
const CURSOR_PIC_URL := "https://savia.nysr.host/savia-cursor/%s.png"
const CURSOR_PIC_DIR := "user://spectate_cursors"
var _own_cursor_mat = null
var _cursor_pic_shown: String = ""
var _cursor_pic_http: HTTPRequest = null

func _spectate_cursor_picture():
	if spectate_cursor == null or not is_instance_valid(spectate_cursor):
		return
	var spec = _spec_settings()
	var lm = _get_lobby_manager()
	var sha := ""
	var theirs_on: bool = lm != null and spec.prefer_theirs() and spec.applied_for() == spectate_peer_id
	if theirs_on:
		var s = lm.player_view_settings.get(spectate_peer_id, {})
		if s is Dictionary:
			sha = String(s.get("cursor_image", "")).to_lower()
		if sha.length() != 64 or not sha.is_valid_hex_number():
			sha = "default" # their cursor is the game's own circle
	if sha == _cursor_pic_shown:
		return
	_cursor_pic_shown = sha
	if sha == "":
		_put_cursor_picture(null)
		return
	if sha == "default":
		_put_cursor_picture(load("res://assets/images/cursors/circle.png"))
		return
	var file: String = Globals.p("%s/%s.png" % [CURSOR_PIC_DIR, sha])
	if File.new().file_exists(file):
		var img := Image.new()
		if img.load(file) == OK:
			_put_cursor_picture(_texture_of(img))
			return
	if _cursor_pic_http != null and is_instance_valid(_cursor_pic_http):
		_cursor_pic_http.queue_free()
	_cursor_pic_http = HTTPRequest.new()
	_cursor_pic_http.use_threads = not OS.has_feature("JavaScript") # (big files: never on the game's main thread; the browser version has no threads: the download never finished there)
	_cursor_pic_http.timeout = 15
	add_child(_cursor_pic_http)
	_cursor_pic_http.connect("request_completed", self, "_on_cursor_picture", [sha, _cursor_pic_http])
	if _cursor_pic_http.request(CURSOR_PIC_URL % sha) != OK:
		_cursor_pic_http.queue_free()
		_cursor_pic_http = null

func _on_cursor_picture(result: int, code: int, _headers, body: PoolByteArray, sha: String, http: HTTPRequest):
	http.queue_free()
	if http == _cursor_pic_http:
		_cursor_pic_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty() or sha != _cursor_pic_shown:
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		return
	var d := Directory.new()
	d.make_dir_recursive(Globals.p(CURSOR_PIC_DIR))
	img.save_png(Globals.p("%s/%s.png" % [CURSOR_PIC_DIR, sha]))
	_put_cursor_picture(_texture_of(img))

static func _texture_of(img: Image) -> ImageTexture:
	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

# tex null: your own cursor picture back
func _put_cursor_picture(tex):
	if spectate_cursor == null or not is_instance_valid(spectate_cursor):
		return
	var mesh = spectate_cursor.get_node_or_null("Mesh")
	if mesh == null or not (mesh is MeshInstance):
		return
	if _own_cursor_mat == null:
		_own_cursor_mat = mesh.get_surface_material(0)
		if _own_cursor_mat == null and mesh.mesh != null:
			_own_cursor_mat = mesh.mesh.surface_get_material(0)
	if tex == null:
		mesh.set_surface_material(0, _own_cursor_mat)
		return
	var mat: SpatialMaterial
	if _own_cursor_mat is SpatialMaterial:
		mat = _own_cursor_mat.duplicate()
	else:
		mat = SpatialMaterial.new()
		mat.flags_transparent = true
		mat.flags_unshaded = true
	mat.albedo_color = Color(1, 1, 1, max(mat.albedo_color.a, 0.5))
	mat.albedo_texture = tex
	mesh.set_surface_material(0, _on_top(mat))

# drawn over the grid, notes and backgrounds, like the cursor you play with
static func _on_top(mat: SpatialMaterial) -> SpatialMaterial:
	mat.flags_no_depth_test = true
	mat.render_priority = 100
	return mat

func _create_ghost_cursor():
	if spectate_cursor != null:
		return
	var real_cursor = Spawn.get_node("Cursor")
	_real_cursor = real_cursor
	spectate_cursor = real_cursor.duplicate(DUPLICATE_USE_INSTANCING | DUPLICATE_SCRIPTS)
	spectate_cursor.name = "SpectatorCursor"

	real_cursor.set_process_input(false)
	real_cursor.set_process(false)
	real_cursor.visible = false

	spectate_cursor.set_script(null)

	Spawn.add_child(spectate_cursor)

	var dup_trail = spectate_cursor.get_node_or_null("Mesh2")
	if dup_trail != null:
		dup_trail.visible = false
	# the one you watch is always shown: a copy of your cursor was hidden with
	# Show cursor off, and could be drawn behind a grid background or panels
	spectate_cursor.visible = true
	var dm = spectate_cursor.get_node_or_null("Mesh")
	if dm is MeshInstance:
		dm.visible = true
		var m0 = dm.get_surface_material(0)
		if m0 == null and dm.mesh != null:
			m0 = dm.mesh.surface_get_material(0)
		if m0 is SpatialMaterial:
			dm.set_surface_material(0, _on_top(m0.duplicate()))

func _on_round_ended():
	exit_spectate_mode()
	var game = get_parent()
	if game != null and game.has_method("show_round_results"):
		game.show_round_results()
	else:
		get_tree().paused = false
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")


# --- the Spectators list (top left) --------------------------------------------------
# Who is watching: shown to the player and to everyone watching them, and
# not at all when nobody is.
var _spectators_banner: Label = null
var _top_left_ui: CanvasLayer = null
var _top_left_box: VBoxContainer = null
const SPECTATORS_SHOWN := 8
# In VR a screen overlay only reaches the desktop window: the list is drawn in
# its own viewport, shown above the left panel like the rest of the HUD.
var _spectators_vr_vp: Viewport = null
var _spectators_vr_sprite: Sprite3D = null

# --- the multiplayer leaderboard in VR ------------------------------------------
# A screen overlay only reaches the desktop window in VR, so the match's
# leaderboard (LobbyBoard.gd, the same board as on the screen, at twice the
# size) is drawn in its own viewport onto a panel standing beside the left grid
# panel, on its outer side, turned a little towards you. Drawn again only when
# the board changes.
var _board_vr_vp: Viewport = null
var _board_vr_sprite: Sprite3D = null
var _board_vr = null
const BOARD_VR_SIZE := Vector2(700, 1100)

func update_leaderboard_vr(rows: Array, title: String, footer: String, show: bool):
	if not Rhythia.vr:
		return
	if not show:
		if _board_vr_sprite != null:
			_board_vr_sprite.visible = false
		return
	if _board_vr_sprite == null and not _make_board_vr():
		return
	_place_board_vr()
	_board_vr_sprite.visible = true
	_board_vr.set_board(rows, title, footer, false)

func _make_board_vr() -> bool:
	var left = get_node_or_null("LeftHud")
	if left == null:
		return false
	var vp := Viewport.new()
	vp.name = "LobbyBoardVP"
	vp.size = BOARD_VR_SIZE
	vp.transparent_bg = true
	vp.hdr = false
	vp.usage = Viewport.USAGE_2D
	vp.msaa = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = Viewport.UPDATE_ONCE
	add_child(vp)
	_board_vr = load("res://scripts/game/LobbyBoard.gd").new(2.0, false)
	_board_vr.rect_min_size = Vector2(BOARD_VR_SIZE.x, 0)
	vp.add_child(_board_vr)
	_board_vr.connect("changed", self, "_redraw_board_vr")
	var s: Sprite3D = left.duplicate(0)
	s.name = "LobbyBoardHud"
	s.pixel_size = left.pixel_size * 0.5 # (drawn at twice the size)
	s.texture = vp.get_texture()
	s.texture.flags = Texture.FLAG_FILTER # (smooth in the headset)
	s.visible = false
	add_child(s)
	_board_vr_vp = vp
	_board_vr_sprite = s
	return true

# beside the left panel (its final place: HudPanels / Sound Space mode move it)
func _place_board_vr():
	var left = get_node_or_null("LeftHud")
	if left == null or _board_vr_sprite == null:
		return
	var s := _board_vr_sprite
	var lw: float = 300.0 * left.pixel_size * left.scale.x
	var lh: float = 900.0 * left.pixel_size * left.scale.y
	var nw: float = BOARD_VR_SIZE.x * s.pixel_size
	var nh: float = BOARD_VR_SIZE.y * s.pixel_size
	# (the panel's +X points outward and its +Z up)
	var t: Transform = left.transform
	t.basis = t.basis.orthonormalized()
	var out: Vector3 = t.basis.x
	var up: Vector3 = t.basis.z
	var origin: Vector3 = t.origin + out * (lw / 2.0 + 0.12 + nw / 2.0) + up * (lh / 2.0 - nh / 2.0)
	# turned towards the middle, so it faces you
	var basis := Basis(Vector3.UP, deg2rad(-14)) * t.basis
	s.transform = Transform(basis, origin)

func _redraw_board_vr():
	if _board_vr_vp == null:
		return
	# (after the board lays itself out, and once more for late sizes)
	_board_vr.rect_size = Vector2(BOARD_VR_SIZE.x, 0)
	_board_vr_vp.render_target_update_mode = Viewport.UPDATE_ONCE
	yield(get_tree(), "idle_frame")
	if _board_vr_vp != null and is_instance_valid(_board_vr_vp):
		_board_vr.rect_size = Vector2(BOARD_VR_SIZE.x, 0)
		_board_vr_vp.render_target_update_mode = Viewport.UPDATE_ONCE

func _make_spectators_vr(label: Label) -> bool:
	var left = get_node_or_null("LeftHud")
	if left == null:
		return false
	var vp := Viewport.new()
	vp.size = Vector2(300, 360)
	vp.transparent_bg = true
	vp.hdr = false
	vp.usage = Viewport.USAGE_2D
	vp.msaa = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = Viewport.UPDATE_ONCE
	add_child(vp)
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.margin_left = 8
	label.margin_right = -8
	label.valign = Label.VALIGN_BOTTOM # (grows upward from the panel)
	label.clip_text = true
	label.get_font("font").size = 30
	vp.add_child(label)
	var s: Sprite3D = left.duplicate(0)
	s.name = "SpectatorsHud"
	s.texture = vp.get_texture()
	var h: float = vp.size.y * s.pixel_size
	var panel_h: float = 900.0 * left.pixel_size
	s.transform.origin = left.transform.origin + Vector3(0, panel_h / 2.0 + h / 2.0 + 0.03, 0)
	s.visible = false
	add_child(s)
	_spectators_vr_vp = vp
	_spectators_vr_sprite = s
	return true

func _top_left() -> VBoxContainer:
	if _top_left_box == null:
		_top_left_ui = CanvasLayer.new()
		_top_left_ui.layer = 50
		add_child(_top_left_ui)
		_top_left_box = VBoxContainer.new()
		_top_left_box.rect_position = Vector2(36, 32)
		_top_left_box.add_constant_override("separation", 6)
		_top_left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top_left_ui.add_child(_top_left_box)
	return _top_left_box

func _create_spectators_banner():
	if _spectators_banner != null:
		return
	_spectators_banner = Label.new()
	var f = DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = 18
	# (the letters drawn now, at the start: the first time someone watched,
	# making them mid-song cost a frame)
	f.get_string_size("Spectators (0123456789) + more ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz_-.")
	_spectators_banner.add_font_override("font", f)
	_spectators_banner.add_color_override("font_color", Color(0.9, 0.9, 0.9))
	_spectators_banner.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	_spectators_banner.add_constant_override("shadow_offset_x", 2)
	_spectators_banner.add_constant_override("shadow_offset_y", 2)
	_spectators_banner.visible = false
	if not (Rhythia.vr and _make_spectators_vr(_spectators_banner)):
		_top_left().add_child(_spectators_banner)
	var t := Timer.new() # (also follows switching who you watch)
	t.wait_time = 0.5
	t.pause_mode = PAUSE_MODE_PROCESS
	t.connect("timeout", self, "_on_lobby_state_changed_for_spectators_list")
	add_child(t)
	t.start()

# the names of those watching the player on screen (you, or who you watch)
func _spectator_names() -> Array:
	var lm = _get_lobby_manager()
	if lm == null:
		return []
	var names := []
	if not lm.lobby_active:
		# playing alone, watched from the Spectate tab
		for n in lm.watcher_names:
			names.append(Globals.s(n))
		for i in range(names.size(), int(lm.watchers_count)):
			names.append("") # (more than the server names)
		return names
	var shown: int = spectate_peer_id if spectating else int(lm.local_peer_id)
	for sp in lm.lobby_spectators:
		if not (sp is Dictionary):
			continue
		# (a watch room has only their watchers; older servers don't say who
		# a spectator watches: then everyone spectating counts)
		if lm.watch_mode or not sp.has("target") or int(sp.get("target", -1)) == shown or int(sp.get("target", -1)) == -1:
			names.append(_you_or(lm, int(sp.get("peer_id", -1)), Globals.s(sp.get("name", "Spectator"))))
	for p in lm.players:
		var pid := int(p.get("peer_id", -1))
		if pid != shown and int(p.get("spectate_target", -1)) == shown and bool(p.get("failed", false)):
			names.append(_you_or(lm, pid, Globals.s(p.get("name", "Player"))))
	return names

static func _you_or(lm, peer_id: int, name: String) -> String:
	return "%s (you)" % name if peer_id == int(lm.local_peer_id) else name

func _exit_tree():
	if Rhythia.has_meta("vr_third_person"):
		Rhythia.remove_meta("vr_third_person") # (3rd person ends with the song)

	if _spectate_banner != null:
		_spectate_banner.queue_free()
		_spectate_banner = null

func _on_watchers_changed_for_list(_count, _names):
	_on_lobby_state_changed_for_spectators_list()

func _on_lobby_state_changed_for_spectators_list():
	if _spectators_banner == null:
		return
	var names := _spectator_names()
	# (Settings > UI > Hide Spectators List: only while you play; watching
	# someone still shows who else is watching them)
	if names.empty() or (Rhythia.hide_spectators_list and not spectating):
		_spectators_banner.visible = false
		if _spectators_vr_sprite != null:
			_spectators_vr_sprite.visible = false
		return
	var lines := ["👁 Spectators (%d)" % names.size()]
	var unnamed := 0
	for n in names:
		if n == "":
			unnamed += 1
		elif lines.size() <= SPECTATORS_SHOWN:
			lines.append("   " + n)
		else:
			unnamed += 1
	if unnamed > 0:
		lines.append("   + %d more" % unnamed)
	var txt := "\n".join(lines)
	if _spectators_vr_sprite != null and (txt != _spectators_banner.text or not _spectators_vr_sprite.visible):
		_spectators_vr_sprite.visible = true
		_spectators_vr_vp.render_target_update_mode = Viewport.UPDATE_ONCE # (redrawn only when it changes)
	_spectators_banner.text = txt
	_spectators_banner.visible = true

func _ready():
	Rhythia.start_log("hud")
	_timer_hud = get_node_or_null("TimerHud")
	_setup_hud_viewports()
	Game.connect("miss", self, "on_miss")
	if Rhythia.colorset_hud:
		Game.connect("hit", self, "_on_hit_for_colorset_hud")
		var cs = Rhythia.selected_colorset
		if cs != null and cs.real_colors.size() > 0:
			_cs_tint_target = _readable(cs.real_colors[0])
			_cs_tint = _cs_tint_target
	_create_spectators_banner()
	var lobby_manager_for_spectators = _get_lobby_manager()
	if lobby_manager_for_spectators != null and not lobby_manager_for_spectators.is_connected("lobby_state_changed", self, "_on_lobby_state_changed_for_spectators_list"):
		lobby_manager_for_spectators.connect("lobby_state_changed", self, "_on_lobby_state_changed_for_spectators_list")
	if lobby_manager_for_spectators != null and not lobby_manager_for_spectators.is_connected("watchers_changed", self, "_on_watchers_changed_for_list"):
		lobby_manager_for_spectators.connect("watchers_changed", self, "_on_watchers_changed_for_list")

	$Stats/Label.visible = Rhythia.show_stats
	_make_sp_label()

	$GiveUpVP/Control.fill_color = giveup_fill_color

	for n in get_tree().get_nodes_in_group("panel_bg"):
		paint(n, panel_bg)

	for n in get_tree().get_nodes_in_group("panel_text"):
		paint(n, panel_text)

	for n in get_tree().get_nodes_in_group("score_text"):
		paint(n, score_text_color)

	for n in get_tree().get_nodes_in_group("pause_text"):
		paint(n, pause_text_color)

	for n in get_tree().get_nodes_in_group("miss_text"):
		paint(n, miss_text_color)

	paint($PauseVP/Control/Paused, unpause_empty_color)
	paint($PauseVP/Control/ProgressBar/Paused, unpause_fill_color)
	paint($PauseVP/Control/HoldR, how_to_quit)
	paint($GiveUpVP/Control/Label, giveup_text)

	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null and not lobby_manager.is_connected("round_ended", self, "_on_round_ended"):
		lobby_manager.connect("round_ended", self, "_on_round_ended")

	if _tinted_hud():
		var cf = max(max(combo_fill_color.r, combo_fill_color.g), combo_fill_color.b)
		var ce = max(max(combo_empty_color.r, combo_empty_color.g), combo_empty_color.b)
		var af = max(max(acc_fill_color.r, acc_fill_color.g), acc_fill_color.b)
		var ae = max(max(acc_empty_color.r, acc_empty_color.g), acc_empty_color.b)

		comboring.fill_color = Color(cf, cf, cf, combo_fill_color.a)
		comboring.empty_color = Color(ce, ce, ce, combo_empty_color.a)
		accbar.get("custom_styles/fg").bg_color = Color(af, af, af, acc_fill_color.a)
		accbar.get("custom_styles/bg").bg_color = Color(ae, ae, ae, acc_empty_color.a)
	else:
		comboring.fill_color = combo_fill_color
		comboring.empty_color = combo_empty_color
		accbar.get("custom_styles/fg").bg_color = acc_fill_color
		accbar.get("custom_styles/bg").bg_color = acc_empty_color

	if not _tinted_hud():
		energybar.get("custom_styles/fg").bg_color = energy_fill_color
		energybar.get("custom_styles/bg").bg_color = energy_empty_color


	if not Rhythia.show_config:
		$ConfigHud.visible = false



	if Rhythia.hr_on() and Rhythia.expand_hud_onhr:
		var HUDScale: Array = [
			$TimerHud,
			$LeftHud,
			$RightHud,
			$EnergyHud,
			$ComboHud,
		]
		# (Harder Rock spreads further: the border and panels move out more)
		var hr_k: float = (Rhythia.hr_spread() - 1.0) / (Rhythia.HARDROCK_SPREAD - 1.0)
		Spawn.get_node("Outer").scale *= Rhythia.hr_spread()
		$TimerHud.transform.origin += Vector3(0, 0.385, 0) * hr_k
		$LeftHud.transform.origin += Vector3(-0.5, 0, 0) * hr_k
		$RightHud.transform.origin += Vector3(0.5, 0, 0) * hr_k
		$EnergyHud.transform.origin += Vector3(0, -0.45, 0) * hr_k
		$ComboHud.transform.origin += Vector3(0, 0.4, 0) * hr_k

		for l in HUDScale:
			l.scale *= 0.85

	if not Rhythia.enable_border:
		Spawn.get_node("Outer").visible = false

	if Rhythia.visual_mode or not Rhythia.show_left_panel:
		$LeftHud.visible = false

	if Rhythia.visual_mode or not Rhythia.show_right_panel:
		$RightHud.visible = false

	if not Rhythia.show_letter_grade:
		lettergrade.visible = false

	if not Rhythia.show_accuracy_bar:
		accbar.visible = false

	if Rhythia.visual_mode or not Rhythia.show_hp_bar:
		energybar.visible = false
		$EnergyVP/Control/Modifiers.margin_top -= 30

	if not Rhythia.show_timer:
		$TimerHud.visible = false

	if Rhythia.attach_hp_to_grid:
		var eh = $EnergyHud
		remove_child(eh)
		Spawn.add_child(eh)
		eh.transform.origin += Vector3(1, -1, 0)

	if Rhythia.attach_timer_to_grid:
		var th = $TimerHud
		remove_child(th)
		Spawn.add_child(th)
		th.transform.origin += Vector3(1, -1, 0)

	if Rhythia.simple_hud:
		$LeftVP/Control.self_modulate = Color(0, 0, 0, 0)
		$RightVP/Control.self_modulate = Color(0, 0, 0, 0)

		for n in $LeftVP/Control.get_children():
			n.visible = n.name == "SimpleBg" or n.name == "Pauses" or n.name == "PausesTitle"
			if n.visible: n.rect_position.y += 100

		for n in $RightVP/Control.get_children():
			n.visible = n.name == "SimpleBg" or n.name == "Misses" or n.name == "MissesTitle" or (n.name == "SP" and _sp_label != null)
			if n.visible: n.rect_position.y += 100

	if Rhythia.faraway_hud:
		transform.origin = Vector3(0, 0, -10)
		scale = Vector3(3.7, 3.7, 3.7)

	if Rhythia.visual_mode:
		$EnergyVP/Control/Modifiers.visible = false

	songnametxt.text = Rhythia.selected_song.name
	load("res://scripts/HudFont.gd").apply_hud(self) # Settings > Fonts
	load("res://scripts/HudPanels.gd").apply(self) # Settings > Background Editor > HUD panels
	load("res://scripts/game/SoundSpaceMode.gd").apply_hud(self) # Sound Space Mode (Experimental)

	var ms = ""

	# (the website's game view shows only the replay: no controls, no
	# "Replaying" mark; WebReplay.gd)
	if Rhythia.replaying and not load("res://scripts/WebReplay.gd").wanted():
		if Rhythia.replay.autoplayer: modicons.get_node("Autoplay").visible = true
		else: modicons.get_node("Replaying").visible = true
		_build_replay_controls()

	if Rhythia.mod_nofail: ms += tr("[ NOFAIL ACTIVE ]") + "\n"
	elif Rhythia.health_model == Globals.HP_OLD: ms += "Using old hp model (more hp + fast regen)\n"

	var mods = []
	modicons.get_node("Window").visible = Rhythia.mod_speed_level != Globals.SPEED_NORMAL and not Rhythia.speed_hitwindow
	if Rhythia.mod_speed_level != Globals.SPEED_NORMAL:
		match Rhythia.mod_speed_level:
			Globals.SPEED_MMMM: modicons.get_node("SpeedMMMM").visible = true
			Globals.SPEED_MMM: modicons.get_node("SpeedMMM").visible = true
			Globals.SPEED_MM: modicons.get_node("SpeedMM").visible = true
			Globals.SPEED_M: modicons.get_node("SpeedM").visible = true
			Globals.SPEED_P: modicons.get_node("SpeedP").visible = true
			Globals.SPEED_PP: modicons.get_node("SpeedPP").visible = true
			Globals.SPEED_PPP: modicons.get_node("SpeedPPP").visible = true
			Globals.SPEED_PPPP: modicons.get_node("SpeedPPPP").visible = true
			Globals.SPEED_CUSTOM:
				_speed_custom_icon() # (with its percentage on it)
	# the other mods: their icons, like the speed ones (only here, in a map)
	if Rhythia.mod_nofail: _mod_icon("nofail")
	if Rhythia.mod_sudden_death: _mod_icon("sudden_death")
	if Rhythia.mod_extra_energy: _mod_icon("extra_energy")
	if Rhythia.mod_no_regen: _mod_icon("no_regen")
	if Rhythia.mod_mirror_x: _mod_icon("mirror_x")
	if Rhythia.mod_mirror_y: _mod_icon("mirror_y")
	if Rhythia.mod_ghost: _mod_icon("ghost")
	if Rhythia.mod_nearsighted: _mod_icon("nearsighted")
	if Rhythia.mod_chaos: _mod_icon("chaos")
	if Rhythia.mod_earthquake: _mod_icon("earthquake")
	if Rhythia.mod_360:
		_mod_icon("mod_360")
		var speed = Rhythia.mod_360_speed
		if speed < 0 or abs(speed) != 1: # (which way and how fast: not on the icon)
			mods.append(("%sx%s" % ["-360" if speed < 0 else "360", abs(speed)]) if abs(speed) != 1 else "-360")
	if Rhythia.mod_strobe: _mod_icon("strobe")
	if Rhythia.mod_hardrock: _mod_icon("hardrock")
	if Rhythia.mod_harderrock: _mod_icon("harderrock")
	if Rhythia.mod_hard_mode: _mod_icon("hard_mode")
	if Rhythia.mod_flashlight: _mod_icon("flashlight")
	if Rhythia.mod_reverse: _mod_icon("reverse")
	if Rhythia.invert_mouse: mods.append(tr("Mouse Inverted"))
	if Rhythia.hitwindow_ms == 58 and Rhythia.note_hitbox_size == 1.14:
		ms += tr(" Vulnus Judgement ")
	elif Rhythia.hitwindow_ms == 300:
		ms += tr(" Brrecken Judgement ")
	elif Rhythia.hitwindow_ms != 55 or Rhythia.note_hitbox_size != 1.14:
		ms += "HW: %.0f ms | HB: %.02f m" % [Rhythia.hitwindow_ms, Rhythia.note_hitbox_size]
	for i in range(mods.size()):
		if i != 0: ms += " "
		ms += mods[i]
	if mods.size() != 0 and not Rhythia.mod_nofail: ms += "\n"


	modtxt.text = ms
