extends Reference
# The other map files Sound Space Quantum Editor Plus opens (Mapping.Parse):
# Rewrite .phxm, Novastra .npk / .nch, SSQE .qem / .qemz, Pulsus .phz and
# Vulnus maps (a .zip with meta.json), ported from NewMaps/Parsing.
#
# read(path) -> {
#   "maps": [{"map": SSQEMap, "title": String}],  (Vulnus and .qemz can hold several)
#   "audio": PoolByteArray,   the song, if the file has it
#   "audio_url": String,      where to download it from (Pulsus), if not
#   "cover": PoolByteArray,   the cover, if any
#   "icon": PoolByteArray,    Novastra's mapper icon, if any
#   "error": String,          "" when it worked
# }

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")

const EXTENSIONS = ["phxm", "npk", "nch", "qem", "qemz", "phz", "zip", "json"]

static func result() -> Dictionary:
	return {"maps": [], "audio": PoolByteArray(), "audio_url": "", "cover": PoolByteArray(), "icon": PoolByteArray(), "error": ""}

static func fail(msg: String) -> Dictionary:
	var r := result()
	r.error = msg
	return r

static func read(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var bytes := _read_bytes(path)
	if bytes.empty():
		return fail("Couldn't read this file.")
	match ext:
		"phxm":
			return read_phxm(_unzip(bytes))
		"npk":
			return read_npk(_unzip(bytes))
		"nch":
			# a chart next to its metadata.json, lyrics and song (an unzipped .npk)
			return read_npk(_folder_files(path.get_base_dir(), {"chart.nch": bytes}))
		"qem":
			return read_qem(bytes, _folder_files(path.get_base_dir(), {}), path.get_file().get_basename())
		"qemz":
			return read_qemz(_unzip(bytes))
		"phz":
			var files := _unzip(bytes)
			for name in files:
				return _read_json_map(_val(files[name]), files, name)
			return fail("This .phz is empty.")
		"zip":
			var zf := _unzip(bytes)
			if zf.empty():
				return fail("This .zip couldn't be opened.")
			for name in zf:
				if name.get_file() == "meta.json":
					return read_vmap(_val(zf[name]), zf, name.get_base_dir())
			return fail("This .zip has no meta.json, so it isn't a Vulnus map.")
		"json":
			return _read_json_map(bytes, _folder_files(path.get_base_dir(), {}), path.get_file())
	return fail("This kind of file can't be opened.")

# a .json is a Pulsus or a Vulnus map
static func _read_json_map(bytes: PoolByteArray, files: Dictionary, name: String) -> Dictionary:
	var d = _json(bytes)
	if d is Dictionary:
		if d.has("beat") and d.has("song") and d.beat is Array:
			return read_phz(d)
		if d.has("_difficulties") and d.has("_music") and d.has("_version"):
			return read_vmap(bytes, files, name.get_base_dir())
	return fail("This .json isn't a Pulsus or Vulnus map.")

# ------------------------------------------------------------------ helpers

static func _read_bytes(path: String) -> PoolByteArray:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

static func _unzip(bytes: PoolByteArray) -> Dictionary:
	return load("res://scripts/content/ZipReader.gd").read(bytes)

# the map files in a folder (not sub-folders), plus `extra`. Values are the
# file's path until something reads it (_val), so a big Downloads folder
# isn't loaded just to open one map.
const FOLDER_EXTS = ["json", "nlr", "nch", "qem", "mp3", "ogg", "wav", "asset", "png", "jpg", "jpeg"]

static func _folder_files(dir_path: String, extra: Dictionary) -> Dictionary:
	var out := {}
	var d := Directory.new()
	if d.open(dir_path) == OK:
		d.list_dir_begin(true, true)
		var n := d.get_next()
		while n != "":
			if not d.current_is_dir() and n.get_extension().to_lower() in FOLDER_EXTS:
				out[n] = dir_path.plus_file(n)
			n = d.get_next()
		d.list_dir_end()
	for k in extra:
		out[k] = extra[k]
	return out

# a file's bytes (reads it if it's still a path)
static func _val(v) -> PoolByteArray:
	if v is PoolByteArray:
		return v
	if v is String:
		return _read_bytes(v)
	return PoolByteArray()

static func _json(bytes: PoolByteArray):
	var t := bytes.get_string_from_utf8()
	if t.begins_with("﻿"):
		t = t.substr(1)
	var p := JSON.parse(t)
	return p.result if p.error == OK else null

static func _find(files: Dictionary, name: String):
	if name == "":
		return null
	for k in files:
		if k == name or k.get_file() == name:
			return _val(files[k])
	return null

static func _s(v) -> String:
	return "" if v == null else String(v)

# Text.GetFixedString: the .txt can't hold these in a text object
static func fix_text(t: String) -> String:
	return t.replace("/", "_").replace("`", "_").replace("|", "_").replace(",", "_")

static func fix_ascii(s: String) -> String:
	var out := ""
	for c in s:
		var o := ord(c)
		if o >= 0x20 and o <= 0x7e:
			out += c
	return out

static func _num(v) -> String:
	# numbers as SSQE writes them in its .txt (no trailing .0)
	var f := float(v)
	if f == int(f):
		return str(int(f))
	return str(f)

static func _difficulty_name(i: int) -> String:
	return SSQEMap.DIFFICULTIES[i] if i >= 0 and i < SSQEMap.DIFFICULTIES.size() else "N/A"

static func _set_song_name(m):
	var a := SSQEMap.ss(m.props.songArtist).replace("\n", ", ")
	var t := SSQEMap.ss(m.props.songTitle)
	m.props.songName = "%s - %s" % [a, t] if a != "" else t

static func _add(m, o):
	if o == null:
		return
	if o.id == 0:
		m.notes.add(o)
	elif o.id == 1:
		m.timing_points.append(o)
	elif o.id == 17:
		m.bookmarks.append(o)
	elif F.is_vfx(o.id):
		m.vfx_objects.add(o)
	else:
		m.special_objects.add(o)

static func _finish(m):
	m.sort_all()

static func _image_ext(b: PoolByteArray) -> bool:
	return b.size() > 4 and ((b[0] == 0x89 and b[1] == 0x50) or (b[0] == 0xff and b[1] == 0xd8))

static func _is_audio_name(n: String) -> bool:
	return n.get_extension().to_lower() in ["mp3", "ogg", "wav", "asset"]

# ------------------------------------------------------------------ Rewrite .phxm (PHXM.Read)

static func read_phxm(files: Dictionary) -> Dictionary:
	var meta = _json(_find(files, "metadata.json") if _find(files, "metadata.json") != null else PoolByteArray())
	var objects = _find(files, "objects.phxmo")
	if not (meta is Dictionary) or objects == null:
		return fail("This .phxm is missing its metadata.json or objects.phxmo.")
	var r := result()
	var m = SSQEMap.new()
	var artist := _s(meta.get("Artist", ""))
	var title := _s(meta.get("Title", ""))
	m.props.songArtist = artist
	m.props.romanizedArtist = fix_ascii(artist)
	m.props.songTitle = title
	m.props.romanizedTitle = fix_ascii(title)
	m.props.difficulty = _difficulty_name(int(meta.get("Difficulty", 0)))
	m.props.customDifficulty = _s(meta.get("DifficultyName", ""))
	var mappers = meta.get("Mappers", [])
	m.props.mappers = PoolStringArray(mappers).join("\n") if mappers is Array else _s(mappers)
	m.props.rating = float(meta.get("Rating", 0))
	m.props.phxmPlatform = _s(meta.get("ArtistPlatform", ""))
	m.artist_links = {artist: _s(meta.get("ArtistLink", ""))}
	m.sound_id = _s(meta.get("ID", ""))
	if m.sound_id == "":
		m.sound_id = F.fix_id(title)
	_set_song_name(m)
	if bool(meta.get("HasAudio", true)):
		var a = _find(files, "audio." + _s(meta.get("AudioExt", "")))
		if a == null:
			for k in files:
				if k.get_file().begins_with("audio."):
					a = _val(files[k])
		if a != null:
			r.audio = a
	var cover = _find(files, "cover.png")
	if bool(meta.get("HasCover", false)) and cover != null:
		r.cover = cover
		m.props.useCover = true
	var sp := StreamPeerBuffer.new()
	sp.data_array = objects
	var types := sp.get_32()
	var count := sp.get_32()
	for _i in range(count):
		if sp.get_position() >= sp.get_size():
			break
		var ms := sp.get_u32()
		var quantum := sp.get_u8() != 0
		var x: float
		var y: float
		if quantum:
			x = 1.0 - sp.get_float()
			y = sp.get_float() + 1.0
		else:
			x = 2.0 - sp.get_u8()
			y = float(sp.get_u8())
		m.notes.add(SSQEMap.note(x, y, ms))
	for id in range(2, types + 1):
		if sp.get_position() + 4 > sp.get_size():
			break
		var n := sp.get_32()
		for _j in range(n):
			var oms := sp.get_u32()
			var data = _phxm_object(sp, id)
			if id == 12:
				_add(m, SSQEMap.beat(oms))
			elif data is Array and id >= 2 and id <= 11:
				_add(m, SSQEMap.raw_object(id, oms, data))
	_finish(m)
	r.maps.append({"map": m, "title": title if title != "" else m.sound_id})
	return r

# PHXM.ParseObject: an object's data after its time, in the .txt order
static func _phxm_object(sp: StreamPeerBuffer, id: int):
	match id:
		2, 3, 4, 5, 6, 9:
			var dur := sp.get_u32()
			var st := sp.get_u8()
			var di := sp.get_u8()
			return [str(dur), str(st), str(di), _num(sp.get_float())]
		7:
			var dur := sp.get_u32()
			var st := sp.get_u8()
			var di := sp.get_u8()
			var r := sp.get_u8()
			var g := sp.get_u8()
			var b := sp.get_u8()
			return [str(dur), str(st), str(di), str(r), str(g), str(b)]
		8:
			var dur := sp.get_u32()
			var st := sp.get_u8()
			var di := sp.get_u8()
			var px := sp.get_float()
			var py := sp.get_float()
			var pz := sp.get_float()
			return [str(dur), str(st), str(di), _num(px), _num(py), _num(pz)]
		10:
			return ["0", "0", "0", _num(sp.get_float())]
		11:
			var dur := sp.get_u32()
			var l := sp.get_u16()
			var t: String = sp.get_data(l)[1].get_string_from_utf8() if l > 0 else ""
			var strength := sp.get_u8()
			return [str(dur), fix_text(t), str(strength)]
	return null

# ------------------------------------------------------------------ Novastra .npk / .nch (NPK.Read)

static func read_npk(files: Dictionary) -> Dictionary:
	var chart = _find(files, "chart.nch")
	if chart == null:
		for k in files:
			if k.get_extension().to_lower() == "nch":
				chart = _val(files[k])
	if chart == null:
		return fail("This Novastra map has no chart.nch.")
	var mb = _find(files, "metadata.json")
	var meta = _json(mb) if mb != null else {}
	if not (meta is Dictionary):
		meta = {}
	var version := int(meta.get("formatVersion", 1))
	if version < 1 or version > 2:
		return fail("This Novastra map is a newer version (%d) than the editor can read." % version)
	var r := result()
	var m = SSQEMap.new()
	m.props.songTitle = _s(meta.get("songTitle", ""))
	m.props.songArtist = _s(meta.get("songArtist", ""))
	m.props.romanizedTitle = fix_ascii(m.props.songTitle)
	m.props.romanizedArtist = fix_ascii(m.props.songArtist)
	m.props.mapCreator = _s(meta.get("mapCreator", ""))
	m.props.mapCreatorPersonalLink = _s(meta.get("mapCreatorPersonalLink", ""))
	if meta.get("previewStartTime") != null:
		m.props.previewStartTime = str(int(float(meta.previewStartTime) * 1000.0))
	if meta.get("previewDuration") != null:
		m.props.previewDuration = str(int(float(meta.previewDuration) * 1000.0))
	m.props.mappers = m.props.mapCreator
	_set_song_name(m)
	# the song, cover and mapper icon sit next to the chart
	for k in files:
		var fn: String = k.get_file()
		var base := fn.get_basename()
		var e := fn.get_extension().to_lower()
		if e in ["mp3", "ogg", "wav"]:
			r.audio = _val(files[k])
			m.sound_id = base
		elif e in ["png", "jpg", "jpeg"]:
			if base == "profile":
				r.icon = _val(files[k])
			else:
				r.cover = _val(files[k])
				m.props.useCover = true
		elif e == "nlr":
			if version == 1:
				_nlr_v1(m, _val(files[k]).get_string_from_utf8())
			else:
				_nlr_v2(m, _val(files[k]).get_string_from_utf8())
	if SSQEMap.ss(m.sound_id) == "":
		m.sound_id = F.fix_id(m.props.songName)
	var c = _json(chart)
	if not (c is Dictionary):
		return fail("This Novastra chart couldn't be read.")
	if c.get("songOffset") != null:
		m.props.songOffset = _num(c.songOffset)
	var last_ms := 0
	for n in c.get("notes", []):
		if not (n is Dictionary):
			continue
		var x := 1.0 - float(n.get("x", 0))
		var y := float(n.get("y", 0)) + 1.0
		var t := int(n.get("t", 0))
		if bool(n.get("m", false)):
			_add(m, SSQEMap.mine(x, y, t))
		else:
			var e = n.get("e")
			if version >= 2 and e is Dictionary:
				_add(m, SSQEMap.note(x, y, t, true, int(e.get("s", 0)), int(e.get("d", 0))))
			else:
				_add(m, SSQEMap.note(x, y, t))
		last_ms = int(max(last_ms, t))
	for b in c.get("beats", []):
		if b is Dictionary:
			_add(m, SSQEMap.beat(int(b.get("t", 0))))
			last_ms = int(max(last_ms, int(b.get("t", 0))))
	for g in c.get("glides", []):
		if g is Dictionary:
			var dirs := {"up": 0, "right": 1, "down": 2, "left": 3}
			_add(m, SSQEMap.glide(int(g.get("t", 0)), dirs.get(_s(g.get("d", "none")), 4)))
			last_ms = int(max(last_ms, int(g.get("t", 0))))
	if version >= 2:
		var fever_start := -1
		for ev in c.get("events", []):
			if not (ev is Dictionary):
				continue
			var t := int(ev.get("t", 0))
			match _s(ev.get("type", "")):
				"fever":
					if bool(ev.get("active", false)):
						fever_start = t
					elif fever_start >= 0:
						_add(m, SSQEMap.fever(fever_start, t - fever_start))
						fever_start = -1
				"tempo":
					var bpm := float(ev.get("bpm", 0))
					if bpm > 0:
						_add(m, SSQEMap.timing_point(bpm, t))
		if fever_start >= 0:
			_add(m, SSQEMap.fever(fever_start, last_ms - fever_start))
	_finish(m)
	r.maps.append({"map": m, "title": m.props.songTitle if m.props.songTitle != "" else m.sound_id})
	return r

# v2 lyrics: "ms|properties|text"
static func _nlr_v2(m, text: String):
	for line in text.split("\n"):
		var sp: PoolStringArray = line.strip_edges(false, true).split("|")
		if sp.size() < 3:
			continue
		var ms := int(sp[0].split(".")[0])
		var props := sp[1]
		var t := PoolStringArray(Array(sp).slice(2, sp.size() - 1)).join("|")
		if "r" in props and t.strip_edges() != "":
			t = "-" + t
		if "n" in props:
			t = t + "-"
		_add(m, SSQEMap.lyric(ms, t, "i" in props, "o" in props))

# v1 lyrics: "[mm:ss.xx] text"
static func _nlr_v1(m, text: String):
	var prev = null
	for line in text.split("\n"):
		line = line.strip_edges()
		if line == "":
			continue
		var space: int = line.find(" ")
		if space < 0:
			continue
		var stamp: String = line.substr(0, space)
		var t: String = line.substr(space + 1)
		if t.strip_edges() == "" or stamp.length() < 3:
			continue
		stamp = stamp.substr(1, stamp.length() - 2)
		var comp: PoolStringArray = stamp.split(".")
		var ms_sec: PoolStringArray = comp[0].split(":")
		if ms_sec.size() < 2:
			continue
		var ms := int(ms_sec[0]) * 60000 + int(ms_sec[1]) * 1000 + (int(comp[1]) if comp.size() > 1 else 0)
		if t == "...>" and prev != null:
			prev.fade_out = true
			if prev.ms != ms:
				prev = SSQEMap.lyric(ms, "", false, false)
				_add(m, prev)
			continue
		elif t == "..." and prev != null and prev.ms != ms:
			prev = SSQEMap.lyric(ms, "", false, false)
		elif t.begins_with("->"):
			prev = SSQEMap.lyric(ms, "-" + t.substr(2), true, false)
		else:
			prev = SSQEMap.lyric(ms, t, false, false)
		_add(m, prev)

# ------------------------------------------------------------------ SSQE .qem / .qemz (QEM.Read)

static func read_qemz(files: Dictionary) -> Dictionary:
	var r := result()
	for k in files:
		if k.get_extension().to_lower() == "qem":
			var one := read_qem(_val(files[k]), files, k.get_file().get_basename())
			if one.error != "":
				return one
			r.maps += one.maps
			if r.audio.empty():
				r.audio = one.audio
			if r.cover.empty():
				r.cover = one.cover
	if r.maps.empty():
		return fail("This .qemz has no map in it.")
	return r

static func read_qem(bytes: PoolByteArray, files: Dictionary, fallback_title: String) -> Dictionary:
	var sp := StreamPeerBuffer.new()
	sp.data_array = bytes
	if bytes.size() < 6 or bytes.subarray(0, 3).get_string_from_ascii() != "IQEM":
		return fail("This isn't a QEM map (its first bytes are wrong).")
	sp.seek(4)
	if sp.get_16() != 0:
		return fail("This QEM map is a newer version than the editor can read.")
	var r := result()
	var m = SSQEMap.new()
	var q := QemReader.new(sp)
	# paths: the song, cover and video, next to the map (or in the .qemz)
	var audio_name := ""
	for _i in range(sp.get_16()):
		var key: String = q.string()
		var value: String = q.string()
		var data = _find(files, value.replace("\\", "/").get_file())
		if data == null:
			# an absolute path from the mapper's computer
			var f := File.new()
			if f.file_exists(value):
				data = _read_bytes(value)
		if data == null:
			continue
		match key:
			"audio":
				r.audio = data
				audio_name = value
			"cover":
				r.cover = data
				m.props.useCover = true
	var map_id := ""
	for _i in range(sp.get_16()):
		var field: String = q.string()
		var v = q.value(sp.get_u8())
		match field:
			"title":
				m.props.songTitle = _s(v)
			"romanizedTitle":
				m.props.romanizedTitle = _s(v)
			"artists":
				m.props.songArtist = PoolStringArray(v if v is Array else []).join("\n")
			"romanizedArtists":
				m.props.romanizedArtist = PoolStringArray(v if v is Array else []).join("\n")
			"mappers":
				m.props.mappers = PoolStringArray(v if v is Array else []).join("\n")
			"difficulty":
				m.props.difficulty = _difficulty_name(int(v))
			"difficultyStars":
				m.props.rating = float(v)
			"difficultyName":
				m.props.customDifficulty = _s(v)
			"songLinks":
				if v is Array:
					for l in v:
						m.song_links.append(_s(l))
			"artistLinks":
				if v is Dictionary:
					for k in v:
						m.artist_links[_s(k)] = _s(v[k])
			"mapperIds":
				if v is Dictionary:
					for k in v:
						m.mapper_ids[_s(k)] = int(v[k])
			"mapId":
				map_id = _s(v)
	m.sound_id = map_id if map_id != "" else F.fix_id(fallback_title)
	_set_song_name(m)
	# objects: a block per object id, each with its field types
	for _i in range(sp.get_u8()):
		var id := sp.get_u8()
		var obj_name: String = q.string()
		var types := []
		for _j in range(sp.get_u8()):
			types.append(sp.get_u8())
		var n := sp.get_32()
		for _j in range(n):
			var ms := int(sp.get_double())
			var d := []
			for t in types:
				d.append(q.value(t))
			if obj_name.strip_edges() == "" and id < 18:
				_add(m, _qem_object(id, ms, d))
		if q.bad:
			return fail("This QEM map is damaged.")
	_finish(m)
	var title := SSQEMap.ss(m.props.songTitle)
	r.maps.append({"map": m, "title": title if title != "" else fallback_title})
	return r

# QEM.ParseObj (d: the fields after the time, defaults for missing ones)
static func _qem_object(id: int, ms: int, d: Array):
	var defaults := {0: [1.0, 1.0, false, 0, 0], 1: [0.0, 4, 4], 2: [0, 0, 0, 1.0], 7: [0, 0, 0, 0, 0, 0, 0],
		8: [0, 0, 0, 0.0, 0.0, 0.0], 9: [0, 0, 0, 0.0], 11: [0, "", 0], 13: [0], 14: [0.0, 0.0], 15: ["", false, false], 16: [0], 17: [0, ""]}
	var dd: Array = defaults.get(id, defaults[2] if id >= 2 and id <= 10 else [])
	var a := d.duplicate()
	while a.size() < dd.size():
		a.append(dd[a.size()])
	match id:
		0: return SSQEMap.note(float(a[0]), float(a[1]), ms, bool(a[2]), int(a[3]), int(a[4]))
		1: return SSQEMap.timing_point(float(a[0]), ms)
		2, 3, 4, 5, 6, 9, 10: return SSQEMap.raw_object(id, ms, [str(int(a[0])), str(int(a[1])), str(int(a[2])), _num(a[3])])
		7: return SSQEMap.raw_object(id, ms, [str(int(a[0])), str(int(a[1])), str(int(a[2])), str(int(a[4])), str(int(a[5])), str(int(a[6]))])
		8: return SSQEMap.raw_object(id, ms, [str(int(a[0])), str(int(a[1])), str(int(a[2])), _num(a[3]), _num(a[4]), _num(a[5])])
		11: return SSQEMap.raw_object(id, ms, [str(int(a[0])), fix_text(_s(a[1])), str(int(a[2]))])
		12: return SSQEMap.beat(ms)
		13: return SSQEMap.glide(ms, int(a[0]))
		14: return SSQEMap.mine(float(a[0]), float(a[1]), ms)
		15: return SSQEMap.lyric(ms, _s(a[0]), bool(a[1]), bool(a[2]))
		16: return SSQEMap.fever(ms, int(a[0]))
		17: return SSQEMap.bookmark(_s(a[1]), ms, ms + int(a[0]))
	return null

# QEM's typed fields
class QemReader:
	var sp: StreamPeerBuffer
	var bad := false

	func _init(s: StreamPeerBuffer):
		sp = s

	func _bytes(n: int) -> PoolByteArray:
		if n <= 0:
			return PoolByteArray()
		if sp.get_position() + n > sp.get_size():
			bad = true
			sp.seek(sp.get_size())
			return PoolByteArray()
		return sp.get_data(n)[1]

	func string() -> String:
		return _bytes(sp.get_16()).get_string_from_utf8()

	func value(t: int):
		if sp.get_position() >= sp.get_size():
			bad = true
			return 0
		match t:
			0: return sp.get_u8()
			1: return sp.get_16()
			2: return sp.get_u16()
			3: return sp.get_32()
			4: return sp.get_u32()
			5: return sp.get_64()
			6: return sp.get_u64()
			7: return sp.get_float()
			8: return sp.get_double()
			9: return sp.get_u8() != 0
			10: return _bytes(sp.get_16()).get_string_from_utf8()
			11: return _bytes(sp.get_32()).get_string_from_utf8()
			12: return _bytes(sp.get_16())
			13: return _bytes(sp.get_32())
			14, 15:
				var n: int = sp.get_16() if t == 14 else sp.get_32()
				var et := sp.get_u8()
				var arr := []
				for _i in range(n):
					arr.append(value(et))
					if bad:
						break
				return arr
			16, 17:
				var n: int = sp.get_16() if t == 16 else sp.get_32()
				var kt := sp.get_u8()
				var vt := sp.get_u8()
				var d := {}
				for _i in range(n):
					var k = value(kt)
					d[k] = value(vt)
					if bad:
						break
				return d
			18:
				var n := sp.get_u8()
				var arr := []
				for _i in range(n):
					arr.append(value(sp.get_u8()))
				return arr
		bad = true
		return 0

# ------------------------------------------------------------------ Pulsus .phz (PHZ.Read)

static func read_phz(d: Dictionary) -> Dictionary:
	var r := result()
	var m = SSQEMap.new()
	var bpm := float(d.get("bpm", 120))
	if bpm <= 0:
		bpm = 120.0
	var song = d.get("song", "processing")
	var id := str(int(song)) if typeof(song) == TYPE_REAL or typeof(song) == TYPE_INT else _s(song)
	var offset := float(d.get("songOffset", 0)) / 1000.0
	m.sound_id = id
	for b in d.get("beat", []):
		if b is Array and b.size() >= 2:
			var tile := int(b[0])
			var t := float(b[1]) / (bpm / 60.0) + offset
			m.notes.add(SSQEMap.note(2.0 - tile % 3, 2.0 - int(tile / 3), int(t * 1000.0)))
	_finish(m)
	r.audio_url = "https://pulsus.cc/play/client/s/%s.mp3" % id
	r.maps.append({"map": m, "title": "Pulsus " + id})
	return r

# ------------------------------------------------------------------ Vulnus maps (VMAP.Read)

static func read_vmap(meta_bytes: PoolByteArray, files: Dictionary, folder: String) -> Dictionary:
	var d = _json(meta_bytes)
	if not (d is Dictionary):
		return fail("This Vulnus map's meta.json couldn't be read.")
	if int(d.get("_version", 1)) != 1:
		return fail("This Vulnus map is version %d; only version 1 can be opened." % int(d._version))
	var r := result()
	var artist := _s(d.get("_artist", ""))
	var title := _s(d.get("_title", ""))
	var mappers = d.get("_mappers", [])
	var music = _find(files, (folder.plus_file(_s(d.get("_music", ""))) if folder != "" else _s(d.get("_music", ""))))
	if music == null:
		music = _find(files, _s(d.get("_music", "")).get_file())
	if music == null:
		return fail("This Vulnus map's song (%s) is missing." % _s(d.get("_music", "")))
	r.audio = music
	var cover = _find(files, "cover.png")
	if cover != null:
		r.cover = cover
	for diff in d.get("_difficulties", []):
		var mb = _find(files, folder.plus_file(_s(diff)) if folder != "" else _s(diff))
		if mb == null:
			mb = _find(files, _s(diff).get_file())
		var md = _json(mb) if mb != null else null
		if not (md is Dictionary):
			continue
		var m = SSQEMap.new()
		m.props.songArtist = artist
		m.props.romanizedArtist = artist
		m.props.songTitle = title
		m.props.romanizedTitle = title
		m.props.mappers = PoolStringArray(mappers if mappers is Array else []).join("\n")
		m.props.useCover = cover != null
		_set_song_name(m)
		var dname := _s(md.get("_name", ""))
		if dname in SSQEMap.DIFFICULTIES:
			m.props.difficulty = dname
		else:
			m.props.customDifficulty = dname
		m.sound_id = F.fix_id("%s - %s - %s" % [artist, title, _s(diff).get_file().get_basename()])
		for n in md.get("_notes", []):
			if n is Dictionary and n.get("_time") != null and n.get("_x") != null and n.get("_y") != null:
				m.notes.add(SSQEMap.note(float(n._x) + 1.0, float(n._y) + 1.0, int(float(n._time) * 1000.0)))
		_finish(m)
		var t: String = title if dname == "" else "%s [%s]" % [title, dname]
		r.maps.append({"map": m, "title": t})
	if r.maps.empty():
		return fail("This Vulnus map has no difficulties that could be read.")
	return r
