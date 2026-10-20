extends ReferenceRect
# "Map Editor" sidebar page: an in-game map editor built after Sound Space
# Quantum Editor (github.com/iloverhythia/Sound-Space-Quantum-Editor-Plus).
#
# Home: your editor projects, "New map" (pick a song), "Edit selected map",
# "Paste map data" (SSQE text). Workspace: track on top, the 3x3 grid in the
# middle (EditorGrid.gd), Map / Timing / Edit tools on the left, snapping and
# sound on the right, seek bar at the bottom. "Save" writes the map into your
# map list; "Playtest" plays it in the real game and comes back here.
#
# Keys (when no text box is focused):
#   Q W E / A S D / Z X C  place (or remove) a note at the current time
#   Space play / pause      Left / Right or wheel  move one snap step
#   Up / Down  next / previous note   Home / End  start / end
#   Ctrl+Z / Ctrl+Y undo / redo     Ctrl+C / X / V copy / cut / paste
#   Ctrl+A select all   Delete remove selected   Ctrl+S save
#   H / V flip selected   R rotate selected   T tap BPM

const EditorProject = preload("res://scripts/editor/EditorProject.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const PANEL_BG = Color(0.07, 0.065, 0.09, 0.88)
const BTN_BG = Color(0.1, 0.095, 0.125, 1)
const BTN_HOVER = Color(0.14, 0.13, 0.18, 1)
const BTN_SEL = Color(0.2, 0.17, 0.25, 1)
const DIVISORS = [1, 2, 3, 4, 5, 6, 8, 12, 16]
const SPEEDS = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
const SETTINGS_PATH = "user://editor/settings.json"
const RETURN_META = "chromia_editor_return"
const MAX_UNDO = 200
const GRID_KEYS = {KEY_Q: Vector2(0, 0), KEY_W: Vector2(1, 0), KEY_E: Vector2(2, 0),
	KEY_A: Vector2(0, 1), KEY_S: Vector2(1, 1), KEY_D: Vector2(2, 1),
	KEY_Z: Vector2(0, 2), KEY_X: Vector2(1, 2), KEY_C: Vector2(2, 2)}

# ---- state used by the grid / track / seek bar
var project = null
var time_ms := 0.0
var playing := false
var song_length_ms := 1.0
var divisor := 4
var quantum := false
var quantum_divisor := 3
var auto_advance := false
var approach_ms := 700.0
var show_letters := true
var show_cursor := true
var hitsounds := true
var metronome := false
var music_vol := 0.8
var hit_vol := 0.6
var speed := 1.0
var zoom := 0.35 # px per ms on the track

var _selected: Dictionary = {} # uid -> true
var _uid := 0
var _undo: Array = []
var _redo: Array = []
var _clip: Array = [] # [x, y, ms from the first]
var _dirty := false
var _autosave_left := 30.0
var _last_hit_ms := 0.0
var _last_beat := -1
var _taps: Array = []
var _tap_bpm := 0.0

# ---- nodes
var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var home: Control
var projects_box: GridContainer
var edit_selected_btn: Button
var workspace: Control
var title_label: Label
var status_label: Label
var track
var grid
var seekbar
var time_label: Label
var length_label: Label
var count_label: Label
var play_btn: Button
var tab_buttons: Array = []
var tab_pages: Array = []
var f_title: LineEdit
var f_mapper: LineEdit
var f_diff: OptionButton
var f_overwrite: CheckBox
var f_cover: TextureRect
var f_bpm: SpinBox
var f_offset: SpinBox
var tap_label: Label
var div_label: Label
var div_slider: HSlider
var qdiv_row: Control
var qdiv_label: Label
var qdiv_slider: HSlider
var music: AudioStreamPlayer
var hit_players: Array = []
var _hit_next := 0
var metro: AudioStreamPlayer
var _paused_menu_players: Array = []
var _built := false

# ================================================================== helpers

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

func _pad(sb: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb

func _label(text: String, font: Font = null, color: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", font if font else font_regular)
	l.add_color_override("font_color", color)
	return l

func _button(text: String, method: String, args: Array = [], toggle: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.toggle_mode = toggle
	b.add_font_override("font", font_bold)
	b.add_color_override("font_color", DIM if toggle else TEXT)
	b.add_color_override("font_color_hover", TEXT)
	b.add_color_override("font_color_pressed", TEXT)
	b.add_color_override("font_color_disabled", Color(0.45, 0.44, 0.5))
	b.add_stylebox_override("normal", _pad(_flat(BTN_BG, 8), 12, 6))
	b.add_stylebox_override("hover", _pad(_flat(BTN_HOVER, 8), 12, 6))
	b.add_stylebox_override("pressed", _pad(_flat(BTN_SEL, 8, LILAC, 1), 12, 6))
	b.add_stylebox_override("disabled", _pad(_flat(Color(0.09, 0.085, 0.11, 1), 8), 12, 6))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.rect_min_size = Vector2(0, 34)
	if method != "":
		b.connect("pressed", self, method, args)
	return b

func _accent_button(text: String, method: String, args: Array = []) -> Button:
	var b = _button(text, method, args)
	b.add_stylebox_override("normal", _pad(_flat(Color(0.2, 0.17, 0.25, 1), 8, Color(LILAC.r, LILAC.g, LILAC.b, 0.5), 1), 12, 6))
	b.add_stylebox_override("hover", _pad(_flat(Color(0.27, 0.22, 0.33, 1), 8, LILAC, 1), 12, 6))
	return b

func _line_edit(placeholder: String, method: String) -> LineEdit:
	var e = LineEdit.new()
	e.placeholder_text = placeholder
	e.rect_min_size = Vector2(0, 34)
	e.add_font_override("font", font_regular)
	e.add_color_override("font_color", TEXT)
	e.add_stylebox_override("normal", _pad(_flat(Color(0.13, 0.125, 0.165, 1), 8), 10, 4))
	e.add_stylebox_override("focus", _pad(_flat(Color(0.13, 0.125, 0.165, 1), 8, LILAC, 1), 10, 4))
	e.connect("text_changed", self, method)
	return e

func _check(text: String, on: bool, method: String) -> CheckBox:
	var c = CheckBox.new()
	c.text = text
	c.pressed = on
	c.focus_mode = FOCUS_NONE
	c.theme = load("res://uitheme.tres")
	c.add_font_override("font", font_regular)
	c.add_color_override("font_color", TEXT)
	c.add_color_override("font_color_hover", TEXT)
	c.add_color_override("font_color_pressed", TEXT)
	c.connect("toggled", self, method)
	return c

# [row, value label, slider]
func _slider_row(text: String, minv: float, maxv: float, stepv: float, value: float, method: String) -> Array:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 2)
	var l = _label(text, font_bold)
	v.add_child(l)
	var s = HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = stepv
	s.value = value
	s.focus_mode = FOCUS_NONE
	s.theme = load("res://uitheme.tres")
	s.rect_min_size = Vector2(0, 22)
	s.connect("value_changed", self, method)
	v.add_child(s)
	return [v, l, s]

func _spin(minv: float, maxv: float, stepv: float, value: float, method: String) -> SpinBox:
	var s = SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = stepv
	s.value = value
	s.theme = load("res://uitheme.tres")
	s.rect_min_size = Vector2(0, 32)
	s.connect("value_changed", self, method)
	return s

func _section(title: String) -> Label:
	var l = _label(title, font_bold, ACCENT)
	return l

static func fmt_time(ms: float) -> String:
	var neg := ms < 0
	var t := int(abs(ms))
	var s := "%d:%02d.%03d" % [t / 60000, (t / 1000) % 60, t % 1000]
	return ("-" + s) if neg else s

func _typing() -> bool:
	var f = get_focus_owner()
	return f is LineEdit or f is TextEdit

# ================================================================== build

func _ready():
	connect("visibility_changed", self, "_on_visibility")
	set_process(false)
	# coming back from a playtest
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
	if open_project(String(info.get("pid", ""))):
		seek(float(info.get("time", 0.0)))

func _on_visibility():
	if is_visible_in_tree():
		_ensure_built()
		_refresh_home()
		_pause_menu_music(true)
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
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	font_small = _font("res://assets/font/Lato/Lato-Bold.ttf", 12)
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

func _build_home():
	home = MarginContainer.new()
	home.anchor_right = 1
	home.anchor_bottom = 1
	home.add_constant_override("margin_left", 76)
	home.add_constant_override("margin_right", 24)
	home.add_constant_override("margin_top", 20)
	home.add_constant_override("margin_bottom", 56)
	add_child(home)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 14)
	home.add_child(v)
	v.add_child(_label("Map Editor", font_title))
	v.add_child(_label("Make and edit maps right in the game. Based on Sound Space Quantum Editor: same grid, keys and quantum placement.", font_regular, DIM))

	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	v.add_child(row)
	var nb = _accent_button("+  New map from a song", "_on_new_map")
	nb.rect_min_size = Vector2(230, 42)
	row.add_child(nb)
	edit_selected_btn = _button("Edit selected map", "_on_edit_selected")
	edit_selected_btn.rect_min_size = Vector2(0, 42)
	edit_selected_btn.clip_text = true
	edit_selected_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(edit_selected_btn)
	var pb = _button("Paste map data", "_on_paste_new")
	pb.hint_tooltip = "Make a map from Sound Space / SSQE map data on your clipboard (\"id,x|y|ms,...\")"
	pb.rect_min_size = Vector2(170, 42)
	row.add_child(pb)

	var panel = PanelContainer.new()
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_stylebox_override("panel", _pad(_flat(PANEL_BG, 10, Color(1, 1, 1, 0.06), 1), 14, 12))
	v.add_child(panel)
	var pv = VBoxContainer.new()
	pv.add_constant_override("separation", 10)
	panel.add_child(pv)
	pv.add_child(_label("Your editor maps", font_bold, ACCENT))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	pv.add_child(sc)
	projects_box = GridContainer.new()
	projects_box.columns = 2
	projects_box.size_flags_horizontal = SIZE_EXPAND_FILL
	projects_box.add_constant_override("hseparation", 12)
	projects_box.add_constant_override("vseparation", 12)
	sc.add_child(projects_box)
	sc.connect("resized", self, "_relayout_projects", [sc])

func _relayout_projects(sc: ScrollContainer):
	projects_box.columns = int(max(1, floor((sc.rect_size.x + 12) / 420)))

func _refresh_home():
	if not _built:
		return
	var s = Rhythia.selected_song
	if s is Song:
		edit_selected_btn.text = "Edit selected map:  " + String(s.name)
		edit_selected_btn.disabled = false
	else:
		edit_selected_btn.text = "Edit selected map (pick one in the map list first)"
		edit_selected_btn.disabled = true
	for c in projects_box.get_children():
		c.queue_free()
	var list: Array = EditorProject.list_projects()
	if list.empty():
		projects_box.add_child(_label("No editor maps yet. Start with \"New map from a song\" or edit a map from your list.", font_regular, DIM))
		return
	for p in list:
		projects_box.add_child(_project_card(p))

func _project_card(p: Dictionary) -> Control:
	var card = PanelContainer.new()
	card.add_stylebox_override("panel", _pad(_flat(Color(0.11, 0.105, 0.14, 1), 10, Color(1, 1, 1, 0.07), 1), 12, 10))
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 12)
	card.add_child(h)
	var cov = TextureRect.new()
	cov.rect_min_size = Vector2(64, 64)
	cov.expand = true
	cov.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if p.has_cover:
		var img = Image.new()
		if img.load(EditorProject.root_dir().plus_file(p.pid).plus_file("cover.png")) == OK:
			if img.get_width() > 128:
				img.resize(128, int(128.0 * img.get_height() / max(img.get_width(), 1)))
			var t = ImageTexture.new()
			t.create_from_image(img)
			cov.texture = t
	h.add_child(cov)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 2)
	h.add_child(v)
	var t1 = _label(p.title, font_bold)
	t1.clip_text = true
	v.add_child(t1)
	var when := ""
	if p.modified > 0:
		var dt = OS.get_datetime_from_unix_time(p.modified)
		when = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	v.add_child(_label("%s%d notes · edited %s" % [("by " + p.mapper + " · ") if p.mapper != "" else "", p.notes, when], font_small, DIM))
	var bh = HBoxContainer.new()
	bh.add_constant_override("separation", 6)
	v.add_child(bh)
	var ob = _accent_button("Open", "open_project", [p.pid])
	ob.rect_min_size = Vector2(90, 30)
	bh.add_child(ob)
	var db = _button("Delete", "_on_delete_project", [p.pid, p.title])
	db.rect_min_size = Vector2(80, 30)
	bh.add_child(db)
	return card

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

func _on_new_map():
	Globals.file_sel.open_file(self, "_on_new_song_picked", PoolStringArray(["*.mp3, *.ogg ; Songs (mp3, ogg)"]), false, "~/Downloads" if OS.has_feature("pc") else "user://")

func _on_new_song_picked(files):
	var path := ""
	if files is PoolStringArray and files.size() > 0:
		path = files[0]
	elif files is String:
		path = files
	if path == "":
		return
	var res = EditorProject.create(path, path.get_file().get_basename(), "")
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Map Editor")
		return
	_open(res)
	_select_tab(0)
	Globals.notify(Globals.NOTIFY_INFO, "Set the BPM and offset in Timing, then place notes with Q W E / A S D / Z X C or the mouse.", "New map")

var _pending_paste: Array = []
func _on_paste_new():
	var notes = EditorProject.notes_from_text(OS.clipboard)
	if notes == null:
		Globals.notify(Globals.NOTIFY_WARN, "Copy Sound Space map data first (\"id,x|y|ms,...\").", "Nothing to paste")
		return
	_pending_paste = notes
	Globals.notify(Globals.NOTIFY_INFO, "%d notes found. Now pick the song for them." % notes.size(), "Paste map data")
	Globals.file_sel.open_file(self, "_on_paste_song_picked", PoolStringArray(["*.mp3, *.ogg ; Songs (mp3, ogg)"]), false, "~/Downloads" if OS.has_feature("pc") else "user://")

func _on_paste_song_picked(files):
	var path := ""
	if files is PoolStringArray and files.size() > 0:
		path = files[0]
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

# Opens a map from the map list in the editor (also used by the map screen's
# "Edit" button).
func edit_song(s):
	_ensure_built()
	if s == null:
		return
	var res = EditorProject.from_song(s)
	if res is String:
		Globals.notify(Globals.NOTIFY_WARN, res, "Can't edit this map")
		return
	_open(res)
	Globals.notify(Globals.NOTIFY_INFO, "Timing guessed from the notes: %s BPM (check it in Timing). Saving makes a new copy; to save over the original, tick it in the Map tab." % str(res.bpm), "Editing " + String(s.name))

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
	notes_changed(false)
	_update_status()

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
	workspace = MarginContainer.new()
	workspace.anchor_right = 1
	workspace.anchor_bottom = 1
	workspace.add_constant_override("margin_left", 70)
	workspace.add_constant_override("margin_right", 10)
	workspace.add_constant_override("margin_top", 8)
	workspace.add_constant_override("margin_bottom", 8)
	add_child(workspace)
	var root = VBoxContainer.new()
	root.add_constant_override("separation", 8)
	workspace.add_child(root)

	# header
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 8)
	root.add_child(head)
	head.add_child(_button("‹  Maps", "close_project"))
	title_label = _label("", font_bold)
	title_label.clip_text = true
	title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	title_label.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(title_label)
	status_label = _label("", font_small, DIM)
	status_label.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(status_label)
	var sv = _accent_button("Save", "save_map")
	sv.hint_tooltip = "Save and put the map in your map list (Ctrl+S)"
	head.add_child(sv)
	var pt = _accent_button("▶  Playtest here", "playtest", [false])
	pt.hint_tooltip = "Play the map in the game from the current time"
	head.add_child(pt)
	head.add_child(_button("Playtest from start", "playtest", [true]))

	# track
	track = load("res://scripts/editor/EditorTrack.gd").new()
	track.page = self
	track.rect_min_size = Vector2(0, 92)
	root.add_child(track)

	# middle
	var mid = HBoxContainer.new()
	mid.size_flags_vertical = SIZE_EXPAND_FILL
	mid.add_constant_override("separation", 10)
	root.add_child(mid)
	mid.add_child(_build_left_panel())
	grid = load("res://scripts/editor/EditorGrid.gd").new()
	grid.page = self
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	mid.add_child(grid)
	mid.add_child(_build_right_panel())

	# bottom
	var bot = PanelContainer.new()
	bot.add_stylebox_override("panel", _pad(_flat(PANEL_BG, 10), 10, 6))
	root.add_child(bot)
	var bh = HBoxContainer.new()
	bh.add_constant_override("separation", 10)
	bot.add_child(bh)
	play_btn = _accent_button("▶", "toggle_play")
	play_btn.rect_min_size = Vector2(48, 34)
	bh.add_child(play_btn)
	time_label = _label("0:00.000", font_bold)
	time_label.rect_min_size = Vector2(86, 0)
	time_label.size_flags_vertical = SIZE_SHRINK_CENTER
	bh.add_child(time_label)
	seekbar = load("res://scripts/editor/EditorSeek.gd").new()
	seekbar.page = self
	seekbar.size_flags_horizontal = SIZE_EXPAND_FILL
	seekbar.rect_min_size = Vector2(0, 34)
	bh.add_child(seekbar)
	length_label = _label("", font_regular, DIM)
	length_label.size_flags_vertical = SIZE_SHRINK_CENTER
	bh.add_child(length_label)
	count_label = _label("", font_bold, ACCENT)
	count_label.size_flags_vertical = SIZE_SHRINK_CENTER
	count_label.rect_min_size = Vector2(96, 0)
	count_label.align = Label.ALIGN_RIGHT
	bh.add_child(count_label)

func _panel(width: float) -> Array:
	var p = PanelContainer.new()
	p.rect_min_size = Vector2(width, 0)
	p.add_stylebox_override("panel", _pad(_flat(PANEL_BG, 10, Color(1, 1, 1, 0.06), 1), 12, 10))
	var sc = ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	p.add_child(sc)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 8)
	sc.add_child(v)
	return [p, v]

func _build_left_panel() -> Control:
	var pv = _panel(290)
	var v: VBoxContainer = pv[1]
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 4)
	v.add_child(tabs)
	var names = ["Map", "Timing", "Edit"]
	for i in range(names.size()):
		var b = _button(names[i], "_select_tab", [i], true)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		tabs.add_child(b)
		tab_buttons.append(b)
		var page = VBoxContainer.new()
		page.add_constant_override("separation", 8)
		v.add_child(page)
		tab_pages.append(page)

	# --- Map
	var m: VBoxContainer = tab_pages[0]
	m.add_child(_label("Title", font_bold))
	f_title = _line_edit("Artist - Song", "_on_title")
	m.add_child(f_title)
	m.add_child(_label("Mapper", font_bold))
	f_mapper = _line_edit("Your name", "_on_mapper")
	m.add_child(f_mapper)
	m.add_child(_label("Difficulty", font_bold))
	f_diff = OptionButton.new()
	f_diff.theme = load("res://uitheme.tres")
	for k in [-1, 0, 1, 2, 3, 4]:
		f_diff.add_item(String(Globals.difficulty_names.get(k, "?")), k + 1)
	f_diff.connect("item_selected", self, "_on_diff")
	m.add_child(f_diff)
	var ch = HBoxContainer.new()
	ch.add_constant_override("separation", 8)
	m.add_child(ch)
	f_cover = TextureRect.new()
	f_cover.rect_min_size = Vector2(56, 56)
	f_cover.expand = true
	f_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ch.add_child(f_cover)
	var cb = _button("Choose cover...", "_on_pick_cover")
	cb.size_flags_horizontal = SIZE_EXPAND_FILL
	cb.size_flags_vertical = SIZE_SHRINK_CENTER
	ch.add_child(cb)
	f_overwrite = _check("Save over the original map", false, "_on_overwrite")
	f_overwrite.hint_tooltip = "Off: saving makes a new copy in your map list"
	m.add_child(f_overwrite)
	m.add_child(HSeparator.new())
	m.add_child(_button("Copy map data", "_on_copy_text"))
	var pm = _button("Paste map data", "_on_paste_text")
	pm.hint_tooltip = "Replace the notes with Sound Space / SSQE map data from the clipboard"
	m.add_child(pm)

	# --- Timing
	var t: VBoxContainer = tab_pages[1]
	t.add_child(_label("BPM", font_bold))
	f_bpm = _spin(1, 2000, 0.001, 120, "_on_bpm")
	t.add_child(f_bpm)
	t.add_child(_label("Offset (ms of the first beat)", font_bold))
	f_offset = _spin(-10000, 600000, 1, 0, "_on_offset")
	t.add_child(f_offset)
	t.add_child(_button("Set offset to current time", "_on_offset_here"))
	var gt = _button("Guess timing from notes", "_on_guess_timing")
	gt.hint_tooltip = "Estimates BPM and offset from where the notes are (maps don't store BPM)"
	t.add_child(gt)
	t.add_child(HSeparator.new())
	t.add_child(_section("BPM tapper"))
	t.add_child(_label("Play the song and tap along (button or T key).", font_small, DIM))
	var th = HBoxContainer.new()
	th.add_constant_override("separation", 6)
	t.add_child(th)
	var tb = _accent_button("Tap", "tap")
	tb.size_flags_horizontal = SIZE_EXPAND_FILL
	th.add_child(tb)
	th.add_child(_button("Reset", "_tap_reset"))
	tap_label = _label("—", font_bold, ACCENT)
	t.add_child(tap_label)
	t.add_child(_button("Use tapped BPM", "_tap_apply"))
	t.add_child(HSeparator.new())
	t.add_child(_check("Metronome", metronome, "_on_metronome"))

	# --- Edit
	var e: VBoxContainer = tab_pages[2]
	e.add_child(_label("Selected notes", font_bold, ACCENT))
	var grid2 = GridContainer.new()
	grid2.columns = 2
	grid2.add_constant_override("hseparation", 6)
	grid2.add_constant_override("vseparation", 6)
	e.add_child(grid2)
	for it in [["Select all", "select_all"], ["Deselect", "deselect"], ["Flip ↔ (H)", "flip_h"], ["Flip ↕ (V)", "flip_v"],
			["Rotate ↻ (R)", "rotate_cw"], ["Delete", "delete_selected"], ["‹ Earlier", "nudge", -1], ["Later ›", "nudge", 1],
			["Copy", "copy_selected"], ["Paste here", "paste_here"]]:
		var b = _button(it[0], it[1], [it[2]] if it.size() > 2 else [])
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		grid2.add_child(b)
	e.add_child(HSeparator.new())
	e.add_child(_button("Undo (Ctrl+Z)", "undo"))
	e.add_child(_button("Redo (Ctrl+Y)", "redo"))
	e.add_child(HSeparator.new())
	var clr = _button("Clear all notes", "_on_clear_all")
	e.add_child(clr)
	e.add_child(HSeparator.new())
	e.add_child(_label("Keys", font_bold, ACCENT))
	var keys = _label("Q W E / A S D / Z X C: place a note\nSpace: play / pause\nLeft / Right, wheel: move one step\nShift+wheel: beat divisor, Ctrl+wheel: zoom\nUp / Down: next / previous note\nCtrl+Z / Y, C / X / V, A, S\nDelete: remove selected\nH / V flip, R rotate, T tap\nRight-click a note: delete it\nRight-drag on the track: select", font_small, DIM)
	keys.autowrap = true
	e.add_child(keys)

	_select_tab(1)
	return pv[0]

func _build_right_panel() -> Control:
	var pv = _panel(250)
	var v: VBoxContainer = pv[1]
	v.add_child(_section("Snapping"))
	var dr = _slider_row("", 0, DIVISORS.size() - 1, 1, max(DIVISORS.find(divisor), 0), "_on_divisor_slider")
	div_label = dr[1]
	div_slider = dr[2]
	v.add_child(dr[0])
	v.add_child(_check("Quantum (place between cells)", quantum, "_on_quantum"))
	var qr = _slider_row("", 1, 12, 1, quantum_divisor, "_on_qdiv")
	qdiv_row = qr[0]
	qdiv_label = qr[1]
	qdiv_slider = qr[2]
	v.add_child(qdiv_row)
	v.add_child(_check("Auto-advance after placing", auto_advance, "_on_autoadvance"))
	v.add_child(HSeparator.new())
	v.add_child(_section("View"))
	var ar = _slider_row("Approach: %d ms" % approach_ms, 200, 2000, 50, approach_ms, "_on_approach")
	v.add_child(ar[0])
	_approach_label = ar[1]
	v.add_child(_check("Key letters on the grid", show_letters, "_on_letters"))
	v.add_child(_check("Autoplay cursor", show_cursor, "_on_cursor"))
	v.add_child(HSeparator.new())
	v.add_child(_section("Sound"))
	v.add_child(_check("Hitsounds", hitsounds, "_on_hitsounds"))
	var mv = _slider_row("Music volume", 0, 1, 0.01, music_vol, "_on_music_vol")
	v.add_child(mv[0])
	var hv = _slider_row("Hitsound volume", 0, 1, 0.01, hit_vol, "_on_hit_vol")
	v.add_child(hv[0])
	v.add_child(_label("Playback speed", font_bold))
	var sp = OptionButton.new()
	sp.theme = load("res://uitheme.tres")
	for s in SPEEDS:
		sp.add_item("%sx" % str(s))
	sp.selected = max(SPEEDS.find(speed), 0)
	sp.connect("item_selected", self, "_on_speed")
	v.add_child(sp)
	_sync_snapping_ui()
	return pv[0]

var _approach_label: Label

func _select_tab(i: int):
	for k in range(tab_pages.size()):
		tab_pages[k].visible = k == i
		tab_buttons[k].pressed = k == i

func _fill_fields():
	title_label.text = project.title
	f_title.text = project.title
	f_mapper.text = project.mapper
	f_diff.select(max(f_diff.get_item_index(project.difficulty + 1), 0))
	f_bpm.set_block_signals(true)
	f_bpm.value = project.bpm
	f_bpm.set_block_signals(false)
	f_offset.set_block_signals(true)
	f_offset.value = project.offset
	f_offset.set_block_signals(false)
	f_overwrite.visible = project.can_overwrite_source()
	f_overwrite.set_block_signals(true)
	f_overwrite.pressed = project.overwrite_source
	f_overwrite.set_block_signals(false)
	_load_cover_preview()

func _load_cover_preview():
	f_cover.texture = null
	if project.has_cover:
		var img = Image.new()
		if img.load(project.cover_path()) == OK:
			var t = ImageTexture.new()
			t.create_from_image(img)
			f_cover.texture = t

func _sync_snapping_ui():
	div_label.text = "Beat divisor: 1/%d" % divisor
	div_slider.set_block_signals(true)
	div_slider.value = max(DIVISORS.find(divisor), 0)
	div_slider.set_block_signals(false)
	qdiv_label.text = "Quantum divisor: %d" % quantum_divisor
	qdiv_row.visible = quantum

# ================================================================== field events

func _on_title(t: String):
	if project:
		project.title = t
		title_label.text = t
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
	if project == null or not (files is PoolStringArray) or files.size() == 0:
		return
	if project.set_cover_from(files[0]):
		_load_cover_preview()
		_mark_dirty()
	else:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't read that image.", "Cover")

func _on_bpm(v: float):
	if project:
		project.bpm = v
		_mark_dirty()
		_redraw()

func _on_offset(v: float):
	if project:
		project.offset = v
		_mark_dirty()
		_redraw()

func _on_offset_here():
	if project:
		f_offset.value = round(time_ms)

func _on_guess_timing():
	if project == null:
		return
	if project.guess_timing():
		f_bpm.value = project.bpm
		f_offset.value = project.offset
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
		tap_label.text = "%.2f BPM  (%d taps)" % [_tap_bpm, _taps.size()]
	else:
		tap_label.text = "Keep tapping..."

func _tap_reset():
	_taps.clear()
	_tap_bpm = 0.0
	tap_label.text = "—"

func _tap_apply():
	if _tap_bpm > 0:
		f_bpm.value = stepify(_tap_bpm, 0.01)

func _on_metronome(on: bool):
	metronome = on
	_save_settings()

func _on_divisor_slider(v: float):
	divisor = DIVISORS[int(v)]
	_sync_snapping_ui()
	_save_settings()
	_redraw()

func change_divisor(d: int):
	var i: int = int(clamp(DIVISORS.find(divisor) + d, 0, DIVISORS.size() - 1))
	divisor = DIVISORS[i]
	_sync_snapping_ui()
	_save_settings()
	_redraw()

func _on_quantum(on: bool):
	quantum = on
	_sync_snapping_ui()
	_save_settings()
	_redraw()

func _on_qdiv(v: float):
	quantum_divisor = int(v)
	_sync_snapping_ui()
	_save_settings()
	_redraw()

func _on_autoadvance(on: bool):
	auto_advance = on
	_save_settings()

func _on_approach(v: float):
	approach_ms = v
	if _approach_label:
		_approach_label.text = "Approach: %d ms" % int(v)
	_save_settings()
	_redraw()

func _on_letters(on: bool):
	show_letters = on
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

func _on_speed(i: int):
	speed = SPEEDS[i]
	if music:
		music.pitch_scale = speed
	_save_settings()

func _apply_volumes():
	if music:
		music.volume_db = linear2db(max(music_vol, 0.0001))
	for h in hit_players:
		h.volume_db = linear2db(max(hit_vol, 0.0001))
	if metro:
		metro.volume_db = linear2db(max(hit_vol, 0.0001))

# ================================================================== settings

func _load_settings():
	var f = File.new()
	if f.open(Globals.p(SETTINGS_PATH), File.READ) != OK:
		return
	var p = JSON.parse(f.get_as_text())
	f.close()
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		return
	var d: Dictionary = p.result
	divisor = int(d.get("divisor", divisor))
	if not divisor in DIVISORS:
		divisor = 4
	quantum = bool(d.get("quantum", quantum))
	quantum_divisor = int(clamp(int(d.get("quantum_divisor", quantum_divisor)), 1, 12))
	auto_advance = bool(d.get("auto_advance", auto_advance))
	approach_ms = clamp(float(d.get("approach_ms", approach_ms)), 200, 2000)
	show_letters = bool(d.get("show_letters", show_letters))
	show_cursor = bool(d.get("show_cursor", show_cursor))
	hitsounds = bool(d.get("hitsounds", hitsounds))
	metronome = bool(d.get("metronome", metronome))
	music_vol = clamp(float(d.get("music_vol", music_vol)), 0, 1)
	hit_vol = clamp(float(d.get("hit_vol", hit_vol)), 0, 1)
	speed = float(d.get("speed", speed))
	if not speed in SPEEDS:
		speed = 1.0
	zoom = clamp(float(d.get("zoom", zoom)), 0.03, 3.0)

func _save_settings():
	var d = Directory.new()
	d.make_dir_recursive(EditorProject.root_dir())
	var f = File.new()
	if f.open(Globals.p(SETTINGS_PATH), File.WRITE) == OK:
		f.store_string(to_json({
			"divisor": divisor, "quantum": quantum, "quantum_divisor": quantum_divisor,
			"auto_advance": auto_advance, "approach_ms": approach_ms, "show_letters": show_letters,
			"show_cursor": show_cursor, "hitsounds": hitsounds, "metronome": metronome,
			"music_vol": music_vol, "hit_vol": hit_vol, "speed": speed, "zoom": zoom,
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
	var was_playing := playing
	if was_playing:
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
	# land on the beat grid so notes go where you expect
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
	if hitsounds and time_ms > _last_hit_ms:
		var i: int = project.lower_bound(_last_hit_ms + 0.001)
		var played := 0
		var last_t := -1.0
		while i < notes.size() and notes[i][2] <= time_ms:
			if notes[i][2] != last_t and played < 3:
				var h: AudioStreamPlayer = hit_players[_hit_next]
				_hit_next = (_hit_next + 1) % hit_players.size()
				h.play()
				played += 1
				last_t = notes[i][2]
			i += 1
	_last_hit_ms = time_ms
	if metronome:
		var beat := int(floor((time_ms - project.offset) / project.beat_ms()))
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
	time_label.text = fmt_time(time_ms)

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

# the note at the current time nearest to grid position gp (within half a cell)
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
	# forget selected notes that are gone
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
	count_label.text = "%d notes" % project.notes.size()
	length_label.text = fmt_time(song_length_ms).split(".")[0]
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
	var s := ""
	if not _selected.empty():
		s = "%d selected · " % _selected.size()
	s += "unsaved changes" if _dirty else "saved"
	status_label.text = s

func place_note(pos: Vector2, toggle: bool = false):
	if project == null:
		return
	var t: float = snap_now(time_ms)
	if not playing:
		time_ms = t
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

func _transform_selected(kind: String):
	if not _need_selection():
		return
	push_undo()
	for n in project.notes:
		if _selected.has(n[3]):
			match kind:
				"h": n[0] = 2.0 - n[0]
				"v": n[1] = 2.0 - n[1]
				"r":
					var x: float = n[0]
					n[0] = 2.0 - n[1]
					n[1] = x
	notes_changed()

func flip_h():
	_transform_selected("h")

func flip_v():
	_transform_selected("v")

func rotate_cw():
	_transform_selected("r")

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
	for c in _clip:
		var n := [c[0], c[1], t + c[2], _next_uid()]
		project.notes.append(n)
		_selected[n[3]] = true
	notes_changed()

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

# autoplay cursor: glides from the last note to the next
func cursor_pos():
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
	t = t * t * (3.0 - 2.0 * t)
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

# Saves the project and puts the map in your map list. Returns the Song or null.
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
		if ev.scancode == KEY_ESCAPE or ev.scancode == KEY_ENTER:
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
