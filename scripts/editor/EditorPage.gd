extends ReferenceRect
# "Map Editor" sidebar page: the in-game map editor, laid out exactly like
# Sound Space Quantum Editor (github.com/iloverhythia/Sound-Space-Quantum-Editor-Plus)
# in Chromia's colours. The middle is the game itself (EditorView3D.gd): your
# note mesh, colorset, approach rate, fades, border, cursor and world.
#
# Layout (SSQE's, at 1280x720, scaled with the window):
#   track across the top; OPTIONS / TIMING / PATTERNS tabs on the left,
#   SNAPPING / GRAPHICS / EXPORT on the right; COPY MAP DATA above the grid,
#   BACK TO MENU under it; PLAYTEST bottom left; timeline, play button and
#   playback speed along the bottom; SFX / Music volume bottom right.
#
# Keys (when no text box is focused):
#   Q W E / A S D / Z X C (or numpad) place / remove a note at the current time
#   Space play / pause      Left / Right, wheel  move one snap step
#   Up / Down  next / previous note   Home / End  start / end
#   Ctrl+Z / Ctrl+Y undo / redo     Ctrl+C / X / V copy / cut / paste
#   Ctrl+A select all   Delete remove selected   Ctrl+S save
#   H / V flip selected   R rotate selected   T tap BPM

const EditorProject = preload("res://scripts/editor/EditorProject.gd")
const EdToggle = preload("res://scripts/editor/EdToggle.gd")
const EdSlider = preload("res://scripts/editor/EdSlider.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_LINE = Color(0.28, 0.26, 0.33, 1)
const SPEEDS = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
const SETTINGS_PATH = "user://editor/settings.json"
const RETURN_META = "chromia_editor_return"
const MAX_UNDO = 200
const SIDEBAR = 0.0 # the page already starts right of the sidebar
const REF_W = 1280.0
const REF_H = 720.0
const GRID_KEYS = {KEY_Q: Vector2(0, 0), KEY_W: Vector2(1, 0), KEY_E: Vector2(2, 0),
	KEY_A: Vector2(0, 1), KEY_S: Vector2(1, 1), KEY_D: Vector2(2, 1),
	KEY_Z: Vector2(0, 2), KEY_X: Vector2(1, 2), KEY_C: Vector2(2, 2)}
const NUMPAD_KEYS = {KEY_KP_7: Vector2(0, 0), KEY_KP_8: Vector2(1, 0), KEY_KP_9: Vector2(2, 0),
	KEY_KP_4: Vector2(0, 1), KEY_KP_5: Vector2(1, 1), KEY_KP_6: Vector2(2, 1),
	KEY_KP_1: Vector2(0, 2), KEY_KP_2: Vector2(1, 2), KEY_KP_3: Vector2(2, 2)}

# ---- state used by the grid / track / seek bar / game view
var project = null
var time_ms := 0.0
var playing := false
var song_length_ms := 1.0
var divisor := 4
var quantum := false
var quantum_divisor := 3
var quantum_offset := Vector2()
var snap_to_grid := true
var auto_advance := false
var approach_ms := 700.0 # 2D view
var ar_override := 0.0   # 0 = the game's approach rate
var show_letters := true
var show_numbers := false
var quantum_lines := true
var show_cursor := true
var game_view := true
var show_world := true
var hit_flash := true
var overlay_opacity := 1.0
var grid_zoom := 1.0
var cursor_position := 0.4
var hitsounds := true
var metronome := false
var metro_scale := false
var sfx_offset := 0.0
var music_vol := 0.8
var hit_vol := 0.6
var speed := 1.0
var zoom := 0.35 # px per ms on the track
var use_numpad := false
var jump_on_paste := false
var pause_on_seek := true
var clamp_bounds := true
var move_on_key := false
var smooth_cursor := true
var show_asq := false
var note_size_2d := 1.0
var apply_on_paste := false
var paste_reversed := false
var curve_bezier := true
var bezier_nodes: Array = [] # [x, y, ms, uid] stored by STORE NODES
var copy_btn: Button
var back_btn: Button
var f_bez: LineEdit

var _selected: Dictionary = {}
var _uid := 0
var _undo: Array = []
var _redo: Array = []
var _clip: Array = []
var _dirty := false
var _autosave_left := 30.0
var _last_hit_ms := 0.0
var _last_beat := -1
var _taps: Array = []
var _tap_bpm := 0.0

# ---- nodes
var f_btn: DynamicFont
var f_lbl: DynamicFont
var f_val: DynamicFont
var f_small: DynamicFont
var f_title: DynamicFont
var f_big: DynamicFont
var home: Control
var projects_box: VBoxContainer
var edit_selected_btn: Button
var workspace: Control
var view3d = null
var grid
var track
var seekbar
var status_label: Label
var zoom_label: Label
var play_btn: Button
var speed_slider
var speed_label: Label
var tab_buttons: Dictionary = {}  # name -> Button
var left_tab := "timing"
var right_tab := "snapping"
var f_bpm: LineEdit
var f_offset: LineEdit
var f_sfx: LineEdit
var f_rot: LineEdit
var f_scale: LineEdit
var f_title_e: LineEdit
var f_mapper: LineEdit
var f_diff: OptionButton
var f_overwrite
var f_cover: TextureRect
var tap_label: Label
var sr_label: Label
var div_slider
var qdiv_slider
var music: AudioStreamPlayer
var hit_players: Array = []
var _hit_next := 0
var metro: AudioStreamPlayer
var _paused_menu_players: Array = []
var _built := false
# layout: [node, h-anchor ("L", "R", "C"), x, y, w, h, v-anchor ("T", "B"), tab]
var _items: Array = []
var _scale := 1.0

# ================================================================== helpers

func _mkfont(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, radius: int = 4, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = 4
	s.content_margin_right = 4
	return s

func _label(text: String, font: Font, color: Color = LILAC) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.add_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

# SSQE-shaped button (dark, 2px outline, bold caps) in Chromia colours
func _btn(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	b.add_font_override("font", f_btn)
	b.add_color_override("font_color", TEXT)
	b.add_color_override("font_color_hover", Color(1, 1, 1))
	b.add_color_override("font_color_pressed", ACCENT)
	b.add_color_override("font_color_disabled", DIM)
	b.add_stylebox_override("normal", _flat(BTN_BG, 4, BTN_LINE, 2))
	b.add_stylebox_override("hover", _flat(Color(0.14, 0.13, 0.18, 1), 4, LILAC, 2))
	b.add_stylebox_override("pressed", _flat(Color(0.2, 0.17, 0.25, 1), 4, ACCENT, 2))
	b.add_stylebox_override("disabled", _flat(Color(0.08, 0.075, 0.1, 1), 4, Color(0.2, 0.19, 0.24), 2))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	if method != "":
		b.connect("pressed", self, method, args)
	return b

func _field(method: String) -> LineEdit:
	var e = LineEdit.new()
	e.align = LineEdit.ALIGN_CENTER
	e.add_font_override("font", f_val)
	e.add_color_override("font_color", ACCENT)
	e.add_stylebox_override("normal", _flat(Color(0.03, 0.03, 0.04, 1), 4, BTN_LINE, 2))
	e.add_stylebox_override("focus", _flat(Color(0.03, 0.03, 0.04, 1), 4, LILAC, 2))
	if method != "":
		e.connect("text_entered", self, method)
		e.connect("focus_exited", self, "_field_left", [e, method])
	return e

func _field_left(e: LineEdit, method: String):
	call(method, e.text)

func _text_field(placeholder: String, method: String) -> LineEdit:
	var e = _field("")
	e.align = LineEdit.ALIGN_LEFT
	e.placeholder_text = placeholder
	e.add_color_override("font_color", TEXT)
	e.connect("text_changed", self, method)
	return e

func _toggle(text: String, on: bool, method: String):
	var t = EdToggle.new()
	t.text = text
	t.pressed = on
	t.font = f_lbl
	t.connect("toggled", self, method)
	return t

func _slider(fmt: String, minv: float, maxv: float, stepv: float, value: float, method: String, label_scale: float = 1.0):
	var s = EdSlider.new()
	s.label_format = fmt
	s.min_value = minv
	s.max_value = maxv
	s.step = stepv
	s.value = value
	s.font = f_lbl
	s.label_scale = label_scale
	s.connect("value_changed", self, method)
	return s

# Places a node by SSQE coordinates (1280x720 reference).
func _put(n: Control, ha: String, x: float, y: float, w: float, h: float, va: String = "T", tab: String = ""):
	if n.get_parent() == null:
		workspace.add_child(n)
	_items.append([n, ha, x, y, w, h, va, tab])
	return n

static func fmt_time(ms: float) -> String:
	var neg := ms < 0
	var t := int(abs(ms))
	var s := "%d:%02d.%03d" % [t / 60000, (t / 1000) % 60, t % 1000]
	return ("-" + s) if neg else s

func _typing() -> bool:
	var f = get_focus_owner()
	return f is LineEdit or f is TextEdit

func approach_rate_3d() -> float:
	return ar_override if ar_override > 0 else float(Rhythia.get("approach_rate"))

# ================================================================== build

func _ready():
	connect("visibility_changed", self, "_on_visibility")
	connect("resized", self, "_layout")
	set_process(false)
	var root = get_tree().root
	if root.has_meta(RETURN_META):
		var info = root.get_meta(RETURN_META)
		root.remove_meta(RETURN_META)
		if typeof(info) == TYPE_DICTIONARY:
			Rhythia.start_offset = float(info.get("prev_start_offset", 0.0))
			call_deferred("_resume_after_playtest", info)

func _resume_after_playtest(info: Dictionary):
	yield(get_tree().create_timer(0.1), "timeout")
	var sidebar = get_node_or_null("../../Sidebar")
	if sidebar and sidebar.has_method("press_page"):
		sidebar.press_page(self)
	_ensure_built()
	if open_project(Globals.s(info.get("pid", ""))):
		seek(float(info.get("time", 0.0)))

func _on_visibility():
	if is_visible_in_tree():
		_ensure_built()
		_refresh_home()
		_pause_menu_music(true)
		_layout()
	else:
		pause()
		_pause_menu_music(false)
		if project != null and _dirty:
			_save_project_only()

func _pause_menu_music(on: bool):
	if on:
		_paused_menu_players.clear()
		var pm = get_node_or_null("../Maps/Results/Results/RS/H1/Info/Control/PreviewMusic")
		if pm:
			for n in ["Song", "MenuSong"]:
				var p = pm.get_node_or_null(n)
				if p is AudioStreamPlayer and p.playing and not p.stream_paused:
					p.stream_paused = true
					_paused_menu_players.append(p)
	else:
		for p in _paused_menu_players:
			if is_instance_valid(p):
				p.stream_paused = false
		_paused_menu_players.clear()

func _ensure_built():
	if _built:
		return
	_built = true
	# the game's own fonts (uitheme.tres: Lato Regular; headings Lato Bold)
	f_btn = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 13)
	f_lbl = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 14)
	f_val = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 14)
	f_small = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 12)
	f_title = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 22)
	f_big = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 44)
	_load_settings()

	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	for i in range(6):
		var h = AudioStreamPlayer.new()
		h.bus = "HitSound"
		h.stream = Rhythia.hit_snd
		add_child(h)
		hit_players.append(h)
	metro = AudioStreamPlayer.new()
	metro.bus = "HitSound"
	metro.stream = _make_click()
	add_child(metro)
	_apply_volumes()

	_build_home()
	_build_workspace()
	workspace.visible = false
	_layout()

func _make_click() -> AudioStreamSample:
	var rate := 44100
	var n := int(rate * 0.03)
	var data := PoolByteArray()
	data.resize(n * 2)
	for i in range(n):
		var env := 1.0 - float(i) / n
		var v := int(sin(TAU * 1500.0 * i / rate) * env * env * 20000)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s

# ------------------------------------------------------------------ home
# Like SSQE's start screen: title top left, your maps on the left (where SSQE
# has its changelog), big buttons on the right.

func _build_home():
	home = Control.new()
	home.anchor_right = 1
	home.anchor_bottom = 1
	home.margin_left = 4
	add_child(home)

	var title = _label("MAP EDITOR", f_big, TEXT)
	title.name = "Title"
	home.add_child(title)
	var sub = _label("Chromia's in-game Quantum Editor", f_lbl, LILAC)
	sub.name = "Sub"
	home.add_child(sub)

	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_stylebox_override("panel", _flat(Color(0.06, 0.055, 0.08, 0.8), 6))
	home.add_child(panel)
	var pv = VBoxContainer.new()
	pv.add_constant_override("separation", 8)
	panel.add_child(pv)
	pv.add_child(_label("YOUR MAPS", f_title, TEXT))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	pv.add_child(sc)
	projects_box = VBoxContainer.new()
	projects_box.size_flags_horizontal = SIZE_EXPAND_FILL
	projects_box.add_constant_override("separation", 6)
	sc.add_child(projects_box)

	var col = VBoxContainer.new()
	col.name = "Buttons"
	col.add_constant_override("separation", 10)
	home.add_child(col)
	for it in [["CREATE NEW MAP", "_on_new_map"], ["EDIT SELECTED MAP", "_on_edit_selected"],
			["LOAD MAP", "_on_load_sspm"], ["PASTE MAP", "_on_paste_new"]]:
		var b = _btn(it[0], it[1])
		b.add_font_override("font", f_title)
		b.size_flags_vertical = SIZE_EXPAND_FILL
		col.add_child(b)
		if it[1] == "_on_edit_selected":
			edit_selected_btn = b
	home.connect("resized", self, "_layout_home")

func _layout_home():
	var w := home.rect_size.x
	var h := home.rect_size.y
	var s: float = clamp(h / REF_H, 0.6, 2.5)
	var t = home.get_node("Title")
	t.rect_position = Vector2(23 * s, 14 * s)
	home.get_node("Sub").rect_position = Vector2(26 * s, 14 * s + f_big.get_height() + 2)
	var panel = home.get_node("Panel")
	panel.rect_position = Vector2(23 * s, 120 * s)
	panel.rect_size = Vector2(w * 0.5 - 23 * s, h - 120 * s - 70 * s)
	var col = home.get_node("Buttons")
	col.rect_position = Vector2(w * 0.5 + 40 * s, 120 * s)
	col.rect_size = Vector2(w * 0.5 - 80 * s, min(4 * 58 * s + 30, h - 190 * s))

func _refresh_home():
	if not _built:
		return
	var s = Rhythia.selected_song
	if s is Song:
		edit_selected_btn.text = "EDIT: " + Globals.s(s.name).to_upper()
		edit_selected_btn.hint_tooltip = "Open the map selected in your map list"
		edit_selected_btn.disabled = false
	else:
		edit_selected_btn.text = "EDIT SELECTED MAP"
		edit_selected_btn.disabled = true
	for c in projects_box.get_children():
		c.queue_free()
	var list: Array = EditorProject.list_projects()
	if list.empty():
		var l = _label("No maps yet. CREATE NEW MAP starts one from a song; EDIT SELECTED MAP opens a map from your list.", f_lbl, DIM)
		l.autowrap = true
		projects_box.add_child(l)
		return
	for p in list:
		projects_box.add_child(_project_row(p))

func _project_row(p: Dictionary) -> Control:
	var row = PanelContainer.new()
	row.add_stylebox_override("panel", _flat(Color(0.06, 0.055, 0.075, 1), 4, BTN_LINE, 1))
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	row.add_child(h)
	var cov = TextureRect.new()
	cov.rect_min_size = Vector2(46, 46)
	cov.expand = true
	cov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if p.has_cover:
		var img = Image.new()
		if img.load(EditorProject.root_dir().plus_file(p.pid).plus_file("cover.png")) == OK:
			if img.get_width() > 96:
				img.resize(96, int(96.0 * img.get_height() / max(img.get_width(), 1)))
			var t = ImageTexture.new()
			t.create_from_image(img)
			cov.texture = t
	h.add_child(cov)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 0)
	h.add_child(v)
	var t1 = _label(p.title, f_val, TEXT)
	t1.clip_text = true
	v.add_child(t1)
	var when := ""
	if p.modified > 0:
		var dt = OS.get_datetime_from_unix_time(p.modified)
		when = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	v.add_child(_label("%s%d notes · %s" % [(p.mapper + " · ") if p.mapper != "" else "", p.notes, when], f_small, LILAC))
	var ob = _btn("OPEN", "open_project", [p.pid])
	ob.rect_min_size = Vector2(70, 30)
	ob.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(ob)
	var db = _btn("DELETE", "_on_delete_project", [p.pid, p.title])
	db.rect_min_size = Vector2(76, 30)
	db.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(db)
	return row

var _confirm: ConfirmationDialog
func _ask(text: String, method: String, args: Array = []):
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.theme = load("res://uitheme.tres")
		_confirm.window_title = "Map Editor"
		_confirm.popup_exclusive = true
		add_child(_confirm)
	for c in _confirm.get_signal_connection_list("confirmed"):
		_confirm.disconnect("confirmed", self, c.method)
	_confirm.dialog_text = text
	_confirm.connect("confirmed", self, method, args, CONNECT_ONESHOT)
	_confirm.popup_centered(Vector2(420, 140))

func _on_delete_project(pid: String, title: String):
	_ask("Delete the editor map \"%s\"?\n(The copy in your map list stays.)" % title, "_do_delete_project", [pid])

func _do_delete_project(pid: String):
	if project != null and project.pid == pid:
		close_project()
	EditorProject.delete_project(pid)
	_refresh_home()

func _pick_song(method: String):
	Globals.file_sel.open_file(self, method, PoolStringArray(["*.mp3, *.ogg ; Songs (mp3, ogg)"]), false, "~/Downloads" if OS.has_feature("pc") else "user://")

func _first(files) -> String:
	if files is PoolStringArray and files.size() > 0:
		return files[0]
	if files is String:
		return files
	return ""

func _on_new_map():
	_pick_song("_on_new_song_picked")

func _on_new_song_picked(files):
	var path := _first(files)
	if path == "":
		return
	var res = EditorProject.create(path, path.get_file().get_basename(), "")
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Map Editor")
		return
	_open(res)
	_set_tab("timing")
	Globals.notify(Globals.NOTIFY_INFO, "Set the BPM and offset in TIMING, then place notes with Q W E / A S D / Z X C or the mouse.", "New map")

func _on_load_sspm():
	Globals.file_sel.open_file(self, "_on_sspm_picked", PoolStringArray(["*.sspm ; Sound Space maps"]), false, "~/Downloads" if OS.has_feature("pc") else "user://")

func _on_sspm_picked(files):
	var path := _first(files)
	if path == "":
		return
	var s = Song.new()
	var r = s.load_from_sspm(path)
	if r is String:
		Globals.notify(Globals.NOTIFY_WARN, r, "Can't open this map")
		return
	edit_song(s)

var _pending_paste: Array = []
func _on_paste_new():
	var notes = EditorProject.notes_from_text(OS.clipboard)
	if notes == null:
		Globals.notify(Globals.NOTIFY_WARN, "Copy Sound Space map data first (\"id,x|y|ms,...\").", "Nothing to paste")
		return
	_pending_paste = notes
	Globals.notify(Globals.NOTIFY_INFO, "%d notes found. Now pick the song for them." % notes.size(), "Paste map")
	_pick_song("_on_paste_song_picked")

func _on_paste_song_picked(files):
	var path := _first(files)
	if path == "" or _pending_paste.empty():
		return
	var id := OS.clipboard.split(",")[0].strip_edges()
	var res = EditorProject.create(path, id if id != "" else path.get_file().get_basename(), "")
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Map Editor")
		return
	res.notes = _pending_paste
	res.sort_notes()
	res.save()
	_pending_paste = []
	_open(res)

func _on_edit_selected():
	edit_song(Rhythia.selected_song)

func edit_song(s):
	_ensure_built()
	if s == null:
		return
	var res = EditorProject.from_song(s)
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Can't edit this map")
		return
	_open(res)
	Globals.notify(Globals.NOTIFY_INFO, "Timing guessed from the notes: %s BPM (check it in TIMING). Saving makes a new copy; to save over the original, tick it in EXPORT." % str(res.bpm), "Editing " + Globals.s(s.name))

func open_project(pid: String) -> bool:
	_ensure_built()
	var pr = EditorProject.load_project(pid)
	if pr == null:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't open that editor map.", "Map Editor")
		return false
	_open(pr)
	return true

func _open(pr):
	if project != null and _dirty:
		_save_project_only()
	pause()
	project = pr
	for n in project.notes:
		if n.size() < 4:
			n.append(_next_uid())
	_selected.clear()
	_undo.clear()
	_redo.clear()
	_dirty = false
	time_ms = project.offset if project.offset > 0 else 0.0
	_last_hit_ms = time_ms
	var stream = Globals.audioLoader.load_file(project.audio_path())
	if stream is AudioStream:
		if "loop" in stream:
			stream.loop = false
		music.stream = stream
		song_length_ms = max(stream.get_length() * 1000.0, project.length_ms() + 2000.0)
	else:
		music.stream = null
		song_length_ms = max(project.length_ms() + 5000.0, 60000.0)
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't load this map's song.", "Map Editor")
	_fill_fields()
	home.visible = false
	workspace.visible = true
	_apply_view_mode()
	notes_changed(false)
	_update_status()
	_layout()

func close_project():
	if project != null and _dirty:
		_save_project_only()
	pause()
	project = null
	music.stream = null
	workspace.visible = false
	home.visible = true
	_refresh_home()

func _next_uid() -> int:
	_uid += 1
	return _uid

# ------------------------------------------------------------------ workspace

func _build_workspace():
	workspace = Control.new()
	workspace.anchor_right = 1
	workspace.anchor_bottom = 1
	add_child(workspace)

	# the game, behind everything, full size (grid lands where SSQE's is)
	view3d = load("res://scripts/editor/EditorView3D.gd").new()
	view3d.page = self
	view3d.show_world = show_world
	view3d.hit_flash = hit_flash
	workspace.add_child(view3d)
	# grid overlay / 2D grid (input on the grid)
	grid = load("res://scripts/editor/EditorGrid.gd").new()
	grid.page = self
	grid.anchor_right = 1
	grid.anchor_bottom = 1
	workspace.add_child(grid)

	track = load("res://scripts/editor/EditorTrack.gd").new()
	track.page = self
	workspace.add_child(track)
	status_label = _label("", f_small, DIM)
	_put(status_label, "L", 6, 94, 420, 16)

	# ---- tabs
	var tl = [["OPTIONS", "options", 6], ["TIMING", "timing", 129], ["PATTERNS", "patterns", 252]]
	for t in tl:
		var b = _btn(t[0], "_set_tab", [t[1]])
		tab_buttons[t[1]] = b
		_put(b, "L", t[2], 114, 119, 34)
	zoom_label = _label("", f_val, LILAC)
	_put(zoom_label, "L", 376, 112, 140, 20)
	var tr = [["SNAPPING", "snapping", 909], ["GRAPHICS", "graphics", 1032], ["EXPORT", "export", 1156]]
	for t in tr:
		var b = _btn(t[0], "_set_tab", [t[1]])
		tab_buttons[t[1]] = b
		_put(b, "R", t[2], 114, 119, 34)
	copy_btn = _btn("COPY MAP DATA", "_on_copy_text")
	_put(copy_btn, "C", 539, 114, 202, 30)
	back_btn = _btn("BACK TO MENU", "close_project")
	_put(back_btn, "C", 539, 640, 202, 30, "B")

	_build_options()
	_build_timing()
	_build_patterns()
	_build_snapping()
	_build_graphics()
	_build_export()

	# ---- bottom
	_put(_btn("PLAYTEST", "playtest", [false]), "L", 6, 630, 240, 35, "B")
	var pfs = _btn("FROM START", "playtest", [true])
	pfs.hint_tooltip = "Playtest from the start of the map"
	_put(pfs, "L", 250, 630, 121, 35, "B")
	seekbar = load("res://scripts/editor/EditorSeek.gd").new()
	seekbar.page = self
	workspace.add_child(seekbar)
	play_btn = _btn("▶", "toggle_play")
	play_btn.add_stylebox_override("normal", StyleBoxEmpty.new())
	play_btn.add_stylebox_override("hover", StyleBoxEmpty.new())
	play_btn.add_stylebox_override("pressed", StyleBoxEmpty.new())
	play_btn.add_font_override("font", f_title)
	_put(play_btn, "R", 900, 680, 38, 38, "B")
	speed_slider = _slider("", 0, SPEEDS.size() - 1, 1, max(SPEEDS.find(speed), 0), "_on_speed")
	_put(speed_slider, "R", 960, 684, 298, 18, "B")
	speed_label = _label("", f_val, LILAC)
	speed_label.align = Label.ALIGN_CENTER
	_put(speed_label, "R", 960, 701, 298, 18, "B")
	_update_speed_label()
	# SFX / Music
	_put(_label("SFX", f_small, LILAC), "R", 1196, 520, 30, 14, "B")
	_put(_label("Music", f_small, LILAC), "R", 1232, 520, 40, 14, "B")
	var sfx = _slider("", 0, 1, 0.01, hit_vol, "_on_hit_vol")
	sfx.vertical = true
	_put(sfx, "R", 1196, 536, 24, 124, "B")
	var mus = _slider("", 0, 1, 0.01, music_vol, "_on_music_vol")
	mus.vertical = true
	_put(mus, "R", 1238, 536, 24, 124, "B")
	_set_tab(left_tab)
	_set_tab(right_tab)

func _build_options():
	var t = "options"
	var y = 155
	for it in [["Use Numpad", use_numpad, "_on_numpad"], ["Jump on Paste", jump_on_paste, "_on_jump_paste"],
			["Pause on Seek", pause_on_seek, "_on_pause_seek"], ["Hitsounds", hitsounds, "_on_hitsounds"]]:
		_put(_toggle(it[0], it[1], it[2]), "L", 6, y, 300, 20, "T", t)
		y += 26
	_put(_btn("KEYBINDS", "_show_keys"), "L", 6, y + 8, 135, 28, "T", t)

func _build_timing():
	var t = "timing"
	_put(_label("BPM:", f_val, LILAC), "L", 6, 160, 110, 18, "T", t)
	_put(_label("Offset:", f_val, LILAC), "L", 119, 160, 110, 18, "T", t)
	_put(_label("SFX Offset:", f_val, LILAC), "L", 232, 160, 110, 18, "T", t)
	f_bpm = _field("_on_bpm_text")
	_put(f_bpm, "L", 6, 180, 89, 28, "T", t)
	f_offset = _field("_on_offset_text")
	_put(f_offset, "L", 119, 180, 89, 28, "T", t)
	f_sfx = _field("_on_sfx_text")
	_put(f_sfx, "L", 232, 180, 89, 28, "T", t)
	_put(_btn("TAP BPM (T)", "tap"), "L", 6, 220, 142, 28, "T", t)
	var gb = _btn("GUESS BPM", "_on_guess_timing")
	gb.hint_tooltip = "Estimates BPM and offset from where the notes are (maps don't store BPM)"
	_put(gb, "L", 152, 220, 142, 28, "T", t)
	_put(_btn("SET OFFSET HERE", "_on_offset_here"), "L", 6, 254, 160, 28, "T", t)
	_put(_toggle("Metronome", metronome, "_on_metronome"), "L", 6, 292, 250, 20, "T", t)
	_put(_toggle("Scale Metronome With Divisor", metro_scale, "_on_metro_scale"), "L", 6, 318, 300, 20, "T", t)
	tap_label = _label("Tap along with T to find the BPM", f_small, DIM)
	_put(tap_label, "L", 6, 350, 330, 16, "T", t)
	_put(_btn("USE TAPPED BPM", "_tap_apply"), "L", 6, 370, 160, 28, "T", t)
	_put(_btn("RESET TAPS", "_tap_reset"), "L", 170, 370, 124, 28, "T", t)

# small up / down arrows next to a number field (SSQE's spin box)
func _arrows(field: LineEdit, stepv: float, minv: float, maxv: float) -> Control:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 0)
	for it in [["▲", stepv], ["▼", -stepv]]:
		var b = Button.new()
		b.text = it[0]
		b.flat = true
		b.focus_mode = FOCUS_NONE
		b.size_flags_vertical = SIZE_EXPAND_FILL
		b.add_font_override("font", f_small)
		b.add_color_override("font_color", LILAC)
		b.add_color_override("font_color_hover", ACCENT)
		b.connect("pressed", self, "_bump_field", [field, it[1], minv, maxv])
		v.add_child(b)
	return v

func _bump_field(field: LineEdit, d: float, minv: float, maxv: float):
	var v: float = float(field.text) if field.text.is_valid_float() else 0.0
	field.text = str(clamp(v + d, minv, maxv))

func _build_patterns():
	var t = "patterns"
	_put(_btn("HORIZONTAL FLIP", "flip_h"), "L", 6, 160, 119, 30, "T", t)
	_put(_btn("VERTICAL FLIP", "flip_v"), "L", 129, 160, 119, 30, "T", t)
	_put(_label("Rotate by Degrees:", f_val, LILAC), "L", 6, 204, 200, 18, "T", t)
	f_rot = _field("")
	f_rot.text = "90"
	_put(f_rot, "L", 6, 220, 58, 28, "T", t)
	_put(_arrows(f_rot, 15, -360, 360), "L", 64, 220, 12, 28, "T", t)
	_put(_btn("ROTATE", "_on_rotate"), "L", 79, 220, 69, 28, "T", t)
	_put(_label("Scale by Percent:", f_val, LILAC), "L", 6, 258, 200, 18, "T", t)
	f_scale = _field("")
	f_scale.text = "150"
	_put(f_scale, "L", 6, 274, 58, 28, "T", t)
	_put(_arrows(f_scale, 10, 1, 1000), "L", 64, 274, 12, 28, "T", t)
	_put(_btn("SCALE", "_on_scale"), "L", 79, 274, 69, 28, "T", t)
	var y = 316
	for it in [["Apply Rotate/Scale on Paste", apply_on_paste, "_on_apply_paste"],
			["Clamp Rotate/Scale in Bounds", clamp_bounds, "_on_clamp"],
			["Paste Reversed", paste_reversed, "_on_paste_reversed"],
			["Move Selected on Grid Key Pressed", move_on_key, "_on_move_key"]]:
		_put(_toggle(it[0], it[1], it[2]), "L", 6, y, 300, 20, "T", t)
		y += 26
	var sn = _btn("STORE NODES", "_on_store_nodes")
	sn.hint_tooltip = "Store the selected notes as bezier nodes"
	_put(sn, "L", 6, 434, 119, 28, "T", t)
	_put(_btn("CLEAR NODES", "_on_clear_nodes"), "L", 129, 434, 119, 28, "T", t)
	_put(_toggle("Curve Bezier", curve_bezier, "_on_curve"), "L", 6, 476, 200, 20, "T", t)
	_put(_label("Draw Bezier with Divisor:", f_val, LILAC), "L", 6, 504, 240, 18, "T", t)
	f_bez = _field("")
	f_bez.text = "4"
	_put(f_bez, "L", 6, 520, 58, 28, "T", t)
	_put(_arrows(f_bez, 1, 1, 32), "L", 64, 520, 12, 28, "T", t)
	var db = _btn("DRAW", "_on_draw_bezier")
	db.hint_tooltip = "Fill notes along the curve through the stored nodes"
	_put(db, "L", 79, 520, 69, 28, "T", t)

func _build_snapping():
	var t = "snapping"
	_put(_toggle("Quantum", quantum, "_on_quantum"), "R", 1072, 155, 200, 20, "T", t)
	_put(_toggle("Snap to Grid", snap_to_grid, "_on_snap"), "R", 1072, 181, 200, 20, "T", t)
	_put(_toggle("Auto-Advance", auto_advance, "_on_autoadvance"), "R", 1072, 207, 200, 20, "T", t)
	div_slider = _slider("Beat Divisor: %d", 1, 16, 1, divisor, "_on_divisor")
	_put(div_slider, "R", 1080, 236, 152, 40, "T", t)
	qdiv_slider = _slider("Quantum Divisor: %d", 2, 12, 1, quantum_divisor, "_on_qdiv")
	_put(qdiv_slider, "R", 1080, 283, 152, 40, "T", t)
	_put(_slider("Quantum X Offset: %.2f", -0.5, 0.5, 0.05, quantum_offset.x, "_on_qx"), "R", 1080, 330, 152, 40, "T", t)
	_put(_slider("Quantum Y Offset: %.2f", -0.5, 0.5, 0.05, quantum_offset.y, "_on_qy"), "R", 1080, 377, 152, 40, "T", t)

func _build_graphics():
	var t = "graphics"
	_put(_toggle("3D Mode", game_view, "_on_game_view"), "R", 909, 155, 160, 20, "T", t)
	_put(_toggle("3D Hit Effect", hit_flash, "_on_hit_flash"), "R", 909, 181, 160, 20, "T", t)
	_put(_toggle("Background World", show_world, "_on_world"), "R", 909, 207, 160, 20, "T", t)
	_put(_slider("3D Grid Opacity: %d%%", 0, 1, 0.05, overlay_opacity, "_on_overlay", 100.0), "R", 920, 236, 132, 40, "T", t)
	_put(_slider("Grid Zoom: %d%%", 0.6, 1.6, 0.05, grid_zoom, "_on_grid_zoom", 100.0), "R", 920, 283, 132, 40, "T", t)
	_put(_slider("Note Size: %d%%", 0.5, 1.2, 0.05, note_size_2d, "_on_note_size", 100.0), "R", 920, 330, 132, 40, "T", t)
	var y = 155
	for it in [["Autoplay", show_cursor, "_on_cursor"], ["Smooth Autoplay Cursor", smooth_cursor, "_on_smooth"],
			["Approach Squares", show_asq, "_on_asq"], ["Grid Numbers", show_numbers, "_on_numbers"],
			["Grid Letters", show_letters, "_on_letters"], ["Quantum Grid Lines", quantum_lines, "_on_qlines"]]:
		_put(_toggle(it[0], it[1], it[2]), "R", 1072, y, 200, 20, "T", t)
		y += 26
	var ar_start: float = ar_override if ar_override > 0 else float(Rhythia.get("approach_rate"))
	_put(_slider("Approach Rate: %d", 5, 150, 1, ar_start, "_on_ar"), "R", 1080, 320, 152, 40, "T", t)
	_put(_slider("Cursor Position: %d%%", 0.1, 0.9, 0.05, cursor_position, "_on_cursor_pos", 100.0), "R", 1080, 367, 152, 40, "T", t)

func _build_export():
	var t = "export"
	_put(_btn("CALCULATE SR", "_on_calc_sr"), "R", 909, 160, 142, 28, "T", t)
	sr_label = _label("", f_val, ACCENT)
	_put(sr_label, "R", 909, 194, 150, 18, "T", t)
	var sv = _btn("SAVE", "save_map")
	sv.hint_tooltip = "Save and put the map in your map list (Ctrl+S)"
	_put(sv, "R", 1092, 160, 69, 28, "T", t)
	var sa = _btn("SAVE AS", "_on_save_as")
	sa.hint_tooltip = "Save as a new map in your map list"
	_put(sa, "R", 1166, 160, 69, 28, "T", t)
	_put(_label("Title:", f_val, LILAC), "R", 1060, 200, 198, 16, "T", t)
	f_title_e = _text_field("Artist - Song", "_on_title")
	_put(f_title_e, "R", 1060, 217, 198, 26, "T", t)
	_put(_label("Mapper:", f_val, LILAC), "R", 1060, 248, 198, 16, "T", t)
	f_mapper = _text_field("Your name", "_on_mapper")
	_put(f_mapper, "R", 1060, 265, 198, 26, "T", t)
	_put(_label("Difficulty:", f_val, LILAC), "R", 1060, 296, 198, 16, "T", t)
	f_diff = OptionButton.new()
	f_diff.theme = load("res://uitheme.tres")
	f_diff.focus_mode = FOCUS_NONE
	for k in [-1, 0, 1, 2, 3, 4]:
		f_diff.add_item(String(Globals.difficulty_names.get(k, "?")), k + 1)
	f_diff.connect("item_selected", self, "_on_diff")
	_put(f_diff, "R", 1060, 313, 198, 26, "T", t)
	_put(_btn("COVER...", "_on_pick_cover"), "R", 1060, 346, 150, 28, "T", t)
	f_cover = TextureRect.new()
	f_cover.expand = true
	f_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_put(f_cover, "R", 1218, 342, 36, 36, "T", t)
	f_overwrite = _toggle("Save Over Original", false, "_on_overwrite")
	_put(f_overwrite, "R", 1060, 382, 198, 20, "T", t)
	_put(_btn("EXPORT .SSPM", "_on_export_file"), "R", 1060, 408, 198, 28, "T", t)
	_put(_btn("REPLACE SONG", "_on_replace_song"), "R", 1060, 440, 198, 28, "T", t)
	_put(_btn("PASTE MAP DATA", "_on_paste_text"), "R", 1060, 472, 198, 28, "T", t)

func _layout():
	if not _built or workspace == null:
		return
	_layout_home()
	var w := rect_size.x
	var h := rect_size.y
	var s: float = clamp(h / REF_H, 0.6, 2.5)
	if abs(s - _scale) > 0.001:
		_scale = s
		f_btn.size = int(round(13 * s))
		f_lbl.size = int(round(14 * s))
		f_val.size = int(round(14 * s))
		f_small.size = int(round(12 * s))
		f_title.size = int(round(22 * s))
		f_big.size = int(round(44 * s))
	for it in _items:
		var n: Control = it[0]
		var x := 0.0
		match it[1]:
			"L": x = SIDEBAR + it[2] * s
			"R": x = w - (REF_W - it[2]) * s
			_: x = w / 2 + (it[2] - REF_W / 2) * s
		var y: float = it[3] * s if it[6] == "T" else h - (REF_H - it[3]) * s
		n.rect_position = Vector2(round(x), round(y))
		n.rect_size = Vector2(round(it[4] * s), round(it[5] * s))
	# the game view fills the whole window; the track reaches the edges too
	view3d.rect_global_position = Vector2.ZERO
	view3d.rect_size = get_viewport_rect().size
	var gp: Vector2 = rect_global_position
	track.rect_position = Vector2(-min(gp.x, 4.0), -gp.y)
	track.rect_size = Vector2(w + min(gp.x, 4.0), round(92 * s) + gp.y)
	seekbar.rect_position = Vector2(round(SIDEBAR + 8 * s), round(h - 48 * s))
	seekbar.rect_size = Vector2(round(w - (REF_W - 875) * s - seekbar.rect_position.x), round(46 * s))
	# long labels (HORIZONTAL FLIP...) get the smaller font so they fit
	for it in _items:
		var b = it[0]
		if b is Button and not b.flat:
			var fits: bool = f_btn.get_string_size(b.text).x <= b.rect_size.x - 8
			b.add_font_override("font", f_btn if fits else f_small)
	# 2D view: inside SSQE's frame, above / below the grid, like SSQE
	if not game_view and copy_btn:
		copy_btn.rect_position = Vector2(round(w / 2 - 101 * s), round(181 * s))
		back_btn.rect_position = Vector2(round(w / 2 - 101 * s), round(515 * s))
	_redraw()

func _set_tab(name: String):
	if name in ["options", "timing", "patterns"]:
		left_tab = name
	else:
		right_tab = name
	for k in tab_buttons.keys():
		var on: bool = k == left_tab or k == right_tab
		var b: Button = tab_buttons[k]
		b.text = ("[%s]" % k.to_upper()) if on else k.to_upper()
	for it in _items:
		var tab: String = it[7]
		if tab != "":
			it[0].visible = tab == left_tab or tab == right_tab
	if f_overwrite and project != null:
		f_overwrite.visible = right_tab == "export" and project.can_overwrite_source()

func _show_keys():
	Globals.notify(Globals.NOTIFY_INFO, "Q W E / A S D / Z X C (or numpad): place · Space: play · Left/Right, wheel: step · Shift+wheel: divisor · Ctrl+wheel: zoom · Up/Down: next/prev note · Ctrl+Z/Y/C/X/V/A/S · Delete · H/V flip · R rotate · T tap · right-click a note: delete · right-drag the track: select", "Keybinds")

func _apply_view_mode():
	if view3d == null:
		return
	view3d.visible = game_view
	_layout()
	if game_view and project != null:
		view3d.build()
		view3d.set_world_visible(show_world)
	_redraw()

func _fill_fields():
	f_title_e.text = project.title
	f_mapper.text = project.mapper
	f_diff.select(max(f_diff.get_item_index(project.difficulty + 1), 0))
	f_bpm.text = str(project.bpm)
	f_offset.text = str(int(project.offset))
	f_sfx.text = str(int(sfx_offset))
	f_overwrite.visible = project.can_overwrite_source() and right_tab == "export"
	f_overwrite.pressed = project.overwrite_source
	sr_label.text = ""
	_load_cover_preview()

func _load_cover_preview():
	f_cover.texture = null
	if project.has_cover:
		var img = Image.new()
		if img.load(project.cover_path()) == OK:
			var t = ImageTexture.new()
			t.create_from_image(img)
			f_cover.texture = t

func _update_speed_label():
	speed_label.text = "PLAYBACK SPEED - %d%%" % int(round(speed * 100))

# ================================================================== field events

func _on_title(t: String):
	if project:
		project.title = t
		_mark_dirty()

func _on_mapper(t: String):
	if project:
		project.mapper = t
		_mark_dirty()

func _on_diff(i: int):
	if project:
		project.difficulty = f_diff.get_item_id(i) - 1
		_mark_dirty()

func _on_overwrite(on: bool):
	if project:
		project.overwrite_source = on
		_mark_dirty()

func _on_pick_cover():
	Globals.file_sel.open_file(self, "_on_cover_picked", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"]), false, "~/Pictures" if OS.has_feature("pc") else "user://")

func _on_cover_picked(files):
	var path := _first(files)
	if project == null or path == "":
		return
	if project.set_cover_from(path):
		_load_cover_preview()
		_mark_dirty()
	else:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't read that image.", "Cover")

func _on_bpm_text(t: String):
	if project and t.is_valid_float() and float(t) > 0:
		var v: float = clamp(float(t), 1, 2000)
		if v != project.bpm:
			project.bpm = v
			_mark_dirty()
			_redraw()
	if project:
		f_bpm.text = str(project.bpm)

func _on_offset_text(t: String):
	if project and t.is_valid_float():
		if float(t) != project.offset:
			project.offset = float(t)
			_mark_dirty()
			_redraw()
	if project:
		f_offset.text = str(int(project.offset))

func _on_sfx_text(t: String):
	if t.is_valid_float():
		sfx_offset = clamp(float(t), -500, 500)
		_save_settings()
	f_sfx.text = str(int(sfx_offset))

func _on_offset_here():
	if project:
		project.offset = round(time_ms)
		f_offset.text = str(int(project.offset))
		_mark_dirty()
		_redraw()

func _on_guess_timing():
	if project == null:
		return
	if project.guess_timing():
		f_bpm.text = str(project.bpm)
		f_offset.text = str(int(project.offset))
		_mark_dirty()
		_redraw()
		Globals.notify(Globals.NOTIFY_INFO, "About %s BPM, first beat at %d ms. Check it by playing with the metronome." % [str(project.bpm), int(project.offset)], "Timing guessed")
	else:
		Globals.notify(Globals.NOTIFY_WARN, "Not enough evenly spaced notes to guess from.", "Timing")

func tap():
	var now := OS.get_ticks_msec()
	if not _taps.empty() and now - _taps[-1] > 2000:
		_taps.clear()
	_taps.append(now)
	if _taps.size() > 32:
		_taps.pop_front()
	if _taps.size() >= 2:
		_tap_bpm = 60000.0 * (_taps.size() - 1) / float(_taps[-1] - _taps[0])
		tap_label.text = "Tapped: %.2f BPM (%d taps)" % [_tap_bpm, _taps.size()]
		tap_label.add_color_override("font_color", ACCENT)
	else:
		tap_label.text = "Keep tapping..."

func _tap_reset():
	_taps.clear()
	_tap_bpm = 0.0
	tap_label.text = "Tap along with T to find the BPM"
	tap_label.add_color_override("font_color", DIM)

func _tap_apply():
	if _tap_bpm > 0 and project:
		_on_bpm_text(str(stepify(_tap_bpm, 0.01)))

func _on_metronome(on: bool):
	metronome = on
	_save_settings()

func _on_metro_scale(on: bool):
	metro_scale = on
	_save_settings()

func _on_numpad(on: bool):
	use_numpad = on
	_save_settings()

func _on_jump_paste(on: bool):
	jump_on_paste = on
	_save_settings()

func _on_pause_seek(on: bool):
	pause_on_seek = on
	_save_settings()

func _on_move_key(on: bool):
	move_on_key = on
	_save_settings()

func _on_smooth(on: bool):
	smooth_cursor = on
	_save_settings()
	_redraw()

func _on_asq(on: bool):
	show_asq = on
	_save_settings()
	_redraw()

func _on_note_size(v: float):
	note_size_2d = v
	_save_settings()
	_redraw()

func _on_apply_paste(on: bool):
	apply_on_paste = on
	_save_settings()

func _on_paste_reversed(on: bool):
	paste_reversed = on
	_save_settings()

func _on_curve(on: bool):
	curve_bezier = on
	_save_settings()
	_redraw()

# ---- bezier (PATTERNS): STORE NODES keeps the selected notes as nodes, DRAW
# fills notes along the curve between the first and last node, one every
# beat / divisor. With Curve Bezier off it goes straight from node to node.
func _on_store_nodes():
	if project == null:
		return
	var nodes := []
	for n in project.notes:
		if _selected.has(n[3]):
			nodes.append([n[0], n[1], n[2], n[3]])
	if nodes.size() < 2:
		Globals.notify(Globals.NOTIFY_INFO, "Select at least 2 notes to use as nodes.", "Bezier")
		return
	bezier_nodes = nodes
	Globals.notify(Globals.NOTIFY_INFO, "Stored %d nodes. Set the divisor and press DRAW." % nodes.size(), "Bezier")
	_redraw()

func _on_clear_nodes():
	bezier_nodes = []
	_redraw()

# point on the path at u (0..1)
func bezier_point(u: float) -> Vector2:
	var pts := []
	for nd in bezier_nodes:
		pts.append(Vector2(nd[0], nd[1]))
	if pts.empty():
		return Vector2(1, 1)
	if not curve_bezier:
		# straight lines, timed like the nodes
		var t0: float = bezier_nodes[0][2]
		var t1: float = bezier_nodes[-1][2]
		var ms: float = t0 + (t1 - t0) * u
		for k in range(1, bezier_nodes.size()):
			if ms <= bezier_nodes[k][2] or k == bezier_nodes.size() - 1:
				var a = bezier_nodes[k - 1]
				var b = bezier_nodes[k]
				var span: float = max(b[2] - a[2], 0.001)
				return Vector2(a[0], a[1]).linear_interpolate(Vector2(b[0], b[1]), clamp((ms - a[2]) / span, 0, 1))
		return pts[-1]
	# de Casteljau over all nodes
	while pts.size() > 1:
		var nxt := []
		for k in range(pts.size() - 1):
			nxt.append(pts[k].linear_interpolate(pts[k + 1], u))
		pts = nxt
	return pts[0]

func _on_draw_bezier():
	if project == null:
		return
	if bezier_nodes.size() < 2:
		Globals.notify(Globals.NOTIFY_INFO, "STORE NODES first (select 2 or more notes).", "Bezier")
		return
	var div: int = int(clamp(int(float(f_bez.text)) if f_bez.text.is_valid_float() else 4, 1, 32))
	var t0: float = bezier_nodes[0][2]
	var t1: float = bezier_nodes[-1][2]
	if t1 - t0 < 1.0:
		return
	push_undo()
	# the middle nodes were only control points for the curve
	if curve_bezier and bezier_nodes.size() > 2:
		var gone := {}
		for k in range(1, bezier_nodes.size() - 1):
			gone[bezier_nodes[k][3]] = true
		var keep := []
		for n in project.notes:
			if not gone.has(n[3]):
				keep.append(n)
		project.notes = keep
	var step: float = project.beat_ms() / div
	_selected.clear()
	var t := t0 + step
	var guard := 0
	while t < t1 - 0.5 and guard < 5000:
		guard += 1
		var u := (t - t0) / (t1 - t0)
		var p := bezier_point(u)
		var n := [stepify(p.x, 0.0001), stepify(p.y, 0.0001), round(t), _next_uid()]
		project.notes.append(n)
		_selected[n[3]] = true
		t += step
	bezier_nodes = []
	notes_changed()

func _on_clamp(on: bool):
	clamp_bounds = on
	_save_settings()

func _on_divisor(v: float):
	divisor = int(v)
	_save_settings()
	_redraw()

func change_divisor(d: int):
	divisor = int(clamp(divisor + d, 1, 16))
	div_slider.value = divisor
	_save_settings()
	_redraw()

func _on_quantum(on: bool):
	quantum = on
	_save_settings()
	_redraw()

func _on_snap(on: bool):
	snap_to_grid = on
	_save_settings()

func _on_qdiv(v: float):
	quantum_divisor = int(v)
	_save_settings()
	_redraw()

func _on_qx(v: float):
	quantum_offset.x = v
	_save_settings()
	_redraw()

func _on_qy(v: float):
	quantum_offset.y = v
	_save_settings()
	_redraw()

func _on_autoadvance(on: bool):
	auto_advance = on
	_save_settings()

func _on_game_view(on: bool):
	game_view = on
	_apply_view_mode()
	_save_settings()

func _on_world(on: bool):
	show_world = on
	if view3d and project != null and game_view:
		view3d.build()
		view3d.set_world_visible(on)
	_save_settings()

func _on_hit_flash(on: bool):
	hit_flash = on
	if view3d:
		view3d.hit_flash = on
	_save_settings()

func _on_overlay(v: float):
	overlay_opacity = v
	_save_settings()
	_redraw()

func _on_grid_zoom(v: float):
	grid_zoom = v
	_save_settings()
	_redraw()

func _on_track_zoom(v: float):
	set_zoom(0.35 * v)

func _on_ar(v: float):
	ar_override = v
	approach_ms = float(Rhythia.get("spawn_distance")) / max(v, 1.0) * 1000.0
	_save_settings()
	_redraw()

func _on_cursor_pos(v: float):
	cursor_position = v
	_save_settings()
	_redraw()

func _on_letters(on: bool):
	show_letters = on
	_save_settings()
	_redraw()

func _on_numbers(on: bool):
	show_numbers = on
	_save_settings()
	_redraw()

func _on_qlines(on: bool):
	quantum_lines = on
	_save_settings()
	_redraw()

func _on_cursor(on: bool):
	show_cursor = on
	_save_settings()
	_redraw()

func _on_hitsounds(on: bool):
	hitsounds = on
	_save_settings()

func _on_music_vol(v: float):
	music_vol = v
	_apply_volumes()
	_save_settings()

func _on_hit_vol(v: float):
	hit_vol = v
	_apply_volumes()
	_save_settings()

func _on_speed(v: float):
	speed = SPEEDS[int(v)]
	if music:
		music.pitch_scale = speed
	_update_speed_label()
	_save_settings()

func _apply_volumes():
	if music:
		music.volume_db = linear2db(max(music_vol, 0.0001))
	for h in hit_players:
		h.volume_db = linear2db(max(hit_vol, 0.0001))
	if metro:
		metro.volume_db = linear2db(max(hit_vol, 0.0001))

func _on_calc_sr():
	var s = save_map()
	if s:
		var sr = s.get_star_rating()
		sr_label.text = ("%.2f ★" % sr) if typeof(sr) == TYPE_REAL and sr >= 0 else "—"

func _on_save_as():
	if project == null:
		return
	project.overwrite_source = false
	project.map_id = "chromia_editor_%s_%d" % [project.pid, OS.get_unix_time()]
	f_overwrite.pressed = false
	save_map()

func _on_export_file():
	if project == null:
		return
	if save_map() == null:
		return
	Globals.file_sel.save_file(self, "_on_export_path", PoolStringArray(["*.sspm ; Sound Space map"]), "~/Downloads" if OS.has_feature("pc") else "user://")

func _on_export_path(path):
	if not (path is String) or path == "":
		return
	if not path.ends_with(".sspm"):
		path += ".sspm"
	var d = Directory.new()
	if d.copy(Globals.p("user://maps/%s.sspm" % project.export_id()), path) == OK:
		Globals.notify(Globals.NOTIFY_SUCCEED, "Exported to " + path, "Map Editor")
	else:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't write the file.", "Map Editor")

func _on_replace_song():
	_pick_song("_on_new_audio")

func _on_new_audio(files):
	var path := _first(files)
	if path == "" or project == null:
		return
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return
	var bytes: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	var ext: String = EditorProject.audio_ext(bytes)
	if ext == "":
		Globals.notify(Globals.NOTIFY_WARN, "That song isn't an .mp3 or .ogg file.", "Replace song")
		return
	pause()
	var old: String = project.audio_path()
	if project._write_audio(bytes, ext):
		if old != project.audio_path():
			Directory.new().remove(old)
		_mark_dirty()
		var stream = Globals.audioLoader.load_file(project.audio_path())
		if stream is AudioStream:
			if "loop" in stream:
				stream.loop = false
			music.stream = stream
			song_length_ms = max(stream.get_length() * 1000.0, project.length_ms() + 2000.0)
		notes_changed(false)

# ================================================================== settings

func _load_settings():
	var f = File.new()
	if f.open(Globals.p(SETTINGS_PATH), File.READ) != OK:
		_sync_approach()
		return
	var p = JSON.parse(f.get_as_text())
	f.close()
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		_sync_approach()
		return
	var d: Dictionary = p.result
	divisor = int(clamp(int(d.get("divisor", divisor)), 1, 16))
	quantum = bool(d.get("quantum", quantum))
	quantum_divisor = int(clamp(int(d.get("quantum_divisor", quantum_divisor)), 2, 12))
	quantum_offset = Vector2(float(d.get("qx", 0)), float(d.get("qy", 0)))
	snap_to_grid = bool(d.get("snap_to_grid", snap_to_grid))
	auto_advance = bool(d.get("auto_advance", auto_advance))
	ar_override = float(d.get("ar_override", 0.0))
	show_letters = bool(d.get("show_letters", show_letters))
	show_numbers = bool(d.get("show_numbers", show_numbers))
	quantum_lines = bool(d.get("quantum_lines", quantum_lines))
	show_cursor = bool(d.get("show_cursor", show_cursor))
	game_view = bool(d.get("game_view", game_view))
	show_world = bool(d.get("show_world", show_world))
	hit_flash = bool(d.get("hit_flash", hit_flash))
	overlay_opacity = clamp(float(d.get("overlay_opacity", 1.0)), 0, 1)
	grid_zoom = clamp(float(d.get("grid_zoom", 1.0)), 0.6, 1.6)
	cursor_position = clamp(float(d.get("cursor_position", 0.4)), 0.1, 0.9)
	hitsounds = bool(d.get("hitsounds", hitsounds))
	metronome = bool(d.get("metronome", metronome))
	metro_scale = bool(d.get("metro_scale", metro_scale))
	sfx_offset = float(d.get("sfx_offset", 0.0))
	music_vol = clamp(float(d.get("music_vol", music_vol)), 0, 1)
	hit_vol = clamp(float(d.get("hit_vol", hit_vol)), 0, 1)
	speed = float(d.get("speed", speed))
	if not speed in SPEEDS:
		speed = 1.0
	zoom = clamp(float(d.get("zoom", zoom)), 0.03, 3.0)
	use_numpad = bool(d.get("use_numpad", use_numpad))
	jump_on_paste = bool(d.get("jump_on_paste", jump_on_paste))
	pause_on_seek = bool(d.get("pause_on_seek", pause_on_seek))
	clamp_bounds = bool(d.get("clamp_bounds", clamp_bounds))
	move_on_key = bool(d.get("move_on_key", move_on_key))
	smooth_cursor = bool(d.get("smooth_cursor", smooth_cursor))
	show_asq = bool(d.get("show_asq", show_asq))
	note_size_2d = clamp(float(d.get("note_size_2d", 1.0)), 0.5, 1.2)
	apply_on_paste = bool(d.get("apply_on_paste", apply_on_paste))
	paste_reversed = bool(d.get("paste_reversed", paste_reversed))
	curve_bezier = bool(d.get("curve_bezier", curve_bezier))
	_sync_approach()

func _sync_approach():
	approach_ms = float(Rhythia.get("spawn_distance")) / max(approach_rate_3d(), 1.0) * 1000.0

func _save_settings():
	var d = Directory.new()
	d.make_dir_recursive(EditorProject.root_dir())
	var f = File.new()
	if f.open(Globals.p(SETTINGS_PATH), File.WRITE) == OK:
		f.store_string(to_json({
			"divisor": divisor, "quantum": quantum, "quantum_divisor": quantum_divisor,
			"qx": quantum_offset.x, "qy": quantum_offset.y, "snap_to_grid": snap_to_grid,
			"auto_advance": auto_advance, "ar_override": ar_override, "show_letters": show_letters,
			"show_numbers": show_numbers, "quantum_lines": quantum_lines, "show_cursor": show_cursor,
			"game_view": game_view, "show_world": show_world, "hit_flash": hit_flash,
			"overlay_opacity": overlay_opacity, "grid_zoom": grid_zoom, "cursor_position": cursor_position,
			"hitsounds": hitsounds, "metronome": metronome, "metro_scale": metro_scale,
			"sfx_offset": sfx_offset, "music_vol": music_vol, "hit_vol": hit_vol, "speed": speed,
			"zoom": zoom, "use_numpad": use_numpad, "jump_on_paste": jump_on_paste,
			"pause_on_seek": pause_on_seek, "clamp_bounds": clamp_bounds, "move_on_key": move_on_key,
			"smooth_cursor": smooth_cursor, "show_asq": show_asq, "note_size_2d": note_size_2d,
			"apply_on_paste": apply_on_paste, "paste_reversed": paste_reversed, "curve_bezier": curve_bezier,
		}))
		f.close()

# ================================================================== time

func snap_now(ms: float) -> float:
	if project == null:
		return ms
	return project.snap(ms, divisor)

func seek(ms: float):
	time_ms = clamp(ms, 0.0, song_length_ms)
	_last_hit_ms = time_ms
	_last_beat = -1
	if playing and music.stream:
		music.play(time_ms / 1000.0)
	_redraw()

func step(dir: int):
	if project == null:
		return
	if playing:
		pause()
	seek(project.step_from(time_ms, divisor, dir))

func set_zoom(z: float):
	zoom = clamp(z, 0.03, 3.0)
	_save_settings()
	_redraw()

func toggle_play():
	if playing:
		pause()
	else:
		play()

func play():
	if project == null or music.stream == null:
		return
	if time_ms >= song_length_ms - 50:
		time_ms = 0.0
	playing = true
	for h in hit_players:
		if h.stream != Rhythia.hit_snd:
			h.stream = Rhythia.hit_snd
	music.pitch_scale = speed
	music.play(time_ms / 1000.0)
	_last_hit_ms = time_ms
	_last_beat = -1
	play_btn.text = "❚❚"
	set_process(true)

func pause():
	if not playing:
		return
	playing = false
	if music:
		music.stop()
	if play_btn:
		play_btn.text = "▶"
	time_ms = snap_now(time_ms)
	_redraw()

func _process(delta):
	if playing:
		var pos: float = music.get_playback_position() + AudioServer.get_time_since_last_mix() * speed
		var ms := pos * 1000.0
		if ms > time_ms or ms < time_ms - 300:
			time_ms = ms
		if not music.playing:
			playing = false
			play_btn.text = "▶"
			time_ms = min(time_ms, song_length_ms)
		_play_sounds()
		_redraw()
	if project != null and _dirty:
		_autosave_left -= delta
		if _autosave_left <= 0:
			_save_project_only()
	if not playing and not _dirty:
		set_process(false)

func _play_sounds():
	var notes: Array = project.notes
	var t := time_ms - sfx_offset
	if hitsounds and t > _last_hit_ms:
		var i: int = project.lower_bound(_last_hit_ms + 0.001)
		var played := 0
		var last_t := -1.0
		while i < notes.size() and notes[i][2] <= t:
			if notes[i][2] != last_t and played < 3:
				var h: AudioStreamPlayer = hit_players[_hit_next]
				_hit_next = (_hit_next + 1) % hit_players.size()
				h.play()
				played += 1
				last_t = notes[i][2]
			i += 1
	_last_hit_ms = max(t, _last_hit_ms)
	if metronome:
		var step_ms: float = project.beat_ms() / (max(divisor, 1) if metro_scale else 1)
		var beat := int(floor((time_ms - project.offset) / step_ms))
		if beat != _last_beat:
			if _last_beat != -1 and time_ms >= project.offset:
				metro.play()
			_last_beat = beat

func _redraw():
	if not _built or project == null:
		return
	track.update()
	grid.update()
	seekbar.update()
	if zoom_label:
		zoom_label.text = "Zoom: %d%%" % int(round(zoom / 0.35 * 100))

# ================================================================== notes

func note_color(idx: int) -> Color:
	var cs = Rhythia.selected_colorset
	if cs != null:
		var cols: Array = cs.colors
		if not cols.empty():
			var c = cols[idx % cols.size()]
			if c is Color:
				return c
	return LILAC

func is_selected(uid) -> bool:
	return _selected.has(uid)

func toggle_select(uid):
	if _selected.has(uid):
		_selected.erase(uid)
	else:
		_selected[uid] = true
	_redraw()
	_update_status()

func select_only(uids: Array):
	_selected.clear()
	for u in uids:
		_selected[u] = true
	_redraw()
	_update_status()

func select_all():
	if project == null:
		return
	_selected.clear()
	for n in project.notes:
		_selected[n[3]] = true
	_redraw()
	_update_status()

func deselect():
	_selected.clear()
	_redraw()
	_update_status()

func select_range(a: float, b: float, add: bool):
	if not add:
		_selected.clear()
	var i: int = project.lower_bound(a)
	while i < project.notes.size() and project.notes[i][2] <= b:
		_selected[project.notes[i][3]] = true
		i += 1
	_redraw()
	_update_status()

func uids_at_ms(ms: float) -> Array:
	var out := []
	var i: int = project.lower_bound(ms - 0.5)
	while i < project.notes.size() and project.notes[i][2] <= ms + 0.5:
		out.append(project.notes[i][3])
		i += 1
	return out

func _at_current() -> Array:
	var out := []
	if project == null:
		return out
	var i: int = project.lower_bound(time_ms - 1.0)
	while i < project.notes.size() and project.notes[i][2] <= time_ms + 1.0:
		out.append(project.notes[i])
		i += 1
	return out

func selected_uids_at_current() -> Array:
	var out := []
	for n in _at_current():
		if _selected.has(n[3]):
			out.append(n[3])
	return out

func note_at_current(gp: Vector2):
	var best = null
	var best_d := 0.55
	for n in _at_current():
		var d := Vector2(n[0], n[1]).distance_to(gp)
		if d < best_d:
			best = n
			best_d = d
	return best

func push_undo():
	var snap := []
	for n in project.notes:
		snap.append([n[0], n[1], n[2], n[3]])
	_undo.append(snap)
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()

func undo():
	if project == null or _undo.empty():
		return
	_redo.append(project.notes)
	project.notes = _undo.pop_back()
	notes_changed()

func redo():
	if project == null or _redo.empty():
		return
	_undo.append(project.notes)
	project.notes = _redo.pop_back()
	notes_changed()

func notes_changed(mark: bool = true):
	project.sort_notes()
	if not _selected.empty():
		var alive := {}
		for n in project.notes:
			if _selected.has(n[3]):
				alive[n[3]] = true
		_selected = alive
	if mark:
		_mark_dirty()
	if seekbar:
		seekbar.mark_dirty()
	_redraw()
	_update_status()

func _mark_dirty():
	_dirty = true
	_autosave_left = 30.0
	set_process(true)
	_update_status()

func _update_status():
	if project == null or status_label == null:
		return
	var s: String = project.title
	if not _selected.empty():
		s += "  ·  %d selected" % _selected.size()
	s += "  ·  " + ("unsaved changes" if _dirty else "saved")
	status_label.text = s

func place_note(pos: Vector2, toggle: bool = false):
	if project == null:
		return
	var t: float = snap_now(time_ms) if snap_to_grid else round(time_ms)
	if not playing:
		time_ms = t
	# Move Selected on Grid Key Pressed
	if toggle and move_on_key:
		var sel: Array = selected_uids_at_current()
		if not sel.empty():
			push_undo()
			for n in project.notes:
				if _selected.has(n[3]) and abs(n[2] - t) <= 1.0:
					n[0] = pos.x
					n[1] = pos.y
			notes_changed()
			return
	for n in _at_current():
		if abs(n[2] - t) <= 1.0 and Vector2(n[0], n[1]).distance_to(pos) < 0.01:
			if toggle:
				delete_uids([n[3]])
			return
	push_undo()
	var note := [pos.x, pos.y, t, _next_uid()]
	project.notes.append(note)
	if not playing:
		_selected.clear()
		_selected[note[3]] = true
	notes_changed()
	if auto_advance and not playing:
		step(1)

func delete_uids(uids: Array):
	if uids.empty():
		return
	push_undo()
	var gone := {}
	for u in uids:
		gone[u] = true
	var keep := []
	for n in project.notes:
		if not gone.has(n[3]):
			keep.append(n)
	project.notes = keep
	notes_changed()

func delete_selected():
	if project == null or _selected.empty():
		return
	delete_uids(_selected.keys())

func move_notes_by(uids: Array, delta: Vector2):
	var ids := {}
	for u in uids:
		ids[u] = true
	var lim := 2.5 if quantum else 2.0
	var lo := -0.5 if quantum else 0.0
	for n in project.notes:
		if ids.has(n[3]):
			n[0] = clamp(n[0] + delta.x, lo, lim)
			n[1] = clamp(n[1] + delta.y, lo, lim)
	_redraw()

func shift_selected_ms(delta: float):
	for n in project.notes:
		if _selected.has(n[3]):
			n[2] = max(0.0, n[2] + delta)
	project.sort_notes()
	_redraw()

func _need_selection() -> bool:
	if project == null:
		return false
	if _selected.empty():
		Globals.notify(Globals.NOTIFY_INFO, "Select notes first (click them, or right-drag on the track).", "Map Editor")
		return false
	return true

# rotate (degrees, clockwise) / scale (factor) / flip the selection around
# the grid's centre
func _transform_selected(kind: String, amount: float = 0.0):
	if not _need_selection():
		return
	push_undo()
	var ang := deg2rad(amount)
	for n in project.notes:
		if _selected.has(n[3]):
			var p := Vector2(n[0] - 1.0, n[1] - 1.0)
			match kind:
				"h": p.x = -p.x
				"v": p.y = -p.y
				"r": p = p.rotated(ang)
				"s": p *= amount
			var q := p + Vector2(1, 1)
			if clamp_bounds:
				var lim := 2.5 if quantum else 2.0
				var lo := -0.5 if quantum else 0.0
				q = Vector2(clamp(q.x, lo, lim), clamp(q.y, lo, lim))
			n[0] = stepify(q.x, 0.0001)
			n[1] = stepify(q.y, 0.0001)
	notes_changed()

# Apply Rotate/Scale on Paste: the rotate and scale fields, on the pasted notes
func _apply_paste_transform():
	var ang := deg2rad(float(f_rot.text)) if f_rot.text.is_valid_float() else 0.0
	var sc := float(f_scale.text) / 100.0 if f_scale.text.is_valid_float() else 1.0
	for n in project.notes:
		if _selected.has(n[3]):
			var q := Vector2(n[0] - 1.0, n[1] - 1.0).rotated(ang) * sc + Vector2(1, 1)
			if clamp_bounds:
				var lim := 2.5 if quantum else 2.0
				var lo := -0.5 if quantum else 0.0
				q = Vector2(clamp(q.x, lo, lim), clamp(q.y, lo, lim))
			n[0] = stepify(q.x, 0.0001)
			n[1] = stepify(q.y, 0.0001)

func flip_h():
	_transform_selected("h")

func flip_v():
	_transform_selected("v")

func rotate_cw():
	_transform_selected("r", 90.0)

func _on_rotate():
	if f_rot.text.is_valid_float():
		_transform_selected("r", float(f_rot.text))

func _on_scale():
	if f_scale.text.is_valid_float():
		_transform_selected("s", float(f_scale.text) / 100.0)

func nudge(dir: int):
	if not _need_selection():
		return
	push_undo()
	shift_selected_ms(dir * project.beat_ms() / max(divisor, 1))
	notes_changed()

func copy_selected() -> bool:
	if not _need_selection():
		return false
	var first := 1e18
	for n in project.notes:
		if _selected.has(n[3]):
			first = min(first, n[2])
	_clip = []
	for n in project.notes:
		if _selected.has(n[3]):
			_clip.append([n[0], n[1], n[2] - first])
	Globals.notify(Globals.NOTIFY_INFO, "Copied %d notes." % _clip.size(), "Map Editor")
	return true

func cut_selected():
	if copy_selected():
		delete_selected()

func paste_here():
	if project == null or _clip.empty():
		return
	push_undo()
	var t: float = snap_now(time_ms)
	_selected.clear()
	var last := t
	var span := 0.0
	for c in _clip:
		span = max(span, c[2])
	for c in _clip:
		var off: float = (span - c[2]) if paste_reversed else c[2]
		var n := [c[0], c[1], t + off, _next_uid()]
		project.notes.append(n)
		_selected[n[3]] = true
		last = max(last, n[2])
	if apply_on_paste:
		_apply_paste_transform()
	notes_changed()
	if jump_on_paste:
		seek(last)

func _on_clear_all():
	if project == null or project.notes.empty():
		return
	_ask("Remove all %d notes? (Ctrl+Z brings them back.)" % project.notes.size(), "_do_clear_all")

func _do_clear_all():
	push_undo()
	project.notes = []
	notes_changed()

func _on_copy_text():
	if project:
		OS.clipboard = project.to_text()
		Globals.notify(Globals.NOTIFY_INFO, "Map data copied (works in SSQE too).", "Map Editor")

func _on_paste_text():
	if project == null:
		return
	var notes = EditorProject.notes_from_text(OS.clipboard)
	if notes == null:
		Globals.notify(Globals.NOTIFY_WARN, "Copy Sound Space map data first (\"id,x|y|ms,...\").", "Nothing to paste")
		return
	push_undo()
	for n in notes:
		n.append(_next_uid())
	project.notes = notes
	notes_changed()
	Globals.notify(Globals.NOTIFY_INFO, "Pasted %d notes (Ctrl+Z to undo)." % notes.size(), "Map Editor")

func cursor_pos():
	if project == null:
		return null
	var notes: Array = project.notes
	if notes.empty():
		return null
	var i: int = project.lower_bound(time_ms)
	if i <= 0:
		return Vector2(notes[0][0], notes[0][1])
	if i >= notes.size():
		return Vector2(notes[-1][0], notes[-1][1])
	var a = notes[i - 1]
	var b = notes[i]
	var span: float = max(b[2] - a[2], 1.0)
	var t: float = clamp((time_ms - a[2]) / span, 0.0, 1.0)
	if smooth_cursor:
		t = t * t * (3.0 - 2.0 * t)
	else:
		t = 0.0 if t < 1.0 else 1.0 # jumps from note to note
	return Vector2(a[0], a[1]).linear_interpolate(Vector2(b[0], b[1]), t)

func _jump_note(dir: int):
	var notes: Array = project.notes
	if notes.empty():
		return
	pause()
	if dir > 0:
		var i: int = project.lower_bound(time_ms + 1.0)
		if i < notes.size():
			seek(notes[i][2])
	else:
		var i: int = project.lower_bound(time_ms - 1.0) - 1
		if i >= 0:
			seek(notes[i][2])

# ================================================================== saving / playtest

func _save_project_only():
	if project == null:
		return
	if project.save():
		_dirty = false
		_autosave_left = 30.0
	_update_status()

func save_map():
	if project == null:
		return null
	_save_project_only()
	var res = project.export_to_maps()
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Map Editor")
		return null
	var list = get_node_or_null("../Maps/MapRegistry/S/VBoxContainer")
	if list != null and list.has_method("refresh_songs"):
		list.refresh_songs()
	Globals.notify(Globals.NOTIFY_SUCCEED, "Saved to your map list.", project.title)
	return res

func playtest(from_start: bool):
	if project == null:
		return
	pause()
	var song = save_map()
	if song == null:
		return
	get_tree().root.set_meta(RETURN_META, {
		"pid": project.pid, "time": time_ms, "prev_start_offset": Rhythia.start_offset,
	})
	Rhythia.select_song(song)
	Rhythia.start_offset = 0.0 if from_start else max(0.0, time_ms - 1000.0)
	Rhythia.replaying = false
	var menu = get_tree().root.get_node_or_null("Menu")
	if menu:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

# ================================================================== keys

func _input(ev):
	if project == null or not workspace.visible or not is_visible_in_tree():
		return
	if not (ev is InputEventKey) or not ev.pressed:
		return
	if _typing():
		if ev.scancode == KEY_ESCAPE:
			get_focus_owner().release_focus()
		return
	if Globals.file_sel and Globals.file_sel.visible:
		return
	var handled := true
	var k: int = ev.scancode
	if ev.control:
		match k:
			KEY_Z:
				if ev.shift: redo()
				else: undo()
			KEY_Y: redo()
			KEY_C: copy_selected()
			KEY_X: cut_selected()
			KEY_V: paste_here()
			KEY_A: select_all()
			KEY_S: save_map()
			_: handled = false
	elif GRID_KEYS.has(k) and not ev.echo:
		place_note(GRID_KEYS[k], true)
	elif use_numpad and NUMPAD_KEYS.has(k) and not ev.echo:
		place_note(NUMPAD_KEYS[k], true)
	else:
		match k:
			KEY_SPACE:
				if not ev.echo: toggle_play()
			KEY_LEFT: step(-1)
			KEY_RIGHT: step(1)
			KEY_UP: _jump_note(1)
			KEY_DOWN: _jump_note(-1)
			KEY_HOME:
				pause()
				seek(0)
			KEY_END:
				pause()
				seek(project.length_ms())
			KEY_DELETE, KEY_BACKSPACE: delete_selected()
			KEY_H: flip_h()
			KEY_V: flip_v()
			KEY_R: rotate_cw()
			KEY_T:
				if not ev.echo: tap()
			_: handled = false
	if handled:
		get_tree().set_input_as_handled()
