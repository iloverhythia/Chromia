extends Reference

# Per-map history of your own attempts ("previous scores").
#
# Every finished attempt (pass, fail, give up; never replays or autoplay) is
# appended to user://score_history/<map id>.json by record_attempt(), which
# Game.gd calls at song end. Files only get read for the map you select.
#
#   ScoreHistory.record_attempt()          # from Game.end()
#   var list = ScoreHistory.load_entries(id)   # ranked best first
#
# Entry keys (kept short, there can be a hundred per map):
#   t  unix time        r  "pass" / "fail" / "giveup"
#   h  notes hit        m  misses        n  notes judged
#   p  end position ms  l  map length ms c  max combo    pz pauses
#   s  speed multiplier mods [short mod tags]  nm player name  so start-from ms
#   av Discord picture url  rp the replay's id (user://replays/<rp>.sspre)

const DIR = "user://score_history"
const MAX_ENTRIES = 100
# When over the cap, the oldest attempt that isn't one of your best few goes.
const KEEP_BEST = 10

const RESULT_PASS = "pass"
const RESULT_FAIL = "fail"
const RESULT_GIVEUP = "giveup"

static func file_for(song_id: String) -> String:
	var safe := ""
	for i in range(song_id.length()):
		var ch: String = song_id[i]
		var c := ord(ch)
		if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch == "_" or ch == "-" or ch == ".":
			safe += ch
		else:
			safe += "_"
	if safe.length() > 80:
		safe = safe.substr(0, 80)
	if safe != song_id or safe == "" or safe.begins_with("."):
		safe += "_" + song_id.md5_text().substr(0, 10)
	return DIR.plus_file(safe + ".json")

# --- grading (same thresholds as EndInfo.update_letter_grade) ---------------

static func grade_for(acc: float, show_fc: bool = true) -> Array:
	if acc >= 1.0 and show_fc: return ["FC", Color("#fa6afa")]
	if acc >= 0.99: return ["SS", Color("#ffb3f0")]
	if acc >= 0.98: return ["S", Color("#91fffa")]
	if acc >= 0.95: return ["A", Color("#91ff92")]
	if acc >= 0.9: return ["B", Color("#e7ffc0")]
	if acc >= 0.85: return ["C", Color("#fcf7b3")]
	if acc >= 0.8: return ["D", Color("#fcd0b3")]
	return ["F", Color("#ff8282")]

static func accuracy(e: Dictionary) -> float:
	var n := float(e.get("n", 0))
	if n <= 0: return 0.0
	return clamp(float(e.get("h", 0)) / n, 0.0, 1.0)

# Same order as the PB check (Song.is_pb_better): passes first, then fails by
# how far they got; then fewer misses, fewer pauses, higher accuracy, older.
static func is_better(a: Dictionary, b: Dictionary) -> bool:
	var ap := int(String(a.get("r", "")) == RESULT_PASS)
	var bp := int(String(b.get("r", "")) == RESULT_PASS)
	if ap != bp: return ap > bp
	if ap == 0:
		var apos := float(a.get("p", 0))
		var bpos := float(b.get("p", 0))
		if apos != bpos: return apos > bpos
	var am := int(a.get("m", 0))
	var bm := int(b.get("m", 0))
	if am != bm: return am < bm
	var az := int(a.get("pz", 0))
	var bz := int(b.get("pz", 0))
	if az != bz: return az < bz
	var aa := accuracy(a)
	var ba := accuracy(b)
	if aa != ba: return aa > ba
	return int(a.get("t", 0)) < int(b.get("t", 0))

func older(a, b) -> bool:
	return int(a.get("t", 0)) < int(b.get("t", 0))

static func rank(entries: Array) -> Array:
	var out := entries.duplicate()
	out.sort_custom(load("res://scripts/ScoreHistory.gd").new(), "is_better")
	return out

# --- file io -----------------------------------------------------------------

# Raw (unsorted) entries for a map. Never fails: a missing or broken file just
# gives an empty list (a broken file is moved aside as .bad so it isn't lost).
static func _read_raw(song_id: String) -> Array:
	var path := file_for(song_id)
	var f := File.new()
	var dir := Directory.new()
	if not f.file_exists(path):
		# A save may have died between writing .tmp and renaming it.
		if f.file_exists(path + ".tmp"):
			dir.rename(path + ".tmp", path)
		if not f.file_exists(path):
			return []
	if f.open(path, File.READ) != OK:
		return []
	var txt := f.get_as_text()
	f.close()
	var res := JSON.parse(txt)
	var data = res.result if res.error == OK else null
	var list = null
	if typeof(data) == TYPE_DICTIONARY:
		list = data.get("attempts")
	elif typeof(data) == TYPE_ARRAY:
		list = data
	if typeof(list) != TYPE_ARRAY:
		push_warning("[score history] unreadable %s, moving it aside" % path)
		dir.rename(path, path + ".bad")
		return []
	var out := []
	for e in list:
		if typeof(e) == TYPE_DICTIONARY and e.has("r") and e.has("n"):
			out.append(e)
	return out

static func load_entries(song_id: String) -> Array:
	if song_id == "" or song_id == "!DELETED":
		return []
	return rank(_read_raw(song_id))

static func _write(song_id: String, entries: Array) -> bool:
	var dir := Directory.new()
	if not dir.dir_exists(DIR):
		if dir.make_dir_recursive(DIR) != OK:
			return false
	var path := file_for(song_id)
	var tmp := path + ".tmp"
	var f := File.new()
	if f.open(tmp, File.WRITE) != OK:
		return false
	f.store_string(to_json({"id": song_id, "v": 1, "attempts": entries}))
	f.close()
	if f.file_exists(path):
		dir.remove(path)
	return dir.rename(tmp, path) == OK

static func add_entry(song_id: String, entry: Dictionary) -> bool:
	if song_id == "" or song_id == "!DELETED":
		return false
	var entries := _read_raw(song_id)
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		var best := rank(entries).slice(0, KEEP_BEST - 1)
		# oldest first
		var by_time := entries.duplicate()
		by_time.sort_custom(load("res://scripts/ScoreHistory.gd").new(), "older")
		for e in by_time:
			if entries.size() <= MAX_ENTRIES: break
			if best.has(e) or e == entry: continue
			entries.erase(e)
	return _write(song_id, entries)

# --- recording ---------------------------------------------------------------

static func player_name() -> String:
	var R = Engine.get_main_loop().root.get_node_or_null("Rhythia")
	if R != null and typeof(R.discord_user) == TYPE_DICTIONARY:
		for k in ["display_name", "username"]:
			var v := String(R.discord_user.get(k, ""))
			if v != "": return v
	var lm = Engine.get_main_loop().root.get_node_or_null("LobbyManager")
	if lm != null and String(lm.player_name) != "" and String(lm.player_name) != "Player":
		return String(lm.player_name)
	return "You"

static func current_mod_tags() -> Array:
	var R = Engine.get_main_loop().root.get_node_or_null("Rhythia")
	var m := []
	if R == null: return m
	if R.mod_nofail: m.append("NF")
	if R.mod_sudden_death: m.append("SD")
	if R.mod_extra_energy: m.append("EE")
	if R.mod_no_regen: m.append("NR")
	if R.mod_mirror_x: m.append("MX")
	if R.mod_mirror_y: m.append("MY")
	if R.mod_ghost: m.append("GH")
	if R.mod_nearsighted: m.append("NS")
	if R.mod_chaos: m.append("CH")
	if R.mod_earthquake: m.append("EQ")
	if R.mod_hardrock: m.append("HR")
	if R.mod_hard_mode: m.append("HM")
	if R.mod_flashlight: m.append("FL")
	if R.mod_360: m.append("360")
	if R.mod_strobe: m.append("ST")
	if R.invert_mouse: m.append("IM")
	return m

# The replay file of an attempt: the one it recorded, or for attempts from
# before that was kept, a replay of this map that started shortly before the
# attempt ended. "" if there's none.
static func replay_path_for(song_id: String, e: Dictionary) -> String:
	var f := File.new()
	var rp := String(e.get("rp", ""))
	if rp != "":
		var p := Globals.p("user://replays/%s.sspre" % rp)
		return p if f.file_exists(p) else ""
	var t := int(e.get("t", 0))
	if t <= 0 or song_id == "":
		return ""
	var dir := Directory.new()
	var folder := Globals.p("user://replays")
	if dir.open(folder) != OK:
		return ""
	var bias := int(OS.get_time_zone_info().get("bias", 0)) * 60 # (replay names use local time)
	var played := float(e.get("p", 0)) / 1000.0 / max(float(e.get("s", 1.0)), 0.1)
	var want := t - played
	var best := ""
	var best_d := 1e9
	dir.list_dir_begin(true, true)
	var fn := dir.get_next()
	var prefix := song_id + "."
	while fn != "":
		if fn.begins_with(prefix) and fn.ends_with(".sspre"):
			var stamp := fn.substr(prefix.length(), fn.length() - prefix.length() - 6)
			var parts := stamp.replace("_", "-").split("-")
			if parts.size() == 6:
				var start := OS.get_unix_time_from_datetime({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
					"hour": int(parts[3]), "minute": int(parts[4]), "second": int(parts[5])}) - bias
				# it started before the attempt ended, and not long before it began
				if start <= t + 5 and start >= want - 180:
					var d: float = abs(start - want)
					if d < best_d:
						best_d = d
						best = folder.plus_file(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	return best

const JUST_ENDED_META = "score_history_just_ended"

# True once after a song ended (the map screen then opens on the result box).
static func take_just_ended() -> bool:
	var root = Engine.get_main_loop().root
	if root.has_meta(JUST_ENDED_META):
		root.remove_meta(JUST_ENDED_META)
		return true
	return false

# Called by Game.gd when a song ends, after Rhythia.song_end_* are filled in.
static func record_attempt() -> void:
	Engine.get_main_loop().root.set_meta(JUST_ENDED_META, true)
	var R = Engine.get_main_loop().root.get_node_or_null("Rhythia")
	if R == null or R.selected_song == null: return
	if R.replaying or R.single_map_mode: return
	if R.replay != null and R.replay.get("autoplayer") == true: return
	var result := RESULT_FAIL
	if R.song_end_type == Globals.END_PASS: result = RESULT_PASS
	elif R.song_end_type == Globals.END_GIVEUP: result = RESULT_GIVEUP
	var e := {
		"t": OS.get_unix_time(),
		"r": result,
		"h": int(R.song_end_hits),
		"m": int(R.song_end_misses),
		"n": int(R.song_end_total_notes),
		"p": int(R.song_end_position),
		"l": int(R.song_end_length),
		"c": int(R.song_end_combo),
		"pz": int(R.song_end_pause_count),
		"s": stepify(float(R.current_speed_multiplier()), 0.001),
		"mods": current_mod_tags(),
		"nm": player_name(),
	}
	if typeof(R.discord_user) == TYPE_DICTIONARY and String(R.discord_user.get("avatar_url", "")) != "":
		e["av"] = String(R.discord_user.get("avatar_url", ""))
	# the replay of this attempt (not the throwaway ones recorded only for the
	# auto retry, which are deleted back in the menu)
	if R.record_replays and not bool(R.get("_forced_replay")) and R.replay != null and String(R.replay.id) != "":
		e["rp"] = String(R.replay.id)
	if float(R.start_offset) > 0:
		e["so"] = int(R.start_offset)
	if not add_entry(String(R.selected_song.id), e):
		push_warning("[score history] could not save attempt for %s" % R.selected_song.id)
