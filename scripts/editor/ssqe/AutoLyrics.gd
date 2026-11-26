extends Reference
# Map Editor > GRAPHICS > Lyrics > AUTO LYRICS (SSQEDialogs.auto_lyrics): the
# song's timed lyrics from LRCLIB (lrclib.net, a free public library of synced
# lyrics; no account or key), placed as Chromia lyrics at their times.
#
# Each line of the song becomes a lyric that starts a new line ("-" in front,
# as Novastra's lyrics do), and a gap of more than GAP_MS between two lines, or
# the end, clears the line a moment after the last words.

const SEARCH_URL := "https://lrclib.net/api/search?q=%s"
const GAP_MS := 7000 # (no words for this long: the line is cleared...)
const CLEAR_AFTER_MS := 4500 # (...this long after it started)

# what to search for: the map's artist and title, else its song name, else its file's name
static func query_for(ed) -> String:
	if ed == null or ed.map == null:
		return ""
	var p: Dictionary = ed.map.props
	var artist := String(p.get("songArtist", "")).strip_edges()
	var title := String(p.get("songTitle", "")).strip_edges()
	if title != "":
		return (artist + " " + title).strip_edges()
	var q := String(ed.map_title()) if ed.has_method("map_title") else ""
	# (file names: "artist_-_title_(lyrics)" and the like)
	q = q.replace("_", " ")
	for junk in ["(lyrics)", "[lyrics]", "lyrics", "(official video)", "(official audio)", "(audio)", "official video", "official audio"]:
		q = q.replacen(junk, "")
	return q.strip_edges()

# LRCLIB's answers, best first: with times, then nearest to the song's length
static func ranked(results, length_s: float) -> Array:
	var out := []
	if not (results is Array):
		return out
	for r in results:
		if r is Dictionary and (String(r.get("syncedLyrics", "")) != "" or String(r.get("plainLyrics", "")) != ""):
			out.append(r)
	var key := {}
	for r in out:
		var timed := String(r.get("syncedLyrics", "")) != ""
		var off: float = abs(float(r.get("duration", 0.0)) - length_s) if length_s > 0 else 0.0
		key[r] = (0.0 if timed else 100000.0) + off
	var sorter := _By.new()
	sorter.key = key
	out.sort_custom(sorter, "less")
	return out

class _By:
	var key := {}
	func less(a, b) -> bool:
		return float(key[a]) < float(key[b])

static func length_text(s: float) -> String:
	var t := int(round(s))
	return "%d:%02d" % [t / 60, t % 60]

# "[mm:ss.xx] words" lines (a line can have several times; word times
# "<mm:ss.xx>" are dropped) -> [[ms, text], ...] in time order, offset added,
# kept within 0 .. total_ms (total_ms <= 0: no end)
static func parse_lrc(lrc: String, offset_ms: int = 0, total_ms: float = -1.0) -> Array:
	var re := RegEx.new()
	re.compile("\\[(\\d+):(\\d+(?:[.:]\\d+)?)\\]")
	var words := RegEx.new()
	words.compile("<\\d+:\\d+(?:[.:]\\d+)?>")
	var lines := []
	for raw in lrc.split("\n"):
		var line := String(raw).strip_edges()
		var times := []
		var pos := 0
		while true:
			var m := re.search(line, pos)
			if m == null or m.get_start() != pos:
				break
			var secs := float(m.get_string(2).replace(":", "."))
			times.append(int(round((int(m.get_string(1)) * 60.0 + secs) * 1000.0)))
			pos = m.get_end()
		if times.empty():
			continue # (tags like [ar:...], or no time)
		var text := words.sub(line.substr(pos), "", true).strip_edges()
		for t in times:
			var ms: int = int(t) + offset_ms
			if ms < 0 or (total_ms > 0 and ms > total_ms):
				continue
			lines.append([ms, text])
	lines.sort_custom(_ByTime.new(), "less")
	return lines

class _ByTime:
	func less(a, b) -> bool:
		return int(a[0]) < int(b[0])

# [[ms, text], ...] -> the lyrics to place: [[ms, lyric text], ...]. Each line
# starts a new line; long gaps and the end clear it.
static func to_lyrics(lines: Array, total_ms: float = -1.0) -> Array:
	var out := []
	for i in range(lines.size()):
		var ms: int = int(lines[i][0])
		var text: String = String(lines[i][1])
		if text == "":
			if not out.empty() and String(out[out.size() - 1][1]) != "":
				out.append([ms, ""])
			continue
		out.append([ms, "-" + text])
		var next_ms: int = int(lines[i + 1][0]) if i + 1 < lines.size() else -1
		if next_ms < 0 or next_ms - ms > GAP_MS:
			var clear_at: int = ms + CLEAR_AFTER_MS
			if total_ms > 0:
				clear_at = int(min(clear_at, total_ms))
			if clear_at > ms:
				out.append([clear_at, ""])
	return out

# plain lyrics (no times): spread evenly between from_ms and to_ms
static func spread_plain(plain: String, from_ms: int, to_ms: int) -> Array:
	var texts := []
	for raw in plain.split("\n"):
		var t := String(raw).strip_edges()
		if t != "":
			texts.append(t)
	var out := []
	if texts.empty() or to_ms <= from_ms:
		return out
	var step: float = float(to_ms - from_ms) / texts.size()
	for i in range(texts.size()):
		out.append([int(from_ms + step * i), texts[i]])
	return out
