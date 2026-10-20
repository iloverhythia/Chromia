extends Reference
# A map being made in the in-game editor (the "Editor" sidebar page, built after
# Sound Space Quantum Editor). Each project lives in user://editor/<pid>/:
#   project.json  - notes, timing, title, mapper, ...
#   audio.mp3/ogg - the song
#   cover.png     - optional cover
# "Save" also exports it as a normal .sspm into user://maps, so it shows up in
# the map list right away.
#
# Notes are [x, y, ms] in the game's own coordinates: x 0..2 is the column
# (0 = left), y 0..2 the row (0 = top), the same values the game reads from
# .sspm files. SSQE's text format ("id,x|y|ms,...") uses 2 - x / 2 - y.

const ROOT = "user://editor"

var pid := ""
var title := ""      # shown as the map name ("Artist - Song")
var mapper := ""
var difficulty := -1 # Globals.DIFF_*
var bpm := 120.0
var offset := 0.0    # ms of the first beat
var audio_file := "" # file name inside the project folder
var has_cover := false
var map_id := ""     # id in the map list for this project's own copy
var source_id := ""  # the map it was opened from (if any)
var overwrite_source := false # save over that map instead of a copy
var modified := 0
var notes: Array = []

static func root_dir() -> String:
	return Globals.p(ROOT)

func dir() -> String:
	return root_dir().plus_file(pid)

# id the map is saved under
func export_id() -> String:
	return source_id if overwrite_source and source_id != "" else map_id

func can_overwrite_source() -> bool:
	if source_id == "" or Rhythia.registry_song == null:
		return false
	var s = Rhythia.registry_song.get_item(source_id)
	if not (s is Song):
		return false
	var fp := String(s.filePath)
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

# ------------------------------------------------------------------ notes

static func note_sort(a, b) -> bool:
	return a[2] < b[2]

func sort_notes():
	notes.sort_custom(get_script(), "note_sort")

func length_ms() -> float:
	return float(notes[-1][2]) if not notes.empty() else 0.0

# first index whose time is >= ms (binary search; notes are sorted)
func lower_bound(ms: float) -> int:
	var lo := 0
	var hi := notes.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if notes[mid][2] < ms:
			lo = mid + 1
		else:
			hi = mid
	return lo

func copy_notes() -> Array:
	var out := []
	out.resize(notes.size())
	for i in range(notes.size()):
		var n = notes[i]
		out[i] = [n[0], n[1], n[2]]
	return out

# ------------------------------------------------------------------ timing

func beat_ms() -> float:
	return 60000.0 / max(bpm, 1.0)

func snap(ms: float, divisor: int) -> float:
	var step := beat_ms() / max(divisor, 1)
	return offset + round((ms - offset) / step) * step

func step_from(ms: float, divisor: int, dir: int) -> float:
	var step := beat_ms() / max(divisor, 1)
	var k := round((ms - offset) / step)
	# if not on the grid, the first step only snaps
	var on := abs(offset + k * step - ms) < 1.0
	if not on:
		k = floor((ms - offset) / step) if dir > 0 else ceil((ms - offset) / step)
	return offset + (k + dir) * step

# .sspm files don't store BPM. This guesses it from the notes: the most common
# gap between notes is some subdivision of a beat; a straight-line fit of all
# note times on that step then gives the exact step and the first beat.
# Returns true if it found something believable.
func guess_timing() -> bool:
	var times := []
	var last := -1e9
	for n in notes:
		if n[2] - last > 5.0:
			times.append(float(n[2]))
			last = n[2]
	if times.size() < 8:
		return false
	var hist := {}
	for i in range(1, times.size()):
		var g := int(round(times[i] - times[i - 1]))
		if g >= 40 and g <= 2000:
			hist[g] = int(hist.get(g, 0)) + 1
	var best_g := 0
	var best_score := 0
	for g in hist.keys():
		var sc := 0
		for d in range(-2, 3):
			sc += int(hist.get(g + d, 0))
		if sc > best_score or (sc == best_score and g < best_g):
			best_score = sc
			best_g = g
	if best_g == 0 or best_score < 4:
		return false
	# fit t = a + b * k on notes that sit on that step
	var step0 := float(best_g)
	var t0: float = times[0]
	var sk := 0.0
	var st := 0.0
	var skk := 0.0
	var skt := 0.0
	var cnt := 0
	for t in times:
		var k: float = round((t - t0) / step0)
		var res: float = abs(t - (t0 + k * step0))
		if res <= step0 * 0.2:
			sk += k
			st += t
			skk += k * k
			skt += k * t
			cnt += 1
	if cnt < 6:
		return false
	var den := cnt * skk - sk * sk
	var step := step0
	var a := t0
	if abs(den) > 0.0001:
		step = (cnt * skt - sk * st) / den
		a = (st - step * sk) / cnt
	# the step is a beat subdivision: choose the beat length for a usual BPM
	var beat := step
	for m in [1, 2, 4, 3, 6, 8]:
		var b: float = 60000.0 / (step * m)
		if b >= 90.0 and b <= 250.0:
			beat = step * m
			break
	bpm = stepify(60000.0 / beat, 0.01)
	offset = round(a)
	return true

# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	var flat := []
	for n in notes:
		flat.append(stepify(float(n[0]), 0.0001))
		flat.append(stepify(float(n[1]), 0.0001))
		flat.append(stepify(float(n[2]), 0.001))
	return {
		"version": 1, "title": title, "mapper": mapper, "difficulty": difficulty,
		"bpm": bpm, "offset": offset, "audio_file": audio_file, "has_cover": has_cover,
		"map_id": map_id, "source_id": source_id, "overwrite_source": overwrite_source,
		"modified": modified, "notes": flat,
	}

func save() -> bool:
	var d = Directory.new()
	d.make_dir_recursive(dir())
	modified = OS.get_unix_time()
	var f = File.new()
	var tmp: String = dir().plus_file("project.json.tmp")
	if f.open(tmp, File.WRITE) != OK:
		return false
	f.store_string(to_json(to_dict()))
	f.close()
	var path: String = dir().plus_file("project.json")
	if d.file_exists(path):
		d.remove(path)
	return d.rename(tmp, path) == OK

static func load_project(project_id: String):
	var f = File.new()
	var path: String = root_dir().plus_file(project_id).plus_file("project.json")
	if f.open(path, File.READ) != OK:
		return null
	var p = JSON.parse(f.get_as_text())
	f.close()
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = p.result
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.pid = project_id
	pr.title = Globals.s(d.get("title", ""))
	pr.mapper = Globals.s(d.get("mapper", ""))
	pr.difficulty = int(d.get("difficulty", -1))
	pr.bpm = float(d.get("bpm", 120.0))
	pr.offset = float(d.get("offset", 0.0))
	pr.audio_file = Globals.s(d.get("audio_file", ""))
	pr.has_cover = bool(d.get("has_cover", false))
	pr.map_id = Globals.s(d.get("map_id", ""))
	pr.source_id = Globals.s(d.get("source_id", ""))
	pr.overwrite_source = bool(d.get("overwrite_source", false))
	if pr.map_id == "":
		pr.map_id = "chromia_editor_" + project_id
	pr.modified = int(d.get("modified", 0))
	var flat = d.get("notes", [])
	if typeof(flat) == TYPE_ARRAY:
		var i := 0
		while i + 2 < flat.size():
			pr.notes.append([float(flat[i]), float(flat[i + 1]), float(flat[i + 2])])
			i += 3
	pr.sort_notes()
	return pr

# [{pid, title, mapper, notes, modified}] newest first
static func list_projects() -> Array:
	var out := []
	var d = Directory.new()
	if d.open(root_dir()) != OK:
		return out
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		if d.current_is_dir():
			var f = File.new()
			if f.open(root_dir().plus_file(n).plus_file("project.json"), File.READ) == OK:
				var p = JSON.parse(f.get_as_text())
				f.close()
				if p.error == OK and typeof(p.result) == TYPE_DICTIONARY:
					var r: Dictionary = p.result
					var nn = r.get("notes", [])
					out.append({
						"pid": n, "title": String(r.get("title", n)), "mapper": String(r.get("mapper", "")),
						"notes": (nn.size() / 3) if typeof(nn) == TYPE_ARRAY else 0,
						"modified": int(r.get("modified", 0)),
						"has_cover": bool(r.get("has_cover", false)),
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

# New project from an audio file. Returns the project, or an error String.
static func create(audio_src: String, map_title: String, map_mapper: String):
	var f = File.new()
	if f.open(audio_src, File.READ) != OK:
		return "Couldn't open the song file."
	var bytes: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	var ext := audio_ext(bytes)
	if ext == "":
		return "That song isn't an .mp3 or .ogg file."
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.title = map_title.strip_edges() if map_title.strip_edges() != "" else audio_src.get_file().get_basename()
	pr.mapper = map_mapper.strip_edges()
	pr.pid = _new_pid(pr.title)
	pr.map_id = "chromia_editor_" + pr.pid
	if not pr._write_audio(bytes, ext):
		return "Couldn't save the song into the editor folder."
	if not pr.save():
		return "Couldn't save the project."
	return pr

func _write_audio(bytes: PoolByteArray, ext: String) -> bool:
	var d = Directory.new()
	d.make_dir_recursive(dir())
	audio_file = "audio." + ext
	var f = File.new()
	if f.open(audio_path(), File.WRITE) != OK:
		return false
	f.store_buffer(bytes)
	f.close()
	return true

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
	var copy := []
	for n in src:
		copy.append([float(n[0]), float(n[1]), float(n[2])])
	Rhythia.unlock_song_notes(s)
	var pr = load("res://scripts/editor/EditorProject.gd").new()
	pr.title = Globals.s(s.name)
	pr.mapper = Globals.s(s.creator)
	pr.difficulty = int(s.difficulty)
	pr.pid = _new_pid(pr.title)
	# saved as a copy unless you choose to overwrite the original (Map tab)
	pr.map_id = "chromia_editor_" + pr.pid
	pr.source_id = Globals.s(s.id)
	pr.notes = copy
	pr.sort_notes()
	pr.guess_timing()
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
func export_to_maps():
	if notes.empty():
		return "Place at least one note first."
	var out_id := export_id()
	var s = Song.new(out_id, title if title != "" else pid, mapper if mapper != "" else "Unknown")
	s.songType = Globals.MAP_RAW
	s.musicFile = audio_path()
	s.difficulty = difficulty
	sort_notes()
	s.notes = copy_notes()
	s.note_count = s.notes.size()
	s.last_ms = length_ms()
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
			old_path = String(old.filePath)
	var res = s.convert_to_sspm(true)
	if res != "Converted!":
		return "Couldn't save the map: " + String(res)
	var new_path: String = Globals.p("user://maps/%s.sspm" % out_id)
	if old_path != "" and Globals.p(old_path) != new_path and (old_path.begins_with("user://maps") or old_path.begins_with(Globals.p("user://maps"))):
		Directory.new().remove(Globals.p(old_path))
	if Rhythia.registry_song:
		Rhythia.registry_song.check_and_remove_id(out_id)
		var added = Rhythia.registry_song.add_sspm_map(Globals.p("user://maps/%s.sspm" % out_id))
		if added:
			return added
	return "The map was saved but couldn't be loaded."

# ------------------------------------------------------------------ text (SSQE)

func to_text() -> String:
	var parts := PoolStringArray([export_id()])
	for n in notes:
		parts.append("%s|%s|%d" % [_num(2.0 - n[0]), _num(2.0 - n[1]), int(round(n[2]))])
	return parts.join(",")

static func _num(v: float) -> String:
	if abs(v - round(v)) < 0.00001:
		return str(int(round(v)))
	return str(stepify(v, 0.0001))

# Notes from SSQE / Sound Space text ("id,x|y|ms,..."). Returns them or null.
static func notes_from_text(t: String):
	var parts := t.strip_edges().split(",")
	if parts.size() < 2:
		return null
	var out := []
	for i in range(1, parts.size()):
		var p: PoolStringArray = parts[i].split("|")
		if p.size() != 3 or not p[0].is_valid_float() or not p[1].is_valid_float() or not p[2].is_valid_float():
			continue
		out.append([2.0 - float(p[0]), 2.0 - float(p[1]), float(p[2])])
	return out if not out.empty() else null
