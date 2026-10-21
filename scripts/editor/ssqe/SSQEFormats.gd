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
