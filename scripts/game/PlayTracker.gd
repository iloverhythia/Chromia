extends Node

# Tracks how you play, note by note, for the Settings Generator
# (scripts/SettingsAdvisor.gd, Settings > Generator). Nothing leaves your
# device: each play is saved to user://play_tracking/<time>.json, together
# with the settings and mods that play was really played with (so the
# generator never mixes them up with the ones you have now).
#
# For every note (a row, see _add_row):
#   when it came (map ms) and where, the gap and jump from the note before,
#   whether you hit it and if not how you missed it (the KIND_* below),
#   how early your cursor got into its hitbox,
#   when your cursor set off toward it after the note before (reaction),
#   how far past it you went while waiting for it (overshoot),
#   how close you got, and where in the hitbox you hit it.
#
# Kinds of miss:
#   late      your cursor was still on its way when the note's time was up
#   overshoot your cursor was on the note but slid off it before it came
#   near      you were just off it (precision)
#   off       you were somewhere else
#   early     you were on it, then left for the next note too soon
#   skip      you went to the next note without touching this one
#
# NoteManager adds it (attach) and calls note_hit / note_miss; Game.end()
# calls finish(). Replays, autoplay, spectating and visual mode aren't tracked.

const DIR := "user://play_tracking"
const MAX_PLAYS := 300
const LOOK_AHEAD := 1500.0 # map ms before a note that the cursor starts being watched
const VERSION := 2

const KIND_HIT := 0
const KIND_LATE := 1
const KIND_OVERSHOOT := 2
const KIND_NEAR := 3
const KIND_OFF := 4
const KIND_EARLY := 5
const KIND_SKIP := 6

# Row columns (v1 plays only have the first 10).
const R_T := 0
const R_X := 1
const R_Y := 2
const R_GAP := 3
const R_JUMP := 4
const R_KIND := 5
const R_ARRIVE := 6   # map ms before the note that the cursor got into its hitbox (-1 never)
const R_MIN := 7      # closest the cursor got (hitboxes)
const R_OFFX := 8     # where in the hitbox you hit it (-1..1)
const R_OFFY := 9
const R_REACT := 10   # map ms after the note before that the cursor set off toward it (-1 unknown)
const R_OVER := 11    # furthest it went from the note after first getting on it (hitboxes)
const R_AT := 12      # distance when the note was judged (hitboxes, -1 unknown)

# the settings saved with each play (what the generator compares)
const SETTINGS := [
	"sensitivity", "absolute_mode", "absolute_scale", "camera_mode", "cam_unlock",
	"parallax", "ui_parallax", "grid_parallax", "approach_rate", "spawn_distance",
	"fade_length", "fov", "note_size", "cursor_scale", "edge_drift", "half_ghost",
	"cursor_trail", "faraway_hud", "hitwindow_ms", "note_hitbox_size",
	"note_visual_approach", "half_ghost_strength",
]
# mods saved with each play: the ones that change how notes look or move
const MODS := [
	"mod_ghost", "mod_nearsighted", "mod_flashlight", "mod_strobe", "mod_chaos",
	"mod_earthquake", "mod_360", "mod_mirror_x", "mod_mirror_y", "mod_hardrock",
	"mod_hard_mode", "mod_nofail", "mod_sudden_death", "invert_mouse",
]

var nm # the NoteManager (Game/Spawn)
var _recs := {}      # note index -> what the cursor did around it
var _rows := []      # finished notes
var _hbs := 0.57     # half the hitbox, in grid units
var _path := 0.0     # how far the cursor moved (grid units)
var _path_ms := 0.0
var _prev_c = null
var _done := false
var _settings := {}  # taken when the song starts (what you play with)
var _mods := []

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
	# the settings this song is played with (Sound Space Mode's own while it
	# is on, since those are the ones on screen)
	for k in SETTINGS:
		var v = Rhythia.get(k)
		if v != null:
			_settings[k] = v
	for m in MODS:
		if Rhythia.get(m) == true:
			_mods.append(m)

func _cursor() -> Vector2:
	var c: Vector3 = nm._n_notes.to_local(nm._n_cursor.global_transform.origin)
	return Vector2(c.x, c.y)

func _note_pos(i: int) -> Vector2:
	var p: Vector2 = nm.notes[i][0]
	if Rhythia.mod_360:
		p += Vector2(-1, 1)
	return p

# distance in hitboxes (square hitbox, like the game's check)
func _hb_dist(c: Vector2, p: Vector2) -> float:
	return max(abs(c.x - p.x), abs(c.y - p.y)) / _hbs

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
	var prev_t: float = float(nm.notes[i - 1][1]) if i > 0 else t - LOOK_AHEAD
	# only once the note before has come: until then the cursor is busy with
	# other notes and passing through this one means nothing
	if ms < prev_t:
		return
	var r = _recs.get(i)
	if r == null:
		r = {"enter": null, "out": false, "left": false, "min": 1e9, "tmin": 0.0, "dlast": 1e9, "dprev": 1e9,
			"react": -1.0, "over": 0.0, "at": -1.0}
		_recs[i] = r
	var p := _note_pos(i)
	var d := _hb_dist(c, p)
	# reaction: how long after the note before the cursor had covered a good
	# part of the jump from there to here
	if r.react < 0 and ms < t and i > 0:
		var jump: float = p.distance_to(_note_pos(i - 1))
		if jump >= 0.3 and c.distance_to(p) <= jump * 0.65:
			r.react = ms - prev_t
	if ms < t:
		if d <= 1.0:
			if r.enter == null or r.out:
				r.enter = ms - t # (the last time it got on: how early it got there to stay)
				r.out = false
		elif r.enter != null:
			r.left = true
			r.out = true
		if r.enter != null and d > r.over:
			r.over = d
	if d < r.min:
		r.min = d
		r.tmin = ms - t
	r.dprev = r.dlast
	r.dlast = d
	r["tlast"] = ms - t

func note_hit(i: int):
	if _done:
		return
	var c := _cursor()
	var p := _note_pos(i)
	var r = _recs.get(i, {})
	var d := _hb_dist(c, p)
	r["at"] = d
	# the hit itself counts as being there (at a low frame rate it may be the
	# first time the cursor was seen on the note)
	if d < float(r.get("min", 1e9)):
		r["min"] = d
	if r.get("enter") == null or r.get("out", false):
		r["enter"] = min(nm.ms - float(nm.notes[i][1]), 0.0)
	var off: Vector2 = (c - p) / _hbs
	_add_row(i, KIND_HIT, r, off)

func note_miss(i: int):
	if _done:
		return
	var r = _recs.get(i, {})
	var c := _cursor()
	r["at"] = _hb_dist(c, _note_pos(i))
	var kind := KIND_OFF
	var mn: float = r.get("min", 1e9)
	# closer to the next note than to this one?
	var to_next := false
	if i + 1 < nm.notes.size():
		var pn := _note_pos(i + 1)
		var pc := _note_pos(i)
		to_next = pn.distance_to(pc) > 0.3 and c.distance_to(pn) < c.distance_to(pc)
	# it was on the note (after the note before) and still missed it: it left,
	# even if that happened between two frames
	if r.get("left", false) or r.get("enter") != null:
		kind = KIND_EARLY if to_next else KIND_OVERSHOOT
	elif r.get("enter") == null and to_next and mn > 1.0:
		kind = KIND_SKIP
	elif float(r.get("dlast", 1e9)) < float(r.get("dprev", 1e9)) - 0.02 and float(r.get("tmin", -1e9)) >= float(r.get("tlast", 0.0)) - 0.5:
		# still on its way (getting closer) when the note's time was up: too late
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
	_rows.append([
		int(t), stepify(p.x, 0.01), stepify(p.y, 0.01), int(gap), stepify(jump, 0.01), kind,
		int(-enter) if enter != null else -1,
		stepify(min(float(r.get("min", 99.0)), 99.0), 0.01),
		stepify(off.x, 0.01), stepify(off.y, 0.01),
		int(r.get("react", -1.0)) if r.get("react", -1.0) >= 0 else -1,
		stepify(min(float(r.get("over", 0.0)), 99.0), 0.01),
		stepify(min(float(r.get("at", -1.0)), 99.0), 0.01) if r.get("at", -1.0) >= 0 else -1,
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
	var hits := 0
	for row in _rows:
		if row[R_KIND] == KIND_HIT:
			hits += 1
	var stars := -1.0
	if song != null and song.has_method("star_rating_cached"):
		stars = song.star_rating_cached()
	var speed := 1.0
	if nm != null and is_instance_valid(nm) and nm.get("speed_multi") != null:
		speed = float(nm.speed_multi)
	elif Rhythia.has_method("current_speed_multiplier"):
		speed = float(Rhythia.current_speed_multiplier())
	var play := {
		"v": VERSION,
		"t": OS.get_unix_time(),
		"map": String(song.id) if song else "",
		"name": String(song.name) if song else "",
		"stars": stars,
		"speed": speed,
		"end": end_type,
		"hits": hits,
		"notes": _rows.size(),
		"cursor_speed": (_path / (_path_ms / 1000.0)) if _path_ms > 1000.0 else 0.0,
		"ss": bool(Rhythia.get("sound_space_mode")),
		"settings": _settings,
		"mods": _mods,
		"hbs": _hbs,
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
