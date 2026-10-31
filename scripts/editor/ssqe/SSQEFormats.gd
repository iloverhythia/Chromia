extends Reference
# Map files for the map editor, ported from Sound Space Quantum Editor Plus
# (Web Editor/js/formats.js: TXT.cs, INI.cs, SSPM.cs, OSU.cs, PHXM.cs):
# the editor's own .txt + .ini pair, SSPM v2, Rhythia .rhm and Rewrite .phxm
# (both zips), and osu! maps.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")

# true: vfx, false: special
const VFX_LOOKUP = [false, false, true, true, true, true, true, true, true, true, true, true, false, false, false, false, false, false]

static func is_vfx(id: int) -> bool:
	return id >= 0 and id < VFX_LOOKUP.size() and VFX_LOOKUP[id]

static func fix_id(id: String) -> String:
	var out := ""
	for c in id:
		if (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or c == "-":
			out += c
		elif c >= "A" and c <= "Z":
			out += c.to_lower()
		else:
			out += "_"
	return out

# TXT.ReadObjects: splits on "," and "|", honouring "quoted \"strings\""
static func read_objects(data: String) -> Array:
	var result := []
	var obj := []
	var chars := ""
	var escaped := false
	var quoted := false
	for c in data:
		if quoted:
			if escaped:
				escaped = false
				chars += c
				continue
			if c == "\\":
				escaped = true
			elif c == "\"":
				quoted = false
			else:
				chars += c
		else:
			if c == "\"":
				quoted = true
			elif c == "|":
				obj.append(chars)
				chars = ""
			elif c == ",":
				obj.append(chars)
				chars = ""
				result.append(obj)
				obj = []
			else:
				chars += c
	obj.append(chars)
	result.append(obj)
	return result

# fast path for plain "id,x|y|ms,..." text (no quotes): String.split is far quicker
static func _read_plain(data: String) -> Array:
	var result := []
	for part in data.split(","):
		result.append(Array(part.split("|")))
	return result

# TXT.ReadData. Returns "" or an error.
static func read_txt(map, data: String) -> String:
	var split := data.split("`")
	if split.size() == 1:
		var map_data := _read_plain(split[0].strip_edges()) if split[0].find("\"") == -1 else read_objects(split[0].strip_edges())
		if map_data.empty():
			return "This isn't map data"
		map.sound_id = SSQEMap.ss(map_data[0][0]).strip_edges()
		for i in range(1, map_data.size()):
			var sub: Array = map_data[i]
			if PoolStringArray(sub).join("|").strip_edges() == "":
				continue
			if sub.size() < 3 or not SSQEMap._is_num(sub[0]) or not SSQEMap._is_num(sub[1]) or not SSQEMap._is_num(sub[2]):
				return "Note failed to parse: " + PoolStringArray(sub).join("|")
			map.notes.add(SSQEMap.note(float(sub[0]), float(sub[1]), int(float(sub[2]))))
		return ""
	if split[0] != "ssmapv2":
		return "Map format not supported - " + split[0]
	if split.size() < 5:
		return "Broken map data"
	map.sound_id = split[1]
	var di := int(split[2])
	var diff_name: String = SSQEMap.DIFFICULTIES[di] if di >= 0 and di < SSQEMap.DIFFICULTIES.size() else "N/A"
	map.props.difficulty = diff_name
	map.props.customDifficulty = "" if split[3] == diff_name else split[3]
	var sets := split[4].split("/")
	for i in range(sets.size()):
		if sets[i].strip_edges() == "":
			continue
		var total := 0
		var delta := 0
		for fields in read_objects(sets[i]):
			var o = SSQEMap.parse_object(i, fields)
			if o == null:
				continue
			delta += o.ms
			total += delta
			o.ms = total
			if o.id == 0:
				map.notes.add(o)
			elif o.id == 1:
				map.timing_points.append(o)
			elif is_vfx(i):
				map.vfx_objects.add(o)
			else:
				map.special_objects.add(o)
	return ""

# TXT.CopyLegacy (what the editor saves and copies)
static func write_txt(map, correct_notes := false) -> String:
	map.notes.sort()
	var offset := int(map.props.exportOffset)
	var final := PoolStringArray([SSQEMap.ss(map.sound_id).replace(",", "")])
	for n in map.notes.items:
		var x: float = n.x
		var y: float = n.y
		var ms: int = n.ms + offset
		if correct_notes:
			x = clamp(x, -0.85, 2.85)
			y = clamp(y, -0.85, 2.85)
			ms = int(clamp(ms, 0, map.duration))
		final.append("%s|%s|%d" % [SSQEMap.fmt(x), SSQEMap.fmt(y), ms])
	return final.join(",")

# notes are kept without the export offset
static func set_export_offset(map, offset: int):
	for n in map.notes.items:
		n.ms += int(map.props.exportOffset)
	map.props.exportOffset = offset
	for n in map.notes.items:
		n.ms -= int(map.props.exportOffset)

# INI.ReadLegacy
static func read_ini_legacy(map, data: String):
	var old_ver := false
	for line in data.split("\n"):
		var sp: PoolStringArray = line.split("=")
		var value: String = sp[1].strip_edges() if sp.size() > 1 else ""
		match sp[0].strip_edges():
			"BPM":
				for point in value.split(","):
					var ps: PoolStringArray = point.split("|")
					if ps.size() == 1:
						ps = PoolStringArray([ps[0], "0"])
						old_ver = true
					if ps.size() == 2 and SSQEMap._is_num(ps[0]) and SSQEMap._is_num(ps[1]):
						map.timing_points.append(SSQEMap.timing_point(float(ps[0]), int(ps[1])))
				map.sort_timings()
			"Bookmarks":
				for b in value.split(","):
					var bs: PoolStringArray = b.split("|")
					if bs.size() == 2 and bs[1].is_valid_integer():
						map.bookmarks.append(SSQEMap.bookmark(bs[0], int(bs[1]), int(bs[1])))
					elif bs.size() == 3 and bs[1].is_valid_integer() and bs[2].is_valid_integer():
						map.bookmarks.append(SSQEMap.bookmark(bs[0], int(bs[1]), int(bs[2])))
				map.sort_bookmarks()
			"Offset":
				if value.is_valid_integer():
					if old_ver:
						if not map.timing_points.empty():
							map.timing_points[0].ms = int(value)
					else:
						set_export_offset(map, int(value))
			"Time":
				if value.is_valid_integer():
					map.current_time = int(value)
			"Divisor":
				if SSQEMap._is_num(value):
					map.beat_divisor = float(value) - 1.0

const STRING_PROPS = ["mappers", "songName", "difficulty", "cover", "customDifficulty", "songOffset", "songTitle", "songArtist",
	"romanizedTitle", "romanizedArtist", "mapCreator", "mapCreatorPersonalLink", "previewStartTime", "previewDuration",
	"novaCover", "novaIcon", "phxmPlatform", "video"]

# INI.Read
static func read_ini(map, data: String):
	var p = JSON.parse(data)
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		read_ini_legacy(map, data)
		return
	var json: Dictionary = p.result
	map.timing_points = []
	map.bookmarks = []
	for key in json:
		var value = json[key]
		match key:
			"songLinks":
				map.song_links = value if value != null else []
			"artistLinks":
				map.artist_links = value if value != null else {}
			"mapperIds":
				map.mapper_ids = value if value != null else {}
			"timings":
				if value is Array:
					for t in value:
						if t is Array and t.size() >= 2:
							map.timing_points.append(SSQEMap.timing_point(float(t[0]), int(float(t[1]))))
			"bookmarks":
				if value is Array:
					for b in value:
						if b is Array and b.size() >= 2:
							map.bookmarks.append(SSQEMap.bookmark(Globals.s(b[0]), int(float(b[1])), int(float(b[b.size() - 1]))))
			"vfxObjects", "specialObjects":
				var list = map.vfx_objects if key == "vfxObjects" else map.special_objects
				list.items = []
				if value is Array:
					for s in value:
						var o = SSQEMap.parse_object(-1, read_objects(SSQEMap.ss(s))[0])
						if o:
							list.add(o)
				list.sort()
			"noteData":
				map.notes.sort()
				if value is Array:
					for nd in value:
						if nd is Array and nd.size() >= 3:
							var idx := int(nd[0])
							if idx >= 0 and idx < map.notes.items.size():
								var n = map.notes.items[idx]
								n.enable_easing = true
								n.style = int(nd[1])
								n.direction = int(nd[2])
			"currentTime":
				map.current_time = float(value) if value != null else 0.0
			"beatDivisor":
				map.beat_divisor = float(value) if value != null else 3.0
			"exportOffset":
				set_export_offset(map, int(float(value)) if value != null else 0)
			"useCover", "useVideo":
				map.props[key] = bool(value)
			"rating":
				map.props.rating = float(value) if value != null else 0.0
			_:
				if key in STRING_PROPS:
					map.props[key] = "" if value == null else Globals.s(value)
	map.sort_timings()
	map.sort_bookmarks()
	map.clear_selected()

# INI.Write
static func write_ini(map) -> String:
	map.notes.sort()
	var note_data := []
	var i := 0
	for n in map.notes.items:
		if n.enable_easing:
			note_data.append([i, n.style, n.direction])
		i += 1
	var timings := []
	for t in map.timing_points:
		timings.append([t.bpm, t.ms])
	var bms := []
	for b in map.bookmarks:
		bms.append([b.text, b.ms, b.end_ms])
	var vfx := []
	for o in map.vfx_objects.items:
		vfx.append("%d|%s" % [o.id, o.to_text()])
	var special := []
	for o in map.special_objects.items:
		special.append("%d|%s" % [o.id, o.to_text()])
	var json := {
		"songLinks": map.song_links, "artistLinks": map.artist_links, "mapperIds": map.mapper_ids,
		"timings": timings, "bookmarks": bms, "vfxObjects": vfx, "specialObjects": special, "noteData": note_data,
		"currentTime": map.current_time, "beatDivisor": map.beat_divisor, "exportOffset": map.props.exportOffset,
	}
	for key in ["mappers", "songName", "difficulty", "useCover", "cover", "customDifficulty", "songOffset", "songTitle", "songArtist",
			"romanizedTitle", "romanizedArtist", "mapCreator", "mapCreatorPersonalLink", "previewStartTime", "previewDuration",
			"novaCover", "novaIcon", "phxmPlatform", "rating", "useVideo", "video"]:
		json[key] = map.props.get(key, "")
	return to_json(json)

# ---------------------------------------------------------------- binary helpers
# (StreamPeerBuffer: a PoolByteArray handed to a function is a copy)

static func _writer() -> StreamPeerBuffer:
	var w := StreamPeerBuffer.new()
	w.big_endian = false
	return w

static func _str16(w: StreamPeerBuffer, s: String):
	var u := s.to_utf8()
	w.put_u16(u.size())
	w.put_data(u)

static func _zeros(w: StreamPeerBuffer, n: int):
	var z := PoolByteArray()
	z.resize(n)
	for i in range(n):
		z[i] = 0
	w.put_data(z)

# SSPM.Write (v2) - meta: {songId, mapName, mappers (one per line), difficulty, customDifficulty}
static func write_sspm(map, meta: Dictionary, audio: PoolByteArray, cover: PoolByteArray) -> PoolByteArray:
	map.notes.sort()
	var export_offset := int(map.props.exportOffset)
	var notes := []
	for n in map.notes.items:
		if not is_nan(n.x) and not is_nan(n.y) and not is_inf(n.x) and not is_inf(n.y):
			notes.append(n)
	var w := _writer()
	w.put_data(PoolByteArray([0x53, 0x53, 0x2b, 0x6d, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]))
	_zeros(w, 20) # hash
	w.put_u32(int(max(0, round(notes[-1].ms + export_offset))) if not notes.empty() else 0)
	w.put_u32(notes.size())
	w.put_u32(notes.size())
	w.put_u8(int(max(0, SSQEMap.DIFFICULTIES.find(SSQEMap.ss(meta.difficulty)))))
	w.put_u16(0)
	w.put_u8(1)
	w.put_u8(1 if cover.size() > 0 else 0)
	w.put_u8(0)
	var pointer_at := w.get_position()
	_zeros(w, 80)
	_str16(w, SSQEMap.ss(meta.songId))
	_str16(w, SSQEMap.ss(meta.mapName))
	_str16(w, SSQEMap.ss(meta.mapName))
	var mappers: PoolStringArray = SSQEMap.ss(meta.mappers).split("\n")
	w.put_u16(mappers.size())
	for m in mappers:
		_str16(w, m)
	var custom_offset := 0
	var custom_length := 0
	if SSQEMap.ss(meta.customDifficulty).strip_edges() != "":
		custom_offset = w.get_position()
		w.put_u16(1)
		_str16(w, "difficulty_name")
		w.put_u8(0x09)
		_str16(w, SSQEMap.ss(meta.customDifficulty))
		custom_length = w.get_position() - custom_offset
	else:
		w.put_u16(0)
	var audio_offset := w.get_position()
	w.put_data(audio)
	var audio_length := audio.size()
	var cover_offset := 0
	var cover_length := 0
	if cover.size() > 0:
		cover_offset = w.get_position()
		w.put_data(cover)
		cover_length = cover.size()
	var def_offset := w.get_position()
	w.put_u8(0x01)
	_str16(w, "ssp_note")
	w.put_data(PoolByteArray([0x01, 0x07, 0x00]))
	var def_length := w.get_position() - def_offset
	var marker_offset := w.get_position()
	for n in notes:
		w.put_u32(int(max(0, round(n.ms + export_offset))))
		w.put_u8(0)
		var quantum: bool = round(n.x) != SSQEMap.round2(n.x) or round(n.y) != SSQEMap.round2(n.y)
		quantum = quantum or n.x < 0 or n.x > 2 or n.y < 0 or n.y > 2
		w.put_u8(1 if quantum else 0)
		if quantum:
			w.put_float(2.0 - n.x)
			w.put_float(2.0 - n.y)
		else:
			w.put_u8(int(round(2.0 - n.x)))
			w.put_u8(int(round(2.0 - n.y)))
	var marker_length := w.get_position() - marker_offset
	var end := w.get_position()
	w.seek(pointer_at)
	for v in [custom_offset, custom_length, audio_offset, audio_length, cover_offset, cover_length, def_offset, def_length, marker_offset, marker_length]:
		w.put_u64(v)
	w.seek(end)
	return w.data_array

# osu! map (OSU.cs). Returns the audio file name it refers to ("" if none).
static func read_osu(map, data: String) -> String:
	var timing := false
	var hit_obj := false
	var artist := ""
	var title := ""
	var audio_path := ""
	for raw in data.split("\n"):
		var line: String = raw.strip_edges()
		var sub := line.split(":")
		var set := line.split(",")
		if not timing and not hit_obj:
			var v := sub[1].strip_edges() if sub.size() > 1 else ""
			match sub[0]:
				"Artist": artist = v
				"Title": title = v
				"AudioFilename": audio_path = v
		if timing and line != "" and set.size() >= 2 and SSQEMap._is_num(set[0]) and SSQEMap._is_num(set[1]):
			var time := float(set[0])
			var bpm := float(set[1])
			var inherited: bool = set[6] == "1" if set.size() > 6 else bpm > 0
			bpm = abs(round(60000.0 / bpm * 1000.0) / 1000.0)
			if bpm > 0 and inherited:
				map.timing_points.append(SSQEMap.timing_point(bpm, int(time)))
		if hit_obj and line != "" and set.size() >= 4 and SSQEMap._is_num(set[0]) and SSQEMap._is_num(set[1]) and SSQEMap._is_num(set[2]) and set[3].is_valid_integer():
			var x := 5.0 - float(set[0]) / 64.0
			var y := 4.0 - float(set[1]) / 64.0
			if int(set[3]) & 1:
				map.notes.add(SSQEMap.note(x, y, int(float(set[2]))))
		timing = line != "[HitObjects]" and (timing or line == "[TimingPoints]")
		hit_obj = line != "[TimingPoints]" and (hit_obj or line == "[HitObjects]")
	if audio_path != "":
		map.sound_id = fix_id("%s - %s" % [artist, title])
	map.sort_timings()
	return audio_path

# ---------------------------------------------------------------- zip (stored entries)

static func crc32(data: PoolByteArray) -> int:
	var table := []
	table.resize(256)
	for n in range(256):
		var c := n
		for _k in range(8):
			c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
		table[n] = c
	var crc := 0xFFFFFFFF
	for b in data:
		crc = table[(crc ^ b) & 0xff] ^ (crc >> 8)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF

# files: [[name, PoolByteArray], ...] -> a zip with the files stored (no compression)
static func zip_files(files: Array) -> PoolByteArray:
	var out := _writer()
	var central := _writer()
	for f in files:
		var name: PoolByteArray = SSQEMap.ss(f[0]).to_utf8()
		var data: PoolByteArray = f[1]
		var crc := crc32(data)
		var local_at := out.get_position()
		out.put_u32(0x04034b50)
		out.put_u16(20)
		out.put_u16(0)
		out.put_u16(0)
		out.put_u16(0)
		out.put_u16(0x21)
		out.put_u32(crc)
		out.put_u32(data.size())
		out.put_u32(data.size())
		out.put_u16(name.size())
		out.put_u16(0)
		out.put_data(name)
		out.put_data(data)
		central.put_u32(0x02014b50)
		central.put_u16(20)
		central.put_u16(20)
		central.put_u16(0)
		central.put_u16(0)
		central.put_u16(0)
		central.put_u16(0x21)
		central.put_u32(crc)
		central.put_u32(data.size())
		central.put_u32(data.size())
		central.put_u16(name.size())
		central.put_u16(0)
		central.put_u16(0)
		central.put_u16(0)
		central.put_u16(0)
		central.put_u32(0)
		central.put_u32(local_at)
		central.put_data(name)
	var dir_at := out.get_position()
	var cd := central.data_array
	out.put_data(cd)
	out.put_u32(0x06054b50)
	out.put_u16(0)
	out.put_u16(0)
	out.put_u16(files.size())
	out.put_u16(files.size())
	out.put_u32(cd.size())
	out.put_u32(dir_at)
	out.put_u16(0)
	return out.data_array

# Rhythia .rhm "map" JSON. meta: {songId, mapName, mappers, difficulty, customDifficulty, duration}
static func write_rhm_map(map, meta: Dictionary) -> PoolByteArray:
	map.notes.sort()
	var export_offset := int(map.props.exportOffset)
	var mappers := []
	for m in SSQEMap.ss(meta.mappers).split("\n"):
		if m.strip_edges() != "":
			mappers.append(m.strip_edges())
	var notes := []
	for n in map.notes.items:
		notes.append({"Time": n.ms + export_offset, "X": stepify(2.0 - n.x, 0.000001), "Y": stepify(2.0 - n.y, 0.000001)})
	var tps := []
	for t in map.timing_points:
		tps.append({"OffsetMs": t.ms + export_offset, "Bpm": t.bpm})
	var dur: float = meta.get("duration", 0)
	if dur <= 0 and not notes.empty():
		dur = notes[-1].Time
	var cd := SSQEMap.ss(meta.customDifficulty).strip_edges()
	var data := {
		"OnlineId": null, "OnlineStatus": null, "LegacyId": null,
		"SongName": meta.mapName, "Mappers": mappers if not mappers.empty() else ["None"], "Title": meta.mapName,
		"Duration": int(round(dur)), "Difficulty": int(max(0, SSQEMap.DIFFICULTIES.find(SSQEMap.ss(meta.difficulty)))),
		"CustomDifficultyName": cd if cd != "" else null, "StarRating": 0, "Notes": notes,
		"AudioFileName": "%s.mp3" % meta.songId, "ImagePath": "cover", "AudioTimingMode": "Native", "TimingPoints": tps,
	}
	return to_json(data).to_utf8()

# Rewrite .phxm: metadata.json, objects.phxmo, the audio and the cover, zipped.
static func write_phxm(map, meta: Dictionary, audio: PoolByteArray, cover: PoolByteArray) -> PoolByteArray:
	var ext := "asset"
	if audio.size() >= 4 and audio[0] == 0x4f and audio[1] == 0x67 and audio[2] == 0x67 and audio[3] == 0x53:
		ext = "ogg"
	elif audio.size() >= 3 and ((audio[0] == 0x49 and audio[1] == 0x44 and audio[2] == 0x33) or (audio[0] == 0xff and (audio[1] & 0xe0) == 0xe0)):
		ext = "mp3"
	var ow := _writer()
	ow.put_32(12)
	ow.put_32(map.notes.items.size())
	for n in map.notes.items:
		var whole: bool = abs(n.x - round(n.x)) < 0.000001 and abs(n.y - round(n.y)) < 0.000001
		ow.put_u32(int(max(0, round(n.ms))))
		ow.put_u8(0 if whole else 1)
		if whole:
			ow.put_u8(int(2 - round(n.x)))
			ow.put_u8(int(round(n.y)))
		else:
			ow.put_float(1.0 - n.x)
			ow.put_float(n.y - 1.0)
	# object types 2-12: none (PHXM.Write writes 11 empty counts)
	for _i in range(11):
		ow.put_32(0)
	var obj := ow.data_array
	var mappers: PoolStringArray = SSQEMap.ss(meta.mappers).split("\n")
	var json := {
		"Artist": meta.get("artist", ""), "AudioExt": ext, "Difficulty": int(max(0, SSQEMap.DIFFICULTIES.find(SSQEMap.ss(meta.difficulty)))),
		"DifficultyName": meta.customDifficulty if SSQEMap.ss(meta.customDifficulty) != "" else meta.difficulty,
		"HasAudio": true, "HasCover": cover.size() > 0, "HasVideo": false,
		"ID": fix_id("%s - %s - %s" % [mappers[0] if mappers.size() > 0 and mappers[0] != "" else "None", meta.get("artist", ""), meta.get("title", "")]),
		"Mappers": Array(mappers), "Rating": float(meta.get("rating", 0)), "Title": meta.get("title", ""),
		"ArtistLink": meta.get("artistLink", ""), "ArtistPlatform": meta.get("artistPlatform", ""), "Length": int(round(meta.get("duration", 0))),
	}
	var files := [["metadata.json", JSON.print(json, "  ").to_utf8()], ["objects.phxmo", obj], ["audio." + ext, audio]]
	if cover.size() > 0:
		files.append(["cover.png", cover])
	return zip_files(files)

# ---------------------------------------------------------------- Novastra .npk (NPK.Write)

const GLIDE_NAMES = ["up", "right", "down", "left"]

# NPK.WriteNCH: the chart (song offset in ms, minus the export offset)
static func write_nch(map, song_offset: int) -> String:
	map.notes.sort()
	map.special_objects.sort()
	var notes := []
	for n in map.notes.items:
		var nd := {"x": 1.0 - n.x, "y": n.y - 1.0, "t": n.ms}
		if n.enable_easing:
			nd["e"] = {"s": n.style, "d": n.direction}
		notes.append(nd)
	var last_ms := 0
	if not map.notes.items.empty():
		last_ms = map.notes.items[-1].ms
	for o in map.special_objects.items:
		if o.id in [12, 13, 14]:
			last_ms = int(max(last_ms, o.ms))
	var beats := []
	var glides := []
	var events := []
	var prev_fever_end = null
	for o in map.special_objects.items:
		match o.id:
			12:
				beats.append({"t": o.ms})
			13:
				glides.append({"t": o.ms, "d": GLIDE_NAMES[o.direction] if o.direction >= 0 and o.direction < 4 else "none"})
			14:
				notes.append({"x": 1.0 - o.x, "y": o.y - 1.0, "t": o.ms, "m": true})
			16:
				if o.ms >= last_ms:
					continue
				var cur: int = int(max(prev_fever_end if prev_fever_end != null else 0, o.ms))
				prev_fever_end = o.ms + o.duration
				events.append({"type": "fever", "t": cur, "active": true})
				events.append({"type": "fever", "t": int(min(o.ms + o.duration, last_ms)), "active": false})
	for t in map.timing_points:
		events.append({"type": "tempo", "t": t.ms, "bpm": t.bpm})
	var chart := {
		"songOffset": song_offset - int(map.props.exportOffset),
		"notes": _by_t(notes), "beats": _by_t(beats), "glides": _by_t(glides), "events": _by_t(events),
	}
	return JSON.print(chart, "  ")

class _ByT:
	static func less(a, b) -> bool:
		if a.t != b.t:
			return a.t < b.t
		return a._i < b._i

# stable sort on "t" (like LINQ OrderBy)
static func _by_t(list: Array) -> Array:
	for i in range(list.size()):
		list[i]["_i"] = i
	list.sort_custom(_ByT, "less")
	for d in list:
		d.erase("_i")
	return list

# NPK.WriteNLR: "ms|properties|text" per lyric ("" when there are none)
static func write_nlr(map) -> String:
	var lines := PoolStringArray()
	for o in map.special_objects.items:
		if o.id != 15:
			continue
		var text: String = o.text
		var props := ""
		if text.strip_edges() == "" and not o.fade_out:
			props += "r"
		if text.begins_with("-"):
			props += "r"
			text = text.substr(1)
		if text.ends_with("-"):
			props += "n"
			text = text.substr(0, text.length() - 1)
		if o.fade_in:
			props += "i"
		if o.fade_out:
			props += "o"
		if props == "":
			props = "x"
		lines.append("%d|%s|%s" % [o.ms, props, text])
	return lines.join("\n")

static func image_ext(b: PoolByteArray) -> String:
	if b.size() > 3 and b[0] == 0xff and b[1] == 0xd8:
		return ".jpg"
	return ".png"

# meta: songTitle, songArtist, mapCreator, mapCreatorPersonalLink, songOffset,
# previewStartTime, previewDuration (ms). audio_ext: "mp3" or "ogg".
static func write_npk(map, meta: Dictionary, audio: PoolByteArray, audio_ext: String, cover: PoolByteArray, icon: PoolByteArray) -> PoolByteArray:
	var id := SSQEMap.ss(map.sound_id)
	if id == "" or id == "-1":
		id = fix_id("%s - %s" % [meta.songArtist, meta.songTitle])
	var files := []
	if not cover.empty():
		files.append([id + image_ext(cover), cover])
	if not icon.empty():
		files.append(["profile" + image_ext(icon), icon])
	files.append([id + "." + audio_ext, audio])
	files.append(["chart.nch", write_nch(map, int(meta.get("songOffset", 0))).to_utf8()])
	var md := {
		"songTitle": meta.songTitle, "songArtist": meta.songArtist,
		"mapCreator": meta.mapCreator, "mapCreatorPersonalLink": meta.mapCreatorPersonalLink,
		"previewStartTime": float(meta.get("previewStartTime", 0)) / 1000.0,
		"previewDuration": float(meta.get("previewDuration", 0)) / 1000.0,
		"formatVersion": 2, "ssqeVersion": "1.0.0.0",
	}
	files.append(["metadata.json", JSON.print(md, "  ").to_utf8()])
	var nlr := write_nlr(map)
	if nlr != "":
		files.append(["lyrics.nlr", nlr.to_utf8()])
	return zip_files(files)

# ---------------------------------------------------------------- SSQE .qem / .qemz (QEM.Write)

static func _qem_str(w: StreamPeerBuffer, s: String):
	# the byte length (SSQE+ writes the character count, which breaks non-English text)
	_str16(w, s)

static func _qem_str_array(w: StreamPeerBuffer, name: String, items: Array):
	_qem_str(w, name)
	w.put_u8(0x0e)
	w.put_16(items.size())
	w.put_u8(0x0a)
	for it in items:
		_qem_str(w, SSQEMap.ss(it))

static func _qem_lines(s) -> Array:
	return Array(SSQEMap.ss(s).split("\n"))

# a block of objects: [id, field types, objects, fields of one object -> Array]
static func _qem_block(w: StreamPeerBuffer, id: int, types: Array, objs: Array):
	w.put_u8(id)
	_qem_str(w, "")
	w.put_u8(types.size())
	for t in types:
		w.put_u8(t)
	w.put_32(objs.size())
	for o in objs:
		w.put_double(float(o.ms))
		var vals: Array = _qem_fields(id, o)
		for i in range(types.size()):
			_qem_put(w, types[i], vals[i])

static func _qem_fields(id: int, o) -> Array:
	match id:
		0: return _qf_note(o)
		1: return _qf_point(o)
		7: return _qf_tint(o)
		8: return _qf_pos(o)
		11: return _qf_text(o)
		13: return _qf_glide(o)
		14: return _qf_mine(o)
		15: return _qf_lyric(o)
		16: return _qf_fever(o)
		17: return _qf_bookmark(o)
	if id >= 2 and id <= 10:
		return _qf_vfx(o)
	return []

static func _qem_put(w: StreamPeerBuffer, t: int, v):
	match t:
		0: w.put_u8(int(v))
		3: w.put_32(int(v))
		7: w.put_float(float(v))
		8: w.put_double(float(v))
		9: w.put_u8(1 if v else 0)
		10: _qem_str(w, SSQEMap.ss(v))

static func _qf_note(o) -> Array: return [o.x, o.y, o.enable_easing, o.style, o.direction]
static func _qf_point(o) -> Array: return [o.bpm, 4, 4]
static func _qf_vfx(o) -> Array:
	var d: Array = o.data
	return [o.duration, int(_dv(d, 1)), int(_dv(d, 2)), float(_dv(d, 3))]
static func _qf_tint(o) -> Array:
	var d: Array = o.data
	return [o.duration, int(_dv(d, 1)), int(_dv(d, 2)), 255, int(_dv(d, 3)), int(_dv(d, 4)), int(_dv(d, 5))]
static func _qf_pos(o) -> Array:
	var d: Array = o.data
	return [o.duration, int(_dv(d, 1)), int(_dv(d, 2)), float(_dv(d, 3)), float(_dv(d, 4)), float(_dv(d, 5))]
static func _qf_text(o) -> Array:
	var d: Array = o.data
	return [o.duration, SSQEMap.ss(d[1]) if d.size() > 1 else "", int(_dv(d, 2))]
static func _qf_none(_o) -> Array: return []
static func _qf_glide(o) -> Array: return [o.direction]
static func _qf_mine(o) -> Array: return [o.x, o.y]
static func _qf_lyric(o) -> Array: return [o.text, o.fade_in, o.fade_out]
static func _qf_fever(o) -> Array: return [o.duration]
static func _qf_bookmark(o) -> Array: return [o.end_ms - o.ms, o.text]

static func _dv(d: Array, i: int):
	return d[i] if i < d.size() and SSQEMap.ss(d[i]).strip_edges() != "" else 0

# the map as a .qem; paths: {"audio": ..., "cover": ...} as written in the file
static func write_qem(map, paths: Dictionary) -> PoolByteArray:
	var p: Dictionary = map.props
	var w := _writer()
	w.put_data("IQEM".to_ascii())
	w.put_16(0)
	w.put_16(paths.size())
	for k in paths:
		_qem_str(w, k)
		_qem_str(w, paths[k])
	var artists := _qem_lines(p.songArtist)
	var mappers := _qem_lines(p.mappers)
	var rartists := _qem_lines(p.romanizedArtist if SSQEMap.ss(p.romanizedArtist) != "" else p.songArtist)
	w.put_16(12)
	_qem_str(w, "title"); w.put_u8(0x0a); _qem_str(w, SSQEMap.ss(p.songTitle))
	_qem_str(w, "romanizedTitle"); w.put_u8(0x0a); _qem_str(w, SSQEMap.ss(p.romanizedTitle) if SSQEMap.ss(p.romanizedTitle) != "" else SSQEMap.ss(p.songTitle))
	_qem_str_array(w, "artists", artists)
	_qem_str_array(w, "romanizedArtists", rartists)
	_qem_str_array(w, "mappers", mappers)
	_qem_str(w, "difficulty"); w.put_u8(0x00); w.put_u8(int(max(0, SSQEMap.DIFFICULTIES.find(SSQEMap.ss(p.difficulty)))))
	_qem_str(w, "difficultyStars"); w.put_u8(0x07); w.put_float(float(p.rating))
	_qem_str(w, "difficultyName"); w.put_u8(0x0a); _qem_str(w, SSQEMap.ss(p.customDifficulty))
	_qem_str_array(w, "songLinks", map.song_links if map.song_links is Array else [])
	var links := {}
	if map.artist_links is Dictionary:
		for k in map.artist_links:
			if SSQEMap.ss(k) in artists:
				links[SSQEMap.ss(k)] = SSQEMap.ss(map.artist_links[k])
	_qem_str(w, "artistLinks"); w.put_u8(0x10); w.put_16(links.size()); w.put_u8(0x0a); w.put_u8(0x0a)
	for k in links:
		_qem_str(w, k)
		_qem_str(w, links[k])
	var ids := {}
	if map.mapper_ids is Dictionary:
		for k in map.mapper_ids:
			if SSQEMap.ss(k) in mappers:
				ids[SSQEMap.ss(k)] = int(map.mapper_ids[k])
	_qem_str(w, "mapperIds"); w.put_u8(0x10); w.put_16(ids.size()); w.put_u8(0x0a); w.put_u8(0x05)
	for k in ids:
		_qem_str(w, k)
		w.put_64(ids[k])
	_qem_str(w, "mapId"); w.put_u8(0x0a)
	_qem_str(w, fix_id("%s - %s - %s" % [mappers[0] if mappers.size() > 0 and mappers[0] != "" else "none", artists[0] if artists.size() > 0 and artists[0] != "" else "unknown", SSQEMap.ss(p.songTitle)]))
	# objects, by id
	var by_id := []
	for i in range(18):
		by_id.append([])
	map.notes.sort()
	by_id[0] = map.notes.items.duplicate()
	by_id[1] = map.timing_points.duplicate()
	for o in map.vfx_objects.items + map.special_objects.items + map.bookmarks:
		if o.id >= 2 and o.id < 18:
			by_id[o.id].append(o)
	w.put_u8(18)
	for id in range(18):
		_qem_block(w, id, QEM_BLOCKS[id], by_id[id])
	return w.data_array

# per object id: the field types after the time (QEM.ParseObj's order)
const QEM_BLOCKS = [
	[7, 7, 9, 0, 0], [7, 0, 0],
	[8, 0, 0, 7], [8, 0, 0, 7], [8, 0, 0, 7], [8, 0, 0, 7], [8, 0, 0, 7],
	[8, 0, 0, 0, 0, 0, 0], [8, 0, 0, 7, 7, 7], [8, 0, 0, 7], [8, 0, 0, 7],
	[8, 10, 3], [], [0], [7, 7], [10, 9, 9], [8], [8, 10],
]

# a .qemz: the .qem with its song and cover beside it (QEMZ.Write)
static func write_qemz(map, audio: PoolByteArray, cover: PoolByteArray) -> PoolByteArray:
	var paths := {"audio": "audio.asset"}
	if not cover.empty():
		paths["cover"] = "cover.png"
	var files := [["data.qem", write_qem(map, paths)], ["audio.asset", audio]]
	if not cover.empty():
		files.append(["cover.png", cover])
	return zip_files(files)
