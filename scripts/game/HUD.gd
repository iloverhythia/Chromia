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
	if shine != lettergrade.material.get_shader_param("amount"):
		lettergrade.material.set_shader_param("amount", shine)

	if not Rhythia.rainbow_hud:
		lettergrade.set("custom_colors/font_color", gcol)

var miss_flash: float = 0

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

	if not Rhythia.rainbow_hud:
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

	timebar.value = (clamp(qms / lms, 0, 1))

	if canSkip:
		var expire_threshold_ms = ms + (3000 * Spawn.speed_multi)
		var skip_expires_sec = max(0.0, (Spawn.next_ms - expire_threshold_ms) / 1000.0)

		var action_text = "TAP" if Rhythia.device("mobile") else "PRESS SPACE"

		timelabel.text = "%s TO SKIP, Expires in  %.1fs" % [action_text, skip_expires_sec]
		if skip_expires_sec < 1:
			timelabel.set_modulate(Color(1, 0.1, 0.1, 1))
		else:
			timelabel.set_modulate(Color(1, 1, 1, 1))
	else:
		timelabel.text = "%d:%02d / %d:%02d" % [m, rs, lm, lrs]

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

func _process(delta: float):
	gtimer += delta
	_update_spectate_render(delta)
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

	if rainbow_letter_grade and not Rhythia.rainbow_hud:
		lettergrade.set("custom_colors/font_color", Color.from_hsv(Rhythia.rainbow_t * 0.1, grade_ss_saturation, grade_ss_value))

	if miss_flash != 0:
		var miss_col = lerp(miss_text_color, miss_flash_color, miss_flash)
		for n in get_tree().get_nodes_in_group("miss_text"):
			paint(n, miss_col)
		miss_flash = max(0, miss_flash - (delta * 3))

	if Rhythia.rainbow_hud:
		energybar.get("custom_styles/fg").bg_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)
		energybar.get("custom_styles/bg").bg_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 0.2, 0.65)
		$TimerHud.modulate = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)
		$ComboHud.modulate = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)
		$LeftHud.modulate = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)
		$RightHud.modulate = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)

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

var _spec_samples: Array = []

var _spec_playback_t: float = -1.0

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func enter_spectate_mode(peer_id: int):
	spectating = true
	spectate_peer_id = peer_id
	_spec_samples.clear()
	_spec_playback_t = -1.0

	var lobby_manager = _get_lobby_manager()

	if lobby_manager != null:
		if not lobby_manager.is_connected("live_state_received", self, "_on_spectate_live_state"):
			lobby_manager.connect("live_state_received", self, "_on_spectate_live_state")
		if not lobby_manager.is_connected("lobby_state_changed", self, "_on_spectate_lobby_state_changed"):
			lobby_manager.connect("lobby_state_changed", self, "_on_spectate_lobby_state_changed")
		if not lobby_manager.is_connected("player_failed", self, "_on_spectate_target_failed"):
			lobby_manager.connect("player_failed", self, "_on_spectate_target_failed")

	if lobby_manager != null:
		lobby_manager.report_spectate_target(peer_id)

	_create_ghost_cursor()
	_create_spectate_banner()
	_update_spectate_target_name()

func spectate_specific_player(peer_id: int):
	if not spectating or peer_id == spectate_peer_id:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or peer_id == lobby_manager.local_peer_id:
		return
	var exists = false
	for p in lobby_manager.players:
		if int(p.get("peer_id", -1)) == peer_id:
			exists = true
			break
	if not exists:
		return
	spectate_peer_id = peer_id
	_spec_samples.clear()
	_spec_playback_t = -1.0
	lobby_manager.report_spectate_target(peer_id)
	_update_spectate_target_name()

func _on_spectate_target_failed(peer_id):
	if not spectating:
		return
	if peer_id != spectate_peer_id:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var next_first = lobby_manager.get_first_place_peer_id()
	if next_first == -1:

		_end_spectate_and_return_to_lobby()
		return
	if next_first != spectate_peer_id:
		spectate_peer_id = next_first
		_spec_samples.clear()
		_spec_playback_t = -1.0
		lobby_manager.report_spectate_target(next_first)
		_update_spectate_target_name()

func exit_spectate_mode():
	spectating = false
	spectate_peer_id = -1
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.report_spectate_target(-1)
	_spec_samples.clear()
	_spec_playback_t = -1.0
	if spectate_cursor != null:
		spectate_cursor.queue_free()
		spectate_cursor = null
	if _spectate_banner != null:
		_spectate_banner.queue_free()
		_spectate_banner = null
	if _real_cursor != null and is_instance_valid(_real_cursor):
		_real_cursor.visible = true
		_real_cursor.set_process(true)
		_real_cursor.set_process_input(true)
	_real_cursor = null

func _end_spectate_and_return_to_lobby():
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

func _on_spectate_live_state(peer_id, x, y, combo, combo_level, score, hits, misses, total_notes, energy_pct, lvl_progress_pct, chart_ms):
	if not spectating or peer_id != spectate_peer_id:
		return
	var now = OS.get_ticks_msec() / 1000.0
	_spec_samples.append({
		"t": now, "x": x, "y": y, "combo": combo, "combo_level": combo_level, "score": score,
		"hits": hits, "misses": misses, "total_notes": total_notes,
		"energy_pct": energy_pct, "lvl_progress_pct": lvl_progress_pct, "ms": chart_ms,
	})
	while _spec_samples.size() > 0 and now - _spec_samples[0].t > 1.0:
		_spec_samples.pop_front()

func _update_spectate_render(delta: float):
	if not spectating or spectate_cursor == null:
		return
	if _spec_samples.size() == 0:
		return

	var lobby_manager = _get_lobby_manager()
	var delay = lobby_manager.SPECTATE_DELAY_SEC if lobby_manager != null else 0.2
	var newest_t = _spec_samples[_spec_samples.size() - 1].t
	var oldest_t = _spec_samples[0].t

	if _spec_playback_t < 0.0:
		_spec_playback_t = newest_t - delay

	_spec_playback_t += delta

	_spec_playback_t = min(_spec_playback_t, newest_t)
	if _spec_playback_t < oldest_t:
		_spec_playback_t = max(oldest_t, newest_t - delay)

	if _spec_samples.size() == 1 or _spec_playback_t <= oldest_t:
		_apply_spectate_sample(_spec_samples[0])
		return
	if _spec_playback_t >= newest_t:
		_apply_spectate_sample(_spec_samples[_spec_samples.size() - 1])
		return

	for i in range(_spec_samples.size() - 1):
		var a = _spec_samples[i]
		var b = _spec_samples[i + 1]
		if _spec_playback_t >= a.t and _spec_playback_t <= b.t:
			var alpha = 0.0
			if b.t > a.t:
				alpha = (_spec_playback_t - a.t) / (b.t - a.t)
			var x = lerp(a.x, b.x, alpha)
			var y = lerp(a.y, b.y, alpha)
			spectate_cursor.transform.origin = Vector3(x, y, spectate_cursor.transform.origin.z)
			_apply_spectate_stats(a)
			update_static_values()
			_sync_note_timeline(lerp(a.ms, b.ms, alpha))
			return

func _apply_spectate_sample(sample: Dictionary):
	spectate_cursor.transform.origin = Vector3(sample.x, sample.y, spectate_cursor.transform.origin.z)
	_apply_spectate_stats(sample)
	update_static_values()
	_sync_note_timeline(sample.ms)


func _sync_note_timeline(target_ms: float):
	if Spawn == null:
		return
	var diff = target_ms - Spawn.ms
	Spawn.ms = target_ms
	if abs(diff) > 1000.0 * max(Spawn.speed_multi, 1.0):
		if Spawn.music_started and Spawn.has_node("Music"):
			Spawn.get_node("Music").play((Spawn.ms + Rhythia.music_offset) / 1000.0)

func _apply_spectate_stats(sample: Dictionary):
	_spectate_data.score = sample.score
	_spectate_data.hits = sample.hits
	_spectate_data.misses = sample.misses
	_spectate_data.total_notes = sample.total_notes
	_spectate_data.combo = sample.combo
	_spectate_data.combo_level = sample.combo_level
	_spectate_data.energy_pct = sample.energy_pct
	_spectate_data.lvl_progress_pct = sample.lvl_progress_pct

func _on_spectate_lobby_state_changed():
	if not spectating:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var target_failed = false
	for p in lobby_manager.players:
		if int(p.get("peer_id", -1)) == spectate_peer_id and bool(p.get("failed", false)):
			target_failed = true
	if not target_failed:
		return
	var first = lobby_manager.get_first_place_peer_id()
	if first == -1:
		_end_spectate_and_return_to_lobby()
		return
	if first != spectate_peer_id:
		spectate_peer_id = first
		_spec_samples.clear()
		_spec_playback_t = -1.0
		lobby_manager.report_spectate_target(first)
		_update_spectate_target_name()

var _spectate_banner: Label = null
func _create_spectate_banner():
	if _spectate_banner != null:
		return
	_spectate_banner = Label.new()
	_spectate_banner.rect_position = Vector2(36, 32)
	var spectate_font = DynamicFont.new()
	spectate_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	spectate_font.size = 20
	_spectate_banner.add_font_override("font", spectate_font)
	_spectate_banner.add_color_override("font_color", Color(1, 0.85, 0.2))
	_spectate_banner.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	_spectate_banner.add_constant_override("shadow_offset_x", 2)
	_spectate_banner.add_constant_override("shadow_offset_y", 2)
	get_tree().get_root().add_child(_spectate_banner)

func _update_spectate_target_name():
	if _spectate_banner == null:
		return
	var lobby_manager = _get_lobby_manager()
	var name_text = "Player"
	if lobby_manager != null:
		for p in lobby_manager.players:
			if int(p.get("peer_id", -1)) == spectate_peer_id:
				name_text = String(p.get("name", "Player"))
	_spectate_banner.text = "👁 SPECTATING: %s" % name_text

var spectate_cursor: Spatial = null
var _real_cursor: Spatial = null

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

func _on_round_ended():
	exit_spectate_mode()
	var game = get_parent()
	if game != null and game.has_method("show_round_results"):
		game.show_round_results()
	else:
		get_tree().paused = false
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")


var _spectators_banner: Label = null

func _create_spectators_banner():
	if _spectators_banner != null:
		return

	var right_control = get_node_or_null("RightVP/Control")
	if right_control == null:
		return
	_spectators_banner = Label.new()
	_spectators_banner.anchor_right = 1.0
	_spectators_banner.margin_top = 10
	_spectators_banner.margin_bottom = 90
	_spectators_banner.align = Label.ALIGN_CENTER
	_spectators_banner.valign = Label.VALIGN_CENTER
	_spectators_banner.autowrap = true

	var banner_font = DynamicFont.new()
	banner_font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	banner_font.size = 32
	_spectators_banner.add_font_override("font", banner_font)
	_spectators_banner.add_color_override("font_color", Color(0.8, 0.8, 0.8))
	_spectators_banner.visible = false
	right_control.add_child(_spectators_banner)

func _exit_tree():

	if _spectate_banner != null:
		_spectate_banner.queue_free()
		_spectate_banner = null

func _on_lobby_state_changed_for_spectators_list():
	if _spectators_banner == null:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var alive_names = {}
	for p in lobby_manager.players:
		if not bool(p.get("failed", false)):
			alive_names[int(p.get("peer_id", -1))] = String(p.get("name", "Player"))
	var groups = {}
	var unassigned = []
	var spectator_count = 0
	for p in lobby_manager.players:
		if not bool(p.get("failed", false)):
			continue
		if int(p.get("peer_id", -1)) == lobby_manager.local_peer_id:
			continue
		spectator_count += 1
		var spec_name = String(p.get("name", "Player"))
		var target_id = int(p.get("spectate_target", -1))
		if target_id != -1 and alive_names.has(target_id):
			if not groups.has(target_id):
				groups[target_id] = []
			groups[target_id].append(spec_name)
		else:
			unassigned.append(spec_name)
	if groups.empty() and unassigned.empty():
		_spectators_banner.visible = false
		return
	_spectators_banner.visible = true
	var spectator_names = []
	for target_id in groups:
		spectator_names += groups[target_id]
	spectator_names += unassigned
	_spectators_banner.text = "👁 %d watching\n%s" % [spectator_count, ", ".join(spectator_names)]

func _ready():
	Game.connect("miss", self, "on_miss")
	_create_spectators_banner()
	var lobby_manager_for_spectators = _get_lobby_manager()
	if lobby_manager_for_spectators != null and not lobby_manager_for_spectators.is_connected("lobby_state_changed", self, "_on_lobby_state_changed_for_spectators_list"):
		lobby_manager_for_spectators.connect("lobby_state_changed", self, "_on_lobby_state_changed_for_spectators_list")

	$Stats/Label.visible = Rhythia.show_stats

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

	if Rhythia.rainbow_hud:
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

	if not Rhythia.rainbow_hud:
		energybar.get("custom_styles/fg").bg_color = energy_fill_color
		energybar.get("custom_styles/bg").bg_color = energy_empty_color


	if not Rhythia.show_config:
		$ConfigHud.visible = false



	if Rhythia.mod_hardrock and Rhythia.expand_hud_onhr:
		var HUDScale: Array = [
			$TimerHud,
			$LeftHud,
			$RightHud,
			$EnergyHud,
			$ComboHud,
		]
		Spawn.get_node("Outer").scale *= 1.35
		$TimerHud.transform.origin += Vector3(0, 0.385, 0)
		$LeftHud.transform.origin += Vector3(-0.5, 0, 0)
		$RightHud.transform.origin += Vector3(0.5, 0, 0)
		$EnergyHud.transform.origin += Vector3(0, -0.45, 0)
		$ComboHud.transform.origin += Vector3(0, 0.4, 0)

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
			n.visible = n.name == "SimpleBg" or n.name == "Misses" or n.name == "MissesTitle"
			if n.visible: n.rect_position.y += 100

	if Rhythia.faraway_hud:
		transform.origin = Vector3(0, 0, -10)
		scale = Vector3(3.7, 3.7, 3.7)

	if Rhythia.visual_mode:
		$EnergyVP/Control/Modifiers.visible = false

	songnametxt.text = Rhythia.selected_song.name

	var ms = ""

	if Rhythia.replaying:
		if Rhythia.replay.autoplayer: modicons.get_node("Autoplay").visible = true
		else: modicons.get_node("Replaying").visible = true
		_build_replay_controls()

	if Rhythia.mod_nofail: ms += tr("[ NOFAIL ACTIVE ]") + "\n"
	elif Rhythia.health_model == Globals.HP_OLD: ms += "Using old hp model (more hp + fast regen)\n"

	var mods = []
	modicons.get_node("Window").visible = Rhythia.mod_speed_level != Globals.SPEED_NORMAL and not Rhythia.speed_hitwindow
	if Rhythia.mod_speed_level != Globals.SPEED_NORMAL:
		match Rhythia.mod_speed_level:
			Globals.SPEED_MMM: modicons.get_node("SpeedMMM").visible = true
			Globals.SPEED_MM: modicons.get_node("SpeedMM").visible = true
			Globals.SPEED_M: modicons.get_node("SpeedM").visible = true
			Globals.SPEED_P: modicons.get_node("SpeedP").visible = true
			Globals.SPEED_PP: modicons.get_node("SpeedPP").visible = true
			Globals.SPEED_PPP: modicons.get_node("SpeedPPP").visible = true
			Globals.SPEED_PPPP: modicons.get_node("SpeedPPPP").visible = true
			Globals.SPEED_CUSTOM: mods.append("S%s" % [Globals.speed_multi[Globals.SPEED_CUSTOM] * 100])
	if Rhythia.mod_sudden_death: mods.append("SuddenDeath")
	if Rhythia.mod_extra_energy: mods.append("Energy+")
	if Rhythia.mod_no_regen: mods.append("NoRegen")
	if Rhythia.mod_mirror_x or Rhythia.mod_mirror_y:
		var mirrorst = tr("Mirror")
		if Rhythia.mod_mirror_x: mirrorst += "X"
		if Rhythia.mod_mirror_y: mirrorst += "Y"
		mods.append(mirrorst)
	if Rhythia.mod_ghost: mods.append(tr("Ghost"))
	if Rhythia.mod_nearsighted: mods.append("Nearsight")
	if Rhythia.mod_chaos: mods.append(tr("Chaos"))
	if Rhythia.mod_earthquake: mods.append(tr("Earthquake"))
	if Rhythia.mod_360:
		var speed = Rhythia.mod_360_speed
		var prefix = "-360" if speed < 0 else "360"
		var abs_speed = abs(speed)

		if abs_speed == 1:
			mods.append(prefix)
		else:
			mods.append("%sx%s" % [prefix, abs_speed])
	if Rhythia.mod_strobe: mods.append(tr("Strobe"))
	if Rhythia.mod_hardrock: mods.append(tr("Hard Rock"))
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
