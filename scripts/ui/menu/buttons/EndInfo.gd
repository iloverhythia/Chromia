extends Control

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""

	for i in range(0, string.length()):
		if i != 0 and i % 3 == mod:
			res += ","
		res += string[i]

	return res

func hide_info(_s = null):
	visible = false

func get_time_ms(ms: float):
	var s = max(floor(ms / 1000), 0)
	var m = floor(s / 60)
	var rs = fmod(s, 60)
	return "%d:%02d" % [m, rs]

var _pb_ts: int = 0
var _pb_time_refresh_t: float = 0.0

const _PB_TIME_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _format_relative_time(ts: int) -> String:
	var diff = OS.get_unix_time() - ts
	if diff < 60:
		return "just now"
	elif diff < 3600:
		return "%dm ago" % int(diff / 60)
	elif diff < 86400:
		return "%dh ago" % int(diff / 3600)
	elif diff < 604800:
		return "%dd ago" % int(diff / 86400)
	elif diff < 2629800:
		return "%dw ago" % int(diff / 604800)
	elif diff < 31557600:
		return "%dmo ago" % int(diff / 2629800)
	else:
		return "%dy ago" % int(diff / 31557600)

func _full_date_string(ts: int) -> String:
	var dt = OS.get_datetime_from_unix_time(ts)
	var hour12 = dt.hour % 12
	if hour12 == 0: hour12 = 12
	var ampm = "AM" if dt.hour < 12 else "PM"
	return "%s %d, %d %d:%02d %s" % [_PB_TIME_MONTHS[dt.month - 1], dt.day, dt.year, hour12, dt.minute, ampm]

func _refresh_pb_time_label():
	if _pb_ts <= 0:
		$PBTime.text = ""
		$PBTime.hint_tooltip = ""
	else:
		$PBTime.text = _format_relative_time(_pb_ts)
		$PBTime.hint_tooltip = _full_date_string(_pb_ts)

func _set_pb_time(ts: int):
	_pb_ts = ts
	_refresh_pb_time_label()

var rainbow_letter_grade: bool = false
func update_letter_grade(acc: float = 0):
	var grade: String = "--"
	var gcol: Color = Color(1, 0, 1)
	var shine: float = 0
	rainbow_letter_grade = (acc >= 0.99)
	if acc == 1 and Rhythia.show_fc_grade:
		grade = "FC"
		gcol = Color("#fa6afa")
	elif acc >= 0.99:
		grade = "SS"
		gcol = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.5, 1)
	elif acc >= 0.98:
		grade = "S"
		gcol = Color("#91fffa")
	elif acc >= 0.95:
		grade = "A"
		gcol = Color("#91ff92")
	elif acc >= 0.9:
		grade = "B"
		gcol = Color("#e7ffc0")
	elif acc >= 0.85:
		grade = "C"
		gcol = Color("#fcf7b3")
	elif acc >= 0.8:
		grade = "D"
		gcol = Color("#fcd0b3")
	else:
		grade = "F"
		gcol = Color("#ff8282")

	$LetterGrade.text = grade
	$LetterGrade.material.set_shader_param("shine", shine)
	$LetterGrade.set("custom_colors/font_color", gcol)

	gcol.a = 0.1
	$LetterGrade2.text = grade
	$LetterGrade2.set("custom_colors/font_color", gcol)


func _process(delta):
	if rainbow_letter_grade:
		$LetterGrade.set("custom_colors/font_color", Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1))
		$LetterGrade2.set("custom_colors/font_color", Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 0.1))
	_pb_time_refresh_t -= delta
	if _pb_time_refresh_t <= 0:
		_pb_time_refresh_t = 1.0
		_refresh_pb_time_label()

func show_pb(_s = null):
	if Rhythia.selected_song != null:
		var pb = Rhythia.get_best()
		if pb:
			visible = true
			var misses = pb.total_notes - pb.hit_notes
			if pb.has_passed:
				$Result.text = "Personal Best"
				$Result.set("custom_colors/font_color", Color("#6ff1ff"))
			else:
				$Result.text = "Best Attempt"
				$Result.set("custom_colors/font_color", Color("#ea4aca"))

			$FullCombo.visible = misses == 0 and pb.has_passed
			$Misses.visible = not misses == 0 or not pb.has_passed
			$Misses.text = comma_sep(misses)

			$NoPauses.visible = pb.pauses == 0
			$Pauses.visible = not pb.pauses == 0
			$Pauses.text = comma_sep(pb.pauses)

			$Accuracy.text = "%s/%s\n%.03f%%" % [
				comma_sep(pb.hit_notes),
				comma_sep(pb.total_notes),
				(float(pb.hit_notes) / float(pb.total_notes)) * 100
			]

			if pb.max_combo < 0:
				$MaxCombo.text = "?"
			else:
				$MaxCombo.text = comma_sep(pb.max_combo)
			$MaxCombo.text += "\n"

			update_letter_grade(float(pb.hit_notes) / float(pb.total_notes))
			$Progress.text = "%s\n%.2f%%" % [get_time_ms(pb.position), clamp(pb.position / Rhythia.selected_song.last_ms, 0, 1) * 100]
			_set_pb_time(int(pb.get("ts", 0)))
		else:
			visible = true
			$Result.text = "No PB"
			$LetterGrade.text = "-"
			$LetterGrade2.text = ""
			rainbow_letter_grade = false
			$LetterGrade.set("custom_colors/font_color", Color(1, 1, 1))
			$LetterGrade.material.set_shader_param("shine", 0)
			$Result.set("custom_colors/font_color", Color("#ffdd99"))
			$FullCombo.visible = false
			$Misses.visible = true
			$Misses.text = "-"
			$NoPauses.visible = false
			$Pauses.visible = true
			$Pauses.text = "-"
			$Accuracy.text = "-\n"
			$Progress.text = "-\n"
			$MaxCombo.text = "-\n"
			_set_pb_time(0)

func _ready():
	Rhythia.connect("selected_song_changed", self, "show_pb")
	Rhythia.connect("mods_changed", self, "show_pb")

	yield(Rhythia, "map_list_ready")

	if not Rhythia.selected_song:
		return

	$NewBest.stream = Rhythia.pb_snd
	if $NewBest.stream != Rhythia.normal_pb_sound:
		$NewBest.pitch_scale = 1

	visible = Rhythia.just_ended_song

	if Rhythia.just_ended_song:
		_handle_post_game_results()
	else:
		show_pb()

	Rhythia.just_ended_song = false

	call_deferred("_transition_to_list")

func _transition_to_list():
	var list = get_node_or_null("/root/Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if list:
		list.switch_to_play_screen()

func _handle_post_game_results():
	var is_best: bool = Rhythia.do_pb_check_and_set()
	if is_best: $NewBest.play()

	if Rhythia.song_end_type == Globals.END_PASS:
		if Rhythia.was_replay: $Result.text = "Replay passed"
		elif is_best: $Result.text = "New best!"
		else: $Result.text = "You passed!"
		$Result.set("custom_colors/font_color", Color("#6ff1ff"))
	elif Rhythia.was_replay:
		$Result.text = "Replay failed"
	elif is_best:
		$Result.text = "You failed (new best!)"
		$Result.set("custom_colors/font_color", Color("#ea4aca"))
	else:
		$Result.text = "You failed!"

	$FullCombo.visible = Rhythia.song_end_misses == 0 and Rhythia.song_end_type == Globals.END_PASS
	$Misses.visible = not Rhythia.song_end_misses == 0 or not Rhythia.song_end_type == Globals.END_PASS
	$Misses.text = comma_sep(Rhythia.song_end_misses)

	$NoPauses.visible = Rhythia.song_end_pause_count == 0
	$Pauses.visible = not Rhythia.song_end_pause_count == 0
	$Pauses.text = comma_sep(Rhythia.song_end_pause_count)

	$Accuracy.text = "%s/%s\n%.03f%%" % [
		comma_sep(Rhythia.song_end_hits),
		comma_sep(Rhythia.song_end_total_notes),
		(float(Rhythia.song_end_hits) / float(Rhythia.song_end_total_notes)) * 100
	]

	if Rhythia.song_end_combo < Rhythia.selected_song.note_count:
		$MaxCombo.text = comma_sep(Rhythia.song_end_combo)
	elif Rhythia.song_end_combo == Rhythia.selected_song.note_count:
		$MaxCombo.text = "FULL COMBO"
	else:
		$MaxCombo.text = "NO COMBO"
	$MaxCombo.text += "\n"

	update_letter_grade(float(Rhythia.song_end_hits) / float(Rhythia.song_end_total_notes))
	var divisor = Rhythia.song_end_length
	if divisor == 0:
		divisor = 1
	$Progress.text = "%s\n%.1f%%" % [Rhythia.song_end_time_str, clamp(Rhythia.song_end_position / divisor, 0, 1) * 100]

	if is_best:
		_set_pb_time(OS.get_unix_time())
	else:
		var pb = Rhythia.get_best()
		_set_pb_time(int(pb.get("ts", 0)) if pb else 0)
