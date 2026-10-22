extends Node

# Tracks how you play, note by note, for the Settings Generator
# (scripts/SettingsAdvisor.gd, Settings > Generator). Nothing leaves your
# device: each play is saved to user://play_tracking/<time>.json.
#
# For every note it keeps: when it came and where (and how far / how fast the
# jump from the note before was), whether you hit it, when your cursor first
# got into its hitbox (how early you were), how close you got, and for a
# miss what kind it was:
#   late      your cursor was still on its way when the note passed
#   overshoot your cursor was on the note but left before it arrived
#   near      you were just off it (precision)
#   off       you were somewhere else
# Plus the play's result, the map's difficulty and the settings you had on.
#
# NoteManager adds it (attach) and calls note_hit / note_miss; Game.end()
# calls finish(). Replays, autoplay, spectating and visual mode aren't tracked.

const DIR := "user://play_tracking"
const MAX_PLAYS := 300
const LOOK_AHEAD := 600.0 # ms before a note that the cursor starts being watched
const VERSION := 1

const KIND_HIT := 0
const KIND_LATE := 1
const KIND_OVERSHOOT := 2
const KIND_NEAR := 3
const KIND_OFF := 4

# the settings saved with each play (what the generator compares)
const SETTINGS := [
	"sensitivity", "absolute_mode", "absolute_scale", "camera_mode", "cam_unlock",
	"parallax", "ui_parallax", "grid_parallax", "approach_rate", "spawn_distance",
	"fade_length", "fov", "note_size", "cursor_scale", "edge_drift", "half_ghost",
	"cursor_trail", "faraway_hud", "hitwindow_ms", "note_hitbox_size",
]

var nm # the NoteManager (Game/Spawn)
var _recs := {}      # note index -> what the cursor did around it
var _rows := []      # finished notes
var _hbs := 0.57     # half the hitbox, in grid units
var _path := 0.0     # how far the cursor moved (grid units)
var _path_ms := 0.0
var _prev_c = null
var _done := false

static func enabled() -> bool:
	var R = Engine.get_main_loop().root.get_node_or_null("Rhythia")
	if R == null or R.get("track_plays") == false:
		return false
	if R.replaying or R.single_map_mode or R.visual_mode:
		return false
	if R.replay != null and R.replay.get("autoplayer") == true:
		return false
	return true

static func attach(note_manager: Node):
	if note_manager == null or note_manager.has_node("PlayTracker") or not enabled():
		return
	var t = load("res://scripts/game/PlayTracker.gd").new()
	t.name = "PlayTracker"
	t.nm = note_manager
	t.process_priority = 3 # after the notes moved this frame
	note_manager.add_child(t)

func _ready():
	_hbs = float(Rhythia.note_hitbox_size) / 2.0
	if Rhythia.mod_hard_mode:
		_hbs *= Rhythia.HARD_MODE_SCALE

func _cursor() -> Vector2:
	var c: Vector3 = nm._n_notes.to_local(nm._n_cursor.global_transform.origin)
	return Vector2(c.x, c.y)

func _note_pos(i: int) -> Vector2:
	var p: Vector2 = nm.notes[i][0]
	if Rhythia.mod_360:
		p += Vector2(-1, 1)
	return p

func _process(delta):
	if _done or nm == null or not is_instance_valid(nm) or nm.notes.empty():
		return
	if get_tree().paused:
		return
	var ms: float = nm.ms
	var c := _cursor()
	if _prev_c != null and ms > 0:
		_path += c.distance_to(_prev_c)
		_path_ms += delta * 1000.0
	_prev_c = c
	var i: int = nm.current_note
	while i < nm.notes.size() and float(nm.notes[i][1]) <= ms + LOOK_AHEAD:
		if nm.notes[i][2] == Globals.NSTATE_ACTIVE:
			_watch(i, ms, c)
		i += 1

func _watch(i: int, ms: float, c: Vector2):
	var t: float = nm.notes[i][1]
	var r = _recs.get(i)
	if r == null:
		r = {"enter": null, "left": false, "min": 1e9, "tmin": 0.0, "dlast": 1e9, "dprev": 1e9}
		_recs[i] = r
	var p := _note_pos(i)
	# distance in hitboxes (square hitbox, like the game's check)
	var d: float = max(abs(c.x - p.x), abs(c.y - p.y)) / _hbs
	if d <= 1.0 and r.enter == null:
		r.enter = ms - t
	elif d > 1.0 and r.enter != null and ms < t:
		r.left = true
	if d < r.min:
		r.min = d
		r.tmin = ms - t
	r.dprev = r.dlast
	r.dlast = d

func note_hit(i: int):
	if _done:
		return
	var c := _cursor()
	var p := _note_pos(i)
	var r = _recs.get(i, {})
	var off: Vector2 = (c - p) / _hbs
	_add_row(i, KIND_HIT, r, off)

func note_miss(i: int):
	if _done:
		return
	var r = _recs.get(i, {})
	var kind := KIND_OFF
	var mn: float = r.get("min", 1e9)
	if r.get("left", false):
		kind = KIND_OVERSHOOT
	elif mn <= 2.5 and r.get("dlast", 1e9) <= r.get("dprev", 1e9) + 0.001 and float(r.get("tmin", 0.0)) > 0.0:
		# still getting closer when the note went: too late
		kind = KIND_LATE
	elif mn <= 1.8:
		kind = KIND_NEAR
	_add_row(i, kind, r, Vector2.ZERO)

func _add_row(i: int, kind: int, r: Dictionary, off: Vector2):
	var p := _note_pos(i)
	var t: float = nm.notes[i][1]
	var gap := 0.0
	var jump := 0.0
	if i > 0:
		gap = t - float(nm.notes[i - 1][1])
		jump = p.distance_to(_note_pos(i - 1))
	var enter = r.get("enter")
	# [time, x, y, gap ms, jump, kind, arrived ms before the note (-1 never),
	#  closest (hitboxes), offset x, offset y]
	_rows.append([
		int(t), stepify(p.x, 0.01), stepify(p.y, 0.01), int(gap), stepify(jump, 0.01), kind,
		int(-enter) if enter != null else -1,
		stepify(min(float(r.get("min", 99.0)), 99.0), 0.01),
		stepify(off.x, 0.01), stepify(off.y, 0.01),
	])
	_recs.erase(i)

# Game.end(): save this play.
func finish(end_type: int):
	if _done:
		return
	_done = true
	if _rows.size() < 20:
		return # too little to learn from
	var song = Rhythia.selected_song
	var settings := {}
	for k in SETTINGS:
		var v = Rhythia.get(k)
		if v != null:
			settings[k] = v
	var hits := 0
	for row in _rows:
		if row[5] == KIND_HIT:
			hits += 1
	var stars := -1.0
	if song != null and song.has_method("star_rating_cached"):
		stars = song.star_rating_cached()
	var play := {
		"v": VERSION,
		"t": OS.get_unix_time(),
		"map": String(song.id) if song else "",
		"name": String(song.name) if song else "",
		"stars": stars,
		"speed": float(Rhythia.current_speed_multiplier()) if Rhythia.has_method("current_speed_multiplier") else 1.0,
		"end": end_type,
		"hits": hits,
		"notes": _rows.size(),
		"cursor_speed": (_path / (_path_ms / 1000.0)) if _path_ms > 1000.0 else 0.0,
		"ss": bool(Rhythia.get("sound_space_mode")),
		"settings": settings,
		"rows": _rows,
	}
	_save(play)

static func _save(play: Dictionary):
	var dir := Directory.new()
	var path: String = Globals.p(DIR)
	if not dir.dir_exists(path):
		dir.make_dir_recursive(path)
	var f := File.new()
	if f.open(path.plus_file("%d_%d.json" % [int(play.t), randi() % 10000]), File.WRITE) != OK:
		return
	f.store_string(to_json(play))
	f.close()
	_prune(path)

static func _prune(path: String):
	var files := list_files()
	if files.size() <= MAX_PLAYS:
		return
	for i in range(files.size() - MAX_PLAYS):
		Directory.new().remove(files[i])

# oldest first
static func list_files() -> Array:
	var out := []
	var dir := Directory.new()
	var path: String = Globals.p(DIR)
	if dir.open(path) != OK:
		return out
	dir.list_dir_begin(true, true)
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".json") and fn[0].is_valid_integer():
			out.append(path.plus_file(fn))
		fn = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

static func load_plays() -> Array:
	var out := []
	for fp in list_files():
		var f := File.new()
		if f.open(fp, File.READ) != OK:
			continue
		var j = JSON.parse(f.get_as_text())
		f.close()
		if j.error == OK and typeof(j.result) == TYPE_DICTIONARY and j.result.has("rows"):
			out.append(j.result)
	return out

static func clear_all():
	for fp in list_files():
		Directory.new().remove(fp)
