extends Reference
# The map editor's map: a GDScript port of Sound Space Quantum Editor Plus's
# map model (Web Editor/js/model.js, itself a port of the desktop editor's
# Objects/*.cs, ObjectList.cs, UndoRedoManager.cs, Map.cs, Timing.cs and
# Patterns.cs). Positions are SSQE's: x and y 0..2, drawn at column 2 - x and
# row 2 - y (the game's .sspm uses 2 - x / 2 - y).

const DIFFICULTIES = ["N/A", "Easy", "Medium", "Hard", "Logic", "Tasukete"]
const EASING_STYLES = ["Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic"]
const EASING_DIRECTIONS = ["In", "Out", "InOut"]
const GLIDE_DIRECTIONS = ["Up", "Right", "Down", "Left"]
const VFX_NAMES = {2: "Brightness", 3: "Contrast", 4: "Saturation", 5: "Blur", 6: "FOV", 7: "Tint", 8: "Position", 9: "Rotation", 10: "AR Factor", 11: "Text"}

enum RenderMode { NOTES = 0, SPECIAL = 1, VFX = 2 }
const OBJ_DISABLED = 0
const OBJ_NOTE = 1
const OBJ_BEAT = 12
const OBJ_GLIDE = 13
const OBJ_MINE = 14
const OBJ_LYRIC = 15
const OBJ_FEVER = 16

# ---------------------------------------------------------------- helpers

# text of any value ("" for null; String(null) can crash the iOS build)
static func ss(v) -> String:
	return "" if typeof(v) == TYPE_NIL else str(v)

# C#'s Math.Round (banker's rounding)
static func round_even(x: float) -> float:
	var r := round(x)
	if abs(fmod(x, 1.0)) == 0.5 and int(r) % 2 != 0:
		return r - sign(x)
	return r

static func round2(x: float) -> float:
	return round(x * 100.0) / 100.0

# a number as the editor writes it (2 decimals, no trailing zeros)
static func fmt(x: float) -> String:
	var v := round2(x)
	if v == int(v):
		return str(int(v))
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s

static func quote_string(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

# ---------------------------------------------------------------- easing

static func ease_value(mn: float, mx: float, t: float, style: int, direction: int) -> float:
	t = clamp(t, 0.0, 1.0)
	return mn + (mx - mn) * _ease(t, style, direction)

static func _bounce_out(t: float) -> float:
	var n1 := 7.5625
	var d1 := 2.75
	if t < 1.0 / d1:
		return n1 * t * t
	if t < 2.0 / d1:
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	if t < 2.5 / d1:
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	t -= 2.625 / d1
	return n1 * t * t + 0.984375

static func _ease(t: float, style: int, d: int) -> float:
	var c1 := 1.70158
	var c2 := c1 * 1.525
	var c3 := c1 + 1.0
	var c4 := TAU / 3.0
	var c5 := TAU / 4.5
	if d == 0:
		match style:
			1: return 1.0 - cos(t * PI / 2.0)
			2: return c3 * t * t * t - c1 * t * t
			3: return t * t
			4: return pow(t, 4)
			5: return pow(t, 5)
			6: return 1.0 - _bounce_out(1.0 - t)
			7: return 0.0 if t == 0.0 else (1.0 if t == 1.0 else -pow(2.0, 10.0 * t - 10.0) * sin((t * 10.0 - 10.75) * c4))
			8: return 0.0 if t == 0.0 else pow(2.0, 10.0 * t - 10.0)
			9: return 1.0 - sqrt(1.0 - t * t)
			10: return pow(t, 3)
		return t
	if d == 1:
		match style:
			1: return sin(t * PI / 2.0)
			2: return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)
			3: return 1.0 - pow(1.0 - t, 2)
			4: return 1.0 - pow(1.0 - t, 4)
			5: return 1.0 - pow(1.0 - t, 5)
			6: return _bounce_out(t)
			7: return 0.0 if t == 0.0 else (1.0 if t == 1.0 else pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0)
			8: return 1.0 if t == 1.0 else 1.0 - pow(2.0, -10.0 * t)
			9: return sqrt(1.0 - pow(t - 1.0, 2))
			10: return 1.0 - pow(1.0 - t, 3)
		return t
	match style:
		1: return -(cos(PI * t) - 1.0) / 2.0
		2: return (pow(2.0 * t, 2) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0 if t < 0.5 else (pow(2.0 * t - 2.0, 2) * ((c2 + 1.0) * (t * 2.0 - 2.0) + c2) + 2.0) / 2.0
		3: return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
		4: return 8.0 * pow(t, 4) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 4) / 2.0
		5: return 16.0 * pow(t, 5) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 5) / 2.0
		6: return (1.0 - _bounce_out(1.0 - 2.0 * t)) / 2.0 if t < 0.5 else (1.0 + _bounce_out(2.0 * t - 1.0)) / 2.0
		7:
			if t == 0.0 or t == 1.0:
				return t
			if t < 0.5:
				return -(pow(2.0, 20.0 * t - 10.0) * sin((20.0 * t - 11.125) * c5)) / 2.0
			return (pow(2.0, -20.0 * t + 10.0) * sin((20.0 * t - 11.125) * c5)) / 2.0 + 1.0
		8:
			if t == 0.0 or t == 1.0:
				return t
			return pow(2.0, 20.0 * t - 10.0) / 2.0 if t < 0.5 else (2.0 - pow(2.0, -20.0 * t + 10.0)) / 2.0
		9: return (1.0 - sqrt(1.0 - pow(2.0 * t, 2))) / 2.0 if t < 0.5 else (sqrt(1.0 - pow(-2.0 * t + 2.0, 2)) + 1.0) / 2.0
		10: return 4.0 * pow(t, 3) if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3) / 2.0
	return t

# ---------------------------------------------------------------- map objects

class Obj extends Reference:
	# 0 note, 1 timing point, 2-11 vfx (kept raw), 12 beat, 13 glide, 14 mine,
	# 15 lyric, 16 fever, 17 bookmark
	var id := 0
	var ms := 0
	var duration := 0
	var name := ""
	var extra: Array = []
	var selected := false
	var drag_start_ms := 0
	var has_duration := true
	var play_hitsound := true
	# xy objects (notes, mines)
	var x := 0.0
	var y := 0.0
	var is_xy := false
	# notes
	var anchored := false
	var enable_easing := false
	var style := 0
	var direction := 0 # notes: easing direction; glides: 0 up 1 right 2 down 3 left
	# timing points
	var bpm := 0.0
	# lyrics / bookmarks
	var text := ""
	var fade_in := false
	var fade_out := false
	var end_ms := 0
	# raw (vfx) objects
	var data: Array = []
	# Chromia: whose note this is in a collab (unused) / colour override
	var by_color = null

	func fields() -> Array:
		match id:
			0: return [fmt2(x), fmt2(y), "1" if enable_easing else "0", str(style), str(direction)]
			1: return [fmt2(bpm)]
			13: return [str(direction)]
			14: return [fmt2(x), fmt2(y)]
			15: return [qs(text), "1" if fade_in else "0", "1" if fade_out else "0"]
			16: return [str(duration)]
		if id >= 2 and id <= 11 or id > 17:
			var d := data.duplicate()
			if has_duration and d.size() > 0:
				d[0] = str(duration)
			return d
		return []

	func fmt2(v: float) -> String:
		var r := round(v * 100.0) / 100.0
		if r == int(r):
			return str(int(r))
		var s := "%.2f" % r
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		return s

	func qs(s: String) -> String:
		return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

	func to_text() -> String:
		var d: Array = fields() + extra
		if d.empty():
			return str(ms)
		return str(ms) + "|" + PoolStringArray(d).join("|")

	func clone():
		var o = get_script().new()
		o.id = id
		o.ms = ms
		o.duration = duration
		o.name = name
		o.extra = extra
		o.has_duration = has_duration
		o.play_hitsound = play_hitsound
		o.x = x
		o.y = y
		o.is_xy = is_xy
		o.enable_easing = enable_easing
		o.style = style
		o.direction = direction
		o.bpm = bpm
		o.text = text
		o.fade_in = fade_in
		o.fade_out = fade_out
		o.end_ms = end_ms
		o.data = data.duplicate()
		o.by_color = by_color
		# (anchored isn't copied, like Note.clone)
		return o

static func note(nx: float, ny: float, nms: int, easing := false, nstyle := 0, ndir := 0) -> Obj:
	var o := Obj.new()
	o.id = 0
	o.name = "Note"
	o.x = nx
	o.y = ny
	o.ms = nms
	o.is_xy = true
	o.enable_easing = easing
	o.style = nstyle
	o.direction = ndir
	return o

static func timing_point(nbpm: float, nms: int) -> Obj:
	var o := Obj.new()
	o.id = 1
	o.name = "BPM"
	o.bpm = nbpm
	o.ms = nms
	o.has_duration = false
	return o

static func raw_object(nid: int, nms: int, ndata: Array) -> Obj:
	var o := Obj.new()
	o.id = nid
	o.ms = nms
	o.name = VFX_NAMES.get(nid, "null")
	o.data = ndata
	o.has_duration = nid >= 2 and nid <= 11
	if o.has_duration and ndata.size() > 0 and ss(ndata[0]).is_valid_integer():
		o.duration = int(ndata[0])
	return o

static func beat(nms: int) -> Obj:
	var o := Obj.new()
	o.id = 12
	o.name = "Beat"
	o.ms = nms
	o.has_duration = false
	return o

static func glide(nms: int, ndir: int) -> Obj:
	var o := Obj.new()
	o.id = 13
	o.name = "Glide"
	o.ms = nms
	o.direction = ndir
	o.has_duration = false
	return o

static func mine(nx: float, ny: float, nms: int) -> Obj:
	var o := Obj.new()
	o.id = 14
	o.name = "Mine"
	o.x = nx
	o.y = ny
	o.ms = nms
	o.is_xy = true
	o.has_duration = false
	o.play_hitsound = false
	return o

static func lyric(nms: int, ntext: String, fin: bool, fout: bool) -> Obj:
	var o := Obj.new()
	o.id = 15
	o.name = "Lyric"
	o.ms = nms
	o.text = ntext
	o.fade_in = fin
	o.fade_out = fout
	o.has_duration = false
	o.play_hitsound = false
	return o

static func fever(nms: int, ndur: int) -> Obj:
	var o := Obj.new()
	o.id = 16
	o.name = "Fever"
	o.ms = nms
	o.duration = ndur
	o.play_hitsound = false
	return o

static func bookmark(ntext: String, nms: int, nend: int) -> Obj:
	var o := Obj.new()
	o.id = 17
	o.name = "Bookmark"
	o.text = ntext
	o.ms = nms
	o.end_ms = nend
	o.has_duration = false
	return o

static func _f(v) -> float:
	var s := ss(v).strip_edges()
	return float(s) if s.is_valid_float() or s.is_valid_integer() else NAN

static func _i(v) -> int:
	var s := ss(v).strip_edges()
	if s.is_valid_integer():
		return int(s)
	if s.is_valid_float():
		return int(float(s))
	return 0

static func _is_num(v) -> bool:
	var s := ss(v).strip_edges()
	return s.is_valid_integer() or s.is_valid_float()

# MOParser: an object from its fields (id first when nid < 0)
static func parse_object(nid: int, d: Array) -> Obj:
	if d.empty():
		return null
	var index := 0
	if nid < 0:
		if not _is_num(d[0]):
			return null
		nid = _i(d[0])
		index += 1
	if index >= d.size() or not _is_num(d[index]):
		return null
	var nms := _i(d[index])
	var o: Obj = null
	match nid:
		0:
			if index + 2 >= d.size() or not _is_num(d[index + 1]) or not _is_num(d[index + 2]):
				return null
			var nx := _f(d[index + 1])
			var ny := _f(d[index + 2])
			index += 2
			var easing := false
			var st := 0
			var di := 0
			if index + 1 < d.size():
				index += 1
				easing = _i(d[index]) == 1
			if index + 1 < d.size():
				index += 1
				st = _i(d[index])
			if index + 1 < d.size():
				index += 1
				di = _i(d[index])
			o = note(nx, ny, nms, easing, st, di)
		1:
			if index + 1 >= d.size():
				return null
			index += 1
			o = timing_point(_f(d[index]), nms)
		12:
			o = beat(nms)
		13:
			index += 1
			o = glide(nms, _i(d[index]) if index < d.size() else 0)
		14:
			if index + 2 >= d.size():
				return null
			o = mine(_f(d[index + 1]), _f(d[index + 2]), nms)
			index += 2
		15:
			var t := ss(d[index + 1]) if index + 1 < d.size() else ""
			var fi := _i(d[index + 2]) == 1 if index + 2 < d.size() else false
			var fo := _i(d[index + 3]) == 1 if index + 3 < d.size() else false
			index += 3
			o = lyric(nms, t, fi, fo)
		16:
			index += 1
			o = fever(nms, _i(d[index]) if index < d.size() else 0)
		17:
			var e := _i(d[index + 1]) if index + 1 < d.size() else nms
			var t2 := ss(d[index + 2]) if index + 2 < d.size() else ""
			index += 2
			o = bookmark(t2, nms, e)
		_:
			return raw_object(nid, nms, d.slice(index + 1, d.size() - 1) if index + 1 < d.size() else [])
	if index + 1 < d.size():
		o.extra = d.slice(index + 1, d.size() - 1)
	return o

# ---------------------------------------------------------------- object list

class Sorter:
	static func by_ms_then_index(a, b) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1]

class ObjList extends Reference:
	var items: Array = []
	var selected: Array = []
	var bezier_nodes: Array = [] # indices into items
	var map_ref: WeakRef

	func size() -> int:
		return items.size()

	func set_selected(v: Array):
		selected = v
		update_selection()

	func clear_selected():
		set_selected([])

	func update_selection():
		for o in items:
			o.selected = false
		for o in selected:
			o.selected = true

	func get_closest(ms: float) -> float:
		var closest := -1.0
		for o in items:
			if abs(o.ms - ms) < abs(closest - ms):
				closest = o.ms
		return closest

	func search_first(key: float) -> int:
		var first := 0
		var count := items.size() - 1
		while count > 0:
			var step := count / 2
			var it := first + step
			if items[it].ms < key:
				first = it + 1
				count -= step + 1
			else:
				count = step
		return first

	func search_last(key: float) -> int:
		var last := 0
		var count := items.size() - 1
		while count > 0:
			var step := count / 2
			var it := last + step
			if items[it].ms <= key:
				last = it + 1
				count -= step + 1
			else:
				count = step
		return last

	# [first, last) of the objects from start to end
	func search_range(start: float, end: float) -> Array:
		start = int(start)
		end = int(end)
		var first := search_first(start)
		var last := search_last(end)
		if items.size() > 0 and items[last].ms <= end and items[first].ms >= start:
			last += 1
		return [first, last]

	static func _by_ms(a, b) -> bool:
		return a.ms < b.ms

	func sort():
		_stable_sort(items)
		var m = map_ref.get_ref() if map_ref else null
		if m:
			m.changed()

	# sort_custom isn't stable; objects at the same time keep their order
	static func _stable_sort(arr: Array):
		var n := arr.size()
		var sorted := true
		for i in range(1, n):
			if arr[i].ms < arr[i - 1].ms:
				sorted = false
				break
		if sorted:
			return
		var keyed := []
		keyed.resize(n)
		for i in range(n):
			keyed[i] = [arr[i].ms, i, arr[i]]
		keyed.sort_custom(Sorter, "by_ms_then_index")
		for i in range(n):
			arr[i] = keyed[i][2]

	func add(o):
		items.append(o)

	func remove_all(list: Array):
		if list.empty():
			return
		var set := {}
		for o in list:
			set[o] = true
		var kept := []
		for o in items:
			if not set.has(o):
				kept.append(o)
		items = kept
		update_selection()

	func clear():
		items = []
		set_selected([])

	# Modify_Replace
	func replace(label: String, old_objects: Array, new_objects: Array):
		var m = map_ref.get_ref()
		if m == null:
			return
		label = label.replace("[S]", "S" if max(old_objects.size(), new_objects.size()) > 1 else "")
		var old_bez := bezier_nodes.duplicate()
		var new_bez := []
		for n in bezier_nodes:
			if n < items.size() + new_objects.size() - old_objects.size():
				new_bez.append(n)
		m.undo.add({"label": label, "kind": "list", "list": self, "old": old_objects.duplicate(), "new": new_objects.duplicate(),
			"old_bez": old_bez, "new_bez": new_bez})

	func apply_replace(remove: Array, add: Array, bez: Array):
		remove_all(remove)
		items += add
		sort()
		set_selected(add.duplicate())
		bezier_nodes = bez.duplicate()

	# Modify_Edit: action is [object, method] called with each copy
	func edit(label: String, to_modify, target: Object, method: String, args: Array = []):
		if to_modify == null:
			to_modify = selected
		if to_modify.empty():
			return
		var completed := []
		for n in to_modify:
			var c = n.clone()
			target.callv(method, [c] + args)
			completed.append(c)
		replace(label, to_modify, completed)

	func add_objects(label: String, to_add):
		var list: Array = to_add if to_add is Array else [to_add]
		replace(label, [], list)

	func remove_objects(label: String, to_remove = null):
		var list: Array = selected if to_remove == null else (to_remove if to_remove is Array else [to_remove])
		replace(label, list.duplicate(), [])

# ---------------------------------------------------------------- undo / redo

class UndoHistory extends Reference:
	var actions: Array = []
	var index := -1
	var prev_bpm_warning := 0
	var editor_ref: WeakRef = null
	var map_ref: WeakRef = null

	func _editor():
		return editor_ref.get_ref() if editor_ref else null

	func _run(a: Dictionary, forward: bool):
		var m = map_ref.get_ref() if map_ref else null
		var olds: Array = a.old
		var news: Array = a.new
		var rem: Array = olds if forward else news
		var addl: Array = news if forward else olds
		match str(a.kind):
			"list":
				a.list.apply_replace(rem, addl, a.new_bez if forward else a.old_bez)
			"points":
				if m:
					m.apply_points(rem, addl)
			"bookmarks":
				if m:
					m.apply_bookmarks(rem, addl)

	func add(a: Dictionary, run_redo := true):
		actions.resize(index + 1)
		actions.append(a)
		index += 1
		if run_redo:
			_run(a, true)
		var e = _editor()
		var m = map_ref.get_ref() if map_ref else null
		if a.label == "ADD NOTE" and run_redo and e and m and m.timing_points.empty():
			var now := OS.get_ticks_msec()
			if now - prev_bpm_warning >= 5000:
				e.toast("Please use BPM!", "warn")
				prev_bpm_warning = now
		if e:
			e.on_map_changed()

	func undo():
		if index >= 0:
			var a: Dictionary = actions[index]
			var e = _editor()
			if e:
				e.toast("UNDONE: " + a.label, "other")
			_run(a, false)
			index -= 1
			if e:
				e.on_map_changed()

	func redo():
		if index + 1 < actions.size():
			var a: Dictionary = actions[index + 1]
			var e = _editor()
			if e:
				e.toast("REDONE: " + a.label, "other")
			_run(a, true)
			index += 1
			if e:
				e.on_map_changed()

	func clear():
		actions = []
		index = -1

# ---------------------------------------------------------------- the map

var undo := UndoHistory.new()
var notes := ObjList.new()
var vfx_objects := ObjList.new()
var special_objects := ObjList.new()
var bookmarks: Array = []
var timing_points: Array = []
var selected_point: Obj = null

var song_links = []
var artist_links = {}
var mapper_ids = {}

var file_name := ""
var sound_id := "-1"

var tempo_slider := 0.9
var zoom := 1.0
var current_time := 0.0
var beat_divisor := 3.0
var duration := 0.0

var render_mode: int = RenderMode.NOTES
var object_mode: int = OBJ_DISABLED

var props := {
	"exportOffset": 0,
	"mappers": "", "songName": "", "difficulty": "N/A", "useCover": false, "cover": "Default",
	"customDifficulty": "", "rating": 0, "useVideo": false, "video": "", "songOffset": "",
	"songTitle": "", "songArtist": "", "mapCreator": "", "mapCreatorPersonalLink": "",
	"previewStartTime": "", "previewDuration": "", "novaCover": "", "novaIcon": "",
	"romanizedArtist": "", "romanizedTitle": "", "colorsetPath": "", "phxmPlatform": "",
}

var version := 0

# never-matching drag point / "no timing point" stand-ins
var zero_point: Obj = timing_point(0, 0)
var any_point: Obj = timing_point(0, 0)

func _init():
	var w := weakref(self)
	undo.map_ref = w
	notes.map_ref = w
	vfx_objects.map_ref = w
	special_objects.map_ref = w

func changed():
	version += 1

func tempo() -> float:
	var t := tempo_slider
	return min(t, 0.9) + max(t - 0.9, 0.0) * 2.0 + 0.1

func bezier_nodes() -> Array:
	return notes.bezier_nodes

func active_list() -> ObjList:
	match render_mode:
		RenderMode.NOTES:
			return notes
		RenderMode.VFX:
			return vfx_objects
	return notes if object_mode == OBJ_NOTE else special_objects

func selected_objects() -> Array:
	return active_list().selected.duplicate()

func set_selected_objects(v: Array):
	active_list().set_selected(v.duplicate())

func clear_selected():
	notes.clear_selected()
	vfx_objects.clear_selected()
	special_objects.clear_selected()
	selected_point = null

func sort_all():
	notes.sort()
	vfx_objects.sort()
	special_objects.sort()
	sort_timings()
	sort_bookmarks()

func sort_objects():
	active_list().sort()

func sort_timings():
	ObjList._stable_sort(timing_points)
	changed()

func sort_bookmarks():
	ObjList._stable_sort(bookmarks)
	changed()

func get_objects_in_range(start: float, end: float) -> Array:
	var list := active_list()
	var r := list.search_range(start, end)
	var result: Array = list.items.slice(r[0], r[1] - 1) if r[1] > r[0] else []
	if list != notes and object_mode != OBJ_DISABLED:
		var f := []
		for n in result:
			if n.id == object_mode:
				f.append(n)
		result = f
	return result

func increment_zoom(delta: int):
	var z := zoom
	var step := 0.1
	if z < 0.1 or (z == 0.1 and delta < 0):
		step /= 10.0
	if z > 10 or (z == 10 and delta > 0):
		step *= 2.0
	z = round((z + delta * step) * 100.0) / 100.0
	if z > 0.1:
		z = round(z * 10.0) / 10.0
	zoom = clamp(z, 0.01, 20.0)

# PointManager / BookmarkManager
func replace_points(label: String, old_points: Array, new_points: Array):
	label = label.replace("[S]", "S" if max(old_points.size(), new_points.size()) > 1 else "")
	undo.add({"label": label, "kind": "points", "old": old_points.duplicate(), "new": new_points.duplicate()})

func apply_points(remove: Array, add: Array):
	var set := {}
	for p in remove:
		set[p] = true
	var kept := []
	for p in timing_points:
		if not set.has(p):
			kept.append(p)
	timing_points = kept + add
	selected_point = add[0] if add.size() == 1 else null
	sort_timings()

func edit_points(label: String, to_modify: Array, target: Object, method: String, args: Array = []):
	if to_modify.empty():
		return
	var completed := []
	for p in to_modify:
		var c = p.clone()
		target.callv(method, [c] + args)
		completed.append(c)
	replace_points(label, to_modify, completed)

func replace_bookmarks(label: String, old_b: Array, new_b: Array):
	label = label.replace("[S]", "S" if max(old_b.size(), new_b.size()) > 1 else "")
	undo.add({"label": label, "kind": "bookmarks", "old": old_b.duplicate(), "new": new_b.duplicate()})

func apply_bookmarks(remove: Array, add: Array):
	var set := {}
	for b in remove:
		set[b] = true
	var kept := []
	for b in bookmarks:
		if not set.has(b):
			kept.append(b)
	bookmarks = kept + add
	sort_bookmarks()

func edit_bookmarks(label: String, to_modify: Array, target: Object, method: String, args: Array = []):
	if to_modify.empty():
		return
	var completed := []
	for b in to_modify:
		var c = b.clone()
		target.callv(method, [c] + args)
		completed.append(c)
	replace_bookmarks(label, to_modify, completed)

func copy_bookmarks_text() -> String:
	var out := PoolStringArray()
	for b in bookmarks:
		var t: String = b.text.replace(" ~", "_~")
		if b.ms != b.end_ms:
			out.append("%d-%d ~ %s" % [b.ms, b.end_ms, t])
		else:
			out.append("%d ~ %s" % [b.ms, t])
	return out.join("\n")

func paste_bookmarks_text(data: String) -> int:
	var temp := []
	for line in data.split("\n"):
		line = line.strip_edges()
		var sp: PoolStringArray = line.split(" ~")
		if sp.size() != 2:
			continue
		var sub: PoolStringArray = sp[0].split("-")
		var t: String = sp[1].strip_edges().replace("_~", " ~")
		if sub.size() == 1 and sub[0].is_valid_integer():
			temp.append(bookmark(t, int(sub[0]), int(sub[0])))
		elif sub.size() == 2 and sub[0].is_valid_integer() and sub[1].is_valid_integer():
			temp.append(bookmark(t, int(sub[0]), int(sub[1])))
	if not temp.empty():
		replace_bookmarks("PASTE BOOKMARK[S]", bookmarks, temp)
	return temp.size()

# ---------------------------------------------------------------- timing (Timing.cs)

func get_current_bpm(current_ms: float, dragging_point = null) -> Obj:
	var current: Obj = zero_point
	for point in timing_points:
		if point == dragging_point:
			continue
		if point.ms < current_ms or (dragging_point == null and point.ms == current_ms):
			current = point
	return current

func get_closest_beat(current_ms: float, dragging_point = null, ignore_divisor := false) -> int:
	var closest := -1
	var point := get_current_bpm(current_ms, dragging_point)
	if point.bpm > 0:
		var interval := 60000.0 / point.bpm
		if not ignore_divisor:
			interval /= beat_divisor + 1.0
		var offset := fmod(point.ms, interval)
		closest = int(round_even(round_even((current_ms - offset) / interval) * interval + offset))
	return closest

func get_closest_beat_scroll(current_ms: float, negative := false, iterations := 1) -> int:
	var closest := get_closest_beat(current_ms)
	if get_current_bpm(closest).bpm <= 0:
		return -1
	for _i in range(iterations):
		var cur := get_current_bpm(current_ms, any_point if negative else null)
		var interval := 60000.0 / cur.bpm / (beat_divisor + 1.0)
		if negative:
			closest = get_closest_beat(current_ms, any_point)
			if closest >= current_ms:
				closest = get_closest_beat(closest - int(interval))
		else:
			if closest <= current_ms:
				closest = get_closest_beat(closest + int(interval))
			if get_current_bpm(current_ms).ms != get_current_bpm(closest).ms:
				closest = get_current_bpm(closest).ms
		current_ms = closest
	if closest < 0:
		return -1
	return int(clamp(closest, 0, duration))

func notes_from_point(point: Obj) -> Array:
	var index := timing_points.find(point)
	var nxt: float = timing_points[index + 1].ms if index + 1 < timing_points.size() else duration
	var out := []
	for n in notes.items:
		if n.ms >= point.ms and n.ms < nxt:
			out.append(n)
	return out

func _adjust_ms(n, p_ms: int, mult: float):
	n.ms = int((n.ms - p_ms) * mult) + p_ms

func update_point(point: Obj, new_bpm: float):
	var mult := point.bpm / new_bpm
	notes.edit("ADJUST NOTE[S]", notes_from_point(point), self, "_adjust_ms", [point.ms, mult])

func _shift_ms(n, offset: int):
	n.ms += offset

func move_points(points: Array, offset: int):
	var to_adjust := []
	for p in points:
		to_adjust += notes_from_point(p)
	notes.edit("ADJUST NOTE[S]", to_adjust, self, "_shift_ms", [offset])

# ---------------------------------------------------------------- patterns (Patterns.cs)

static func horizontal_flip(n):
	n.x = 2.0 - n.x

static func vertical_flip(n):
	n.y = 2.0 - n.y

static func rotate_note(n, deg: float, clamp_sr: bool):
	var angle := rad2deg(atan2(n.y - 1.0, n.x - 1.0))
	var distance := Vector2(n.x - 1.0, n.y - 1.0).length()
	var a := deg2rad(angle + deg)
	n.x = cos(a) * distance + 1.0
	n.y = sin(a) * distance + 1.0
	if clamp_sr:
		n.x = clamp(n.x, -0.85, 2.85)
		n.y = clamp(n.y, -0.85, 2.85)

static func scale_note(n, scale: float, clamp_sr: bool):
	var s := scale / 100.0
	n.x = (n.x - 1.0) * s + 1.0
	n.y = (n.y - 1.0) * s + 1.0
	if clamp_sr:
		n.x = clamp(n.x, -0.85, 2.85)
		n.y = clamp(n.y, -0.85, 2.85)

static func _binomial(n: int, k: int) -> float:
	var r := 1.0
	for i in range(1, k + 1):
		r = r * (n - k + i) / i
	return r

static func draw_bezier(nodes: Array, divisor: int, curve: bool) -> Array:
	var final := []
	var degree := nodes.size() - 1
	if curve:
		var steps := divisor * degree
		var delta_ms: float = nodes[degree].ms - nodes[0].ms
		var coef := []
		for p in range(degree + 1):
			coef.append(_binomial(degree, p))
		var tp := []
		var up := []
		tp.resize(degree + 1)
		up.resize(degree + 1)
		for s in range(steps + 1):
			var t := float(s) / steps
			var u := 1.0 - t
			tp[0] = 1.0
			up[0] = 1.0
			for p in range(1, degree + 1):
				tp[p] = tp[p - 1] * t
				up[p] = up[p - 1] * u
			var x := 0.0
			var y := 0.0
			for p in range(degree + 1):
				var v: float = coef[p] * up[degree - p] * tp[p]
				x += v * nodes[p].x
				y += v * nodes[p].y
			final.append(note(x, y, int(nodes[0].ms + delta_ms * t)))
	else:
		for p in range(degree):
			var a = nodes[p]
			var b = nodes[p + 1]
			for s in range(divisor + 1):
				if s > 0 or p == 0:
					var t := float(s) / divisor
					final.append(note(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, int(a.ms + (b.ms - a.ms) * t)))
	return final

static func bezier_segments(nodes: Array, divisor: int, curve: bool) -> Array:
	var anchored := [0]
	for i in range(1, nodes.size()):
		if nodes[i].anchored:
			anchored.append(i)
	if not (nodes.size() - 1) in anchored:
		anchored.append(nodes.size() - 1)
	var segments := []
	for i in range(1, anchored.size()):
		segments.append(draw_bezier(nodes.slice(anchored[i - 1], anchored[i]), divisor, curve))
	return segments

# stored patterns (keys 0-9): "1,x|y|beats,..." or "0,x|y|ms,..."
func store_pattern(settings: Dictionary, index: int) -> bool:
	var sel: Array = notes.selected
	if sel.empty():
		return false
	var point := get_current_bpm(sel[0].ms)
	var on_point := point.bpm > 0
	var interval: float = 60000.0 / point.bpm / (beat_divisor + 1.0) if on_point else 0.0
	var pattern := "1" if on_point else "0"
	var offset: int = sel[0].ms
	for n in sel:
		var t: float = (n.ms - offset) / interval if on_point else float(n.ms - offset)
		pattern += ",%s|%s|%s" % [str(n.x), str(n.y), str(t)]
	settings.patterns[index] = pattern
	return true

func recall_pattern(settings: Dictionary, index: int):
	var pattern := ss(settings.patterns[index])
	if pattern == "":
		return
	var offset := current_time
	var point := get_current_bpm(offset)
	var on_point := point.bpm > 0
	var split := pattern.split(",")
	var quantized := split[0] == "1"
	var to_add := []
	for i in range(1, split.size()):
		var p: PoolStringArray = split[i].split("|")
		if p.size() < 3:
			continue
		var x := float(p[0])
		var y := float(p[1])
		var t := float(p[2])
		if not quantized:
			to_add.append(note(x, y, int(t + offset)))
		else:
			var b: float = point.bpm if on_point else 60.0
			var interval := 60000.0 / b / (beat_divisor + 1.0)
			to_add.append(note(x, y, int(t * interval + offset)))
	if to_add.empty():
		return
	if not quantized and on_point:
		var interval := 60000.0 / point.bpm / (beat_divisor + 1.0)
		var min_dist := 1e30
		for i in range(1, to_add.size()):
			var dist: float = min(min_dist, to_add[i].ms - to_add[i - 1].ms)
			if dist > 0:
				min_dist = dist
		for i in range(1, to_add.size()):
			to_add[i].ms = int((to_add[i].ms - offset) / min_dist * interval + offset)
	notes.add_objects("ADD PATTERN", to_add)
