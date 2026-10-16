extends Resource
class_name Replay

const file_sig: PoolByteArray = PoolByteArray([83, 115, 42, 82])
const current_sv: int = 4
var debug: bool = false

var dance: DanceMover
var song: Song
var past_cursor_positions: Array = []
var cursor_positions: Array = []
var past_triggers: Array = []
var triggers: Array = []
var note_results: Dictionary = {}
var settings: Dictionary = {}

var id: String
var sv: int = 2

var file: File = File.new()
var recording: bool = false
var loaded: bool = false
var autoplayer: bool = false
var end_ms: float = 0

var read_start_offset: int = 0

func replay_error(txt: String):
	Rhythia.get_tree().paused = true
	Globals.confirm_prompt.s_alert.play()
	Globals.confirm_prompt.open(txt, "Error", [{text = "OK"}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.s_back.play()
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	Rhythia.just_ended_song = false
	Rhythia.get_tree().change_scene("res://scenes/loaders/menuload.tscn")

var debug_label: Label

var debug_txt = {}

signal progress
signal done_loading

func update_debug_text():
	if debug:
		var txt: String = "-- replay debug --"
		for k in debug_txt.keys():
			txt += "\n%s: %s" % [k, String(debug_txt[k])]
		debug_label.text = txt
		debug_label.raise()

func read_data(from_path: String = ""):
	print("reading data")
	if not loaded:
		if debug:
			if Globals.get_tree().root.has_node("ReplayDebug"):
				debug_label = Globals.get_tree().root.get_node("ReplayDebug")
			else:
				debug_label = Label.new()
				Globals.get_tree().root.add_child(debug_label)
				debug_label.set("custom_fonts/font", load("res://assets/font/debug.tres"))
				debug_label.name = "ReplayDebug"
				debug_label.rect_position = Vector2(10, 10)
				debug_label.rect_scale = Vector2(0.5, 0.5)
				debug_label.text = "-- replay debug --"
			debug_label.raise()

			debug_txt = {source_path = from_path}
			update_debug_text()

		if from_path:
			var err: int = file.open(from_path, File.READ)

			debug_txt.autoplayer = false
			update_debug_text()

			if err != OK:
				replay_error("The replay could not be read. You will now be returned to the main menu.\n(file open error %s)" % err)
				return
			if file.get_buffer(4) != file_sig:
				file.close()
				replay_error("The replay is corrupted. You will now be returned to the main menu.\n(check failed)")
				return

			sv = file.get_16()
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)
			print(sv)

			debug_txt.sv = sv
			update_debug_text()

			if sv > current_sv or sv == 0:
				file.close()
				replay_error("The replay is corrupted. You will now be returned to the main menu.\n(invalid file version)")
				return

			debug_txt.reserved_1 = file.get_64()
			if sv >= 4: debug_txt.replay_hwid = file.get_line()
			id = file.get_line()
			var song_id = id.substr(0, id.find_last(".")).substr(0, id.find_last("."))
			var fsong = Rhythia.registry_song.get_item(song_id)

			debug_txt.replay_id = id
			debug_txt.song_id = song_id
			update_debug_text()

			if not fsong:
				file.close()
				replay_error("Could not find the song used by this replay. You will now be returned to the main menu.\n(song id: %s)" % song_id)
				return

			song = fsong
			Rhythia.selected_song = fsong
			var state_str = file.get_line()
			var state = Rhythia.parse_pb_str(state_str)
			debug_txt.state_str_after_offset = file.get_position()
			Rhythia.apply_state(state)
			debug_txt.state_str = state_str
			debug_txt.state = state

			if sv >= 3:
				settings.approach_rate = file.get_float()
				settings.spawn_distance = file.get_float()
				settings.fade_length = file.get_float()
				settings.parallax = file.get_float()
				settings.ui_parallax = file.get_float()
				settings.grid_parallax = file.get_float()
				settings.fov = file.get_float()
				settings.cam_unlock = file.get_8() == 1
				settings.edge_drift = file.get_float()

			debug_txt.reserved_2 = file.get_8()
			end_ms = float(file.get_32())
			debug_txt.end_ms = end_ms
			update_debug_text()

			var sigcount = file.get_32()
			debug_txt.sigcount = sigcount
			update_debug_text()

			if sigcount == 0:
				file.close()
				replay_error("The replay is corrupted. You will now be returned to the main menu.\n(signal count is zero)")
				return

			read_start_offset = file.get_position()
			debug_txt.read_start_offset = read_start_offset
			update_debug_text()

			var kind: int = file.get_8()
			print(kind)
			var i = 0
			var cursor_unrev = []
			while kind != Globals.RS_END:
				i += 1
				debug_txt.kind = kind
				debug_txt.i = i
				update_debug_text()
				if fmod(i, 70) == 0:
					emit_signal("progress", (float(i) / float(sigcount)) * 0.6)
					yield(Rhythia.get_tree(), "idle_frame")

				if kind == Globals.RS_CURSOR:
					var ms = file.get_32()
					var c = Vector3(file.get_float(), file.get_float(), ms)
					debug_txt.c = c
					cursor_unrev.append(c)

				elif kind == Globals.RS_PAUSE and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_PAUSE])

				elif kind == Globals.RS_START_UNPAUSE and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_START_UNPAUSE])

				elif kind == Globals.RS_CANCEL_UNPAUSE and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_CANCEL_UNPAUSE])

				elif kind == Globals.RS_SKIP and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_SKIP])

				elif kind == Globals.RS_FINISH_UNPAUSE and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_FINISH_UNPAUSE])

				elif kind == Globals.RS_GIVEUP and sv >= 2:
					var ms = file.get_32()
					triggers.append([ms, Globals.RS_GIVEUP])

				elif kind == Globals.RS_HIT and sv >= 2:
					var nid = file.get_32()
					note_results[nid] = true

				elif kind == Globals.RS_MISS and sv >= 2:
					var nid = file.get_32()
					note_results[nid] = false

				else:
					file.close()
					replay_error("The replay is corrupted. You will now be returned to the main menu.\n(invalid signal type %s)" % kind)
					return
				kind = file.get_8()
			if sv != 1 and note_results.size() == 0:
				file.close()
				replay_error("The replay is corrupted. You will now be returned to the main menu.\n(no note data)")
				return

			cursor_positions = cursor_unrev
			emit_signal("progress", 1.0)

			debug_txt.noteres_amt = note_results.size()
			debug_txt.cur_amt = cursor_positions.size()
			debug_txt.trig_amt = triggers.size()
			update_debug_text()

			print("nr: ", note_results.size())
			print("cur: ", cursor_positions.size())
			print("tr: ", triggers.size())
			emit_signal("done_loading")
			loaded = true
		else:
			autoplayer = true
			debug_txt.autoplayer = true
			update_debug_text()
			song = Rhythia.selected_song
			dance = BouncyDanceMover.new(song)


































			end_ms = Rhythia.selected_song.last_ms
			yield(Rhythia.get_tree(), "idle_frame")
			emit_signal("done_loading")
			loaded = true


var last_ms: float = -100000000000
var last_pos_offset: int = 0

func get_cursor_position(ms: float):
	if autoplayer:
		return Vector2(1, -1) * dance.update(ms)
	var n = cursor_positions.size()
	if n == 0:
		return Vector2(1, -1)
	var ap: Vector3
	var bp: Vector3
	if ms <= cursor_positions[0].z:
		ap = Vector3(1, -1, -3000 * Globals.speed_multi[Rhythia.mod_speed_level])
		bp = cursor_positions[0]
		last_pos_offset = 0
	elif ms >= end_ms:
		ap = cursor_positions[n - 1]
		bp = Vector3(1, -1, end_ms + 3000)
		last_pos_offset = n - 1
	else:
		var lo: int = 0
		var hi: int = n - 1
		if last_pos_offset >= 0 and last_pos_offset < n - 1 and cursor_positions[last_pos_offset].z <= ms and cursor_positions[last_pos_offset + 1].z >= ms:
			lo = last_pos_offset
			hi = last_pos_offset + 1
		else:
			while hi - lo > 1:
				var mid = (lo + hi) / 2
				if cursor_positions[mid].z <= ms: lo = mid
				else: hi = mid
		last_pos_offset = lo
		ap = cursor_positions[lo]
		bp = cursor_positions[hi]

	var a2 = Vector2(ap.x, ap.y)
	var b2 = Vector2(bp.x, bp.y)
	var v = clamp(smoothstep(ap.z, bp.z, ms), 0, 1)
	return lerp(a2, b2, v)

var trigger_cursor: int = 0
func get_signals(ms: float) -> Array:
	var out: Array = []
	while trigger_cursor < triggers.size() and triggers[trigger_cursor][0] <= ms:
		out.append(triggers[trigger_cursor])
		trigger_cursor += 1
	if out.size() != 0: print("out ", out)
	return out

func reset_signal_cursor_to(ms: float):
	trigger_cursor = 0
	while trigger_cursor < triggers.size() and triggers[trigger_cursor][0] <= ms:
		trigger_cursor += 1

func get_all_triggers() -> Array:
	return triggers

func should_hit(nid: int) -> bool:
	if autoplayer: return true
	if not note_results.has(nid): return false
	return note_results[nid]


var endms_offset: int = 0
var sig_count: int = 0

var max_usec = 0
func store_cursor_pos(ms: float, x: float, y: float):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(Globals.RS_CURSOR)
	file.store_32(floor(ms))
	last_ms = max(last_ms, floor(ms))
	file.store_float(x)
	file.store_float(y)
	if debug:
		max_usec = max(max_usec, OS.get_ticks_usec() - a)

func note_miss(nid: int):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(Globals.RS_MISS)
	file.store_32(nid)
	if debug:
		print("note %s miss saved @ #%s, took %s usec" % [nid, sig_count, Globals.comma_sep(OS.get_ticks_usec() - a)])

func note_hit(nid: int):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(Globals.RS_HIT)
	file.store_32(nid)
	if debug:
		print("note %s hit saved @ #%s, took %s usec" % [nid, sig_count, Globals.comma_sep(OS.get_ticks_usec() - a)])

func store_sig(ms: float, sig: int):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(sig)
	file.store_32(floor(ms))
	if debug:
		print("signal %s saved @ #%s, ms %s, took %s usec" % [sig, sig_count, ms, Globals.comma_sep(OS.get_ticks_usec() - a)])

func store_pause(ms: float):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(Globals.RS_PAUSE)
	file.store_32(floor(ms))
	if debug:
		print("pause saved @ #%s, ms %s, took %s usec" % [sig_count, ms, Globals.comma_sep(OS.get_ticks_usec() - a)])

func store_giveup(ms: float):
	if not recording: return
	var a = OS.get_ticks_usec()
	sig_count += 1
	file.store_8(Globals.RS_GIVEUP)
	file.store_32(floor(ms))
	if debug:
		print("giveup saved @ #%s, ms %s, took %s usec" % [sig_count, ms, Globals.comma_sep(OS.get_ticks_usec() - a)])

func start_recording(with_song: Song):
	var a = OS.get_ticks_usec()
	var dt = OS.get_datetime()
	song = with_song
	id = "%s.%s-%s-%s_%s-%s-%s" % [song.id, dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var err: int = file.open(Globals.p("user://replays/%s.sspre" % id), File.WRITE)
	file.store_buffer(file_sig)
	file.store_16(current_sv)
	file.store_64(0)
	file.store_line(OS.get_unique_id())
	file.store_line(id)
	file.store_line(Rhythia.generate_pb_str())

	file.store_float(Rhythia.approach_rate)
	file.store_float(Rhythia.spawn_distance)
	file.store_float(Rhythia.fade_length)
	file.store_float(Rhythia.parallax)
	file.store_float(Rhythia.ui_parallax)
	file.store_float(Rhythia.grid_parallax)
	file.store_float(Rhythia.fov)
	if Rhythia.cam_unlock: file.store_8(1)
	else: file.store_8(0)
	file.store_float(Rhythia.edge_drift)

	file.store_8(0)
	endms_offset = file.get_position()
	file.store_32(0)
	file.store_32(0)
	recording = true
	if debug:
		print("Recording startup took %s usec" % [Globals.comma_sep(OS.get_ticks_usec() - a)])

func end_recording():
	var a = OS.get_ticks_usec()
	recording = false
	sig_count += 1
	file.store_8(Globals.RS_END)
	file.seek(endms_offset)
	file.store_32(last_ms)
	file.store_32(sig_count)
	file.close()
	if debug:
		print("Recording end took %s usec. Highest cursor save time was %s usec." % [Globals.comma_sep(OS.get_ticks_usec() - a), max_usec])
