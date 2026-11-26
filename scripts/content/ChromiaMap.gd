extends Reference

# Chromia maps (.chrm): a Sound Space map file (SSPM v2) with Chromia's own
# extras kept in it. A .chrm is a .sspm through and through (notes, song,
# cover and details where SSPM keeps them), so everything that takes a map
# takes it: the map list, multiplayer, sharing, the editor. The extras sit in
# the SSPM's "custom data" block under the key "chromia", as JSON:
#
#   {"version": 1, "lyrics": [[ms, "text", fade_in, fade_out], ...]}
#
# Other SSPM readers skip a custom data field they don't know, so a .chrm
# renamed to .sspm still plays elsewhere, without the extras. Maps the editor
# saves into the map list carry the extras the same way.
#
# Lyrics work as in Novastra (and SSQE's Nova lyrics, SSQEEditor.lyric_preview):
#   - each lyric adds its text to the line shown, after a space;
#   - "-" at the start of a lyric starts a new line in place of the shown one;
#   - "-" at the end joins the next lyric on without a space (a syllable);
#   - an empty lyric clears the line (with Fade Out: the line fades out first);
#   - Fade In: the line fades in over a second from the lyric's time; Fade Out:
#     it fades out over a second.

const KEY := "chromia"
const VERSION := 1
const EXT := "chrm"
const FADE_MS := 1000.0

# --- the extras from an editor map (SSQEMap) and back -------------------------------

# the editor map's lyrics, times as the game plays them (with the map's export offset)
static func extras_from_map(m) -> Dictionary:
	var off := int(m.props.get("exportOffset", 0)) if m.props is Dictionary else 0
	var lyrics := []
	for o in m.special_objects.items:
		if o.id == 15:
			lyrics.append([int(max(0, o.ms + off)), String(o.text), bool(o.fade_in), bool(o.fade_out)])
	lyrics.sort_custom(_ByMs, "less")
	if lyrics.empty():
		return {}
	return {"version": VERSION, "lyrics": lyrics}

static func add_to_map(m, extras: Dictionary):
	var SSQEMap = load("res://scripts/editor/ssqe/SSQEMap.gd")
	var off := int(m.props.get("exportOffset", 0)) if m.props is Dictionary else 0
	for l in lyrics_of(extras):
		m.special_objects.add(SSQEMap.lyric(int(l[0]) - off, String(l[1]), bool(l[2]), bool(l[3])))
	m.special_objects.sort()

class _ByMs:
	static func less(a, b) -> bool:
		return float(a[0]) < float(b[0])

static func to_text(extras: Dictionary) -> String:
	return to_json(extras) if not extras.empty() else ""

# [[ms, text, fade_in, fade_out], ...] from the extras (checked: odd entries are left out)
static func lyrics_of(extras) -> Array:
	var out := []
	if not (extras is Dictionary) or not (extras.get("lyrics") is Array):
		return out
	for l in extras.lyrics:
		if l is Array and l.size() >= 2 and (l[0] is float or l[0] is int):
			out.append([float(l[0]), String(l[1]).substr(0, 500), bool(l[2]) if l.size() > 2 else false, bool(l[3]) if l.size() > 3 else false])
		if out.size() >= 20000:
			break
	out.sort_custom(_ByMs, "less")
	return out

# --- reading them from a map file ---------------------------------------------------

# the extras in an SSPM v2 / .chrm file ({} when it has none or isn't one)
static func read_file(path: String) -> Dictionary:
	if path == "":
		return {}
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return {}
	var out := {}
	if f.get_len() > 128 and f.get_buffer(4) == PoolByteArray([83, 83, 43, 109]) and f.get_16() == 2:
		f.seek(48) # (after the header's fixed part: the offsets, custom data first)
		var at := f.get_64()
		var length := f.get_64()
		var end := at + length
		if at > 0 and length > 2 and end <= f.get_len():
			f.seek(at)
			var count := f.get_16()
			var reader = load("res://scripts/content/game/Song.gd").new()
			for i in range(min(count, 64)):
				var klen := f.get_16()
				if klen <= 0 or klen > 64 or f.get_position() + klen > end:
					break
				var key := f.get_buffer(klen).get_string_from_utf8()
				var v = reader.read_data_type(f, false, false)
				if f.get_position() > end:
					break
				if key == KEY and v is String:
					var p := JSON.parse(v)
					if p.error == OK and p.result is Dictionary:
						out = p.result
					break
	f.close()
	return out

static func read_song(song) -> Dictionary:
	if song == null:
		return {}
	var path := String(song.get("filePath")) if song.get("filePath") != null else ""
	if path == "" or not File.new().file_exists(path):
		return {}
	return read_file(path)

# --- what the lyrics show at a time (Nova's rules) ----------------------------------

# lyrics: lyrics_of(...); ms: the song's time -> [text, alpha]
static func lyric_at(lyrics: Array, ms: float) -> Array:
	var prev = null
	var cur = null
	var text := ""
	var alpha := 1.0
	var fading_in := false
	for l in lyrics:
		prev = cur
		cur = l
		if float(cur[0]) > ms:
			break
		var fi: bool = cur[2]
		var fo: bool = cur[3]
		if fo:
			alpha = 1.0 - clamp((ms - float(cur[0])) / FADE_MS, 0.0, 1.0)
			fading_in = false
		elif fi:
			alpha = clamp((ms - float(cur[0])) / FADE_MS, 0.0, 1.0)
			fading_in = true
		elif not fading_in:
			alpha = 1.0
		var ct: String = cur[1]
		if ct.strip_edges() != "":
			if prev != null and String(prev[1]).strip_edges() == "":
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
		elif not fo:
			text = ct
	if not lyrics.empty() and ms < float(lyrics[0][0]):
		return ["", 0.0]
	if text.ends_with("-"):
		text = text.substr(0, text.length() - 1)
	return [text, alpha]
