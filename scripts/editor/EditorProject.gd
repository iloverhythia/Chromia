extends Reference
# A map being made in the in-game editor (the "Map Editor" sidebar page). Each
# project lives in user://editor/<pid>/:
#   project.json  - title, mapper, difficulty, the song's file, ids
#   map.txt       - the map as the Sound Space Quantum Editor saves it
#   map.ini       - its timing points, bookmarks, extra objects... (SSQE's .ini)
#   audio.mp3/ogg - the song
#   cover.png     - optional cover
# "Save" also exports it as a normal .sspm into user://maps, so it shows up in
# the map list right away.
#
# The editor works in SSQE's positions (x and y 0..2, drawn at column 2 - x);
# the game's notes ([x, y, ms], x 0 = left) are 2 - x / 2 - y.

const ROOT = "user://editor"
const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")

var pid := ""
var title := ""      # shown as the map name ("Artist - Song")
var mapper := ""
var difficulty := -1 # Globals.DIFF_*
var audio_file := "" # file name inside the project folder
var has_cover := false
var map_id := ""     # id in the map list for this project's own copy
var source_id := ""  # the map it was opened from (if any)
var overwrite_source := false # save over that map instead of a copy
var modified := 0
var note_count := 0
var save_txt_path := "" # where SAVE AS last wrote the .txt (SSQE's "file name")
var map_text := ""   # SSQE .txt
var map_ini := ""    # SSQE .ini
# old projects (before the SSQE editor): their notes and timing
var _legacy_notes = null
var _legacy_bpm := 0.0
var _legacy_offset := 0.0

static func root_dir() -> String:
	return Globals.p(ROOT)

func dir() -> String:
	return root_dir().plus_file(pid)

func export_id() -> String:
	return source_id if overwrite_source and source_id != "" else map_id

func can_overwrite_source() -> bool:
	if source_id == "" or Rhythia.registry_song == null:
		return false
	var s = Rhythia.registry_song.get_item(source_id)
	if not (s is Song):
		return false
	var fp := SSQEMap.ss(s.filePath)
	return fp.begins_with("user://maps") or (Globals.p("user://maps") != "user://maps" and fp.begins_with(Globals.p("user://maps")))

func audio_path() -> String:
	return dir().plus_file(audio_file) if audio_file != "" else ""

func cover_path() -> String:
	return dir().plus_file("cover.png")

static func slug(t: String) -> String:
	var out := ""
	for c in t.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif out != "" and not out.ends_with("_"):
			out += "_"
	out = out.strip_edges().trim_suffix("_")
	if out.length() > 40:
		out = out.substr(0, 40)
	return out if out != "" else "map"

# ------------------------------------------------------------------ the map

# The SSQE map of this project (a new SSQEMap each call).
func build_map():
	var m = SSQEMap.new()
	if map_text != "":
		F.read_txt(m, map_text)
		if map_ini != "":
			F.read_ini(m, map_ini)
	elif _legacy_notes != null:
		for n in _legacy_notes:
			m.notes.add(SSQEMap.note(2.0 - float(n[0]), 2.0 - float(n[1]), int(round(float(n[2])))))
		if _legacy_bpm > 0:
			m.timing_points.append(SSQEMap.timing_point(_legacy_bpm, int(_legacy_offset)))
	if SSQEMap.ss(m.sound_id) == "" or m.sound_id == "-1":
		m.sound_id = F.fix_id(map_id if map_id != "" else pid)
	if SSQEMap.ss(m.props.songName) == "":
		m.props.songName = title
	if SSQEMap.ss(m.props.mappers) == "" and mapper != "":
		m.props.mappers = mapper
	m.notes.sort()
	m.sort_timings()
	m.sort_bookmarks()
	m.special_objects.sort()
	m.vfx_objects.sort()
	return m

# Keeps the editor's map (written as SSQE's .txt and .ini).
func store_map(m):
	map_text = F.write_txt(m)
	map_ini = F.write_ini(m)
	note_count = m.notes.items.size()
	_legacy_notes = null

# The game's notes ([x, y, ms], x 0 = left, sorted) from the editor's map
static func game_notes(m) -> Array:
	m.notes.sort()
	var off := int(m.props.exportOffset)
	var out := []
	for n in m.notes.items:
		if is_nan(n.x) or is_nan(n.y):
			continue
		out.append([2.0 - n.x, 2.0 - n.y, float(max(0, n.ms + off))])
	return out

# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	return {
		"version": 2, "title": title, "mapper": mapper, "difficulty": difficulty,
		"audio_file": audio_file, "has_cover": has_cover, "map_id": map_id, "source_id": source_id,
		"overwrite_source": overwrite_source, "modified": modified, "note_count": note_count,
		"save_txt_path": save_txt_path,
	}

static func _write_text(path: String, text: String) -> bool:
	var f := File.new()
	var tmp := path + ".tmp"
	if f.open(tmp, File.WRITE) != OK:
		return false
	f.store_string(text)
	f.close()
	var d := Directory.new()
	if d.file_exists(path):
		d.remove(path)
	return d.rename(tmp, path) == OK

static func _read_text(path: String) -> String:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func save() -> bool:
	var d = Directory.new()
	d.make_dir_recursive(dir())
	modified = OS.get_unix_time()
	if _legacy_notes == null or map_text != "":
		if not _write_text(dir().plus_file("map.txt"), map_text):
			return false
		if not _write_text(dir().plus_file("map.ini"), map_ini):
			return false
	return _write_text(dir().plus_file("project.json"), to_json(to_dict()))

static func load_project(project_id: String):
	var path: String = root_dir().plus_file(project_id).plus_file("project.json")
	var txt := _read_text(path)
	if txt == "":
		return null
	var p = JSON.parse(txt)
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = p.result
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.pid = project_id
	pr.title = Globals.s(d.get("title", ""))
	pr.mapper = Globals.s(d.get("mapper", ""))
	pr.difficulty = int(d.get("difficulty", -1))
	pr.audio_file = Globals.s(d.get("audio_file", ""))
	pr.has_cover = bool(d.get("has_cover", false))
	pr.map_id = Globals.s(d.get("map_id", ""))
	pr.source_id = Globals.s(d.get("source_id", ""))
	pr.overwrite_source = bool(d.get("overwrite_source", false))
	pr.save_txt_path = Globals.s(d.get("save_txt_path", ""))
	if pr.map_id == "":
		pr.map_id = "chromia_editor_" + project_id
	pr.modified = int(d.get("modified", 0))
	pr.note_count = int(d.get("note_count", 0))
	var base: String = root_dir().plus_file(project_id)
	pr.map_text = _read_text(base.plus_file("map.txt"))
	pr.map_ini = _read_text(base.plus_file("map.ini"))
	if pr.map_text == "" and d.has("notes"):
		# a project from the old editor: notes as [x, y, ms] in the game's positions
		var flat = d.get("notes", [])
		var notes := []
		if typeof(flat) == TYPE_ARRAY:
			var i := 0
			while i + 2 < flat.size():
				notes.append([float(flat[i]), float(flat[i + 1]), float(flat[i + 2])])
				i += 3
		pr._legacy_notes = notes
		pr._legacy_bpm = float(d.get("bpm", 0.0))
		pr._legacy_offset = float(d.get("offset", 0.0))
		pr.note_count = notes.size()
	return pr

# [{pid, title, mapper, notes, modified, has_cover}] newest first
static func list_projects() -> Array:
	var out := []
	var d = Directory.new()
	if d.open(root_dir()) != OK:
		return out
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir():
			var txt := _read_text(root_dir().plus_file(n).plus_file("project.json"))
			if txt != "":
				var p = JSON.parse(txt)
				if p.error == OK and typeof(p.result) == TYPE_DICTIONARY:
					var r: Dictionary = p.result
					var count := int(r.get("note_count", 0))
					var nn = r.get("notes", null)
					if nn is Array:
						count = nn.size() / 3
					out.append({
						"pid": n, "title": Globals.s(r.get("title", n)), "mapper": Globals.s(r.get("mapper", "")),
						"notes": count, "modified": int(r.get("modified", 0)), "has_cover": bool(r.get("has_cover", false)),
					})
		n = d.get_next()
	d.list_dir_end()
	out.sort_custom(load("res://scripts/editor/EditorProject.gd"), "_newest_first")
	return out

static func _newest_first(a, b) -> bool:
	return a.modified > b.modified

static func delete_project(project_id: String):
	if project_id == "" or project_id.find("/") != -1 or project_id.find("\\") != -1 or project_id.begins_with("."):
		return
	var base: String = root_dir().plus_file(project_id)
	var d = Directory.new()
	if d.open(base) != OK:
		return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	var files := []
	while n != "":
		if not d.current_is_dir():
			files.append(n)
		n = d.get_next()
	d.list_dir_end()
	for f in files:
		d.remove(base.plus_file(f))
	d.remove(base)

static func _new_pid(t: String) -> String:
	var base := slug(t)
	var d = Directory.new()
	var pid_try := base
	var i := 2
	while d.dir_exists(root_dir().plus_file(pid_try)):
		pid_try = "%s_%d" % [base, i]
		i += 1
	return pid_try

static func audio_ext(bytes: PoolByteArray) -> String:
	var fmt: String = Globals.audioLoader.get_format(bytes)
	return fmt if fmt == "mp3" or fmt == "ogg" else ""

# New project from song bytes (mp3 / ogg). Returns the project, or an error String.
static func create_from_bytes(bytes: PoolByteArray, map_title: String, map_mapper: String):
	var ext := audio_ext(bytes)
	if ext == "":
		return "That song isn't an .mp3 or .ogg file."
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.title = map_title.strip_edges() if map_title.strip_edges() != "" else "New map"
	pr.mapper = map_mapper.strip_edges()
	pr.pid = _new_pid(pr.title)
	pr.map_id = "chromia_editor_" + pr.pid
	if not pr._write_audio(bytes, ext):
		return "Couldn't save the song into the editor folder."
	return pr

# New project from an audio file. Returns the project, or an error String.
static func create(audio_src: String, map_title: String, map_mapper: String):
	var f = File.new()
	if f.open(audio_src, File.READ) != OK:
		return "Couldn't open the song file."
	var bytes: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	var res = create_from_bytes(bytes, map_title if map_title != "" else audio_src.get_file().get_basename(), map_mapper)
	if res is String:
		return res
	var m = SSQEMap.new()
	m.sound_id = F.fix_id(res.title)
	m.props.songName = res.title
	res.store_map(m)
	if not res.save():
		return "Couldn't save the project."
	return res

func _write_audio(bytes: PoolByteArray, ext: String) -> bool:
	var d = Directory.new()
	d.make_dir_recursive(dir())
	var old := audio_path()
	audio_file = "audio." + ext
	if old != "" and old != audio_path():
		d.remove(old)
	var f = File.new()
	if f.open(audio_path(), File.WRITE) != OK:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

func audio_bytes() -> PoolByteArray:
	var f := File.new()
	if audio_path() == "" or f.open(audio_path(), File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

func cover_bytes() -> PoolByteArray:
	if not has_cover:
		return PoolByteArray()
	var f := File.new()
	if f.open(cover_path(), File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

# New project from a map in your map list (its notes, song and cover).
static func from_song(s):
	if s == null:
		return "No map selected."
	var buf = s.get_music_buffer()
	if not (buf is PoolByteArray) or buf.size() == 0:
		return "This map has no song to edit with."
	var ext := audio_ext(buf)
	if ext == "":
		return "This map's song isn't an .mp3 or .ogg."
	Rhythia.lock_song_notes(s)
	var src: Array = s.read_notes()
	var m = SSQEMap.new()
	for n in src:
		m.notes.add(SSQEMap.note(2.0 - float(n[0]), 2.0 - float(n[1]), int(round(float(n[2])))))
	Rhythia.unlock_song_notes(s)
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.title = Globals.s(s.name)
	pr.mapper = Globals.s(s.creator)
	pr.difficulty = int(s.difficulty)
	pr.pid = _new_pid(pr.title)
	pr.map_id = "chromia_editor_" + pr.pid
	pr.source_id = Globals.s(s.id)
	m.sound_id = F.fix_id(pr.source_id)
	m.props.songName = pr.title
	m.props.mappers = pr.mapper
	m.props.difficulty = _diff_name(pr.difficulty)
	m.notes.sort()
	pr.store_map(m)
	if not pr._write_audio(buf, ext):
		return "Couldn't save the song into the editor folder."
	var cov = s.cover if s.has_cover else null
	if cov is Texture:
		var img: Image = cov.get_data()
		if img != null and img.save_png(pr.cover_path()) == OK:
			pr.has_cover = true
	if not pr.save():
		return "Couldn't save the project."
	return pr

# Chromia difficulty <-> SSQE difficulty names
static func _diff_name(d: int) -> String:
	match d:
		Globals.DIFF_EASY: return "Easy"
		Globals.DIFF_MEDIUM: return "Medium"
		Globals.DIFF_HARD: return "Hard"
		Globals.DIFF_LOGIC: return "Logic"
		Globals.DIFF_AMOGUS: return "Tasukete"
	return "N/A"

static func diff_from_name(n: String) -> int:
	match n:
		"Easy": return Globals.DIFF_EASY
		"Medium": return Globals.DIFF_MEDIUM
		"Hard": return Globals.DIFF_HARD
		"Logic": return Globals.DIFF_LOGIC
		"Tasukete": return Globals.DIFF_AMOGUS
	return Globals.DIFF_UNKNOWN

func set_cover_from(path: String) -> bool:
	var img: Image = null
	var f = File.new()
	if f.open(path, File.READ) == OK:
		var bytes = f.get_buffer(f.get_len())
		f.close()
		img = Globals.imageLoader.load_buffer_image(bytes)
	if img == null or img.is_empty():
		return false
	if img.get_width() > 1024 or img.get_height() > 1024:
		var s := 1024.0 / max(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_BILINEAR)
	var d = Directory.new()
	d.make_dir_recursive(dir())
	if img.save_png(cover_path()) != OK:
		return false
	has_cover = true
	return true

# Writes the map into user://maps and (re)adds it to the map list.
# Returns the Song, or an error String.
func export_to_maps(m):
	var notes := game_notes(m)
	if notes.empty():
		return "Place at least one note first."
	var out_id := export_id()
	var name := SSQEMap.ss(m.props.songName) if SSQEMap.ss(m.props.songName) != "" else title
	var by := SSQEMap.ss(m.props.mappers).replace("\n", ", ") if SSQEMap.ss(m.props.mappers) != "" else mapper
	var s = Song.new(out_id, name if name != "" else pid, by if by != "" else "Unknown")
	s.songType = Globals.MAP_RAW
	s.musicFile = audio_path()
	s.difficulty = difficulty
	s.notes = notes
	s.note_count = notes.size()
	s.last_ms = notes[-1][2]
	if has_cover:
		var img = Image.new()
		if img.load(cover_path()) == OK:
			var tex = ImageTexture.new()
			tex.create_from_image(img)
			s.cover = tex
			s.has_cover = true
	# the file the map list has for this id now (may be named differently)
	var old_path := ""
	if Rhythia.registry_song:
		var old = Rhythia.registry_song.get_item(out_id)
		if old is Song:
			old_path = SSQEMap.ss(old.filePath)
	var res = s.convert_to_sspm(true)
	if res != "Converted!":
		return "Couldn't save the map: " + SSQEMap.ss(res)
	var new_path: String = Globals.p("user://maps/%s.sspm" % out_id)
	if old_path != "" and Globals.p(old_path) != new_path and (old_path.begins_with("user://maps") or old_path.begins_with(Globals.p("user://maps"))):
		Directory.new().remove(Globals.p(old_path))
	if Rhythia.registry_song:
		Rhythia.registry_song.check_and_remove_id(out_id)
		var added = Rhythia.registry_song.add_sspm_map(Globals.p("user://maps/%s.sspm" % out_id))
		if added:
			return added
	return "The map was saved but couldn't be loaded."
