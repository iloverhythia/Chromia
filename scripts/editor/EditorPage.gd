extends ReferenceRect
# "Map Editor" sidebar page: the in-game map editor, a port of Sound Space
# Quantum Editor Plus (github.com/iloverhythia/Sound-Space-Quantum-Editor-Plus)
# in Chromia's UI. The editor screen itself is scripts/editor/ssqe/SSQEEditor.gd;
# this page has the editor's start screen (your maps, CREATE NEW MAP, LOAD
# MAP, PASTE MAP) and keeps each map's song, cover and copy in the map list.

const EditorProject = preload("res://scripts/editor/EditorProject.gd")
const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const SSQEImport = preload("res://scripts/editor/ssqe/SSQEImport.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const RETURN_META = "chromia_editor_return"
const REF_H = 720.0

var project = null
var map = null
var ed = null # SSQEEditor
var audio = null # SSQEAudio (song analysis: waveform, BPM, auto mapper)

var home: Control
var projects_box: VBoxContainer
var edit_selected_btn: Button
var edit_last_btn = null
var f_btn: DynamicFont
var f_lbl: DynamicFont
var f_val: DynamicFont
var f_small: DynamicFont
var f_title: DynamicFont
var f_big: DynamicFont
var _built := false
var _paused_menu_players: Array = []

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
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _label(text: String, font: Font, color: Color = LILAC) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.add_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.theme = load("res://uitheme.tres")
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	b.add_font_override("font", f_btn)
	if method != "":
		b.connect("pressed", self, method, args)
	return b

func _first(files) -> String:
	if files is PoolStringArray and files.size() > 0:
		return files[0]
	if files is Array and files.size() > 0:
		return SSQEMap.ss(files[0])
	if files is String:
		return files
	return ""

static func _start_dir() -> String:
	if OS.has_feature("pc"):
		var d := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		return d if d != "" else "user://"
	return "user://"

func _notify(text: String, title := "Map Editor", kind = null):
	Globals.notify(Globals.NOTIFY_INFO if kind == null else kind, text, title)

# ================================================================== lifecycle

func _ready():
	connect("visibility_changed", self, "_on_visibility")
	connect("resized", self, "_layout_home")
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
		ed.set_current_time(float(info.get("time", 0.0)))

func _on_visibility():
	if is_visible_in_tree():
		_ensure_built()
		_refresh_home()
		_pause_menu_music(true)
		_layout_home()
	else:
		if ed and ed.playing:
			ed.pause_music()
		_pause_menu_music(false)
		if project != null and ed and ed.dirty:
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
	f_btn = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 15)
	f_lbl = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 15)
	f_val = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 15)
	f_small = _mkfont("res://assets/font/Lato/Lato-Regular.ttf", 13)
	f_title = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 22)
	f_big = _mkfont("res://assets/font/Lato/Lato-Bold.ttf", 44)
	_build_home()
	audio = load("res://scripts/editor/ssqe/SSQEAudio.gd").new()
	audio.page = self
	add_child(audio)

# ================================================================== start screen
# Like the editor's menu: your maps on the left, big buttons on the right.

func _build_home():
	home = Control.new()
	home.anchor_right = 1
	home.anchor_bottom = 1
	home.margin_left = 4
	add_child(home)
	var title = _label("SOUND SPACE QUANTUM EDITOR PLUS", f_big, TEXT)
	title.name = "Title"
	home.add_child(title)
	var sub = _label("Chromia's map editor", f_lbl, LILAC)
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
	for it in [["CREATE NEW MAP", "_on_new_map"], ["LOAD MAP", "_on_load_map"], ["PASTE MAP", "_on_paste_new"],
			["EDIT LAST MAP", "_on_edit_last"], ["EDIT SELECTED MAP", "_on_edit_selected"]]:
		var b = _btn(it[0], it[1])
		b.add_font_override("font", f_title)
		b.size_flags_vertical = SIZE_EXPAND_FILL
		b.clip_text = true
		col.add_child(b)
		if it[1] == "_on_edit_selected":
			edit_selected_btn = b
		elif it[1] == "_on_edit_last":
			edit_last_btn = b
	home.connect("resized", self, "_layout_home")

func _layout_home():
	if home == null:
		return
	var w := home.rect_size.x
	var h := home.rect_size.y
	var s: float = clamp(h / REF_H, 0.6, 2.5)
	var t = home.get_node("Title")
	f_big.size = int(clamp(40 * s, 20, 90))
	var tw: float = f_big.get_string_size(t.text).x
	if tw > w - 40 * s:
		f_big.size = int(f_big.size * (w - 40 * s) / tw)
	t.rect_position = Vector2(23 * s, 14 * s)
	home.get_node("Sub").rect_position = Vector2(26 * s, 14 * s + f_big.get_height() + 2)
	var panel = home.get_node("Panel")
	panel.rect_position = Vector2(23 * s, 120 * s)
	panel.rect_size = Vector2(w * 0.5 - 23 * s, h - 120 * s - 40 * s)
	var col = home.get_node("Buttons")
	col.rect_position = Vector2(w * 0.5 + 40 * s, 120 * s)
	col.rect_size = Vector2(w * 0.5 - 80 * s, min(5 * 64 * s + 40, h - 160 * s))
	f_title.size = int(clamp(22 * s, 14, 48))
	f_btn.size = int(clamp(15 * s, 11, 32))

func _refresh_home():
	if not _built:
		return
	var s = Rhythia.selected_song
	if s is Song:
		edit_selected_btn.text = "EDIT: " + Globals.s(s.name).to_upper()
		edit_selected_btn.disabled = false
	else:
		edit_selected_btn.text = "EDIT SELECTED MAP"
		edit_selected_btn.disabled = true
	for c in projects_box.get_children():
		c.queue_free()
	var list: Array = EditorProject.list_projects()
	# (newest first: the last map you edited)
	edit_last_btn.disabled = list.empty()
	edit_last_btn.text = "EDIT LAST MAP" if list.empty() else "EDIT LAST: " + Globals.s(list[0].title).to_upper()
	if list.empty():
		var l = _label("No maps yet. CREATE NEW MAP starts one from a song; LOAD MAP opens a map file (SSQE .txt/.qem/.qemz, .sspm, .rhm, Rewrite .phxm, Novastra .npk, osu!, Pulsus or Vulnus); EDIT SELECTED MAP opens a map from your list.", f_lbl, DIM)
		l.autowrap = true
		projects_box.add_child(l)
		return
	for p in list:
		projects_box.add_child(_project_row(p))

func _project_row(p: Dictionary) -> Control:
	var row = PanelContainer.new()
	row.add_stylebox_override("panel", _flat(Color(0.06, 0.055, 0.075, 1), 4, Color(0.28, 0.26, 0.33, 1), 1))
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
	ob.rect_min_size = Vector2(70, 32)
	ob.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(ob)
	var db = _btn("DELETE", "_on_delete_project", [p.pid, p.title])
	db.rect_min_size = Vector2(76, 32)
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
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, method, PoolStringArray(["*.mp3, *.ogg ; Songs (mp3, ogg)"]), false, _start_dir())

# ---- CREATE NEW MAP
func _on_new_map():
	_pick_song("_on_new_song_picked")

func _on_new_song_picked(files):
	var path := _first(files)
	if path == "":
		return
	var res = EditorProject.create(path, path.get_file().get_basename(), "")
	if res is String:
		_notify(res, "Map Editor", Globals.NOTIFY_WARN)
		return
	_open(res)
	_notify("Set up the BPM in TIMING > OPEN BPM SETUP (or DETECT BPM), then place notes with Q W E / A S D / Z X C or the mouse.", "New map")

# ---- EDIT SELECTED MAP
# EDIT LAST MAP (SSQE+: Settings.lastFile): the map edited most recently
func _on_edit_last():
	var list: Array = EditorProject.list_projects()
	if list.empty():
		_notify("No maps yet.", "Map Editor")
		return
	open_project(list[0].pid)

func _on_edit_selected():
	edit_song(Rhythia.selected_song)

func edit_song(s):
	_ensure_built()
	if s == null:
		return
	var res = EditorProject.from_song(s)
	if res is String:
		_notify(res, "Can't edit this map", Globals.NOTIFY_WARN)
		return
	_open(res)
	_notify("Saving makes a new copy in your map list. To find its BPM, use TIMING > DETECT BPM.", "Editing " + Globals.s(s.name))

# ---- LOAD MAP (.txt with its .ini, .sspm, .osu, .rhm, and SSQEImport's formats)
var _pending_map = null
var _pending_cover := PoolByteArray()

func _on_load_map():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_on_map_file_picked", PoolStringArray([
		"*.txt, *.sspm, *.osu, *.rhm, *.phxm, *.npk, *.nch, *.qem, *.qemz, *.phz, *.zip, *.json ; All maps",
		"*.txt ; Map data (SSQE)", "*.qem, *.qemz ; SSQE maps", "*.sspm ; Sound Space maps", "*.rhm ; Rhythia maps",
		"*.phxm ; Rewrite maps", "*.npk, *.nch ; Novastra maps", "*.osu ; osu! maps", "*.phz ; Pulsus maps",
		"*.zip, *.json ; Vulnus maps"]), false, _start_dir())

func _on_map_file_picked(files):
	var path := _first(files)
	if path == "":
		return
	var ext := path.get_extension().to_lower()
	match ext:
		"sspm":
			var s = Song.new()
			var r = s.load_from_sspm(path)
			if r is String:
				_notify(r, "Can't open this map", Globals.NOTIFY_WARN)
				return
			edit_song(s)
		"txt":
			var m = SSQEMap.new()
			var err := F.read_txt(m, _read_text(path))
			if err != "":
				_notify(err, "Can't open this map", Globals.NOTIFY_WARN)
				return
			var ini := path.get_basename() + ".ini"
			if File.new().file_exists(ini):
				F.read_ini(m, _read_text(ini))
			_with_song(m, path.get_file().get_basename(), _find_song(path.get_base_dir(), [SSQEMap.ss(m.sound_id), path.get_file().get_basename()]))
		"osu":
			var m2 = SSQEMap.new()
			var audio_name := F.read_osu(m2, _read_text(path))
			var song := path.get_base_dir().plus_file(audio_name) if audio_name != "" else ""
			_with_song(m2, path.get_file().get_basename(), song if File.new().file_exists(song) else "")
		"rhm":
			_load_rhm(path)
		_:
			if ext in SSQEImport.EXTENSIONS:
				_import_other(path)
			else:
				_notify("This kind of file isn't a map the editor can open.", "Map Editor", Globals.NOTIFY_WARN)

# ---- the other formats SSQE+ opens (scripts/editor/ssqe/SSQEImport.gd)
var _pending_import = null # an import still waiting for its song

func _import_other(path: String):
	var r: Dictionary = SSQEImport.read(path)
	if r.error != "":
		_notify(r.error, "Can't open this map", Globals.NOTIFY_WARN)
		return
	if r.audio.empty() and r.audio_url != "":
		_download_song(r)
		return
	_finish_import(r)

# Pulsus maps name their song by id: fetch it, or ask for it
func _download_song(r: Dictionary):
	_notify("Downloading the song...", "Load map")
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30
	http.connect("request_completed", self, "_on_song_downloaded", [http, r])
	if http.request(r.audio_url) != OK:
		_on_song_downloaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PoolStringArray(), PoolByteArray(), http, r)

func _on_song_downloaded(result: int, code: int, _headers, body: PoolByteArray, http: HTTPRequest, r: Dictionary):
	http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and EditorProject.audio_ext(body) != "":
		r.audio = body
	else:
		_notify("The song couldn't be downloaded.", "Load map", Globals.NOTIFY_WARN)
	_finish_import(r)

func _finish_import(r: Dictionary):
	if r.audio.empty():
		_pending_import = r
		_notify("Now pick the song for this map.", "Load map")
		_pick_song("_on_import_song_picked")
		return
	var first = null
	for e in r.maps:
		var p = _create_from(e.map, e.title, r.audio, r.cover, false, r.icon)
		if p == null:
			return
		if first == null:
			first = p
	if first != null:
		_open(first)
	if r.maps.size() > 1:
		_notify("This file had %d maps. They're all in YOUR MAPS; the first one is open." % r.maps.size(), "Load map")

func _on_import_song_picked(files):
	var path := _first(files)
	if path == "" or _pending_import == null:
		return
	var r: Dictionary = _pending_import
	_pending_import = null
	r.audio = _read_bytes(path)
	if r.audio.empty():
		_notify("That song couldn't be read.", "Load map", Globals.NOTIFY_WARN)
		return
	_finish_import(r)

static func _read_text(path: String) -> String:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

static func _read_bytes(path: String) -> PoolByteArray:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

# the map's song next to it (named after its id, or the map's file)
static func _find_song(folder: String, names: Array) -> String:
	var f := File.new()
	for n in names:
		for ext in ["mp3", "ogg"]:
			var p := folder.plus_file("%s.%s" % [n, ext])
			if f.file_exists(p):
				return p
	return ""

# a map to open, with its song (or the song to ask for)
func _with_song(m, title: String, song_path: String):
	if song_path != "":
		_create_from(m, title, _read_bytes(song_path), PoolByteArray())
		return
	_pending_map = [m, title]
	_notify("Now pick the song for this map.", "Load map")
	_pick_song("_on_pending_song_picked")

func _on_pending_song_picked(files):
	var path := _first(files)
	if path == "" or _pending_map == null:
		return
	_create_from(_pending_map[0], _pending_map[1], _read_bytes(path), _pending_cover)
	_pending_map = null
	_pending_cover = PoolByteArray()

# A new project from a map, its song and cover (and Novastra's mapper icon).
# Opens it unless open is false; returns it, or null when it couldn't be made.
func _create_from(m, title: String, song: PoolByteArray, cover: PoolByteArray, open := true, icon := PoolByteArray()):
	var res = EditorProject.create_from_bytes(song, SSQEMap.ss(m.props.songName) if SSQEMap.ss(m.props.songName) != "" else title, SSQEMap.ss(m.props.mappers).replace("\n", ", "))
	if res is String:
		_notify(res, "Map Editor", Globals.NOTIFY_WARN)
		return null
	res.difficulty = EditorProject.diff_from_name(SSQEMap.ss(m.props.difficulty))
	if SSQEMap.ss(m.sound_id) == "" or m.sound_id == "-1":
		m.sound_id = F.fix_id(res.title)
	if not cover.empty():
		var img: Image = Globals.imageLoader.load_buffer_image(cover)
		if img and not img.is_empty() and img.save_png(res.cover_path()) == OK:
			res.has_cover = true
			m.props.useCover = true
	if not icon.empty():
		var ic: Image = Globals.imageLoader.load_buffer_image(icon)
		if ic and not ic.is_empty() and ic.save_png(res.dir().plus_file("icon.png")) == OK:
			m.props.novaIcon = res.dir().plus_file("icon.png")
	res.store_map(m)
	res.save()
	if open:
		_open(res)
	return res

func _load_rhm(path: String):
	var files := _read_zip(_read_bytes(path))
	if not files.has("map"):
		_notify("This .rhm has no map in it.", "Can't open this map", Globals.NOTIFY_WARN)
		return
	var p := JSON.parse(files["map"].get_string_from_utf8())
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		_notify("This .rhm's map couldn't be read.", "Can't open this map", Globals.NOTIFY_WARN)
		return
	var d: Dictionary = p.result
	var m = SSQEMap.new()
	if d.get("Notes") is Array:
		for n in d.Notes:
			m.notes.add(SSQEMap.note(2.0 - float(n.get("X", 1)), 2.0 - float(n.get("Y", 1)), int(round(float(n.get("Time", 0))))))
	if d.get("TimingPoints") is Array:
		for t in d.TimingPoints:
			if float(t.get("Bpm", 0)) > 0:
				m.timing_points.append(SSQEMap.timing_point(float(t.Bpm), int(round(float(t.get("OffsetMs", 0))))))
	var title: String = Globals.s(d.get("Title", "")) if d.get("Title") else Globals.s(d.get("SongName", ""))
	m.sound_id = F.fix_id(title if title != "" else path.get_file().get_basename())
	m.props.songName = Globals.s(d.get("SongName", title)) if d.get("SongName") else title
	m.props.songTitle = title
	var mp = d.get("Mappers", [])
	if mp is Array:
		m.props.mappers = PoolStringArray(mp).join("\n")
	elif mp != null:
		m.props.mappers = SSQEMap.ss(mp)
	var di: int = int(d.get("Difficulty", 0)) if d.get("Difficulty") != null else 0
	m.props.difficulty = SSQEMap.DIFFICULTIES[di] if di >= 0 and di < SSQEMap.DIFFICULTIES.size() else "N/A"
	m.props.customDifficulty = Globals.s(d.get("CustomDifficultyName", "")) if d.get("CustomDifficultyName") else ""
	m.props.useCover = files.has("cover")
	m.sort_all()
	if not files.has("audio"):
		_with_song(m, title, "")
		return
	_create_from(m, title, files["audio"], files.get("cover", PoolByteArray()))

# A zip's files (stored or deflated) -> {name: bytes}
static func _read_zip(bytes: PoolByteArray) -> Dictionary:
	return load("res://scripts/content/ZipReader.gd").read(bytes)

# ---- PASTE MAP
func _on_paste_new():
	var m = SSQEMap.new()
	var text := OS.clipboard.strip_edges()
	if text == "" or (text.find(",") == -1 and text.find("`") == -1):
		_notify("Copy map data first (\"id,x|y|ms,...\").", "Nothing to paste", Globals.NOTIFY_WARN)
		return
	var err := F.read_txt(m, text)
	if err != "" or m.notes.items.empty():
		_notify(err if err != "" else "No notes found in the copied text.", "Can't paste this map", Globals.NOTIFY_WARN)
		return
	_notify("%d notes found. Now pick the song for them." % m.notes.items.size(), "Paste map")
	_pending_map = [m, SSQEMap.ss(m.sound_id)]
	_pick_song("_on_pending_song_picked")

# ================================================================== the open map

func open_project(pid: String) -> bool:
	_ensure_built()
	var pr = EditorProject.load_project(pid)
	if pr == null:
		_notify("Couldn't open that editor map.", "Map Editor", Globals.NOTIFY_WARN)
		return false
	_open(pr)
	return true

func _open(pr):
	if project != null and ed and ed.dirty:
		_save_project_only()
	project = pr
	map = pr.build_map()
	if ed == null:
		ed = load("res://scripts/editor/ssqe/SSQEEditor.gd").new()
		ed.page = self
		add_child(ed)
	var stream = Globals.audioLoader.load_file(project.audio_path())
	if not (stream is AudioStream):
		stream = null
		_notify("Couldn't load this map's song.", "Map Editor", Globals.NOTIFY_WARN)
	home.visible = false
	ed.visible = true
	ed.open_map(map, stream)
	ed.dirty = false
	if audio:
		audio.analyse(project.audio_path(), stream)

func close_project():
	if project != null and ed and ed.dirty:
		_save_project_only()
	if ed:
		ed.pause_music()
		ed.dialogs.close_all()
		ed.visible = false
	if audio:
		audio.cancel()
	project = null
	map = null
	home.visible = true
	_refresh_home()

func on_map_edited():
	pass

func autosave():
	_save_project_only()

func _save_project_only():
	if project == null or map == null:
		return
	project.store_map(map)
	_sync_meta()
	if project.save() and ed:
		ed.dirty = false

# the map list's name / mapper / difficulty come from the map's properties
func _sync_meta():
	var p: Dictionary = map.props
	if SSQEMap.ss(p.songName) != "":
		project.title = SSQEMap.ss(p.songName)
	if SSQEMap.ss(p.mappers) != "":
		project.mapper = SSQEMap.ss(p.mappers).replace("\n", ", ")
	project.difficulty = EditorProject.diff_from_name(SSQEMap.ss(p.difficulty))

# SAVE: the editor map, and its copy in your map list
func save_map():
	if project == null:
		return null
	_save_project_only()
	var res = project.export_to_maps(map)
	if res is String:
		_notify(res, "Map Editor", Globals.NOTIFY_WARN)
		return null
	var list = get_node_or_null("../Maps/MapRegistry/S/VBoxContainer")
	if list != null and list.has_method("refresh_songs"):
		list.refresh_songs()
	if ed:
		ed.toast("SAVED")
	return res

# SAVE AS: the map's .txt and .ini, where you choose (like the original editor)
func save_as():
	if project == null:
		return
	_save_project_only()
	Globals.file_sel.raise()
	var start: String = project.save_txt_path if project.save_txt_path != "" else _start_dir().plus_file(F.fix_id(SSQEMap.ss(map.sound_id)) + ".txt")
	Globals.file_sel.save_file(self, "_on_save_as_path", PoolStringArray(["*.txt ; Map data (.txt + .ini)"]), start)

func _on_save_as_path(path):
	if not (path is String) or path == "" or project == null:
		return
	if path.get_extension().to_lower() != "txt":
		path += ".txt"
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		ed.dialogs.message("Couldn't write " + path)
		return
	f.store_string(F.write_txt(map))
	f.close()
	if f.open(path.get_basename() + ".ini", File.WRITE) == OK:
		f.store_string(F.write_ini(map))
		f.close()
	project.save_txt_path = path
	project.save()
	ed.toast("SAVED " + path.get_file())

func playtest(from_start: bool):
	if project == null:
		return
	if ed.playing:
		ed.pause_music()
	var song = save_map()
	if song == null:
		return
	get_tree().root.set_meta(RETURN_META, {
		"pid": project.pid, "time": ed.current_time(), "prev_start_offset": Rhythia.start_offset,
	})
	Rhythia.select_song(song)
	Rhythia.start_offset = 0.0 if from_start else max(0.0, ed.current_time() - 1000.0)
	Rhythia.replaying = false
	var menu = Rhythia.menu_node()
	if menu:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

# ---- the song and cover (for the export windows)
func has_cover() -> bool:
	return project != null and project.has_cover

func cover_bytes() -> PoolByteArray:
	return project.cover_bytes() if project else PoolByteArray()

func audio_bytes() -> PoolByteArray:
	return project.audio_bytes() if project else PoolByteArray()

func set_cover(path: String):
	if project and project.set_cover_from(path):
		project.save()

# IMPORT INI
func import_ini():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_on_ini_picked", PoolStringArray(["*.ini ; Map properties"]), false, _start_dir())

func _on_ini_picked(files):
	var path := _first(files)
	if path == "" or map == null:
		return
	F.read_ini(map, _read_text(path))
	ed.on_map_changed()
	ed.toast("IMPORTED " + path.get_file())

# CONVERT TO MP3
func convert_to_mp3():
	if project == null:
		return
	if project.audio_file.ends_with(".mp3"):
		ed.dialogs.message("This map's song is already an MP3.")
	else:
		ed.dialogs.message("Chromia can't re-encode songs. Its maps play .ogg songs as well as .mp3, so there's no need to convert this one; to use another file, LOAD MAP or CREATE NEW MAP with the MP3.")

# ================================================================== song analysis (SSQEAudio.gd)

func detect_bpm_to_map():
	detect_bpm(0, 0, self, "_on_detected_for_map")

func _on_detected_for_map(found):
	if not (found is Dictionary) or map == null:
		return
	if not map.timing_points.empty():
		ed.dialogs.confirm("Detected %s BPM (first downbeat at %d ms)%s.\n\nReplace the map's %d timing point%s with it?" % [
			str(found.bpm), found.offsetMs, "" if found.steady else ", though the tempo drifts in places",
			map.timing_points.size(), "" if map.timing_points.size() == 1 else "s"], self, "_on_replace_bpm", [found])
	else:
		_on_replace_bpm("yes", found)

func _on_replace_bpm(answer: String, found: Dictionary):
	if answer != "yes":
		return
	map.replace_points("DETECT BPM", map.timing_points.duplicate(), [SSQEMap.timing_point(float(found.bpm), int(found.offsetMs))])
	ed.toast("SET BPM TO %s AT %dMS" % [str(found.bpm), found.offsetMs], "other")

# Calls target.method(found): {bpm, offsetMs, steady} or null
func detect_bpm(from_ms: int, to_ms: int, target: Object, method: String):
	if audio == null or not audio.ready():
		ed.dialogs.message("The song is still being read (%d%%), so its BPM can't be detected yet. Try again in a moment." % int(audio.progress() * 100 if audio else 0))
		target.call(method, null)
		return
	ed.toast("DETECTING THE BPM...", "other")
	var found = audio.detect_bpm(from_ms, to_ms)
	if not (found is Dictionary):
		ed.toast("NO CLEAR BEAT FOUND", "other")
		ed.dialogs.message("Pick at least 15 seconds of the song to detect its BPM from." if to_ms > from_ms and to_ms - from_ms < 15000 else "No clear beat could be found in this part of the song. Try a part with drums, or tap it with the BPM Tapper.")
		target.call(method, null)
		return
	ed.toast("DETECTED %s BPM - OFFSET %dMS%s" % [str(found.bpm), found.offsetMs, "" if found.steady else " (THE TEMPO DRIFTS)"], "other")
	target.call(method, found)

func on_waveform(wave):
	if ed:
		ed.waveform = wave

# ---- auto mapper
func auto_map():
	if audio == null or not audio.ready():
		ed.dialogs.message("The song is still being read (%d%%), so it can't be auto mapped yet. Try again in a moment." % int(audio.progress() * 100 if audio else 0))
		return
	audio.auto_map(ed, map)

func auto_map_learn():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_on_learn_picked", PoolStringArray(["*.sspm, *.txt, *.osu ; Maps"]), true, _start_dir())

func _on_learn_picked(files):
	if audio and files is PoolStringArray and files.size() > 0:
		audio.learn_files(files, ed)

func auto_map_reset():
	ed.dialogs.confirm("Forget everything the auto mapper has learned?", self, "_on_reset_learning")

func _on_reset_learning(answer: String):
	if answer == "yes" and audio:
		audio.reset_learning()
		ed.toast("THE AUTO MAPPER FORGOT WHAT IT LEARNED", "other")

func auto_map_stats_text() -> String:
	return audio.stats_text() if audio else ""
