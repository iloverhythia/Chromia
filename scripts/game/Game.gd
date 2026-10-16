extends Spatial
class_name SongPlayerManager

signal hit
signal miss

var rawMapData: String
var notes: Array
var last_ms: float = 0
onready var colors: Array = Rhythia.selected_colorset.colors
onready var speed_multi = Globals.speed_multi[Rhythia.mod_speed_level]

var score: int = 0
var combo: int = 0
var combo_level: int = 1
var lvl_progress: int = 0
var song_has_failed: bool = false

export(StyleBox) var timer_fg_done

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""

	for i in range(0, string.length()):
		if i != 0 and i % 3 == mod:
			res += ","
		res += string[i]

	return res

func loadMapFile():
	var map: Song = Rhythia.selected_song
	last_ms = map.last_ms

	if map.should_reload_on_play:
		map.setup_from_file(map.initFile, map.musicFile)
	notes = map.read_notes()
	var file: File = File.new()
	var song: AudioStream = map.stream()


	$Spawn.spawn_notes(notes)

	get_node("Spawn/Music").stream = song

onready var head: Spatial = get_node("Avatar/Head")

var hits: float = 0
var misses: float = 0
var total_notes: float = 0
var energy: float = 6
var max_energy: float = 6
var energy_per_hit: float = 1
var max_combo: int = 0

func update_hud():
	$HUD.update_static_values()

var ending: bool = false
func end(end_type: int):
	if ending: return
	print("My god, what are you doing!?")
	ending = true
	if end_type == Globals.END_GIVEUP and Rhythia.record_replays and not Rhythia.replaying:
		Rhythia.replay.store_sig($Spawn.rms, Globals.RS_GIVEUP)
	if end_type != Globals.END_PASS:
		Rhythia.fail_asp.play()
	if end_type == Globals.END_FAIL and Rhythia.death_slowdown_enabled and not Rhythia.replaying:
		var spawn = $Spawn
		var music = $Spawn/Music
		var normal_speed = spawn.speed_multi
		var prev_disable_desync = Rhythia.disable_desync
		Rhythia.disable_desync = true
		var start_ticks = OS.get_ticks_msec()
		while true:
			var elapsed_sec = (OS.get_ticks_msec() - start_ticks) / 1000.0
			if elapsed_sec >= Rhythia.DEATH_SLOWDOWN_DURATION_SEC:
				break
			var t = elapsed_sec / Rhythia.DEATH_SLOWDOWN_DURATION_SEC
			var cur_speed = lerp(normal_speed, 0.0, t)
			spawn.speed_multi = cur_speed
			music.pitch_scale = max(cur_speed, 0.05)
			yield(get_tree(), "idle_frame")
		spawn.speed_multi = 0.0
		music.pitch_scale = normal_speed
		Rhythia.disable_desync = prev_disable_desync
	get_tree().paused = true
	if total_notes == 0: total_notes = 1
	update_hud()
	Rhythia.just_ended_song = true
	Rhythia.song_end_hits = hits
	Rhythia.song_end_misses = misses
	Rhythia.song_end_total_notes = total_notes
	Rhythia.song_end_position = min($Spawn.ms, last_ms)
	Rhythia.song_end_length = last_ms
	Rhythia.song_end_type = end_type
	Rhythia.song_end_combo = max_combo
	print("song max combo: ", max_combo)

	if Rhythia.record_replays and not Rhythia.replaying:
		Rhythia.replay.end_recording()

	if end_type == Globals.END_PASS and not Rhythia.replaying and Rhythia.selected_song != null:
		Rhythia.report_map_completion(String(Rhythia.selected_song.id))

	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager != null and lobby_manager.lobby_active:
		if end_type == Globals.END_PASS:
			lobby_manager.notify_passed()
		else:
			lobby_manager.notify_failed()
			$Spawn.active = false
			var first_peer_id = lobby_manager.get_first_place_peer_id()
			var hud = get_node("HUD")
			if hud != null and first_peer_id != -1:
				hud.enter_spectate_mode(first_peer_id)
		get_tree().paused = false
		return

	if Rhythia.queue_active and end_type == Globals.END_PASS:
		if Rhythia.do_pb_check_and_set():
			Globals.notify(Globals.NOTIFY_SUCCEED, "new best!")
		var next = Rhythia.get_next()
		$Spawn.ms_offset += max($Spawn.ms - (Rhythia.start_offset - (Rhythia.lead_in_ms * $Spawn.speed_multi)), 0)
		if Rhythia.queue_active and next:
			$Spawn.ms = Rhythia.start_offset - (Rhythia.lead_in_ms * $Spawn.speed_multi)
			Rhythia.select_song(next)
			$HUD.set_song_name(Rhythia.selected_song.name)
			Rhythia.update_rpc_song()
			if Rhythia.record_replays and not Rhythia.replaying:
				Rhythia.replay = Replay.new()
				Rhythia.replay.start_recording(Rhythia.selected_song)

			$Spawn.notes_loaded = false
			$Spawn.chaos_rng = RandomNumberGenerator.new()
			$Spawn.earthquake_rng = RandomNumberGenerator.new()
			$Spawn.chaos_rng.seed = hash(Rhythia.selected_song.id)
			$Spawn.earthquake_rng.seed = hash(Rhythia.selected_song.id)
			$Spawn.music_started = false
			$Spawn.out_of_notes = false
			$Spawn.note_count = 0

			$Spawn.prev_ms = (Rhythia.start_offset - (Rhythia.lead_in_ms * $Spawn.speed_multi))
			$Spawn.next_ms = 0
			get_tree().paused = false
			$Spawn.emit_signal("ms_change", $Spawn.ms)
			loadMapFile()
			ending = false
			return
	elif Rhythia.restart_on_death and end_type == Globals.END_FAIL and not Rhythia.replaying:
		if Rhythia.do_pb_check_and_set():
			print("Logging PB, restarting death")
		"""
		Change this func and one in EndInfo.gd to display PB when giving up with restart_on_death (since its the only escape outside of passing)
		It saves the PB yet it shows you failed until you reload the song in the menu
		My poor brain is fuming with this code lmao

		- helmeto
		"""

		get_tree().change_scene("res://scenes/song.tscn")
	else:
		black_fade_target = true
		yield(get_tree().create_timer(0.35), "timeout")
		Rhythia.arm_post_death_quick_restart()
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func update_timer(ms: float, canSkip: bool = false):
	var qms = ms + $Spawn.ms_offset
	var lms = last_ms

	if Rhythia.queue_active:
		lms = Rhythia.queue_end_length + (Rhythia.lead_in_ms * (Rhythia.song_queue.size() - 1))

	var s = clamp(floor(qms / 1000), 0, lms / 1000)
	var _m = floor(s / 60)
	var _rs = fmod(s, 60)

	var ls = floor(lms / 1000)
	var _lm = floor(ls / 60)
	var _lrs = fmod(ls, 60)

	$HUD.update_timer(ms, canSkip)

	if Rhythia.queue_active:
		if ms >= last_ms + $Spawn.hit_window:
			get_node("Spawn/Music").volume_db -= (17 * get_process_delta_time())
		else:
			get_node("Spawn/Music").volume_db = Rhythia.music_volume_db

	if ms >= last_ms + $Spawn.hit_window:
		if Rhythia.queue_active and ms >= last_ms + max($Spawn.hit_window, Rhythia.lead_in_ms):
			get_node("Spawn/Music").stop()
			end(Globals.END_PASS)
		elif not Rhythia.queue_active and not get_node("Spawn/Music").playing:
			end(Globals.END_PASS)


var loaded = false

var giving_up: float = 0
var black_fade_target: bool = true
var black_fade: float = 1
var passed: bool = false

onready var lobby_score_canvas: CanvasLayer = $LobbyScoreUI
onready var lobby_score_panel: PanelContainer = $LobbyScoreUI/Panel
onready var lobby_score_rows_box: VBoxContainer = $LobbyScoreUI/Panel/Margin/Outer/Rows
onready var lobby_score_title: Label = $LobbyScoreUI/Panel/Margin/Outer/Title
var _lobby_score_row_nodes: Dictionary = {}
var lobby_score_label: Label
var lobby_score_timer: float = 0.0

var showing_round_results: bool = false
onready var _results_continue_button: Button = $LobbyScoreUI/Panel/Margin/Outer/Continue
onready var _results_countdown_label: Label = $LobbyScoreUI/Panel/Margin/Outer/Countdown
var _results_time_left: float = 0.0
const ROUND_RESULTS_AUTO_CONTINUE_SEC: float = 2.0

const _RANK_COLORS = [
	Color(1.0, 0.84, 0.0),
	Color(0.78, 0.82, 0.87),
	Color(0.8, 0.5, 0.2),
]
const _DEFAULT_RANK_COLOR = Color(0.55, 0.58, 0.65)

func _make_lobby_score_row() -> Dictionary:
	var ui_theme = load("res://uitheme.tres")

	var row = PanelContainer.new()
	row.theme = ui_theme
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.connect("gui_input", self, "_on_lobby_score_row_input", [row])

	var row_style = StyleBoxFlat.new()
	row_style.bg_color = Color(1, 1, 1, 0.05)
	row_style.corner_radius_top_left = 6
	row_style.corner_radius_top_right = 6
	row_style.corner_radius_bottom_left = 6
	row_style.corner_radius_bottom_right = 6
	row_style.content_margin_left = 10
	row_style.content_margin_right = 10
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	row.add_stylebox_override("panel", row_style)


	var you_style = row_style.duplicate()
	you_style.bg_color = Color(1.0, 0.85, 0.2, 0.28)

	var hbox = HBoxContainer.new()
	hbox.add_constant_override("separation", 8)
	row.add_child(hbox)

	var rank_label = Label.new()
	rank_label.rect_min_size = Vector2(22, 0)
	rank_label.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	hbox.add_child(rank_label)

	var name_vbox = VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.add_constant_override("separation", 2)
	hbox.add_child(name_vbox)

	var name_row = HBoxContainer.new()
	name_row.add_constant_override("separation", 6)
	name_vbox.add_child(name_row)

	var name_label = Label.new()
	name_label.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var tag_label = Label.new()
	tag_label.visible = false
	name_row.add_child(tag_label)

	var acc_bar_bg = PanelContainer.new()
	acc_bar_bg.rect_min_size = Vector2(0, 4)
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(1, 1, 1, 0.08)
	bar_bg_style.corner_radius_top_left = 2
	bar_bg_style.corner_radius_top_right = 2
	bar_bg_style.corner_radius_bottom_left = 2
	bar_bg_style.corner_radius_bottom_right = 2
	acc_bar_bg.add_stylebox_override("panel", bar_bg_style)
	name_vbox.add_child(acc_bar_bg)

	var acc_bar_fill = ColorRect.new()
	acc_bar_fill.rect_min_size = Vector2(0, 4)
	acc_bar_fill.color = Color(0.4, 0.85, 0.55)
	acc_bar_fill.anchor_top = 0
	acc_bar_fill.anchor_bottom = 1
	acc_bar_fill.anchor_left = 0
	acc_bar_bg.add_child(acc_bar_fill)

	var stats_vbox = VBoxContainer.new()
	stats_vbox.alignment = BoxContainer.ALIGN_CENTER
	hbox.add_child(stats_vbox)

	var score_label = Label.new()
	score_label.align = Label.ALIGN_RIGHT
	stats_vbox.add_child(score_label)

	var meta_label = Label.new()
	meta_label.align = Label.ALIGN_RIGHT
	meta_label.add_color_override("font_color", Color(0.6, 0.63, 0.7))
	stats_vbox.add_child(meta_label)

	return {
		"root": row,
		"rank_label": rank_label,
		"name_label": name_label,
		"tag_label": tag_label,
		"acc_bar_bg": acc_bar_bg,
		"acc_bar_fill": acc_bar_fill,
		"score_label": score_label,
		"meta_label": meta_label,
		"default_style": row_style,
		"you_style": you_style,
	}

func _sort_lobby_player_stats(a, b):
	if a.alive != b.alive:
		return a.alive
	if a.accuracy > b.accuracy:
		return true
	if a.accuracy < b.accuracy:
		return false
	if a.score > b.score:
		return true
	if a.score < b.score:
		return false
	return a.name < b.name

func _on_lobby_score_row_input(event: InputEvent, row: Control):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	var hud = get_node_or_null("HUD")
	if hud == null or not hud.spectating:
		return
	var peer_id = int(row.get_meta("peer_id", -1))
	if peer_id == -1:
		return
	hud.spectate_specific_player(peer_id)

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func _update_lobby_score_ui():
	var lobby_manager = _get_lobby_manager()
	if lobby_score_canvas == null or lobby_manager == null:
		return
	var show = showing_round_results or (lobby_manager.lobby_active and lobby_manager.lobby_state.get("started", false))
	lobby_score_canvas.visible = show
	if not show:
		return
	lobby_score_title.text = "RESULTS" if showing_round_results else "LEADERBOARD"

	var rows = []
	if lobby_manager.players.size() > 0:
		for p in lobby_manager.players:
			rows.append({
				"name": String(p.get("name", "Player")),
				"score": int(p.get("score", 0)),
				"misses": int(p.get("misses", 0)),
				"accuracy": float(p.get("accuracy", 0.0)),
				"is_host": bool(p.get("is_host", false)),
				"is_you": int(p.get("peer_id", -1)) == lobby_manager.local_peer_id,
				"peer_id": int(p.get("peer_id", -1)),
				"alive": not bool(p.get("failed", false)),
				"tag_text": String(p.get("tag_text", "")),
				"tag_color": String(p.get("tag_color", "")),
			})
	else:
		rows.append({
			"name": "You", "score": score, "misses": misses,
			"accuracy": (float(hits) / float(total_notes)) if total_notes > 0 else 0.0,
			"is_host": false, "is_you": true, "peer_id": -1, "alive": not ending,
			"tag_text": "", "tag_color": "",
		})

	rows.sort_custom(self, "_sort_lobby_player_stats")

	var existing_children = lobby_score_rows_box.get_children()
	while existing_children.size() < rows.size():
		var new_row = _make_lobby_score_row()
		lobby_score_rows_box.add_child(new_row.root)
		new_row.root.set_meta("refs", new_row)
		existing_children = lobby_score_rows_box.get_children()
	while existing_children.size() > rows.size():
		var extra = existing_children.pop_back()
		extra.queue_free()

	for i in range(rows.size()):
		var row_node = lobby_score_rows_box.get_child(i)
		var refs = row_node.get_meta("refs")
		var row = rows[i]
		var rank = i + 1

		refs.rank_label.text = "#%d" % rank
		refs.rank_label.add_color_override("font_color",
			_RANK_COLORS[rank - 1] if rank <= 3 else _DEFAULT_RANK_COLOR)

		var display_name = row.name
		if row.is_host: display_name = "(host) " + display_name
		refs.name_label.text = display_name
		refs.name_label.add_color_override("font_color",
			Color(0.4, 0.85, 1.0) if row.is_you else Color(1, 1, 1))

		var tag_text = String(row.get("tag_text", ""))
		if tag_text != "":
			var tag_color_str = String(row.get("tag_color", ""))
			refs.tag_label.text = "● [%s]" % tag_text
			refs.tag_label.add_color_override("font_color", Color(tag_color_str) if tag_color_str != "" else Color(1, 1, 1))
			refs.tag_label.visible = true
		else:
			refs.tag_label.visible = false

		var bar_bg_width = refs.acc_bar_bg.rect_size.x
		if bar_bg_width <= 0:
			bar_bg_width = refs.acc_bar_bg.rect_min_size.x
		refs.acc_bar_fill.rect_size.x = clamp(row.accuracy, 0.0, 1.0) * bar_bg_width
		refs.acc_bar_fill.rect_size.y = 4

		refs.score_label.text = "%d" % row.score
		refs.meta_label.text = "%.2f%% · %d miss" % [row.accuracy * 100.0, row.misses]

		row_node.add_stylebox_override("panel", refs.you_style if row.is_you else refs.default_style)
		row_node.self_modulate = Color(1, 1, 1, 1) if row.is_you else Color(1, 1, 1, 0.85)
		row_node.set_meta("peer_id", row.peer_id)

	_layout_lobby_score_ui()
	call_deferred("_layout_lobby_score_ui")

const LOBBY_SCORE_WIDTH_NORMAL: float = 300.0
const LOBBY_SCORE_WIDTH_SPIN: float = 230.0

func _layout_lobby_score_ui():
	if lobby_score_panel == null:
		return
	var viewport_size = get_viewport().size
	var target_width = LOBBY_SCORE_WIDTH_SPIN if Rhythia.get("cam_unlock") else LOBBY_SCORE_WIDTH_NORMAL
	lobby_score_panel.rect_min_size.x = target_width
	var panel_size = lobby_score_panel.get_combined_minimum_size()
	panel_size.x = target_width
	lobby_score_panel.rect_size = panel_size
	var margin = 16
	lobby_score_panel.rect_position = Vector2(
		margin,
		(viewport_size.y - panel_size.y) / 2.0
	)

func _accuracy_color(acc: float) -> Color:
	if acc >= 0.95: return Color(0.4, 0.9, 0.6)
	if acc >= 0.85: return Color(0.95, 0.85, 0.3)
	if acc >= 0.7: return Color(0.95, 0.6, 0.3)
	return Color(0.9, 0.35, 0.35)

func _sync_lobby_stats():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or not lobby_manager.lobby_active:
		return
	lobby_manager.update_player_stats(score, hits, misses, total_notes)

func show_round_results():
	if showing_round_results:
		return
	showing_round_results = true
	_results_time_left = ROUND_RESULTS_AUTO_CONTINUE_SEC
	_results_continue_button.visible = true
	_results_countdown_label.visible = true
	get_tree().paused = false

func _finish_round_results():
	if not showing_round_results:
		return
	showing_round_results = false
	_results_continue_button.visible = false
	_results_countdown_label.visible = false
	var lobby_manager = _get_lobby_manager()
	if lobby_manager != null:
		lobby_manager.reset_lobby_round()
	get_tree().paused = false
	black_fade_target = true
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func _process(delta):
	_update_lobby_score_ui()
	if showing_round_results:
		_results_time_left -= delta
		_results_countdown_label.text = "Returning to lobby in %d..." % int(max(0, ceil(_results_time_left)))
		if _results_time_left <= 0:
			_finish_round_results()

	if not Rhythia.queue_active and $Spawn.ms > last_ms:
		passed = true

		head.get_node("EyeL").visible = false
		head.get_node("HappyL").visible = true

		head.get_node("EyeR").visible = false
		head.get_node("HappyR").visible = true

	if passed:
		$Avatar/ArmR.translation.y += (1 - $Avatar/ArmR.translation.y) * 0.01

	if not ending:
		if Input.is_action_pressed("give_up"):
			giving_up += delta / 0.6
			if giving_up >= 1:
				if not Rhythia.queue_active and $Spawn.ms > last_ms: end(Globals.END_PASS)
				else: end(Globals.END_GIVEUP)
		else:
			giving_up = 0

	if Rhythia.replaying and Input.is_action_just_pressed("pause"):
		get_tree().paused = not get_tree().paused

	if get_tree().paused:
		$Spawn.last_usec = OS.get_ticks_usec()


	if black_fade_target and black_fade != 1:
		black_fade = min(black_fade + (delta / 0.3), 1)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	elif not black_fade_target and black_fade != 0:
		black_fade = max(black_fade - (delta / 0.75), 0)
		$BlackFade.color = Color(0, 0, 0, black_fade)
	$BlackFade.visible = (black_fade != 0)

	lobby_score_timer += delta
	if lobby_score_timer >= 0.25:
		lobby_score_timer = 0.0
		_sync_lobby_stats()

func linstep(a: float, b: float, x: float):
	if a == b: return float(x >= a)
	return clamp(abs((x - a) / (b - a)), 0, 1)

func get_point_amt() -> int:
	var spd = clamp(((speed_multi - 1) * 1.5) + 1, 0, 1.9)

	var hitbox_diff = Rhythia.note_hitbox_size - 1.14
	var hbo = clamp(linstep(1.14, 0, hitbox_diff), 0, 1)

	var hitwin_diff = Rhythia.note_hitbox_size - 55
	var hwi = clamp(linstep(55, 0, hitwin_diff), 0, 1)

	var mod = 1

	return int(floor((50 * spd * min(hbo, hwi) * mod) + 0.5) * combo_level)

func _recompute_score_state(all_notes: Array, resolved_count: int):
	score = 0
	combo = 0
	combo_level = 1
	lvl_progress = 0
	hits = 0
	misses = 0
	total_notes = 0
	max_combo = 0
	energy = max_energy
	song_has_failed = false
	for i in range(resolved_count):
		total_notes += 1
		if all_notes[i][2] == Globals.NSTATE_HIT:
			hits += 1
			if not Rhythia.mod_no_regen: energy = clamp(energy + energy_per_hit, 0, max_energy)
			combo += 1
			if combo > max_combo: max_combo = combo
			if combo_level != 8:
				lvl_progress += 1
			if combo_level != 8 and lvl_progress == 10:
				lvl_progress = 0
				combo_level += 1
				if combo_level == 8: lvl_progress = 10
			score += get_point_amt()
		else:
			misses += 1
			energy = clamp(energy - 1, 0, max_energy)
			combo = 0
			lvl_progress = 0
			if combo_level != 1: combo_level -= 1
	update_hud()

func hit(col):
	if ending: return
	emit_signal("hit", col)
	hits += 1
	total_notes += 1
	_sync_lobby_stats()
	if not Rhythia.mod_no_regen: energy = clamp(energy + energy_per_hit, 0, max_energy)
	combo += 1

	if combo > max_combo: max_combo = combo

	var points = get_point_amt()
	if combo_level != 8:
		lvl_progress += 1
	if combo_level != 8 and lvl_progress == 10:
		lvl_progress = 0
		combo_level += 1
		if combo_level == 8: lvl_progress = 10
	update_hud()

	if Rhythia.hit_fov:
		if Rhythia.hit_fov_additive:
			$"../Camera".fov += Rhythia.hit_fov_amplifier
		elif Rhythia.hit_fov_exponential:
			$"../Camera".fov *= Rhythia.hit_fov_amplifier
		else:
			$"../Camera".fov = Rhythia.get("fov") - Rhythia.hit_fov_amplifier

	score += points
	return points

func miss(col):
	if ending: return
	emit_signal("miss", col)
	misses += 1
	total_notes += 1
	_sync_lobby_stats()
	energy = clamp(energy - 1, 0, max_energy)
	combo = 0
	lvl_progress = 0
	if combo_level != 1: combo_level -= 1
	update_hud()
	if energy == 0:
		if Rhythia.mod_nofail:
			if not song_has_failed:
				song_has_failed = true
				Rhythia.fail_asp.play()
		else:
			end(Globals.END_FAIL)


func _exit_tree():
	Rhythia.in_map = false

func _ready():
	Rhythia.in_map = true
	_results_continue_button.connect("pressed", self, "_finish_round_results")
	Rhythia.song_end_pause_count = 0
	Rhythia.song_end_misses = 0
	if Rhythia.selected_song != null:
		Rhythia.check_xp_eligibility_notice(String(Rhythia.selected_song.id))
	get_tree().paused = true
	get_node("Spawn/Music").volume_db = Rhythia.music_volume_db
	if Rhythia.mod_sudden_death:
		max_energy = 1
	elif Rhythia.health_model == Globals.HP_OLD:
		energy_per_hit = 1
		if Rhythia.mod_extra_energy: max_energy = 10
		else: max_energy = 6
	elif Rhythia.health_model == Globals.HP_SOUNDSPACE:
		energy_per_hit = 0.5
		if Rhythia.mod_extra_energy: max_energy = 8
		else: max_energy = 5

	energy = max_energy

	var spinst = Rhythia.loaded_world.instance()
	get_parent().call_deferred("add_child", spinst)
	spinst.name = "Space"

	$BlackFade.visible = true
	$BlackFade.color = Color(0, 0, 0, black_fade)
	get_tree().paused = false

	$Spawn.connect("timer_update", self, "update_timer")

	$Spawn.connect("miss", self, "miss")
	loadMapFile()


	Rhythia.update_rpc_song()

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	black_fade_target = false
	$ForceMatLoad.visible = false

	var lobby_manager = get_node_or_null("/root/LobbyManager")
	var is_late_join = lobby_manager != null and lobby_manager.consume_late_join_pending()

	if lobby_manager != null and lobby_manager.lobby_active and not is_late_join:
		_wait_for_all_players_loaded(lobby_manager)
	else:
		$Spawn.active = true

	if is_late_join:
		$Spawn.active = false
		var target_peer_id = lobby_manager.get_first_place_peer_id()
		var hud = get_node("HUD")
		if hud != null and target_peer_id != -1:
			ending = true
			hud.enter_spectate_mode(target_peer_id)

var _waiting_for_players_canvas: CanvasLayer = null

func _wait_for_all_players_loaded(lobby_manager):
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	var label = Label.new()
	label.text = "Waiting for players"
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.margin_left = -200
	label.margin_right = 200
	label.margin_top = -20
	label.margin_bottom = 20
	label.align = Label.ALIGN_CENTER
	label.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	canvas.add_child(label)
	add_child(canvas)
	_waiting_for_players_canvas = canvas

	lobby_manager.connect("all_players_loaded", self, "_on_all_players_loaded")
	lobby_manager.report_round_loaded()
	var t = get_tree().create_timer(15.0)
	t.connect("timeout", self, "_on_wait_for_players_timeout")

func _on_all_players_loaded():
	_begin_round_after_wait()

func _on_wait_for_players_timeout():
	_begin_round_after_wait()

func _begin_round_after_wait():
	if $Spawn.active:
		return
	if is_instance_valid(_waiting_for_players_canvas):
		_waiting_for_players_canvas.queue_free()
	_waiting_for_players_canvas = null
	$Spawn.active = true
