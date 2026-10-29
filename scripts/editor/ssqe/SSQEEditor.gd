extends Control
# The map editor screen: a GDScript port of Sound Space Quantum Editor Plus's
# editor (Web Editor/js/editor.js + editorwindow.js, from the desktop editor's
# GuiWindowEditor, GuiGrid, GuiTrack, GuiSliderTimeline and KeybindManager),
# drawn with Chromia's UI. Everything is laid out on SSQE's 1920x1080 stage,
# scaled to the page (SSQEPanels.gd builds the buttons, SSQETrack/Grid/
# Timeline.gd draw the rest).
#
# The page (EditorPage.gd) owns the project (song, cover, map list copy) and
# gives this the map to edit.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const RM = SSQEMap.RenderMode

const W0 := 1920.0
const H0 := 1080.0
const TEXT_K := 0.78 # SSQE text size -> Lato pixel size at 1080p
const CLIPBOARD_PATH = "user://editor/clipboard.json"

signal closed

var page # EditorPage
var s: Dictionary
var map
var panels # SSQEPanels
var track
var grid
var timeline
var dialogs # SSQEDialogs

var music: AudioStreamPlayer
var hit_players: Array = []
var _hit_next := 0
var metro: AudioStreamPlayer
var _music_bus := -1
var song_length := 0.0 # seconds
var waveform = null # {res, left: PoolRealArray, right: PoolRealArray, count}

# ---- playback
var playing := false
var _pos := 0.0 # seconds, when paused
var _clock = null # steady clock {pos, t, out}
var _ended := false

# ---- input
var mouse := Vector2(-1, -1)
var mouse_left := false
var mouse_right := false
var key_ctrl := false
var key_alt := false
var key_shift := false

# ---- grid state
var hovering_cell = null # Vector2 or null
var placing := false
var last_placed_pos = null
var hovering_xy = null
var dragging_xy: Array = []
var drag_cell_start := Vector2()

# ---- track state
var selecting := false
var select_ms_start := 0.0
var select_ms_end := 0.0
var hovering_object = null
var hovering_duration = null
var dragging_objects: Array = []
var dragging_duration = null
var drag_ms_start := 0.0
var drag_x_start := 0.0
var track_dragging := false
var should_replay := false
var last_played_object = null
var last_played_tick := -1
var track_start_rel := 0.0
var track_end_rel := 1.0

# ---- layout (editor-local pixels)
var wd := 1.0
var hd := 1.0
var TRACK := Rect2(0, 0, 1920, 86)
var GRID := Rect2(810, 390, 300, 300)
var _fonts := {}
var _autosave_left := 30.0
var dirty := false
var last_selected_lyric = null
var last_selected_note = null

# ================================================================== setup

func _init():
	s = SSQESettings.load_settings()

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	connect("resized", self, "_layout")
	_setup_audio()
	panels = load("res://scripts/editor/ssqe/SSQEPanels.gd").new()
	panels.ed = self
	dialogs = load("res://scripts/editor/ssqe/SSQEDialogs.gd").new()
	dialogs.ed = self
	add_child(dialogs)
	panels.build()
	move_child(dialogs, get_child_count() - 1) # windows above everything
	_layout()
	set_process(true)

func _exit_tree():
	if playing:
		pause_music()

func _setup_audio():
	_music_bus = AudioServer.get_bus_index("EditorMusic")
	if _music_bus == -1:
		AudioServer.add_bus()
		_music_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_music_bus, "EditorMusic")
		AudioServer.set_bus_send(_music_bus, "Music")
		var ps := AudioEffectPitchShift.new()
		AudioServer.add_bus_effect(_music_bus, ps)
		AudioServer.set_bus_effect_enabled(_music_bus, 0, false)
	music = AudioStreamPlayer.new()
	music.bus = "EditorMusic"
	add_child(music)
	for i in range(8):
		var h := AudioStreamPlayer.new()
		h.bus = "HitSound" if AudioServer.get_bus_index("HitSound") != -1 else "Master"
		h.stream = Rhythia.hit_snd
		add_child(h)
		hit_players.append(h)
	metro = AudioStreamPlayer.new()
	metro.bus = hit_players[0].bus
	metro.stream = _make_click()
	add_child(metro)
	update_volume()

static func _make_click() -> AudioStreamSample:
	var rate := 44100
	var n := int(rate * 0.03)
	var data := PoolByteArray()
	data.resize(n * 2)
	for i in range(n):
		var env := 1.0 - float(i) / n
		var v := int(sin(TAU * 1500.0 * i / rate) * env * env * 20000)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var smp := AudioStreamSample.new()
	smp.format = AudioStreamSample.FORMAT_16_BITS
	smp.mix_rate = rate
	smp.stereo = false
	smp.data = data
	return smp

# Opens a map: map (SSQEMap), the song's stream and the waveform (or null).
func open_map(m, stream: AudioStream):
	pause_music()
	map = m
	map.undo.editor_ref = weakref(self)
	music.stream = stream
	if stream and "loop" in stream:
		stream.loop = false
	song_length = stream.get_length() if stream else 0.0
	map.duration = song_length * 1000.0
	if map.duration <= 0:
		var last := 0.0
		if not map.notes.items.empty():
			last = map.notes.items[-1].ms
		map.duration = last + 5000.0
	map.current_time = clamp(map.current_time, 0, map.duration)
	_pos = map.current_time / 1000.0
	set_tempo_slider(map.tempo_slider)
	waveform = null
	hovering_cell = null
	hovering_xy = null
	dragging_xy = []
	dragging_objects = []
	dragging_duration = null
	placing = false
	selecting = false
	last_played_object = null
	if panels:
		panels.on_map_opened()
	_layout()

func settings_changed():
	SSQESettings.save_settings(s)
	update_volume()

func update_volume():
	if music == null:
		return
	var mv: float = 0.0 if s.muteMusic else clamp(s.masterVolume * 2.0, 0.0, 2.0)
	music.volume_db = linear2db(max(mv, 0.0001))
	var sv: float = 0.0 if s.muteSfx else clamp(s.sfxVolume * 2.0, 0.0, 2.0)
	for h in hit_players:
		h.volume_db = linear2db(max(sv, 0.0001))
	metro.volume_db = linear2db(max(sv, 0.0001))

# counts edits, so drawings that only change with the map (the timeline's
# ticks) are made again only after one
var edit_count := 0

func on_map_changed():
	map.changed()
	edit_count += 1
	dirty = true
	_autosave_left = max(float(s.autosaveInterval), 0.1) * 60.0
	if page and page.has_method("on_map_edited"):
		page.on_map_edited()

# GuiWindowEditor.ShowInfo / ShowWarn / ShowError / ShowOther
func toast(text: String, kind := "info"):
	var c := SSQESettings.color(s, "color1")
	if kind == "warn":
		c = SSQESettings.color(s, "color2")
	elif kind == "error":
		c = Color8(255, 200, 0)
	elif kind == "other":
		c = Color8(255, 109, 0)
	if panels:
		panels.show_toast(text, c)

# ================================================================== layout

func font(px: int, bold := false) -> DynamicFont:
	px = int(clamp(px, 6, 160))
	var key := px * 2 + (1 if bold else 0)
	if _fonts.has(key):
		return _fonts[key]
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf" if bold else "res://assets/font/Lato/Lato-Regular.ttf")
	f.size = px
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	_fonts[key] = f
	return f

# a font for an SSQE text size (as laid out at 1920x1080)
func text_font(text_size: float, scale := -1.0, bold := false) -> DynamicFont:
	if scale < 0:
		scale = min(wd, hd)
	return font(int(round(text_size * TEXT_K * scale)), bold)

# Control.Resize: a stage rect -> editor pixels (stretch: "XY", "X", "Y" or "")
func stage_rect(x: float, y: float, w: float, h: float, stretch := "XY") -> Rect2:
	var rx := x * wd
	var ry := y * hd
	var rw := w * wd
	var rh := h * hd
	var mn: float = min(wd, hd)
	if stretch.find("X") == -1:
		var width := w * mn
		rx += (rw - width) / 2
		rw = width
	if stretch.find("Y") == -1:
		var height := h * mn
		ry += (rh - height) / 2
		rh = height
	rx = round(rx)
	ry = round(ry)
	return Rect2(rx, ry, round(rx + rw) - rx, round(ry + rh) - ry)

func _layout():
	if rect_size.x <= 0 or rect_size.y <= 0:
		return
	wd = rect_size.x / W0
	hd = rect_size.y / H0
	TRACK = stage_rect(0, 0, 1920, 86)
	var size := 300.0 * clamp(float(s.gridZoom) / 100.0, 0.5, 2.0)
	GRID = stage_rect(960 - size / 2, 540 - size / 2, size, size, "")
	if panels:
		panels.layout()
	if track:
		track.rect_position = Vector2(TRACK.position.x, TRACK.position.y)
		track.rect_size = Vector2(TRACK.size.x, TRACK.size.y * 2)
		track.update()
	if grid:
		var c := GRID.size.x / 3.0
		grid.rect_position = GRID.position - Vector2(c, c)
		grid.rect_size = GRID.size + Vector2(c, c) * 2
		grid.update()
	if timeline:
		timeline.update()

func local_mouse() -> Vector2:
	return get_local_mouse_position()

# ================================================================== music (MusicPlayer)

func current_time() -> float:
	return map.current_time if map else 0.0

func set_current_time(v: float):
	if map:
		map.current_time = v

func total_time() -> float:
	return map.duration if map else 1.0

func music_offset() -> float:
	return float(s.musicOffset)

func tempo() -> float:
	return map.tempo() if map else 1.0

func set_tempo_slider(v: float):
	if map == null:
		return
	var was := playing
	var t := current_time()
	if was:
		pause_music()
	map.tempo_slider = v
	var tp := tempo()
	music.pitch_scale = tp
	var ps = AudioServer.get_bus_effect(_music_bus, 0)
	if ps is AudioEffectPitchShift:
		ps.pitch_scale = 1.0 / tp
	AudioServer.set_bus_effect_enabled(_music_bus, 0, abs(tp - 1.0) > 0.001)
	if was:
		set_current_time(t)
		play_music()

func _real_pos() -> float:
	var p := music.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * tempo()
	if abs(tempo() - 1.0) > 0.001:
		p -= 2048.0 / AudioServer.get_mix_rate() * tempo() # the pitch shift's own delay
	return p

# the steady clock (see the web editor's MusicPlayer.steady)
func _media_pos() -> float:
	if not playing:
		return _pos
	var now := OS.get_ticks_usec() / 1000000.0
	var real := _real_pos()
	if typeof(_clock) == TYPE_NIL:
		_clock = {"pos": real, "t": now, "out": real}
		return real
	var pos: float = _clock.pos + (now - _clock.t) * tempo()
	var err := real - pos
	pos = real if abs(err) > 0.25 else pos + err * 0.1
	_clock.pos = pos
	_clock.t = now
	var out: float = _clock.out if (pos < _clock.out and _clock.out - pos < 0.25) else pos
	_clock.out = out
	return out

func play_music():
	if music.stream == null:
		return
	playing = true
	_ended = false
	_clock = null
	var p: float = clamp((current_time() - music_offset()) / 1000.0, 0.0, song_length)
	music.play(p)

func pause_music():
	if not playing:
		return
	var t := _media_pos() * 1000.0 + music_offset()
	playing = false
	_clock = null
	music.stop()
	set_current_time(clamp(t, 0, total_time()))
	_pos = current_time() / 1000.0

func seek_music(ms: float):
	if playing:
		_clock = null
		music.play(clamp((ms - music_offset()) / 1000.0, 0.0, song_length))

func toggle_play():
	if map == null:
		return
	if playing:
		pause_music()
	else:
		if current_time() >= total_time() - 1:
			set_current_time(0)
		play_music()

# ================================================================== timing helpers

func closest_beat(ms: float, dragging_point = null, ignore_divisor := false) -> int:
	return map.get_closest_beat(ms, dragging_point, ignore_divisor)

func current_bpm(ms: float, dragging_point = null):
	return map.get_current_bpm(ms, dragging_point)

# Timing.Advance
func advance(reverse := false):
	if current_bpm(current_time()).bpm > 0:
		set_current_time(map.get_closest_beat_scroll(current_time(), reverse))

# Timing.Scroll
func scroll(reverse: bool, mult := 1.0):
	var delta := mult * (-1.0 if reverse else 1.0)
	var t := current_time()
	var total := total_time()
	if playing and not s.pauseScroll:
		t += delta * 500.0 * tempo()
		t = clamp(t, 0, total)
		set_current_time(t)
		seek_music(t)
	else:
		if playing:
			pause_music()
		t = current_time()
		var closest: int = map.get_closest_beat_scroll(t, delta < 0)
		var bpm0 = current_bpm(0)
		t = closest if (closest >= 0 or bpm0.bpm > 0) else t + delta / 10.0 * 1000.0 / map.zoom * 0.5
		if current_bpm(current_time()).bpm == 0 and current_bpm(t).bpm != 0:
			t = current_bpm(t).ms
		set_current_time(clamp(t, 0, total))

func click_mode() -> String:
	return ("select" if s.selectTool else "place") if s.separateClickTools else "both"

func can_select() -> bool:
	return click_mode() != "place"

func can_place() -> bool:
	return click_mode() != "select"

func render_notes() -> bool:
	return map.render_mode == RM.NOTES or map.object_mode == SSQEMap.OBJ_NOTE

# ================================================================== frame

func _process(delta):
	if map == null or not is_visible_in_tree():
		return
	if playing:
		set_current_time(clamp(_media_pos() * 1000.0 + music_offset(), 0, total_time()))
		if not music.playing and not _ended:
			# MusicPlayer.OnEnded
			_ended = true
			playing = false
			_clock = null
			set_current_time(total_time())
			_pos = song_length
	_update_modifiers()
	grid_pre_render()
	track_pre_render()
	_play_sounds()
	if panels:
		panels.update()
	if track:
		track.update()
	if grid:
		grid.update()
	if timeline:
		timeline.update()
	if dirty and s.autosave:
		_autosave_left -= delta
		if _autosave_left <= 0:
			_autosave_left = max(float(s.autosaveInterval), 0.1) * 60.0
			if page and page.has_method("autosave"):
				page.autosave()

func _update_modifiers():
	key_ctrl = Input.is_key_pressed(KEY_CONTROL) or Input.is_key_pressed(KEY_META)
	key_alt = Input.is_key_pressed(KEY_ALT)
	key_shift = Input.is_key_pressed(KEY_SHIFT)

# index of the last object at or before ms (-1 if none)
static func last_at_or_before(items: Array, ms: float) -> int:
	var lo := 0
	var hi := items.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if items[mid].ms <= ms:
			lo = mid + 1
		else:
			hi = mid
	return lo - 1

# hit sounds and metronome (from GuiTrack's render)
func _play_sounds():
	var t := current_time()
	var sfx_offset := float(s.sfxOffset)
	var to_play = null
	var polyphony := 0
	if render_notes():
		var items: Array = map.notes.items
		# the last note at or before now
		var i := last_at_or_before(items, t - sfx_offset)
		if i >= 0:
			to_play = items[i]
			var last_ms: float = last_played_object.ms if last_played_object else -1.0
			var j := i
			while j >= 0 and items[j].ms > last_ms and polyphony < 16:
				polyphony += 1
				j -= 1
	elif map.render_mode == RM.SPECIAL:
		for o in map.special_objects.items:
			if o.ms > t - sfx_offset:
				break
			if o.play_hitsound:
				to_play = o
	if to_play != last_played_object:
		var dist: float = abs((to_play.ms if to_play else 0) - t)
		if to_play and playing and dist < 200:
			for _k in range(min(int(s.maxPolyphony), max(polyphony, 1))):
				var h: AudioStreamPlayer = hit_players[_hit_next]
				_hit_next = (_hit_next + 1) % hit_players.size()
				if h.stream != Rhythia.hit_snd:
					h.stream = Rhythia.hit_snd
				h.play()
		last_played_object = to_play
	if s.metronome and playing:
		var ms := t - sfx_offset
		var b := closest_beat(ms, null, not s.scaleMetronome)
		if b != last_played_tick and b <= ms and b > 0:
			last_played_tick = b
			metro.play()

# ================================================================== input

func typing() -> bool:
	var f := get_focus_owner()
	return f is LineEdit or f is TextEdit

func _input(ev):
	if map == null or not is_visible_in_tree():
		return
	if ev is InputEventMouseMotion:
		mouse = get_local_mouse_position()
		grid_mouse_move(mouse)
		track_mouse_move(mouse)
		return
	if not (ev is InputEventKey) or not ev.pressed:
		return
	if dialogs and dialogs.wants_keys():
		return
	if Globals.file_sel and Globals.file_sel.visible:
		return
	if typing():
		if ev.scancode == KEY_ESCAPE:
			get_focus_owner().release_focus()
			get_tree().set_input_as_handled()
		return
	var code: int = ev.scancode
	var binds := SSQESettings.compare_keybind(s, code, ev.control or ev.command, ev.alt, ev.shift)
	var handled := not binds.empty()
	for b in binds:
		if ev.echo and (b.begins_with("gridKey") or b.begins_with("pattern")):
			continue
		run_keybind(b)
	# GuiTrack.KeyDown
	if code == KEY_SPACE:
		handled = true
		if not ev.echo and (not track_dragging or not dragging_objects.empty() or dragging_duration != null) and not (timeline and timeline.dragging):
			toggle_play()
	elif code == KEY_LEFT or code == KEY_RIGHT:
		handled = true
		scroll(code == KEY_LEFT)
	elif code == KEY_ESCAPE:
		handled = true
		map.clear_selected()
	if handled:
		get_tree().set_input_as_handled()

# clicks that no button took (GuiWindow.MouseDown: the track and grid first)
func _gui_input(ev):
	if map == null:
		return
	if ev is InputEventMouseButton:
		var p: Vector2 = ev.position
		mouse = p
		var f := get_focus_owner()
		if ev.pressed and f and f != self:
			f.release_focus()
		if ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				mouse_left = true
				var on_track := TRACK.has_point(p)
				if on_track:
					track_mouse_down_left(p)
				track_mouse_down_left_global(p)
				if not on_track:
					grid_mouse_down_left_global(p)
			elif mouse_left:
				mouse_left = false
				track_mouse_up_left(p)
				grid_mouse_up_left_global(p)
			accept_event()
		elif ev.button_index == BUTTON_RIGHT:
			if ev.pressed:
				mouse_right = true
				map.selected_point = null
				if not TRACK.has_point(p):
					map.clear_selected()
				else:
					track_mouse_down_right(p)
			else:
				mouse_right = false
				selecting = false
			accept_event()
		elif ev.pressed and (ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN):
			on_wheel(1 if ev.button_index == BUTTON_WHEEL_UP else -1)
			accept_event()
	elif ev is InputEventPanGesture:
		if abs(ev.delta.y) > 0.5:
			on_wheel(-1 if ev.delta.y > 0 else 1)

# GuiWindowEditor.MouseScroll
func on_wheel(delta: int):
	_update_modifiers()
	if key_shift:
		var step := 0.5 * (1.0 if key_ctrl else 2.0) * delta
		map.beat_divisor = clamp(map.beat_divisor + step, 0, 31)
	elif key_ctrl:
		map.increment_zoom(delta)
	else:
		scroll((delta < 0) != bool(s.reverseScroll), 1)

# ================================================================== keybinds (KeybindManager.ParseKeybind)

func run_keybind(bind: String):
	_update_modifiers()
	if bind.begins_with("pattern"):
		var index := int(bind.substr(7))
		if key_shift:
			if map.store_pattern(s, index):
				settings_changed()
				toast("BOUND PATTERN %d" % index)
		elif key_ctrl:
			s.patterns[index] = ""
			settings_changed()
			toast("UNBOUND PATTERN %d" % index)
		else:
			map.recall_pattern(s, index)
		return
	if bind.begins_with("gridKey"):
		var p := bind.substr(7).split("|")
		grid_key(2 - int(p[0]), 2 - int(p[1]))
		return
	match bind:
		"selectAll":
			map.clear_selected()
			if render_notes():
				map.notes.set_selected(map.notes.items.duplicate())
			else:
				var list = map.vfx_objects if map.render_mode == RM.VFX else map.special_objects
				if map.object_mode != SSQEMap.OBJ_DISABLED:
					var sel := []
					for n in list.items:
						if n.id == map.object_mode:
							sel.append(n)
					list.set_selected(sel)
				else:
					list.set_selected(list.items.duplicate())
		"undo":
			map.undo.undo()
		"redo":
			map.undo.redo()
		"copy":
			copy_selection(false)
		"cut":
			copy_selection(true)
		"paste":
			paste()
		"delete":
			delete_selection()
		"quantum":
			s.enableQuantum = not s.enableQuantum
			settings_changed()
		"anchorNode":
			if not map.notes.selected.empty():
				map.notes.edit("ANCHOR NODE[S]", null, self, "_toggle_anchor")
		"exportSSPM":
			dialogs.export_sspm("sspm")
		"createBPM":
			if map.notes.selected.size() == 2:
				var a = map.notes.selected[0]
				var b = map.notes.selected[1]
				var mn: int = min(a.ms, b.ms)
				var mx: int = max(a.ms, b.ms)
				if mx > mn:
					var bpm := round(60000.0 / (mx - mn) * 4.0) / 4.0
					if bpm > 0:
						map.replace_points("CREATE TIMING POINT", [], [SSQEMap.timing_point(bpm, mn)])
		"hFlip":
			h_flip()
		"vFlip":
			v_flip()
		"switchClickTool":
			s.selectTool = not s.selectTool
			settings_changed()
		"openTimings":
			dialogs.timings()
		"openBookmarks":
			dialogs.bookmarks()
		"storeNodes":
			store_nodes()
		"drawBezier":
			run_bezier()
		"save":
			if page:
				page.save_map()
		"saveAs":
			if page:
				page.save_as()

func _toggle_anchor(n):
	n.anchored = not n.anchored

# ================================================================== editing actions

func copy_selection(cut: bool):
	var lists := [[map.notes, "NOTES", "NOTE[S]"], [map.vfx_objects, "OBJECTS", "OBJECT[S]"], [map.special_objects, "OBJECTS", "OBJECT[S]"]]
	for l in lists:
		if not l[0].selected.empty():
			var copied: Array = l[0].selected.duplicate()
			copy_objects(copied)
			if cut:
				l[0].remove_objects("CUT " + l[2], copied)
			toast(("CUT " if cut else "COPIED ") + l[1], "other")
			return

# copied objects are the editor's (pasted into any map), notes also on disk
var _clipboard = null
func copy_objects(objects: Array):
	var time := OS.get_unix_time() * 1000 + OS.get_ticks_msec() % 1000
	var items := []
	for o in objects:
		items.append(o.clone())
	_clipboard = {"items": items, "time": time}
	var all_notes := true
	for o in objects:
		if o.id != 0:
			all_notes = false
			break
	if all_notes and not objects.empty():
		var nl := []
		for n in objects:
			nl.append([n.x, n.y, n.ms, 1 if n.enable_easing else 0, n.style, n.direction])
		Directory.new().make_dir_recursive(Globals.p("user://editor"))
		var f := File.new()
		if f.open(Globals.p(CLIPBOARD_PATH), File.WRITE) == OK:
			f.store_string(to_json({"time": time, "notes": nl}))
			f.close()

func copied_objects() -> Array:
	var stored = null
	var f := File.new()
	if f.open(Globals.p(CLIPBOARD_PATH), File.READ) == OK:
		var p := JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and typeof(p.result) == TYPE_DICTIONARY:
			stored = p.result
	if typeof(stored) == TYPE_DICTIONARY and stored.get("notes") is Array and (typeof(_clipboard) == TYPE_NIL or float(stored.get("time", 0)) > float(_clipboard.time)):
		var out := []
		for n in stored.notes:
			if n is Array and n.size() >= 3:
				out.append(SSQEMap.note(float(n[0]), float(n[1]), int(n[2]), n.size() > 3 and int(n[3]) == 1, int(n[4]) if n.size() > 4 else 0, int(n[5]) if n.size() > 5 else 0))
		return out
	var res := []
	if typeof(_clipboard) == TYPE_DICTIONARY:
		for o in _clipboard.items:
			res.append(o.clone())
	return res

func paste():
	var copied := copied_objects()
	if copied.empty():
		return
	var is_note: bool = copied[0].id == 0
	var offset: int = copied[0].ms
	var mx: int = copied[0].ms
	for n in copied:
		offset = min(offset, n.ms)
		mx = max(mx, n.ms)
	for n in copied:
		n.ms = int(clamp(current_time() + n.ms - offset, 0, total_time()))
	if is_note and render_notes():
		if s.pasteReversed:
			for i in range(copied.size() / 2):
				var cur = copied[i]
				var opp = copied[copied.size() - 1 - i]
				var cx: float = cur.x
				var cy: float = cur.y
				cur.x = opp.x
				cur.y = opp.y
				opp.x = cx
				opp.y = cy
		if s.applyOnPaste:
			for n in copied:
				SSQEMap.rotate_note(n, float(s.rotateBy), s.clampSR)
				SSQEMap.scale_note(n, float(s.scaleBy), s.clampSR)
		map.notes.add_objects("PASTE NOTE[S]", copied)
		_jump_after_paste(mx - offset)
	elif not is_note and map.render_mode != RM.NOTES:
		var vfx := []
		var special := []
		for o in copied:
			if F.is_vfx(o.id):
				vfx.append(o)
			else:
				special.append(o)
		if map.render_mode == RM.VFX:
			map.vfx_objects.add_objects("PASTE OBJECT[S]", vfx)
		else:
			map.special_objects.add_objects("PASTE OBJECT[S]", special)
		_jump_after_paste(mx - offset)

func _jump_after_paste(length: int):
	if s.jumpPaste:
		set_current_time(current_time() + length)
		if s.autoAdvance:
			advance()

func delete_selection():
	if map.selected_point:
		map.replace_points("DELETE POINT", [map.selected_point], [])
	elif render_notes():
		map.notes.remove_objects("DELETE NOTE[S]")
	elif map.render_mode == RM.VFX:
		map.vfx_objects.remove_objects("DELETE OBJECT[S]")
	else:
		map.special_objects.remove_objects("DELETE OBJECT[S]")

func h_flip():
	map.notes.edit("HORIZONTAL FLIP", null, SSQEMap, "horizontal_flip")

func v_flip():
	map.notes.edit("VERTICAL FLIP", null, SSQEMap, "vertical_flip")

func rotate_notes(deg: float):
	map.notes.edit("ROTATE " + SSQEMap.fmt(deg), null, SSQEMap, "rotate_note", [deg, bool(s.clampSR)])

func scale_notes(scale: float):
	map.notes.edit("SCALE %s%%" % SSQEMap.fmt(scale), null, SSQEMap, "scale_note", [scale, bool(s.clampSR)])

func store_nodes():
	var notes = map.notes
	var sel := {}
	for n in notes.selected:
		sel[n] = true
	notes.bezier_nodes = []
	for i in range(notes.items.size()):
		if sel.has(notes.items[i]):
			notes.bezier_nodes.append(i)

func clear_nodes():
	map.notes.bezier_nodes = []

# Patterns.RunBezier
func run_bezier():
	var divisor := int(float(s.bezierDivisor) + 0.5)
	var idx: Array = map.notes.bezier_nodes
	if divisor > 0 and (idx.size() > 1 or map.notes.selected.size() > 1):
		var nodes := []
		if idx.size() > 1:
			for i in idx:
				if i < map.notes.items.size():
					nodes.append(map.notes.items[i])
		else:
			nodes = map.notes.selected.duplicate()
			SSQEMap.ObjList._stable_sort(nodes)
		var result := []
		for segment in SSQEMap.bezier_segments(nodes, divisor, bool(s.curveBezier)):
			for j in range(1, segment.size()):
				result.append(segment[j])
		for n in result:
			if is_nan(n.x) or is_nan(n.y) or is_inf(n.x) or is_inf(n.y):
				toast("TOO MANY NODES", "error")
				return
		map.clear_selected()
		result.append(nodes[0])
		map.notes.replace("DRAW BEZIER", nodes, result)
	for n in map.notes.items:
		n.anchored = false
	map.notes.bezier_nodes = []

# ================================================================== grid (GuiGrid.cs)

func cell_size() -> float:
	return GRID.size.x / 3.0

func cell_bounds() -> Vector2:
	return Vector2(-0.85, 2.85) if s.enableQuantum else Vector2(0, 2)

func mouse_to_grid_unclamped_old(m: Vector2) -> Vector2:
	var quantum: bool = s.enableQuantum
	var inc: float = (float(s.quantumSnapping) + 3.0) / 3.0 if quantum else 1.0
	var x := (m.x - GRID.position.x - GRID.size.x / 2) / GRID.size.x * 3.0 + 1.0 / inc
	var y := (m.y - GRID.position.y - GRID.size.y / 2) / GRID.size.y * 3.0 + 1.0 / inc
	if s.quantumGridSnap or not quantum:
		x = floor((x + 1.0 / inc / 2.0) * inc) / inc
		y = floor((y + 1.0 / inc / 2.0) * inc) / inc
	x = x - 1.0 / inc + 1.0
	y = y - 1.0 / inc + 1.0
	return Vector2(2.0 - x, 2.0 - y)

func mouse_to_grid_unclamped(m: Vector2) -> Vector2:
	var quantum: bool = s.enableQuantum
	var cell := cell_size()
	var mx := m.x
	var my := m.y
	if quantum:
		mx -= cell * (float(s.quantumXOffset) - 1.0)
		my -= cell * (float(s.quantumYOffset) - 1.0)
	var inc: float = 2.0 / (float(s.quantumSnapping) + 2.0) if quantum else 1.0
	var x := (mx - GRID.position.x - cell / 2) / cell
	var y := (my - GRID.position.y - cell / 2) / cell
	if s.quantumGridSnap or not quantum:
		x = SSQEMap.round_even(x / inc) * inc
		y = SSQEMap.round_even(y / inc) * inc
	if quantum:
		x += float(s.quantumXOffset) - 1.0
		y += float(s.quantumYOffset) - 1.0
	return Vector2(2.0 - x, 2.0 - y)

func mouse_to_grid(m: Vector2) -> Vector2:
	var pos: Vector2 = mouse_to_grid_unclamped_old(m) if s.oldQuantumSnap else mouse_to_grid_unclamped(m)
	var b := cell_bounds()
	return Vector2(clamp(pos.x, b.x, b.y), clamp(pos.y, b.x, b.y))

func grid_mouse_move(m: Vector2):
	var hover := mouse_to_grid(m)
	var unclamped := mouse_to_grid_unclamped(m)
	hovering_cell = hover if abs(hover.x - unclamped.x) <= 1 and abs(hover.y - unclamped.y) <= 1 else null
	if placing and not playing:
		if typeof(last_placed_pos) == TYPE_NIL or hover != last_placed_pos:
			var ms := closest_beat(current_time())
			map.notes.add_objects("ADD NOTE", SSQEMap.note(hover.x, hover.y, ms if ms >= 0 else int(current_time())))
			if s.autoAdvance:
				advance()
			last_placed_pos = hover
	elif not dragging_xy.empty():
		var drag = dragging_xy[0]
		var x_off: float = hover.x - drag.x
		var y_off: float = hover.y - drag.y
		if x_off == 0 and y_off == 0:
			return
		var min_x: float = drag.x
		var max_x: float = drag.x
		var min_y: float = drag.y
		var max_y: float = drag.y
		for o in dragging_xy:
			min_x = min(min_x, o.x)
			max_x = max(max_x, o.x)
			min_y = min(min_y, o.y)
			max_y = max(max_y, o.y)
		var b := cell_bounds()
		x_off = max(b.x, min_x + x_off) - min_x
		x_off = min(b.y, max_x + x_off) - max_x
		y_off = max(b.x, min_y + y_off) - min_y
		y_off = min(b.y, max_y + y_off) - max_y
		for i in range(1, dragging_xy.size()):
			dragging_xy[i].x += x_off
			dragging_xy[i].y += y_off

func grid_mouse_down_left_global(_p: Vector2):
	var mode := click_mode()
	if (hovering_xy == null and mode == "both") or mode == "place":
		if not render_notes() or typeof(hovering_cell) == TYPE_NIL:
			return
		var ms := closest_beat(current_time())
		map.notes.add_objects("ADD NOTE", SSQEMap.note(hovering_cell.x, hovering_cell.y, ms if ms >= 0 else int(current_time())))
		if s.autoAdvance and not playing:
			advance()
		last_placed_pos = hovering_cell
		placing = true
	elif hovering_xy != null:
		var hovering = hovering_xy
		var selected := []
		for n in map.selected_objects():
			if n.is_xy:
				selected.append(n)
		if key_shift:
			var first = selected[0] if not selected.empty() else hovering
			var mn: float = min(first.ms, hovering.ms)
			var mx: float = max(first.ms, hovering.ms)
			selected = []
			for n in map.get_objects_in_range(mn, mx):
				if n.is_xy and n != first:
					selected.append(n)
			selected.push_front(first)
		elif key_ctrl:
			if hovering.selected:
				selected.erase(hovering)
			else:
				selected.append(hovering)
		elif selected.empty() or not hovering in selected:
			selected = [hovering]
		map.set_selected_objects(selected)
		if hovering.selected:
			dragging_xy = [hovering] + selected
			drag_cell_start = Vector2(hovering.x, hovering.y)

func grid_mouse_up_left_global(_p: Vector2):
	placing = false
	last_placed_pos = null
	if not dragging_xy.empty():
		var dx: float = dragging_xy[0].x - drag_cell_start.x
		var dy: float = dragging_xy[0].y - drag_cell_start.y
		if dx * dx + dy * dy > 0:
			for i in range(1, dragging_xy.size()):
				dragging_xy[i].x -= dx
				dragging_xy[i].y -= dy
			var list = map.active_list()
			list.edit("MOVE NOTE[S]" if list == map.notes else "MOVE OBJECT[S]", null, self, "_move_xy", [dx, dy])
		dragging_xy = []

func _move_xy(n, dx: float, dy: float):
	if n.is_xy:
		n.x += dx
		n.y += dy

func _set_xy(n, x: float, y: float):
	n.x = x
	n.y = y

# GuiGrid.KeybindUsed
func grid_key(x: int, y: int):
	var ms: int = min(closest_beat(current_time()), int(total_time()))
	if ms < 0:
		ms = int(current_time())
	if render_notes():
		if not s.moveOnGridKey or map.notes.selected.empty():
			map.notes.add_objects("ADD NOTE", SSQEMap.note(x, y, ms))
			if s.moveOnGridKey:
				map.notes.clear_selected()
		else:
			map.notes.edit("MOVE NOTE[S]", null, self, "_set_xy", [float(x), float(y)])
			return
	elif map.render_mode == RM.SPECIAL:
		var o = object_for_key(map.object_mode, x, y)
		if o == null:
			return
		o.ms = ms
		map.special_objects.add_objects("ADD " + o.name.to_upper(), o)
	else:
		return
	if s.autoAdvance:
		advance()

# GuiGrid.objectLookup: which extra object a grid key places
static func object_for_key(mode: int, x: int, y: int):
	match mode:
		SSQEMap.OBJ_BEAT:
			if x == 1 and y == 1:
				return SSQEMap.beat(0)
		SSQEMap.OBJ_MINE:
			return SSQEMap.mine(x, y, 0)
		SSQEMap.OBJ_GLIDE:
			if x == 1 and y == 2:
				return SSQEMap.glide(0, 0)
			if x == 1 and y == 0:
				return SSQEMap.glide(0, 2)
			if x == 2 and y == 1:
				return SSQEMap.glide(0, 3)
			if x == 0 and y == 1:
				return SSQEMap.glide(0, 1)
		SSQEMap.OBJ_FEVER:
			if x == 1 and y == 1:
				return SSQEMap.fever(0, 0)
	return null

static func object_key_exists(mode: int, x: int, y: int) -> bool:
	return object_for_key(mode, x, y) != null

# GuiGrid.PreRender: placing notes while the song plays and the mouse is held
func grid_pre_render():
	if placing and playing:
		var ms := closest_beat(current_time())
		if ms > 0 and ms <= current_time():
			var r: Array = map.notes.search_range(ms - 2, ms + 2)
			var exists := false
			for i in range(r[0], r[1]):
				if abs(map.notes.items[i].ms - ms) < 2:
					exists = true
					break
			if not exists:
				var p := mouse_to_grid(mouse)
				map.notes.add_objects("ADD NOTE", SSQEMap.note(p.x, p.y, ms))

# ================================================================== track (GuiTrack.cs)

func ms_to_px() -> float:
	return map.zoom * 0.5

func px_to_ms() -> float:
	return 2.0 / map.zoom

func track_note_size() -> float:
	return TRACK.size.y * 0.52

func track_cell_gap() -> float:
	return TRACK.size.y * 0.14

func cursor_x() -> float:
	return TRACK.size.x * float(s.cursorPos) / 100.0

func track_mouse_move(m: Vector2):
	var x := m.x
	var total := total_time()
	var cursor_ms := (x - cursor_x()) * px_to_ms() + current_time()
	if x == drag_x_start:
		return
	var bpm: float = current_bpm(cursor_ms).bpm
	var threshold := 12.0
	if bpm > 0 and map.beat_divisor > 0:
		threshold = clamp(60000.0 / bpm * ms_to_px() / map.beat_divisor / 1.75, 1, 12)
	if not dragging_objects.empty():
		cursor_ms -= track_note_size() / 2 * px_to_ms()
	var first = dragging_objects[0] if not dragging_objects.empty() else null
	if first and first.id == 1:
		var snapped: float = closest_beat(cursor_ms, first)
		var snapped_note: float = map.notes.get_closest(cursor_ms)
		if abs(snapped_note - cursor_ms) < abs(snapped - cursor_ms):
			snapped = snapped_note
		if abs(snapped - cursor_ms) * ms_to_px() <= threshold:
			cursor_ms = snapped
		if abs(cursor_ms) * ms_to_px() <= threshold:
			cursor_ms = 0
		first.ms = int(min(cursor_ms, total))
		map.sort_timings()
	else:
		if bpm > 0:
			var snapped2: float = closest_beat(cursor_ms)
			if abs(snapped2 - cursor_ms) * ms_to_px() <= threshold:
				cursor_ms = snapped2
		if dragging_duration != null:
			dragging_duration.duration = int(max(cursor_ms - dragging_duration.ms, 0))
		elif not dragging_objects.empty():
			var offset: float = cursor_ms - first.drag_start_ms
			for o in dragging_objects:
				o.ms = int(clamp(o.drag_start_ms + offset, 0, total))
			map.sort_objects()
		elif track_dragging:
			var time := drag_ms_start - (x - drag_x_start) * px_to_ms()
			if current_bpm(time).bpm > 0:
				time = closest_beat(time)
			set_current_time(clamp(time, 0, total))

func track_mouse_down_left(p: Vector2):
	var play_check := false
	if hovering_duration != null:
		dragging_objects = []
		dragging_duration = hovering_duration
		dragging_duration.drag_start_ms = dragging_duration.duration
		map.clear_selected()
	elif hovering_object != null and hovering_object.id != 1:
		var hovering = hovering_object
		var selected: Array = map.selected_objects()
		if key_shift:
			var first = selected[0] if not selected.empty() else hovering
			var mn: float = min(first.ms, hovering.ms)
			var mx: float = max(first.ms, hovering.ms)
			selected = []
			for n in map.get_objects_in_range(mn, mx):
				if n != first:
					selected.append(n)
			selected.push_front(first)
		elif key_ctrl:
			if hovering.selected:
				selected.erase(hovering)
			else:
				selected.append(hovering)
		elif not hovering in selected:
			selected = [hovering]
		map.clear_selected()
		map.set_selected_objects(selected)
		if hovering.selected:
			dragging_objects = [hovering] + selected
			for o in dragging_objects:
				o.drag_start_ms = o.ms
		dragging_duration = null
	elif hovering_object == null:
		play_check = true
	drag_ms_start = current_time()
	drag_x_start = p.x
	track_dragging = true
	should_replay = play_check and playing
	if should_replay:
		pause_music()

func track_mouse_down_left_global(_p: Vector2):
	if hovering_object != null and hovering_object.id == 1:
		var point = hovering_object
		dragging_objects = [point]
		dragging_duration = null
		point.drag_start_ms = point.ms
		map.clear_selected()
		map.selected_point = point

func track_mouse_up_left(_p: Vector2):
	var first = dragging_objects[0] if not dragging_objects.empty() else null
	if first and first.id == 1:
		var diff: int = first.ms - first.drag_start_ms
		if diff != 0:
			first.ms = first.drag_start_ms
			map.edit_points("MOVE POINT", [first], map, "_shift_ms", [diff])
	elif first:
		var diff2: int = first.ms - first.drag_start_ms
		if diff2 != 0:
			for o in dragging_objects:
				o.ms = o.drag_start_ms
			var list = map.active_list()
			list.edit("MOVE NOTE[S]" if list == map.notes else "MOVE OBJECT[S]", null, map, "_shift_ms", [diff2])
	elif dragging_duration != null:
		var d = dragging_duration
		var diff3: int = d.duration - d.drag_start_ms
		if diff3 != 0:
			d.duration = d.drag_start_ms
			map.active_list().edit("MOVE OBJ DURATION", [d], self, "_add_duration", [diff3])
	dragging_objects = []
	dragging_duration = null
	if track_dragging and should_replay:
		play_music()
	should_replay = false
	track_dragging = false

func _add_duration(o, d: int):
	o.duration += d

func track_mouse_down_right(p: Vector2):
	select_ms_start = (p.x - cursor_x()) * px_to_ms() + current_time()
	select_ms_end = select_ms_start
	selecting = true

func track_pre_render():
	if selecting:
		select_ms_end = (mouse.x - cursor_x()) * px_to_ms() + current_time()
		var start: float = min(select_ms_start, select_ms_end) - track_note_size() * px_to_ms()
		var end: float = max(select_ms_start, select_ms_end)
		map.set_selected_objects(map.get_objects_in_range(start, end))

# ================================================================== lyrics

# GuiWindowEditor.Render lyric preview -> [text, alpha]
func lyric_preview() -> Array:
	var t := current_time()
	var prev = null
	var cur = null
	var text := ""
	var alpha := 1.0
	var fading_in := false
	for o in map.special_objects.items:
		if o.id != 15:
			continue
		prev = cur
		cur = o
		if cur.ms > t:
			break
		if cur.fade_out:
			alpha = 1.0 - clamp((t - cur.ms) / 1000.0, 0, 1)
			fading_in = false
		elif cur.fade_in:
			alpha = clamp((t - cur.ms) / 1000.0, 0, 1)
			fading_in = true
		elif not fading_in:
			alpha = 1.0
		var ct: String = cur.text
		if ct.strip_edges() != "":
			if prev and SSQEMap.ss(prev.text).strip_edges() == "":
				text = ct
				if text.begins_with("-"):
					text = text.substr(1)
			elif ct.begins_with("-"):
				text = ct.substr(1)
			elif text.ends_with("-"):
				text = text.substr(0, text.length() - 1) + ct
			elif text.strip_edges() != "":
				text += " " + ct
			else:
				text = ct
		elif not cur.fade_out:
			text = ct
	if text.ends_with("-"):
		text = text.substr(0, text.length() - 1)
	return [text, alpha]

func set_special(on: bool):
	map.render_mode = RM.SPECIAL if on else RM.NOTES
	map.object_mode = SSQEMap.OBJ_DISABLED
	map.clear_selected()
	if panels:
		panels.on_special_changed(on)
