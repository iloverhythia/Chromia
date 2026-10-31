extends Control
# The map editor's windows, laid out like Sound Space Quantum Editor Plus's
# (Web Editor/js/dialogs.js, from the desktop editor's Avalonia windows):
# BPM Setup, BPM Tapper, Bookmarks, Export SSPM / RHM, Export PHXM, the auto
# mapper's options, and message boxes. They float over the editor in Chromia's
# style; drag them by the title bar.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")
const SSQEImport = preload("res://scripts/editor/ssqe/SSQEImport.gd")
const EditorProject = preload("res://scripts/editor/EditorProject.gd")
const TEXT = Color(0.898039, 0.94902, 1)
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)

var ed
var theme_res: Theme
var windows := {} # id -> {win, body, scale, ...}
var focused := ""
var _modal: Control = null
var _modal_cb = null
var _drag_win = null
var _drag_off := Vector2()

func _ready():
	anchor_right = 1
	anchor_bottom = 1
	mouse_filter = MOUSE_FILTER_IGNORE
	theme_res = load("res://uitheme.tres")

# Chromia's lilac boxes, with small margins so they fit the windows' sizes
func _compact(c: Control, k: float):
	var names := []
	if c is LineEdit:
		names = ["normal", "focus", "read_only"]
	elif c is Button:
		names = ["normal", "hover", "pressed", "disabled", "focus"]
	for n in names:
		var base = c.get_stylebox(n)
		var sb: StyleBox = base.duplicate() if base else StyleBoxFlat.new()
		sb.content_margin_left = 3 * k
		sb.content_margin_right = 3 * k
		sb.content_margin_top = 1 * k
		sb.content_margin_bottom = 1 * k
		c.add_stylebox_override(n, sb)

func wants_keys() -> bool:
	if _modal != null or _kb_capture != "":
		return true
	return focused == "tapper" and windows.has("tapper")

func scale() -> float:
	return clamp(ed.hd * 1.15, 0.55, 2.2)

# ================================================================== window frame

# big: as large as fits (most of the editor), for the settings
func floating(id: String, title: String, w: float, h: float, big := false) -> Dictionary:
	if windows.has(id):
		close(id)
	var k := scale()
	var vp: Vector2 = ed.rect_size
	var fit: float = min((vp.x - 8) / (w + 2), (vp.y - 8) / (h + 32))
	k = fit * 0.92 if big else min(k, fit)
	var win := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	win.add_stylebox_override("panel", sb)
	win.rect_size = Vector2(w * k + 4, (h + 30) * k + 4)
	win.rect_position = ((vp - win.rect_size) / 2).floor()
	win.mouse_filter = MOUSE_FILTER_STOP
	win.connect("gui_input", self, "_on_win_input", [id])
	add_child(win)
	var tl := Label.new()
	tl.text = title
	tl.add_font_override("font", ed.font(int(15 * k), true))
	tl.add_color_override("font_color", TEXT)
	tl.rect_position = Vector2(10 * k, 6 * k)
	tl.mouse_filter = MOUSE_FILTER_IGNORE
	win.add_child(tl)
	var x := Button.new()
	x.theme = theme_res
	x.text = "X"
	x.focus_mode = FOCUS_NONE
	x.add_font_override("font", ed.font(int(13 * k), true))
	x.rect_position = Vector2(win.rect_size.x - 30 * k, 4 * k)
	x.rect_size = Vector2(26 * k, 22 * k)
	x.connect("pressed", self, "close", [id])
	win.add_child(x)
	var body := Control.new()
	body.rect_position = Vector2(2, 30 * k + 2)
	body.rect_size = Vector2(w * k, h * k)
	body.mouse_filter = MOUSE_FILTER_PASS
	win.add_child(body)
	raise()
	var info := {"id": id, "win": win, "body": body, "k": k}
	windows[id] = info
	focused = id
	return info

func close(id: String):
	if not windows.has(id):
		return
	var info: Dictionary = windows[id]
	windows.erase(id)
	if is_instance_valid(info.win):
		info.win.queue_free()
	if focused == id:
		focused = ""

func close_all():
	for id in windows.keys():
		close(id)

func _on_win_input(ev, id: String):
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		if ev.pressed:
			focused = id
			var info: Dictionary = windows.get(id, {})
			if info.empty():
				return
			info.win.raise()
			if ev.position.y < 30 * info.k:
				_drag_win = info.win
				_drag_off = ev.position
		else:
			_drag_win = null
	elif ev is InputEventMouseMotion and _drag_win != null and is_instance_valid(_drag_win):
		var p: Vector2 = get_local_mouse_position() - _drag_off
		p.x = clamp(p.x, 0, max(0, rect_size.x - _drag_win.rect_size.x))
		p.y = clamp(p.y, 0, max(0, rect_size.y - _drag_win.rect_size.y))
		_drag_win.rect_position = p

# ---- controls placed in a window's own pixels (scaled)

func _font(info: Dictionary, px := 13.0, bold := false) -> DynamicFont:
	return ed.font(int(round(px * info.k)), bold)

func _place(info: Dictionary, c: Control, x: float, y: float, w: float, h: float, fs := 13.0) -> Control:
	var k: float = info.k
	if fs > 0:
		c.add_font_override("font", _font(info, fs))
	if c is LineEdit or (c is Button and not c is CheckBox and not c is OptionButton):
		_compact(c, k)
	info.body.add_child(c)
	c.rect_position = Vector2(x * k, y * k)
	c.rect_size = Vector2(w * k, h * k)
	return c

func a_label(info: Dictionary, text: String, x: float, y: float, w: float, h: float, align := "left") -> Label:
	var l := Label.new()
	l.text = text
	l.valign = Label.VALIGN_CENTER
	l.add_color_override("font_color", TEXT)
	if align == "right":
		l.align = Label.ALIGN_RIGHT
	elif align == "center":
		l.align = Label.ALIGN_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	_place(info, l, x, y, w, h)
	return l

func a_button(info: Dictionary, text: String, x: float, y: float, w: float, h: float, method: String, args: Array = []) -> Button:
	var b := Button.new()
	b.theme = theme_res
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	if method != "":
		b.connect("pressed", self, method, args)
	SSQESettings.add_gradient(b, bool(ed.s.get("controlGradients", true)), ed)
	_place(info, b, x, y, w, h, 12)
	if text.find("\n") == -1:
		b.text = text
		var f: DynamicFont = b.get_font("font")
		if f and f.get_string_size(text).x > b.rect_size.x - 6 * info.k:
			b.add_font_override("font", ed.font(int(max(6, f.size * (b.rect_size.x - 6 * info.k) / f.get_string_size(text).x))))
	else:
		# (two or three lines, as the original's buttons have)
		var l := Label.new()
		l.text = text
		l.align = Label.ALIGN_CENTER
		l.valign = Label.VALIGN_CENTER
		l.anchor_right = 1
		l.anchor_bottom = 1
		l.mouse_filter = MOUSE_FILTER_IGNORE
		l.add_color_override("font_color", Color(0, 0, 0))
		l.add_color_override("font_color_shadow", Color(0, 0, 0, 0))
		l.add_font_override("font", _font(info, 11))
		b.add_child(l)
	return b

func a_box(info: Dictionary, x: float, y: float, w: float, h: float, value := "") -> LineEdit:
	var e := LineEdit.new()
	e.theme = theme_res
	e.text = value
	_place(info, e, x, y, w, h, 12)
	return e

func a_check(info: Dictionary, text: String, on: bool, x: float, y: float, w: float, h: float) -> CheckBox:
	var c := CheckBox.new()
	c.theme = theme_res
	c.flat = true
	c.text = text
	c.pressed = on
	c.focus_mode = FOCUS_NONE
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
		c.add_color_override(k, TEXT)
	_place(info, c, x, y, w, h, 12)
	return c

func a_combo(info: Dictionary, options: Array, value: String, x: float, y: float, w: float, h: float) -> OptionButton:
	var o := OptionButton.new()
	o.theme = theme_res
	o.focus_mode = FOCUS_NONE
	for opt in options:
		o.add_item(SSQEMap.ss(opt))
	o.select(max(0, options.find(value)))
	_place(info, o, x, y, w, h, 12)
	o.get_popup().add_font_override("font", _font(info, 13))
	return o

func a_grid(info: Dictionary, columns: Array, x: float, y: float, w: float, h: float) -> Tree:
	var t := Tree.new()
	t.theme = theme_res
	t.columns = columns.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.select_mode = Tree.SELECT_MULTI
	for i in range(columns.size()):
		t.set_column_title(i, columns[i][0])
		t.set_column_min_width(i, int(columns[i][1] * info.k))
		t.set_column_expand(i, true)
	_place(info, t, x, y, w, h, 12)
	t.add_font_override("title_button_font", _font(info, 12, true))
	return t

# ================================================================== message boxes (GuiWindowDialog)

func message(text: String, title := "Map Editor"):
	_modal_box(text, title, [["OK", "ok"]], null, "", [])

func confirm(text: String, target: Object, method: String, args: Array = [], buttons := [["Yes", "yes"], ["No", "no"]]):
	_modal_box(text, "Map Editor", buttons, target, method, args)

func _modal_box(text: String, title: String, buttons: Array, target, method: String, args: Array):
	if _modal != null:
		_modal.queue_free()
	var k := scale()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	dim.mouse_filter = MOUSE_FILTER_STOP
	add_child(dim)
	_modal = dim
	_modal_cb = [target, method, args]
	raise()
	var w := 450.0 * k
	var lf: DynamicFont = ed.font(int(15 * k))
	var lines := 1
	for line in text.split("\n"):
		lines += 1 + int(lf.get_string_size(line).x / max(w - 40 * k, 1))
	var h: float = max(160.0 * k, lines * lf.get_height() + 110 * k)
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	box.add_stylebox_override("panel", sb)
	box.rect_size = Vector2(w, h)
	box.rect_position = ((ed.rect_size - box.rect_size) / 2).floor()
	dim.add_child(box)
	var tl := Label.new()
	tl.text = title
	tl.add_font_override("font", ed.font(int(15 * k), true))
	tl.add_color_override("font_color", LILAC)
	tl.rect_position = Vector2(14 * k, 10 * k)
	box.add_child(tl)
	var l := Label.new()
	l.text = text
	l.autowrap = true
	l.add_font_override("font", lf)
	l.add_color_override("font_color", TEXT)
	l.rect_position = Vector2(20 * k, 40 * k)
	l.rect_size = Vector2(w - 40 * k, h - 100 * k)
	box.add_child(l)
	var n := buttons.size()
	var bw := 120.0 * k
	var gap := 12.0 * k
	var total := n * bw + (n - 1) * gap
	for i in range(n):
		var b := Button.new()
		b.theme = theme_res
		b.text = buttons[i][0]
		b.focus_mode = FOCUS_NONE
		b.add_font_override("font", ed.font(int(14 * k)))
		b.rect_size = Vector2(bw, 34 * k)
		b.rect_position = Vector2((w - total) / 2 + i * (bw + gap), h - 48 * k)
		b.connect("pressed", self, "_modal_answer", [buttons[i][1]])
		box.add_child(b)

func _modal_answer(value: String):
	if _modal:
		_modal.queue_free()
	_modal = null
	var cb = _modal_cb
	_modal_cb = null
	if cb and cb[0] and cb[1] != "":
		cb[0].callv(cb[1], [value] + cb[2])

func _input(ev):
	if not is_visible_in_tree():
		return
	if _kb_capture != "" and ev is InputEventKey:
		if not windows.has("settings"):
			_kb_capture = ""
		elif _st_kb_input(ev):
			get_tree().set_input_as_handled()
			return
	if _modal != null and ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.scancode == KEY_ESCAPE:
			_modal_answer("cancel")
			get_tree().set_input_as_handled()
		elif ev.scancode == KEY_ENTER or ev.scancode == KEY_KP_ENTER:
			_modal_answer("ok" if _modal_cb == null or _modal_cb[1] == "" else "yes")
			get_tree().set_input_as_handled()
		return
	if focused == "tapper" and windows.has("tapper") and ev is InputEventKey and ev.pressed and not ev.echo:
		var f := get_focus_owner()
		if f is LineEdit:
			return
		if ev.scancode == KEY_ESCAPE:
			close("tapper")
		else:
			tap()
		get_tree().set_input_as_handled()

# ================================================================== BPM Setup (TimingsWindow)

var _t: Dictionary = {}

func timings():
	var map = ed.map
	var s: Dictionary = ed.s
	var X := 15.0
	var Y := 15.0
	var O := Y + 375
	var info := floating("timings", "BPM Setup", 390, 720)
	_t = {"info": info, "version": -1}
	_t.grid = a_grid(info, [["BPM", 180], ["Ms", 180]], X, Y, 360, 370)
	_t.grid.connect("multi_selected", self, "_t_selected")
	a_label(info, "  BPM", X, O, 80, 20)
	_t.bpm = a_box(info, X + 80, O, 90, 20, "0")
	a_label(info, "  Offset (ms)", X, O + 25, 80, 20)
	_t.offset = a_box(info, X + 80, O + 25, 90, 20, "0")
	a_button(info, "Add Point", X + 175, O, 90, 20, "_t_add")
	a_button(info, "Update Point", X + 175, O + 25, 90, 20, "_t_update")
	a_button(info, "Delete Point", X + 270, O, 90, 20, "_t_delete")
	a_button(info, "Current Pos", X + 270, O + 25, 90, 20, "_t_current")
	_t.move = a_box(info, X + 175, O + 50, 90, 20, "0")
	a_button(info, "Move Points", X + 270, O + 50, 90, 20, "_t_move")
	a_label(info, "  Move Selected Points (ms)", X, O + 50, 170, 20)
	var adj := a_check(info, "Adjust notes when changing points", bool(s.adjustNotes), X + 55, O + 78, 300, 20)
	adj.connect("toggled", self, "_t_adjust")
	a_button(info, "Paste OSU\nTimings", X, O + 125, 86, 50, "_t_paste", ["osu"])
	a_button(info, "Paste ADOFAI\nTimings", X + 92, O + 125, 86, 50, "_t_paste", ["adofai"])
	a_button(info, "Paste Clone\nHero Timings", X + 183, O + 125, 86, 50, "_t_paste", ["ch"])
	a_button(info, "Open\nBeatmap\nTimings", X + 274, O + 125, 86, 50, "_t_open_beatmap")
	a_button(info, "Open BPM\nTapper", X, O + 180, 86, 50, "tapper")
	a_label(info, "Start (ms)  ", X + 92, O + 180, 86, 22, "right")
	a_label(info, "End (ms)  ", X + 92, O + 208, 86, 22, "right")
	_t.start = a_box(info, X + 182, O + 180, 86, 22, "0")
	_t.end = a_box(info, X + 182, O + 208, 86, 22, "0")
	a_button(info, "Detect BPM", X + 274, O + 180, 86, 22, "_t_detect")
	_t.result = a_box(info, X + 274, O + 208, 86, 22, "0")
	_t.result.editable = false
	_t.result.align = LineEdit.ALIGN_CENTER
	# BPM from where the notes are (SSQENoteBpm.gd): selected notes, or the
	# notes between Start and End (all of them when both are 0)
	a_button(info, "Detect From Notes", X, O + 240, 176, 24, "_t_from_notes")
	a_button(info, "x2", X + 182, O + 240, 41, 24, "_t_notes_scale", [2.0])
	a_button(info, "/2", X + 228, O + 240, 41, 24, "_t_notes_scale", [0.5])
	_t.apply = a_button(info, "Apply", X + 274, O + 240, 86, 24, "_t_notes_apply")
	_t.apply.disabled = true
	_t.notes_info = a_label(info, "", X, O + 268, 360, 42)
	_t.notes_info.clip_text = true
	_t.notes_info.valign = Label.VALIGN_TOP
	_t_info("Finds the BPM and offset (and tempo changes) that fit the notes: the selected ones, or the notes between Start and End")
	_t.found = []
	_t_reset_list()
	var cur = map.get_current_bpm(ed.current_time())
	var idx: int = map.timing_points.find(cur)
	if idx >= 0:
		_t_select(idx)
		_t.bpm.text = SSQEMap.fmt(cur.bpm) if cur.bpm == round(cur.bpm * 100) / 100 else str(cur.bpm)
		_t.offset.text = str(cur.ms)

func _process(_d):
	if ed == null or ed.map == null:
		return
	if windows.has("timings") and not _t.empty() and _t.version != ed.map.version:
		_t_reset_list()
	if windows.has("bookmarks") and not _b.empty() and _b.version != ed.map.version:
		_b_reset_list()

func _tree_selected_items(tree: Tree) -> Array:
	var out := []
	var root := tree.get_root()
	if root == null:
		return out
	var it := root.get_children()
	while it:
		if it.is_selected(0):
			out.append(it.get_metadata(0))
		it = it.get_next()
	return out

func _t_reset_list():
	var map = ed.map
	var tree: Tree = _t.grid
	var sel := {}
	for p in _tree_selected_items(tree):
		sel[p] = true
	tree.clear()
	var root := tree.create_item()
	for p in map.timing_points:
		var it := tree.create_item(root)
		it.set_text(0, str(stepify(p.bpm, 0.001)))
		it.set_text(1, str(p.ms))
		it.set_metadata(0, p)
		if sel.has(p):
			it.select(0)
	_t.version = map.version

func _t_select(index: int):
	var root: TreeItem = _t.grid.get_root()
	if root == null:
		return
	var it := root.get_children()
	var i := 0
	while it:
		if i == index:
			it.select(0)
		else:
			it.deselect(0)
		it = it.get_next()
		i += 1

func _t_selected(_item, _col, _sel):
	var pts := _tree_selected_items(_t.grid)
	if not pts.empty():
		_t.bpm.text = str(pts[0].bpm)
		_t.offset.text = str(pts[0].ms)

static func _num(t: String):
	t = t.strip_edges()
	if t.is_valid_float() or t.is_valid_integer():
		return float(t)
	return null

func _t_add():
	var bpm = _num(_t.bpm.text)
	var ms = _num(_t.offset.text)
	if bpm == null or ms == null:
		return
	ms = int(min(ms, ed.total_time()))
	for p in ed.map.timing_points:
		if p.ms == ms:
			return
	ed.map.replace_points("ADD POINT", [], [SSQEMap.timing_point(bpm, ms)])

func _t_update():
	var pts := _tree_selected_items(_t.grid)
	var bpm = _num(_t.bpm.text)
	var ms = _num(_t.offset.text)
	if pts.empty() or bpm == null or ms == null:
		return
	var point = pts[0]
	for p in ed.map.timing_points:
		if p.ms == int(ms) and p != point:
			return
	if ed.s.adjustNotes:
		ed.map.update_point(point, bpm)
	ed.map.edit_points("EDIT POINT", [point], self, "_set_point", [float(bpm), int(ms)])

func _set_point(p, bpm: float, ms: int):
	p.bpm = bpm
	p.ms = ms

func _t_delete():
	var pts := _tree_selected_items(_t.grid)
	if not pts.empty():
		ed.map.replace_points("DELETE POINT[S]", pts, [])

func _t_current():
	_t.offset.text = str(int(ed.current_time()))

func _t_move():
	var off = _num(_t.move.text)
	var pts := _tree_selected_items(_t.grid)
	if off == null or int(off) == 0 or pts.empty():
		return
	ed.map.edit_points("MOVE POINT[S]", pts, ed.map, "_shift_ms", [int(off)])
	if ed.s.adjustNotes:
		ed.map.move_points(pts, int(off))

func _t_adjust(on: bool):
	ed.s.adjustNotes = on
	ed.settings_changed()

func _t_paste(kind: String):
	var text := OS.clipboard
	if text.strip_edges() == "":
		message("Copy the timings first, then press this again.")
		return
	_t_import(kind, text)

func _t_import(kind: String, text: String):
	var pts = null
	match kind:
		"osu": pts = parse_osu_timing(text)
		"adofai": pts = parse_adofai_timing(text)
		"ch": pts = parse_ch_timing(text)
	if pts == null or (pts is Array and pts.empty()):
		message("Failed to parse beatmap\n[ %s : FormatException ]" % kind.to_upper(), "Error")
		return
	ed.map.replace_points("IMPORT POINTS", ed.map.timing_points, pts)

func _t_open_beatmap():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_t_beatmap_picked", PoolStringArray(["*.osu, *.chart, *.adofai ; Beatmaps"]), false, _start_dir())

func _t_beatmap_picked(files):
	var path := _first(files)
	if path == "":
		return
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return
	var text := f.get_as_text()
	f.close()
	var ext := path.get_extension().to_lower()
	_t_import("adofai" if ext == "adofai" else ("ch" if ext == "chart" else "osu"), text)

func _t_detect():
	var from = _num(_t.start.text)
	var to = _num(_t.end.text)
	from = max(0, from if from != null else 0)
	to = to if to != null else 0
	_t.result.text = "..."
	if ed.page:
		ed.page.detect_bpm(int(from), int(to) if to > from else 0, self, "_t_detected")

func _t_detected(found):
	if not windows.has("timings"):
		return
	if found is Dictionary:
		_t.result.text = str(found.bpm)
		_t.bpm.text = str(found.bpm)
		_t.offset.text = str(found.offsetMs)
	else:
		_t.result.text = "0"

# the info line under Detect From Notes, broken into lines that fit
func _t_info(text: String):
	var lines := []
	var line := ""
	for word in text.split(" "):
		if line != "" and (line + " " + word).length() > 66:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		lines.append(line)
	_t.notes_info.text = PoolStringArray(lines).join("\n")

func _t_note_times() -> Array:
	var map = ed.map
	var picked := []
	for o in map.notes.selected:
		picked.append(o.ms)
	if picked.size() >= 8:
		return picked
	var from = _num(_t.start.text)
	var to = _num(_t.end.text)
	from = from if from != null else 0.0
	to = to if to != null and to > from else INF
	var out := []
	for o in map.notes.items:
		if o.ms >= from and o.ms <= to:
			out.append(o.ms)
	return out

func _t_from_notes():
	var times := _t_note_times()
	var ref := 150.0
	var cur = ed.map.get_current_bpm(ed.current_time())
	if cur != null and cur.bpm > 0:
		ref = cur.bpm
	var r: Dictionary = load("res://scripts/editor/ssqe/SSQENoteBpm.gd").detect(times, ref)
	if r.has("error"):
		_t.found = []
		_t.apply.disabled = true
		_t_info(r.error)
		return
	_t.found = r.points
	if not times.empty():
		var last := 0.0
		for t in times:
			last = max(last, float(t))
		_t.found_end = last
	_t_show_found(r)

func _t_show_found(r = null):
	var pts: Array = _t.found
	if pts.empty():
		return
	_t.bpm.text = str(pts[0].bpm)
	_t.offset.text = str(pts[0].ms)
	_t.apply.disabled = false
	var txt := ""
	if pts.size() == 1:
		txt = "%s BPM, offset %d ms" % [str(pts[0].bpm), pts[0].ms]
	else:
		var parts := []
		for p in pts.slice(0, min(pts.size(), 4) - 1):
			parts.append("%s @ %d" % [str(p.bpm), p.ms])
		txt = "%d tempos: %s%s" % [pts.size(), PoolStringArray(parts).join(", "), " ..." if pts.size() > 4 else ""]
	if r is Dictionary:
		txt += " - fits %d%% of %d notes" % [int(round(r.fit * 100.0)), r.notes]
		if r.has("also") and not r.also.empty():
			var alts := []
			for a in r.also:
				alts.append(str(a))
			txt += ". Also fits: " + PoolStringArray(alts).join(", ")
		_t.last_result = r
	txt += ". Apply adds them as timing points"
	_t_info(txt)

func _t_notes_scale(k: float):
	if _t.found.empty():
		return
	var out := []
	for p in _t.found:
		out.append({"bpm": stepify(p.bpm * k, 0.001), "ms": p.ms})
	_t.found = out
	_t_show_found(_t.get("last_result"))

# Replaces the timing points in the detected range with the detected ones.
func _t_notes_apply():
	var pts: Array = _t.found
	if pts.empty():
		return
	var start: int = pts[0].ms
	var end: float = _t.get("found_end", INF)
	var old := []
	for p in ed.map.timing_points:
		if p.ms >= start and p.ms <= end:
			old.append(p)
	var add := []
	for p in pts:
		add.append(SSQEMap.timing_point(float(p.bpm), int(p.ms)))
	ed.map.replace_points("DETECT FROM NOTES", old, add)
	_t.apply.disabled = true
	_t_info("Added %d timing point%s." % [add.size(), "" if add.size() == 1 else "s"])

# ---- timing formats (TimingsWindow.ParseOSU / ParseCH / ParseADOFAI)

static func parse_osu_timing(data: String):
	data = data.replace("\r\n", "\n")
	if data.find("TimingPoints") != -1:
		data = data.substr(data.find("TimingPoints") + 13)
		if data.find("[") != -1:
			data = data.substr(0, data.find("["))
	var points := []
	for line in data.split("\n"):
		if line.find(",") == -1:
			continue
		var sp: PoolStringArray = line.split(",")
		if _num(sp[0]) == null or _num(sp[1]) == null:
			return null
		var time := int(float(sp[0]))
		var bpm := float(sp[1])
		var inherited: bool = sp[6].strip_edges() == "1" if sp.size() > 6 else bpm > 0
		bpm = abs(round(60000.0 / bpm * 1000.0) / 1000.0)
		if bpm > 0 and inherited:
			points.append(SSQEMap.timing_point(bpm, time))
	return points

static func parse_ch_timing(data: String):
	data = data.replace("\r\n", "\n")
	var ri := data.find("Resolution")
	if ri == -1:
		return null
	var res := data.substr(ri)
	res = res.substr(0, res.find("\n")).replace("Resolution = ", "")
	if _num(res) == null:
		return null
	var resolution := float(res)
	var si := data.find("SyncTrack")
	if si == -1:
		return null
	data = data.substr(si)
	data = data.substr(0, data.find("}")).replace("SyncTrack]\n{", "")
	var bpms := []
	var times := []
	for line in data.split("\n"):
		var bi: int = line.find(" B ")
		if bi == -1:
			continue
		bpms.append(float(line.substr(bi + 3)) / 1000.0)
		times.append(float(line.substr(0, bi).replace(" =", "")))
	var ms := []
	for i in range(times.size()):
		if i > 0:
			var diff := round(1000.0 * ((times[i] - times[i - 1]) / (bpms[i - 1] * resolution / 60.0)) * 100) / 100
			ms.append(diff + ms[i - 1])
		else:
			ms.append(times[i])
	var out := []
	for i in range(ms.size()):
		out.append(SSQEMap.timing_point(bpms[i], int(ms[i])))
	return out

const ADOFAI_DEGREES = {
	"R": 0, "J": 30, "E": 45, "T": 60, "U": 90, "G": 120, "Q": 135, "H": 150, "L": 180, "N": 210, "Z": 225, "F": 240,
	"D": 270, "B": 300, "C": 315, "M": 330, "x": 195, "W": 165, "A": 345, "p": 15, "q": 105, "Y": 285, "o": 75, "V": 255, "!": 999,
}

static func parse_adofai_timing(data: String):
	# (ADOFAI writes trailing commas, which JSON doesn't allow)
	var rx := RegEx.new()
	rx.compile(",(\\s*[}\\]])")
	var clean := rx.sub(data.trim_prefix("﻿"), "$1", true)
	var p := JSON.parse(clean)
	if p.error != OK or typeof(p.result) != TYPE_DICTIONARY:
		return null
	var level: Dictionary = p.result
	var settings: Dictionary = level.get("settings", {}) if level.get("settings") is Dictionary else {}
	var angles := []
	if level.get("angleData") is Array:
		for a in level.angleData:
			angles.append(float(a))
	elif level.get("pathData") is String:
		for c in SSQEMap.ss(level.pathData):
			angles.append(float(ADOFAI_DEGREES.get(c, 0)))
	if angles.size() < 2:
		return null
	var speed_at := {}
	var twirl_at := {}
	if level.get("actions") is Array:
		for a in level.actions:
			if a is Dictionary:
				if a.get("eventType") == "SetSpeed":
					speed_at[int(a.get("floor", 0))] = a
				elif a.get("eventType") == "Twirl":
					twirl_at[int(a.get("floor", 0))] = true
	var bpm := float(settings.get("bpm", 100))
	if bpm <= 0:
		bpm = 100.0
	bpm = _adofai_apply(speed_at, 0, bpm)
	var time := float(settings.get("offset", 0))
	var clockwise := true
	var points := [SSQEMap.timing_point(round(bpm * 1000) / 1000, int(round(time)))]
	var i := 1
	while i < angles.size():
		var prev: float = angles[i - 1]
		if prev == 999:
			i += 1
			continue
		var nxt: float = angles[i]
		var midspin := nxt == 999
		if midspin:
			if i + 1 >= angles.size():
				break
			nxt = angles[i + 1]
		if twirl_at.has(i):
			clockwise = not clockwise
		var before := bpm
		bpm = _adofai_apply(speed_at, i, bpm)
		if bpm != before and bpm > 0:
			points.append(SSQEMap.timing_point(round(bpm * 1000) / 1000, int(round(time))))
		var angle := fmod(fmod(prev + (0.0 if midspin else 180.0) - nxt, 360.0) + 360.0, 360.0)
		if angle <= 0:
			angle += 360
		if not clockwise:
			angle = 360 - angle
		if angle <= 0:
			angle += 360
		time += 60000.0 / bpm * angle / 180.0
		i += 1
	var by_ms := {}
	for pt in points:
		by_ms[pt.ms] = pt
	var out := by_ms.values()
	SSQEMap.ObjList._stable_sort(out)
	return out

static func _adofai_apply(speed_at: Dictionary, floor_i: int, bpm: float) -> float:
	if not speed_at.has(floor_i):
		return bpm
	var sp: Dictionary = speed_at[floor_i]
	if sp.get("speedType") == "Multiplier":
		return bpm * (float(sp.get("bpmMultiplier", 1)) if float(sp.get("bpmMultiplier", 1)) != 0 else 1.0)
	return float(sp.get("beatsPerMinute")) if float(sp.get("beatsPerMinute", 0)) > 0 else bpm

# ================================================================== BPM Tapper

var _tap_n := 0
var _tap_start := 0
var _tapping := false
var _tap_ui := {}

func tapper():
	var X := 21.0
	var Y := 12.0
	var info := floating("tapper", "BPM Tapper", 226, 244)
	_tap_ui = {"info": info}
	_tap_ui.bpm = a_label(info, "", X, Y, 184, 32, "center")
	_tap_ui.bpm.add_font_override("font", _font(info, 22, true))
	_tap_ui.dec = a_label(info, "", X, Y + 74, 184, 24, "center")
	a_label(info, "Decimal Places", X, Y + 37, 96, 30)
	_tap_ui.places = a_box(info, X + 96, Y + 37, 88, 30, "2")
	a_button(info, "TAP OR PRESS ANY KEY", X, Y + 108, 184, 65, "tap")
	a_button(info, "RESET", X, Y + 179, 184, 41, "_tap_reset")
	_tap_reset()

func _tap_reset():
	_tap_n = 0
	_tapping = false
	if not _tap_ui.empty():
		_tap_ui.bpm.text = ""
		_tap_ui.dec.text = ""

func tap():
	if _tap_ui.empty() or not windows.has("tapper"):
		return
	_tap_n += 1
	if not _tapping:
		_tapping = true
		_tap_start = OS.get_ticks_usec()
		_tap_ui.bpm.text = "0"
		_tap_ui.dec.text = "0"
	else:
		var d := int(clamp(int(_tap_ui.places.text) if _tap_ui.places.text.is_valid_integer() else 0, 0, 15))
		var mins := (OS.get_ticks_usec() - _tap_start) / 60000000.0
		var bpm := (_tap_n - 1) / max(mins, 0.000001)
		_tap_ui.bpm.text = str(int(round(bpm)))
		_tap_ui.dec.text = ("%." + str(d) + "f") % bpm

# ================================================================== Bookmarks (BookmarksWindow)

var _b: Dictionary = {}

func bookmarks():
	var X := 15.0
	var Y := 15.0
	var O := Y + 375
	var info := floating("bookmarks", "Bookmarks", 650, 450)
	_b = {"info": info, "version": -1}
	_b.grid = a_grid(info, [["Text", 420], ["Start Ms", 100], ["End Ms", 100]], X, Y, 620, 370)
	_b.grid.connect("multi_selected", self, "_b_selected")
	_b.grid.connect("item_activated", self, "_b_activated")
	a_label(info, "Text", X, O, 60, 20)
	_b.text = a_box(info, X + 60, O, 300, 20)
	a_label(info, "Offset", X, O + 25, 60, 20)
	_b.start = a_box(info, X + 60, O + 25, 147, 20, "0")
	_b.end = a_box(info, X + 213, O + 25, 147, 20, "0")
	a_button(info, "Add Bookmark", X + 375, O, 117, 20, "_b_add")
	a_button(info, "Update Bookmark", X + 375, O + 25, 117, 20, "_b_update")
	a_button(info, "Delete Bookmark", X + 503, O, 117, 20, "_b_delete")
	a_button(info, "Current Pos", X + 503, O + 25, 117, 20, "_b_current")
	_b_reset_list()
	_b.start.text = str(int(ed.current_time()))
	_b.end.text = _b.start.text

func _b_reset_list():
	var tree: Tree = _b.grid
	var sel := {}
	for b in _tree_selected_items(tree):
		sel[b] = true
	tree.clear()
	var root := tree.create_item()
	for b in ed.map.bookmarks:
		var it := tree.create_item(root)
		it.set_text(0, b.text)
		it.set_text(1, str(b.ms))
		it.set_text(2, str(b.end_ms))
		it.set_metadata(0, b)
		if sel.has(b):
			it.select(0)
	_b.version = ed.map.version

func _b_selected(_item, _col, _sel):
	var bs := _tree_selected_items(_b.grid)
	if not bs.empty():
		_b.text.text = bs[0].text
		_b.start.text = str(bs[0].ms)
		_b.end.text = str(bs[0].end_ms)

func _b_activated():
	var it: TreeItem = _b.grid.get_selected()
	if it:
		var b = it.get_metadata(0)
		if ed.playing:
			ed.pause_music()
		ed.set_current_time(b.ms)

func _b_add():
	var ms = _num(_b.start.text)
	var e = _num(_b.end.text)
	if ms == null or e == null:
		return
	for b in ed.map.bookmarks:
		if b.text == _b.text.text and b.ms == int(ms) and b.end_ms == int(e):
			return
	ed.map.replace_bookmarks("ADD BOOKMARK", [], [SSQEMap.bookmark(_b.text.text, int(ms), int(e))])

func _b_update():
	var bs := _tree_selected_items(_b.grid)
	var ms = _num(_b.start.text)
	var e = _num(_b.end.text)
	if bs.empty() or ms == null or e == null:
		return
	ed.map.edit_bookmarks("EDIT BOOKMARK", [bs[0]], self, "_set_bookmark", [_b.text.text, int(ms), int(e)])

func _set_bookmark(b, text: String, ms: int, e: int):
	b.text = text
	b.ms = ms
	b.end_ms = e

func _b_delete():
	var bs := _tree_selected_items(_b.grid)
	if not bs.empty():
		ed.map.replace_bookmarks("DELETE BOOKMARK[S]", bs, [])

func _b_current():
	var t := str(int(ed.current_time()))
	if _b.start.text != _b.end.text:
		_b.start.text = t
	_b.end.text = t

# ================================================================== Export SSPM / RHM (ExportSSPM)

var _x: Dictionary = {}

func export_sspm(format := "sspm"):
	var map = ed.map
	var p: Dictionary = map.props
	var X := 12.0
	var Y := 12.0
	var info := floating("export_" + format, "Export " + format.to_upper(), 344, 358)
	_x = {"info": info, "format": format, "cover_path": ""}
	a_label(info, "Map ID", X, Y, 84, 20)
	_x.id = a_box(info, X + 84, Y, 236, 20, map.sound_id)
	_x.id.editable = false
	a_label(info, "Song Name", X, Y + 25, 84, 20)
	_x.name = a_box(info, X + 84, Y + 25, 236, 20, SSQEMap.ss(p.songName))
	a_label(info, "Difficulty", X, Y + 50, 84, 20)
	_x.diff = a_combo(info, SSQEMap.DIFFICULTIES, SSQEMap.ss(p.difficulty), X + 84, Y + 50, 236, 20)
	a_label(info, "Custom Difficulty (Optional)", X, Y + 74, 184, 20)
	_x.custom = a_box(info, X + 184, Y + 74, 136, 20, SSQEMap.ss(p.customDifficulty))
	var ml := a_label(info, "Mapper(s)\n\n(One per line)", X, Y + 99, 84, 60)
	ml.valign = Label.VALIGN_TOP
	_x.mappers = TextEdit.new()
	_x.mappers.theme = theme_res
	_x.mappers.text = SSQEMap.ss(p.mappers)
	_place(info, _x.mappers, X + 84, Y + 99, 236, 130, 12)
	a_label(info, "Cover Image", X, Y + 239, 84, 20)
	_x.cover = a_box(info, X + 84, Y + 236.5, 176, 25, "Map cover" if ed.page and ed.page.has_cover() else "Default")
	_x.cover.editable = false
	a_button(info, "Select", X + 265, Y + 236.5, 55, 25, "_x_select_cover")
	_x.use_cover = a_check(info, "Use Cover", bool(p.useCover), X + 84, Y + 274, 236, 20)
	a_button(info, "Finish", X, Y + 298, 320, 36, "_x_finish")

func _x_select_cover():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_x_cover_picked", PoolStringArray(["*.png, *.jpg, *.jpeg ; Images"]), false, _start_dir())

func _x_cover_picked(files):
	var path := _first(files)
	if path == "" or _x.empty():
		return
	_x.cover_path = path
	_x.cover.text = path.get_file()
	_x.use_cover.pressed = true

func _x_finish():
	var map = ed.map
	var p: Dictionary = map.props
	p.songName = _x.name.text
	p.difficulty = SSQEMap.DIFFICULTIES[_x.diff.selected]
	p.customDifficulty = _x.custom.text
	p.mappers = _x.mappers.text
	p.useCover = _x.use_cover.pressed
	ed.on_map_changed()
	var cover := PoolByteArray()
	if _x.use_cover.pressed:
		if _x.cover_path != "":
			cover = _read_bytes(_x.cover_path)
			if ed.page:
				ed.page.set_cover(_x.cover_path)
		elif ed.page:
			cover = ed.page.cover_bytes()
	var audio := PoolByteArray()
	if ed.page:
		audio = ed.page.audio_bytes()
	if audio.empty():
		message("No audio is loaded for this map.", "Error")
		return
	var id := F.fix_id(SSQEMap.ss(map.sound_id))
	var mappers := []
	for m in SSQEMap.ss(_x.mappers.text).split("\n"):
		if m.strip_edges() != "":
			mappers.append(m.strip_edges())
	var meta := {
		"songId": id, "mapName": _x.name.text, "mappers": PoolStringArray(mappers if not mappers.empty() else ["None"]).join("\n"),
		"difficulty": SSQEMap.DIFFICULTIES[_x.diff.selected], "customDifficulty": _x.custom.text,
	}
	var bytes: PoolByteArray
	var format: String = _x.format
	if format == "rhm":
		meta.duration = ed.song_length * 1000.0
		if SSQEMap.ss(meta.mapName) == "":
			meta.mapName = SSQEMap.ss(p.songTitle) if SSQEMap.ss(p.songTitle) != "" else SSQEMap.ss(map.sound_id)
		var entries := [["map", F.write_rhm_map(map, meta)], ["audio", audio]]
		if not cover.empty():
			entries.append(["cover", cover])
		bytes = F.zip_files(entries)
	else:
		bytes = F.write_sspm(map, meta, audio, cover)
	_save_bytes(bytes, "%s.%s" % [id, format], "*.%s ; %s map" % [format, format.to_upper()])
	close("export_" + format)

# ================================================================== Export PHXM (Rewrite)

func export_phxm():
	var map = ed.map
	var p: Dictionary = map.props
	var X := 12.0
	var Y := 12.0
	var W := 236.0
	var info := floating("export_phxm", "Export PHXM", 364, 403)
	_x = {"info": info, "format": "phxm", "cover_path": ""}
	var split := SSQEMap.ss(p.songName).split(" - ")
	var title := SSQEMap.ss(p.songTitle)
	if title == "":
		title = PoolStringArray(Array(split).slice(1, split.size() - 1)).join(" - ") if split.size() > 1 else SSQEMap.ss(p.songName)
	var artist := SSQEMap.ss(p.songArtist)
	if artist == "" and split.size() > 1:
		artist = split[0]
	a_label(info, "Song Title", X, Y, 104, 20)
	_x.title = a_box(info, X + 104, Y, W, 20, title)
	a_label(info, "Song Artist", X, Y + 25, 104, 20)
	_x.artist = a_box(info, X + 104, Y + 25, W, 20, artist)
	a_label(info, "Difficulty", X, Y + 50, 104, 20)
	_x.diff = a_combo(info, SSQEMap.DIFFICULTIES, SSQEMap.ss(p.difficulty), X + 104, Y + 50, W, 20)
	a_label(info, "Custom Difficulty (Optional)", X, Y + 74, 204, 20)
	_x.custom = a_box(info, X + 204, Y + 74, 136, 20, SSQEMap.ss(p.customDifficulty))
	a_label(info, "Rating", X, Y + 99, 104, 20)
	_x.rating = a_box(info, X + 104, Y + 99, W, 20, str(p.rating))
	a_label(info, "Artist Link", X, Y + 124, 104, 20)
	var link := ""
	if map.artist_links is Dictionary and not map.artist_links.empty():
		link = SSQEMap.ss(map.artist_links.values()[0])
	_x.link = a_box(info, X + 104, Y + 124, W, 20, link)
	a_label(info, "Artist Platform", X, Y + 149, 104, 20)
	_x.platform = a_box(info, X + 104, Y + 149, W, 20, SSQEMap.ss(p.phxmPlatform))
	var ml := a_label(info, "Mapper(s)\n\n(One per line)", X, Y + 174, 104, 60)
	ml.valign = Label.VALIGN_TOP
	_x.mappers = TextEdit.new()
	_x.mappers.theme = theme_res
	_x.mappers.text = SSQEMap.ss(p.mappers) if SSQEMap.ss(p.mappers) != "" else SSQEMap.ss(p.mapCreator)
	_place(info, _x.mappers, X + 104, Y + 174, W, 100, 12)
	a_label(info, "Cover Image", X, Y + 284, 104, 20)
	_x.cover = a_box(info, X + 104, Y + 281.5, W - 60, 25, "Map cover" if ed.page and ed.page.has_cover() else "None")
	_x.cover.editable = false
	a_button(info, "Select", X + 285, Y + 281.5, 55, 25, "_x_select_cover")
	_x.use_cover = a_check(info, "Use Cover", bool(p.useCover), X + 104, Y + 319, W, 20)
	a_button(info, "Finish", X, Y + 343, 340, 36, "_x_finish_phxm")

func _x_finish_phxm():
	var map = ed.map
	var p: Dictionary = map.props
	var title: String = _x.title.text.strip_edges()
	if title == "":
		title = "Untitled Song"
	p.songTitle = title
	p.songArtist = _x.artist.text
	p.difficulty = SSQEMap.DIFFICULTIES[_x.diff.selected]
	p.customDifficulty = _x.custom.text
	p.rating = float(_x.rating.text) if _x.rating.text.is_valid_float() else 0.0
	p.phxmPlatform = _x.platform.text
	p.mappers = _x.mappers.text
	p.useCover = _x.use_cover.pressed
	map.artist_links = {_x.artist.text: _x.link.text} if _x.link.text != "" else {}
	ed.on_map_changed()
	var cover := PoolByteArray()
	if _x.use_cover.pressed:
		if _x.cover_path != "":
			cover = _read_bytes(_x.cover_path)
		elif ed.page:
			cover = ed.page.cover_bytes()
	var audio: PoolByteArray = ed.page.audio_bytes() if ed.page else PoolByteArray()
	if audio.empty():
		message("No audio is loaded for this map.", "Error")
		return
	var mappers := []
	for m in SSQEMap.ss(_x.mappers.text).split("\n"):
		if m.strip_edges() != "":
			mappers.append(m.strip_edges())
	var meta := {
		"title": title, "artist": _x.artist.text, "mappers": PoolStringArray(mappers if not mappers.empty() else ["None"]).join("\n"),
		"difficulty": p.difficulty, "customDifficulty": _x.custom.text, "rating": p.rating,
		"artistLink": _x.link.text, "artistPlatform": _x.platform.text, "duration": ed.song_length * 1000.0,
	}
	var bytes := F.write_phxm(map, meta, audio, cover)
	var id := F.fix_id("%s - %s - %s" % [SSQEMap.ss(meta.mappers).split("\n")[0], title, meta.artist])
	_save_bytes(bytes, id + ".phxm", "*.phxm ; Rewrite map")
	close("export_phxm")

# ================================================================== Novastra export (ExportNOVA)

func export_nova():
	var p: Dictionary = ed.map.props
	var X := 12.0
	var Y := 12.0
	var W := 236.0
	var info := floating("export_nova", "Export NOVA", 364, 330)
	_x = {"info": info, "format": "npk", "cover_path": "", "icon_path": SSQEMap.ss(p.novaIcon)}
	var split := SSQEMap.ss(p.songName).split(" - ")
	var title := SSQEMap.ss(p.songTitle)
	if title == "":
		title = PoolStringArray(Array(split).slice(1, split.size() - 1)).join(" - ") if split.size() > 1 else SSQEMap.ss(p.songName)
	var artist := SSQEMap.ss(p.songArtist).replace("\n", ", ")
	if artist == "" and split.size() > 1:
		artist = split[0]
	var mapper := SSQEMap.ss(p.mapCreator)
	if mapper == "":
		mapper = SSQEMap.ss(p.mappers).split("\n")[0]
	a_label(info, "Title", X, Y, 104, 20)
	_x.title = a_box(info, X + 104, Y, W, 20, title)
	a_label(info, "Artist", X, Y + 25, 104, 20)
	_x.artist = a_box(info, X + 104, Y + 25, W, 20, artist)
	a_label(info, "Mapper", X, Y + 50, 104, 20)
	_x.mapper = a_box(info, X + 104, Y + 50, W, 20, mapper)
	a_label(info, "Social Link (Optional)", X, Y + 75, 150, 20)
	_x.link = a_box(info, X + 154, Y + 75, W - 50, 20, SSQEMap.ss(p.mapCreatorPersonalLink))
	a_label(info, "Cover Image", X, Y + 103, 104, 20)
	_x.cover = a_box(info, X + 104, Y + 100.5, W - 60, 25, "Map cover" if ed.page and ed.page.has_cover() else "None")
	_x.cover.editable = false
	a_button(info, "Select", X + 285, Y + 100.5, 55, 25, "_x_select_cover")
	_x.use_cover = a_check(info, "Use Cover", bool(p.useCover) or (ed.page != null and ed.page.has_cover()), X + 104, Y + 130, W, 20)
	a_label(info, "Profile Icon", X, Y + 158, 104, 20)
	_x.icon = a_box(info, X + 104, Y + 155.5, W - 60, 25, _x.icon_path.get_file() if _x.icon_path != "" else "None")
	_x.icon.editable = false
	a_button(info, "Select", X + 285, Y + 155.5, 55, 25, "_x_select_icon")
	a_label(info, "Song Offset (ms)", X, Y + 188, 140, 20)
	_x.offset = a_box(info, X + 144, Y + 188, 110, 20, str(int(float(SSQEMap.ss(p.songOffset)))) if SSQEMap.ss(p.songOffset).is_valid_float() else "0")
	a_button(info, "Current Pos", X + 260, Y + 186, 80, 24, "_x_nova_pos", ["offset"])
	a_label(info, "Preview Start (ms)", X, Y + 216, 140, 20)
	_x.pstart = a_box(info, X + 144, Y + 216, 110, 20, SSQEMap.ss(p.previewStartTime) if SSQEMap.ss(p.previewStartTime) != "" else "0")
	a_button(info, "Current Pos", X + 260, Y + 214, 80, 24, "_x_nova_pos", ["start"])
	a_label(info, "Preview Duration (ms)", X, Y + 244, 140, 20)
	_x.pdur = a_box(info, X + 144, Y + 244, 110, 20, SSQEMap.ss(p.previewDuration) if SSQEMap.ss(p.previewDuration) != "" else "0")
	a_button(info, "Current Pos", X + 260, Y + 242, 80, 24, "_x_nova_pos", ["duration"])
	a_button(info, "Finish", X, Y + 274, 340, 36, "_x_finish_nova")

func _x_nova_pos(which: String):
	if _x.empty():
		return
	var now := int(ed.current_time())
	var start := int(_x.pstart.text) if _x.pstart.text.is_valid_integer() else 0
	var dur := int(_x.pdur.text) if _x.pdur.text.is_valid_integer() else 0
	match which:
		"offset":
			_x.offset.text = str(now)
		"start":
			# keep the preview's end where it was
			_x.pstart.text = str(now)
			_x.pdur.text = str(max(0, dur + start - now))
		"duration":
			_x.pdur.text = str(max(0, now - start))

func _x_select_icon():
	Globals.file_sel.raise()
	Globals.file_sel.open_file(self, "_x_icon_picked", PoolStringArray(["*.png, *.jpg, *.jpeg ; Images"]), false, _start_dir())

func _x_icon_picked(files):
	var path := _first(files)
	if path == "" or _x.empty():
		return
	_x.icon_path = path
	_x.icon.text = path.get_file()

func _x_finish_nova():
	var map = ed.map
	var p: Dictionary = map.props
	var audio: PoolByteArray = ed.page.audio_bytes() if ed.page else PoolByteArray()
	if audio.empty():
		message("No audio is loaded for this map.", "Error")
		return
	var ext: String = EditorProject.audio_ext(audio)
	if ext == "":
		message("Novastra needs the song as an MP3 or OGG. Use CONVERT TO MP3 (TIMING) first.", "Error")
		return
	var title: String = _x.title.text.strip_edges()
	if title == "":
		title = "Untitled Song"
	var meta := {
		"songTitle": title, "songArtist": _x.artist.text.strip_edges(), "mapCreator": _x.mapper.text.strip_edges(),
		"mapCreatorPersonalLink": _x.link.text.strip_edges(),
		"songOffset": int(_x.offset.text) if _x.offset.text.is_valid_integer() else 0,
		"previewStartTime": int(_x.pstart.text) if _x.pstart.text.is_valid_integer() else 0,
		"previewDuration": int(_x.pdur.text) if _x.pdur.text.is_valid_integer() else 0,
	}
	p.songTitle = meta.songTitle
	p.romanizedTitle = SSQEImport.fix_ascii(meta.songTitle)
	p.songArtist = meta.songArtist
	p.romanizedArtist = SSQEImport.fix_ascii(meta.songArtist)
	p.mapCreator = meta.mapCreator
	p.mapCreatorPersonalLink = meta.mapCreatorPersonalLink
	p.songOffset = str(meta.songOffset)
	p.previewStartTime = str(meta.previewStartTime)
	p.previewDuration = str(meta.previewDuration)
	p.novaIcon = _x.icon_path
	p.useCover = _x.use_cover.pressed
	ed.on_map_changed()
	var cover := PoolByteArray()
	if _x.use_cover.pressed:
		cover = _read_bytes(_x.cover_path) if _x.cover_path != "" else (ed.page.cover_bytes() if ed.page else PoolByteArray())
	var icon := _read_bytes(_x.icon_path) if _x.icon_path != "" else PoolByteArray()
	var bytes := F.write_npk(map, meta, audio, ext, cover, icon)
	var id := F.fix_id("%s_-_%s_-_%s" % [meta.mapCreator.to_lower().replace(" ", "_"), meta.songArtist.to_lower().replace(" ", "_"), title.to_lower().replace(" ", "_")])
	_save_bytes(bytes, id + ".npk", "*.npk ; Novastra chart")
	close("export_nova")

# ================================================================== SSQE export (QEMZ.Export)

func export_qemz():
	var map = ed.map
	var audio: PoolByteArray = ed.page.audio_bytes() if ed.page else PoolByteArray()
	if audio.empty():
		message("No audio is loaded for this map.", "Error")
		return
	var cover: PoolByteArray = ed.page.cover_bytes() if ed.page and bool(map.props.useCover) else PoolByteArray()
	var mappers := SSQEMap.ss(map.props.mappers).split("\n")
	var artists := SSQEMap.ss(map.props.songArtist).split("\n")
	var id := F.fix_id("%s - %s - %s" % [mappers[0] if mappers[0] != "" else "none", artists[0] if artists[0] != "" else "unknown", SSQEMap.ss(map.props.songTitle)])
	_save_bytes(F.write_qemz(map, audio, cover), id + ".qemz", "*.qemz ; Quantum Editor map")

# ================================================================== saving files

var _pending_bytes := PoolByteArray()
var _pending_name := ""

func _save_bytes(bytes: PoolByteArray, name: String, filter: String):
	_pending_bytes = bytes
	_pending_name = name
	Globals.file_sel.raise()
	Globals.file_sel.save_file(self, "_save_picked", PoolStringArray([filter]), _start_dir().plus_file(name))

func _save_picked(path):
	if not (path is String) or path == "":
		return
	var ext := _pending_name.get_extension()
	if path.get_extension().to_lower() != ext:
		path += "." + ext
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		message("Couldn't write " + path, "Error")
		return
	f.store_buffer(_pending_bytes)
	f.close()
	_pending_bytes = PoolByteArray()
	ed.toast("EXPORTED " + ext.to_upper())

static func _start_dir() -> String:
	if OS.has_feature("pc"):
		var d := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		return d if d != "" else "user://"
	return "user://"

static func _first(files) -> String:
	if files is PoolStringArray and files.size() > 0:
		return files[0]
	if files is Array and files.size() > 0:
		return SSQEMap.ss(files[0])
	if files is String:
		return files
	return ""

static func _read_bytes(path: String) -> PoolByteArray:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return PoolByteArray()
	var b := f.get_buffer(f.get_len())
	f.close()
	return b

# ================================================================== auto mapper options

var _am_rows := []

func auto_map_options():
	var s: Dictionary = ed.s
	var X := 12.0
	var LW := 150.0
	var CW := 170.0
	var VX := X + LW + CW + 8
	var rows := []
	# the height is known once all rows are added: build in a list first
	var y := 12.0
	var spec := [
		["slider", "Target Stars", "autoMapStars", 1, 15, 0.1, 5.0, "%.1f*"],
		["slider", "Density", "autoMapDensity", 25, 300, 5, 100, "%d%%"],
		["number", "Notes to Add (0 = Auto)", "autoMapCount", 0, 100000, 0],
		["gap", 6],
		["slider", "Flow", "autoMapFlow", 0, 100, 5, 70, "%d%%"],
		["slider", "Follow Learned Maps", "autoMapFollow", 0, 100, 5, 75, "%d%%"],
		["slider", "Jump Size", "autoMapJump", 50, 200, 5, 100, "%d%%"],
		["choice", "Patterns", "autoMapPatterns", [["mixed", "Mixed (streams and jumps)"], ["streams", "Stream map (only streams)"], ["jumps", "Jump map (big moves)"]], "mixed"],
		["slider", "Streams / Jumps", "autoMapJumpShare", 0, 100, 5, 50, "%d%% jumps"],
		["slider", "Drop Intensity", "autoMapDrops", 0, 200, 10, 100, "%d%%"],
		["slider", "Variety", "autoMapVariety", 0, 100, 5, 50, "%d%%"],
		["sources"],
		["slider", "Sensitivity", "autoMapSensitivity", 0, 100, 5, 50, "%d%%"],
		["choice", "Fill Streams", "autoMapFill", [["intense", "In intense parts"], ["busy", "Wherever the song is busy"], ["never", "Never (only on sounds)"]], "intense"],
		["slider", "Calm Parts", "autoMapCalm", 0, 100, 5, 30, "%d%%"],
		["gap", 6],
		["slider", "Quantum", "autoMapQuantumPct", 0, 100, 1, 0, "%d%%"],
		["slider", "Similar to This Map", "autoMapSimilarity", 0, 100, 5, 0, "%d%%"],
		["check", "Follow this map's own patterns", "autoMapUseMap", true],
		["check", "Set the detected BPM when the map has none", "autoMapSetBpm", true],
		["gap", 8],
	]
	var height := 12.0
	for r in spec:
		match r[0]:
			"slider", "number", "choice": height += 30
			"check": height += 28
			"gap": height += r[1]
			"sources": height += 78
	height += 42
	var info := floating("autoMapOptions", "Auto Mapper Options", 418, height)
	_am_rows = []
	for r in spec:
		match r[0]:
			"gap":
				y += r[1]
			"slider":
				a_label(info, r[1], X, y, LW, 22)
				var sl := HSlider.new()
				sl.theme = theme_res
				sl.min_value = r[3]
				sl.max_value = r[4]
				sl.step = r[5]
				sl.value = float(s.get(r[2], r[6]))
				_place(info, sl, X + LW, y, CW, 22, 0)
				var vl := a_label(info, "", VX, y, 60, 22)
				sl.connect("value_changed", self, "_am_slider", [r[2], vl, r[7]])
				_am_slider(sl.value, r[2], vl, r[7], false)
				_am_rows.append({"key": r[2], "def": r[6], "node": sl})
				y += 30
			"number":
				a_label(info, r[1], X, y, LW, 22)
				var box := a_box(info, X + LW, y, 80, 22, str(s.get(r[2], r[5])))
				box.connect("text_entered", self, "_am_number", [box, r[2], r[3], r[4]])
				box.connect("focus_exited", self, "_am_number", ["", box, r[2], r[3], r[4]])
				_am_rows.append({"key": r[2], "def": r[5], "node": box})
				y += 30
			"choice":
				a_label(info, r[1], X, y, LW, 22)
				var names := []
				var values := []
				for o in r[3]:
					values.append(o[0])
					names.append(o[1])
				var cb := a_combo(info, names, names[max(0, values.find(SSQEMap.ss(s.get(r[2], r[4]))))], X + LW, y, CW + 60, 22)
				cb.connect("item_selected", self, "_am_choice", [r[2], values])
				_am_rows.append({"key": r[2], "def": r[4], "node": cb, "values": values})
				y += 30
			"check":
				var c := a_check(info, r[1], bool(s.get(r[2], r[3])), X, y, LW + CW + 60, 22)
				c.connect("toggled", self, "_am_check", [r[2]])
				_am_rows.append({"key": r[2], "def": r[3], "node": c})
				y += 28
			"sources":
				a_label(info, "Sync To", X, y, LW, 22)
				var on := SSQEMap.ss(s.get("autoMapSources", "kick,snare,hat")).split(",")
				var srcs := [["kick", "Kicks"], ["snare", "Snares & claps"], ["hat", "Hi-hats & cymbals"], ["melody", "Melody & vocals"], ["bass", "Bass"]]
				var boxes := []
				for i in range(srcs.size()):
					var c2 := a_check(info, srcs[i][1], srcs[i][0] in on, X + LW + (i % 2) * 125, y + (i / 2) * 24, 122, 22)
					boxes.append([c2, srcs[i][0]])
				for b in boxes:
					b[0].connect("toggled", self, "_am_sources", [b[0], boxes])
				_am_rows.append({"key": "autoMapSources", "def": "kick,snare,hat", "boxes": boxes})
				y += 78
	a_button(info, "Reset to Defaults", X, y, 170, 30, "_am_reset")
	a_button(info, "Auto Map", X + 180, y, 214, 30, "_am_run")

func _am_slider(v: float, key: String, label: Label, fmt: String, save := true):
	label.text = fmt % v
	if save:
		ed.s[key] = v
		ed.settings_changed()

func _am_number(_t, box: LineEdit, key: String, mn: float, mx: float):
	var v := int(clamp(round(float(box.text)) if box.text.is_valid_float() else 0.0, mn, mx))
	box.text = str(v)
	ed.s[key] = v
	ed.settings_changed()

func _am_choice(i: int, key: String, values: Array):
	ed.s[key] = values[i]
	ed.settings_changed()

func _am_check(on: bool, key: String):
	ed.s[key] = on
	ed.settings_changed()

func _am_sources(on: bool, c: CheckBox, boxes: Array):
	var list := []
	for b in boxes:
		if b[0].pressed:
			list.append(b[1])
	if list.empty():
		c.pressed = true
		return
	ed.s.autoMapSources = PoolStringArray(list).join(",")
	ed.settings_changed()

func _am_reset():
	for r in _am_rows:
		ed.s[r.key] = r.def
	ed.settings_changed()
	auto_map_options()

func _am_run():
	if ed.page:
		ed.page.auto_map()

# ================================================================== Settings (GuiWindowSettings + GuiWindowKeybinds)
# Sound Space Quantum Editor Plus's settings window: tabs on the left, the
# settings of the tab on the right, saved as you change them (ed.s, saved to
# user://editor/ssqe_settings.json by ed.settings_changed).

const SETTINGS_TABS = ["COLORS", "GRAPHICS", "MAPPING", "PLAYER", "AUDIO", "KEYBINDS", "OTHER"]
var _st: Dictionary = {}
var _kb_capture := "" # the keybind waiting for a key

func settings(tab := ""):
	var info := floating("settings", "Editor Settings", 860, 560, true)
	var k: float = info.k
	_st = {"info": info, "tab": "", "content": null, "rows": [], "k": k}
	# the tabs, down the left
	var side := Panel.new()
	side.add_stylebox_override("panel", _st_box(ST_SIDE, 8))
	side.mouse_filter = MOUSE_FILTER_PASS
	_place(info, side, 8, 8, 176, 494, 0)
	var tabs := VBoxContainer.new()
	tabs.anchor_right = 1
	tabs.anchor_bottom = 1
	tabs.margin_left = 8 * k
	tabs.margin_top = 8 * k
	tabs.margin_right = -8 * k
	tabs.margin_bottom = -8 * k
	tabs.add_constant_override("separation", int(4 * k))
	side.add_child(tabs)
	_st.tab_buttons = {}
	for t in SETTINGS_TABS:
		var b := Button.new()
		b.text = ST_TAB_NAMES.get(t, t.capitalize())
		b.align = Button.ALIGN_LEFT
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.rect_min_size = Vector2(0, 40 * k)
		b.add_font_override("font", ed.font(int(15 * k), true))
		b.connect("pressed", self, "_st_tab", [t])
		tabs.add_child(b)
		_st.tab_buttons[t] = b
	# the settings of a tab, scrolling when there are many
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.mouse_filter = MOUSE_FILTER_PASS
	_place(info, sc, 196, 8, 656, 494, 0)
	_st.scroll = sc
	# the bottom bar
	_st_flat(a_button(info, "RESET TO DEFAULT", 8, 512, 176, 38, "_st_reset"), false)
	_st_flat(a_button(info, "OPEN EDITOR FOLDER", 506, 512, 170, 38, "_st_folder"), false)
	_st_flat(a_button(info, "SAVE AND CLOSE", 684, 512, 168, 38, "close", ["settings"]), true)
	_st_tab(tab if tab in SETTINGS_TABS else String(ed.s.get("lastSettingsTab", "COLORS")))

const ST_TAB_NAMES = {"COLORS": "Colors", "GRAPHICS": "Graphics", "MAPPING": "Mapping", "PLAYER": "Playtest",
	"AUDIO": "Audio", "KEYBINDS": "Keybinds", "OTHER": "Other"}
const ST_SIDE = Color(0.05, 0.043, 0.075, 1)
const ST_ROW = Color(1, 1, 1, 0.035)
const ST_ROW_HOVER = Color(1, 1, 1, 0.06)
const ST_DIM = Color(0.62, 0.6, 0.68, 1)

func _st_box(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb

# a bottom-bar button: lilac (the main one) or quiet
func _st_flat(b: Button, main: bool):
	var k: float = _st.k
	var dark := Color(0.1, 0.07, 0.12)
	for st in ["normal", "hover", "pressed", "focus"]:
		var bg: Color
		if main:
			bg = LILAC if st == "normal" else ACCENT
		else:
			bg = Color(1, 1, 1, 0.05) if st == "normal" else Color(1, 1, 1, 0.1)
		var sb: StyleBox = _st_box(bg, int(8 * k)) if st != "focus" else StyleBoxEmpty.new()
		b.add_stylebox_override(st, sb)
	b.add_font_override("font", ed.font(int(13 * k), true))
	for c in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_color_override(c, dark if main else TEXT)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND

func _st_tab(t: String):
	if _st.empty() or not windows.has("settings"):
		return
	var k: float = _st.k
	_kb_capture = ""
	_st.tab = t
	ed.s["lastSettingsTab"] = t
	# the open tab: lit, with a lilac bar on its left
	for name in _st.tab_buttons:
		var b: Button = _st.tab_buttons[name]
		var on: bool = name == t
		var n := _st_box(Color(LILAC.r, LILAC.g, LILAC.b, 0.16) if on else Color(0, 0, 0, 0), int(7 * k))
		n.content_margin_left = 14 * k
		if on:
			n.border_color = LILAC
			n.border_width_left = int(max(2, 3 * k))
		var h := _st_box(Color(LILAC.r, LILAC.g, LILAC.b, 0.2) if on else Color(1, 1, 1, 0.05), int(7 * k))
		h.content_margin_left = 14 * k
		h.border_color = LILAC
		h.border_width_left = int(max(2, 3 * k)) if on else 0
		b.add_stylebox_override("normal", n)
		b.add_stylebox_override("hover", h)
		b.add_stylebox_override("pressed", h)
		b.add_stylebox_override("focus", StyleBoxEmpty.new())
		for c in ["font_color", "font_color_hover", "font_color_pressed"]:
			b.add_color_override(c, TEXT if on else ST_DIM)
	if _st.content != null and is_instance_valid(_st.content):
		_st.content.queue_free()
	# (rows of the tab that's going)
	_st.rows = []
	_st.erase("note_box")
	_st.erase("note_pick")
	var sc: ScrollContainer = _st.scroll
	var list := VBoxContainer.new()
	list.rect_min_size = Vector2(sc.rect_size.x - 16 * k, 0)
	list.add_constant_override("separation", int(5 * k))
	list.mouse_filter = MOUSE_FILTER_PASS
	sc.add_child(list)
	sc.scroll_vertical = 0
	_st.content = list
	_st.list = list
	match t:
		"COLORS":
			_sr_section("Editor colors", "The track, grid and timeline")
			_sr_color("Color 1", "1/X beat ticks, primary", "color1")
			_sr_color("Color 2", "1/1 beat ticks, secondary", "color2")
			_sr_color("Color 3", "1/2 beat ticks, preview", "color3")
			_sr_color("Color 4", "Waveform", "color4")
			_sr_color("Color 5", "Special objects", "color5")
			_st_note_colors()
		"GRAPHICS":
			_sr_section("Display", "")
			_sr_slider("Editor background opacity", "", "editorBGOpacity", 0, 255, 1)
			_sr_slider("Grid opacity", "", "gridOpacity", 0, 255, 1)
			_sr_slider("Track opacity", "", "trackOpacity", 0, 255, 1)
			_sr_toggle("Show control gradients", "A soft shade on the buttons", "controlGradients")
			_sr_section("Grid", "")
			_sr_slider("Grid zoom", "%", "gridZoom", 25, 200, 1)
			_sr_slider("Grid note size", "%", "gridNoteSize", 25, 200, 1)
			_sr_toggle("Grid squircles", "Rounded notes on the grid", "gridSquircles")
			_sr_slider("Squircle corner radius", "Share of the note's size", "gridSquircleRadius", 0, 0.5, 0.005)
			_sr_slider("Squircle corner detail", "Points per rounded corner", "gridSquircleDetail", 1, 20, 1)
			_sr_toggle("Grid letters", "", "gridLetters")
			_sr_toggle("Grid numbers", "", "gridNumbers")
			_sr_toggle("Approach squares", "", "approachSquares")
			_sr_toggle("Quantum grid lines", "", "quantumGridLines")
			_sr_section("Waveform", "")
			_sr_toggle("Enable waveform", "", "waveform")
			_sr_toggle("Classic waveform", "One line, like the original SSQE", "classicWaveform")
			_sr_slider("Waveform level of detail", "Points per 10 ms", "waveformDetail", 1, 20, 1)
			_sr_section("3D", "")
			_sr_toggle("3D mode", "", "mode3D")
			_sr_toggle("3D hit effect", "", "mode3DHitEffect")
		"MAPPING":
			_sr_section("Placing and moving", "")
			_sr_toggle("Separate click tools", "Left click places, right click selects", "separateClickTools")
			_sr_toggle("Auto-advance", "Move on a beat after placing a note", "autoAdvance")
			_sr_toggle("Snap to quantum grid", "", "quantumGridSnap")
			_sr_toggle("Old quantum snapping", "", "oldQuantumSnap")
			_sr_toggle("Move cursor with grid keys", "", "moveOnGridKey")
			_sr_toggle("Use numpad for grid keys", "", "numpad")
			_sr_toggle("Adjust notes with timing", "Notes follow when a timing point moves", "adjustNotes")
			_sr_section("Copy and paste", "")
			_sr_toggle("Correct errors on copy", "", "correctOnCopy")
			_sr_toggle("Apply timing on paste", "", "applyOnPaste")
			_sr_toggle("Jump to pasted notes", "", "jumpPaste")
			_sr_toggle("Paste reversed", "", "pasteReversed")
			_sr_section("Scrolling", "")
			_sr_toggle("Reverse scroll direction", "", "reverseScroll")
			_sr_toggle("Pause when scrolling", "", "pauseScroll")
			_sr_section("Patterns", "")
			_sr_toggle("Curve bezier", "", "curveBezier")
			_sr_slider("Bezier divisor", "", "bezierDivisor", 1, 32, 1)
			_sr_toggle("Clamp star rating", "", "clampSR")
		"PLAYER":
			_sr_section("Playtest and preview", "")
			_sr_slider("Approach rate", "", "approachRate", 1, 50, 1)
			_sr_slider("Track cursor position", "% from the left", "cursorPos", 0, 100, 1)
			_sr_toggle("Autoplay cursor", "", "autoplay")
			_sr_toggle("Smooth autoplay", "", "smoothAutoplay")
		"AUDIO":
			_sr_section("Volume", "")
			_sr_slider("Music volume", "", "masterVolume", 0, 1, 0.01)
			_sr_slider("Hit sound volume", "", "sfxVolume", 0, 1, 0.01)
			_sr_toggle("Mute music", "", "muteMusic")
			_sr_toggle("Mute hit sounds", "", "muteSfx")
			_sr_toggle("Mono audio", "Left and right mixed together", "monoAudio")
			_sr_section("Timing", "")
			_sr_slider("Hit sound offset", "ms", "sfxOffset", -200, 200, 1)
			_sr_slider("Music offset", "ms", "musicOffset", -500, 500, 1)
			_sr_slider("Maximum polyphony", "Hit sounds at once", "maxPolyphony", 1, 16, 1)
			_sr_section("Metronome", "")
			_sr_toggle("Metronome", "", "metronome")
			_sr_toggle("Scale metronome with divisor", "", "scaleMetronome")
		"KEYBINDS":
			_st_keybinds()
		"OTHER":
			_sr_section("Saving", "")
			_sr_toggle("Enable autosave", "", "autosave")
			_sr_slider("Autosave interval", "minutes", "autosaveInterval", 0.5, 30, 0.5)
			var note := _sr_text("Your maps are saved in the editor folder (OPEN EDITOR FOLDER). Exported maps go to your map list.")
			note.autowrap = true

# ---- rows

func _sr_text(text: String, bold := false, size := 13, color := ST_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", ed.font(int(size * _st.k), bold))
	l.add_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	_st.list.add_child(l)
	return l

func _sr_section(title: String, desc: String):
	var k: float = _st.k
	var gap := Control.new()
	gap.rect_min_size = Vector2(0, (6 if _st.list.get_child_count() == 0 else 14) * k)
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	_st.list.add_child(gap)
	_sr_text(title.to_upper(), true, 12, LILAC)
	if desc != "":
		_sr_text(desc, false, 12)

# a row: the name (and a short note) on the left, its control on the right
func _sr_row(label: String, hint: String) -> HBoxContainer:
	var k: float = _st.k
	var row := PanelContainer.new()
	var sb := _st_box(ST_ROW, int(8 * k))
	sb.content_margin_left = 14 * k
	sb.content_margin_right = 12 * k
	sb.content_margin_top = 7 * k
	sb.content_margin_bottom = 7 * k
	row.add_stylebox_override("panel", sb)
	row.mouse_filter = MOUSE_FILTER_PASS
	row.connect("mouse_entered", self, "_sr_hover", [sb, true])
	row.connect("mouse_exited", self, "_sr_hover", [sb, false])
	_st.list.add_child(row)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", int(12 * k))
	row.add_child(h)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	names.size_flags_vertical = SIZE_SHRINK_CENTER
	names.add_constant_override("separation", 0)
	h.add_child(names)
	var l := Label.new()
	l.text = label
	l.add_font_override("font", ed.font(int(14 * k), true))
	l.add_color_override("font_color", TEXT)
	names.add_child(l)
	if hint != "":
		var hl := Label.new()
		hl.text = hint
		hl.add_font_override("font", ed.font(int(12 * k)))
		hl.add_color_override("font_color", ST_DIM)
		names.add_child(hl)
	return h

func _sr_hover(sb: StyleBoxFlat, on: bool):
	sb.bg_color = ST_ROW_HOVER if on else ST_ROW

func _sr_toggle(label: String, hint: String, key: String) -> CheckButton:
	var h := _sr_row(label, hint)
	var cb := CheckButton.new()
	cb.focus_mode = FOCUS_NONE
	cb.flat = true
	cb.pressed = bool(ed.s.get(key, false))
	cb.size_flags_vertical = SIZE_SHRINK_CENTER
	cb.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	cb.add_icon_override("on", _st_switch(true))
	cb.add_icon_override("off", _st_switch(false))
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		cb.add_stylebox_override(st, StyleBoxEmpty.new())
	cb.connect("toggled", self, "_st_set", [key])
	h.add_child(cb)
	return cb

func _sr_slider(label: String, hint: String, key: String, mn: float, mx: float, step: float) -> HSlider:
	var k: float = _st.k
	var h := _sr_row(label, hint)
	var sl := HSlider.new()
	sl.theme = theme_res
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(ed.s.get(key, mn))
	sl.focus_mode = FOCUS_NONE
	sl.rect_min_size = Vector2(210 * k, 0)
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	h.add_child(sl)
	var vl := Label.new()
	vl.text = _st_fmt(sl.value, step)
	vl.align = Label.ALIGN_CENTER
	vl.valign = Label.VALIGN_CENTER
	vl.rect_min_size = Vector2(62 * k, 0)
	vl.size_flags_vertical = SIZE_SHRINK_CENTER
	vl.add_font_override("font", ed.font(int(13 * k), true))
	vl.add_color_override("font_color", TEXT)
	var pill := _st_box(Color(0, 0, 0, 0.3), int(6 * k))
	pill.content_margin_top = 3 * k
	pill.content_margin_bottom = 3 * k
	vl.add_stylebox_override("normal", pill)
	h.add_child(vl)
	sl.connect("value_changed", self, "_st_slid", [key, vl, step])
	return sl

func _sr_color(label: String, hint: String, key: String):
	var k: float = _st.k
	var h := _sr_row(label, hint)
	var p := ColorPickerButton.new()
	p.theme = theme_res
	p.edit_alpha = false
	p.color = SSQESettings.color(ed.s, key)
	p.focus_mode = FOCUS_NONE
	p.rect_min_size = Vector2(110 * k, 28 * k)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	p.connect("color_changed", self, "_st_color_set", [key])
	h.add_child(p)
	var d := Button.new()
	d.text = "Default"
	d.focus_mode = FOCUS_NONE
	d.size_flags_vertical = SIZE_SHRINK_CENTER
	d.connect("pressed", self, "_st_color_default", [key, p])
	_st_small(d)
	h.add_child(d)

func _st_small(b: Button):
	var k: float = _st.k
	for st in ["normal", "hover", "pressed"]:
		var sb := _st_box(Color(1, 1, 1, 0.06 if st == "normal" else 0.12), int(6 * k))
		sb.content_margin_left = 10 * k
		sb.content_margin_right = 10 * k
		sb.content_margin_top = 4 * k
		sb.content_margin_bottom = 4 * k
		b.add_stylebox_override(st, sb)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_font_override("font", ed.font(int(12 * k), true))
	for c in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_color_override(c, TEXT)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND

# an on / off switch (smooth edges, sized for this window)
func _st_switch(on: bool) -> Texture:
	var key := "sw_%s_%d" % [str(on), int(_st.k * 100)]
	if _sw_cache.has(key):
		return _sw_cache[key]
	var w := int(round(42 * _st.k))
	var hh := int(round(24 * _st.k))
	var img := Image.new()
	img.create(w, hh, false, Image.FORMAT_RGBA8)
	img.lock()
	var r := hh / 2.0
	var track: Color = LILAC if on else Color(0.24, 0.22, 0.3)
	var knob: Color = Color(1, 1, 1) if on else Color(0.72, 0.7, 0.78)
	var kc: Vector2 = Vector2(w - r if on else r, r)
	var kr: float = r - 3.0 * _st.k
	for y in range(hh):
		for x in range(w):
			var p := Vector2(x + 0.5, y + 0.5)
			# distance to the pill's middle line, then to the knob
			var cx: float = clamp(p.x, r, w - r)
			var dt := p.distance_to(Vector2(cx, r)) - r
			var dk := p.distance_to(kc) - kr
			var a_t: float = clamp(0.5 - dt, 0.0, 1.0)
			var a_k: float = clamp(0.5 - dk, 0.0, 1.0)
			var col := track.linear_interpolate(knob, a_k)
			col.a = a_t
			img.set_pixel(x, y, col)
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	_sw_cache[key] = tex
	return tex

var _sw_cache := {}

# SSQE+'s note colour list (the notes cycle through it): a swatch per colour,
# PICK COLOR chooses one and ADD COLOR adds it. Left click a swatch to remove
# it, right click to move it left. Used when "Use these note colors" is on;
# otherwise the notes take the game's colour set.
const MAX_NOTE_COLORS = 32

func _st_note_colors():
	var k: float = _st.k
	_sr_section("Note colors", "The notes cycle through these. Left click a colour to remove it, right click to move it left.")
	_sr_toggle("Use these note colors", "Off: your colour set from the game's settings", "customNoteColors")
	var h := _sr_row("Colors", "")
	var box := GridContainer.new()
	box.columns = 8
	box.add_constant_override("hseparation", int(5 * k))
	box.add_constant_override("vseparation", int(5 * k))
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(box)
	_st.note_box = box
	_st.note_k = k
	_st_note_swatches()
	var h2 := _sr_row("Add a colour", "")
	var pick := ColorPickerButton.new()
	pick.theme = theme_res
	pick.edit_alpha = false
	pick.focus_mode = FOCUS_NONE
	pick.color = Color8(255, 255, 255)
	pick.rect_min_size = Vector2(80 * k, 28 * k)
	pick.size_flags_vertical = SIZE_SHRINK_CENTER
	h2.add_child(pick)
	_st.note_pick = pick
	var pb := Button.new()
	pb.text = "Pick color"
	pb.focus_mode = FOCUS_NONE
	pb.size_flags_vertical = SIZE_SHRINK_CENTER
	pb.connect("pressed", self, "_st_note_pick")
	_st_small(pb)
	h2.add_child(pb)
	var ab := Button.new()
	ab.text = "Add color"
	ab.focus_mode = FOCUS_NONE
	ab.size_flags_vertical = SIZE_SHRINK_CENTER
	ab.connect("pressed", self, "_st_note_add")
	_st_small(ab)
	h2.add_child(ab)

func _st_note_swatches():
	var box = _st.get("note_box")
	if box == null or not is_instance_valid(box):
		return
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	var k: float = _st.note_k
	var cols: Array = ed.s.get("noteColors", [])
	for i in range(cols.size()):
		var col: Array = cols[i]
		var sw := Panel.new()
		var sb := _st_box(Color8(int(col[0]), int(col[1]), int(col[2])), int(6 * k), Color(1, 1, 1, 0.35), 1)
		sw.add_stylebox_override("panel", sb)
		sw.rect_min_size = Vector2(26, 26) * k
		sw.hint_tooltip = "Colour %d: left click removes it, right click moves it left" % (i + 1)
		sw.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		sw.connect("gui_input", self, "_st_note_click", [i])
		box.add_child(sw)

func _st_note_click(ev: InputEvent, i: int):
	if not (ev is InputEventMouseButton) or not ev.pressed:
		return
	var cols: Array = ed.s.get("noteColors", []).duplicate(true)
	if i >= cols.size():
		return
	if ev.button_index == BUTTON_LEFT:
		if cols.size() <= 1:
			message("Keep at least one note colour.", "Note Colors")
			return
		cols.remove(i)
	elif ev.button_index == BUTTON_RIGHT and i > 0:
		var t = cols[i - 1]
		cols[i - 1] = cols[i]
		cols[i] = t
	else:
		return
	ed.s["noteColors"] = cols
	ed.settings_changed()
	call_deferred("_st_note_swatches")

func _st_note_pick():
	if _st.has("note_pick") and is_instance_valid(_st.note_pick):
		var pp: PopupPanel = _st.note_pick.get_popup()
		pp.rect_global_position = _st.note_pick.rect_global_position + Vector2(0, _st.note_pick.rect_size.y)
		pp.popup()

func _st_note_add():
	var cols: Array = ed.s.get("noteColors", []).duplicate(true)
	if cols.size() >= MAX_NOTE_COLORS:
		message("There can be up to %d note colours." % MAX_NOTE_COLORS, "Note Colors")
		return
	var col: Color = _st.note_pick.color if _st.has("note_pick") and is_instance_valid(_st.note_pick) else Color(1, 1, 1)
	cols.append([int(round(col.r * 255)), int(round(col.g * 255)), int(round(col.b * 255))])
	ed.s["noteColors"] = cols
	ed.settings_changed()
	_st_note_swatches()

func _st_set(v, key: String):
	ed.s[key] = v
	ed.settings_changed()

static func _st_fmt(v: float, step: float) -> String:
	return str(int(round(v))) if step >= 1.0 else str(stepify(v, step))

func _st_slid(v: float, key: String, vl: Label, step: float):
	vl.text = _st_fmt(v, step)
	ed.s[key] = int(round(v)) if typeof(SSQESettings.defaults().get(key)) == TYPE_INT else v
	ed.settings_changed()

func _st_color_set(col: Color, key: String):
	ed.s[key] = [int(round(col.r * 255)), int(round(col.g * 255)), int(round(col.b * 255))]
	ed.settings_changed()

func _st_color_default(key: String, p: ColorPickerButton):
	ed.s[key] = SSQESettings.defaults()[key].duplicate()
	p.color = SSQESettings.color(ed.s, key)
	ed.settings_changed()

func _st_keybinds():
	var k: float = _st.k
	_sr_section("Keybinds", "Click a key, then press the new key (with Ctrl / Alt / Shift if you want). Esc cancels.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", int(6 * k))
	grid.add_constant_override("vseparation", int(5 * k))
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_st.list.add_child(grid)
	var rows := []
	for name in SSQESettings.KEYBINDS.keys():
		var row := PanelContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		var sb := _st_box(ST_ROW, int(8 * k))
		sb.content_margin_left = 12 * k
		sb.content_margin_right = 8 * k
		sb.content_margin_top = 5 * k
		sb.content_margin_bottom = 5 * k
		row.add_stylebox_override("panel", sb)
		grid.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var l := Label.new()
		l.text = SSQESettings.KEYBIND_LABELS.get(name, name)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.clip_text = true
		l.valign = Label.VALIGN_CENTER
		l.add_font_override("font", ed.font(int(13 * k), true))
		l.add_color_override("font_color", TEXT)
		h.add_child(l)
		var b := Button.new()
		b.text = SSQESettings.keybind_text(ed.s.keybinds[name])
		b.focus_mode = FOCUS_NONE
		b.rect_min_size = Vector2(120 * k, 0)
		b.connect("pressed", self, "_st_kb_pick", [name])
		_st_small(b)
		h.add_child(b)
		rows.append([name, b])
	_st.rows = rows

func _st_kb_pick(name: String):
	_kb_capture = name
	for r in _st.rows:
		if is_instance_valid(r[1]):
			r[1].text = "Press a key..." if r[0] == name else SSQESettings.keybind_text(ed.s.keybinds[r[0]])

func _st_kb_input(ev: InputEventKey) -> bool:
	if _kb_capture == "" or not ev.pressed or ev.echo:
		return false
	if ev.scancode in [KEY_CONTROL, KEY_ALT, KEY_SHIFT, KEY_META]:
		return true # (waiting for the key itself)
	if ev.scancode != KEY_ESCAPE:
		ed.s.keybinds[_kb_capture] = [ev.scancode, ev.control or ev.command, ev.alt, ev.shift]
		ed.settings_changed()
	_kb_capture = ""
	for r in _st.rows:
		if is_instance_valid(r[1]):
			r[1].text = SSQESettings.keybind_text(ed.s.keybinds[r[0]])
	return true

func _st_reset():
	confirm("Reset every editor setting (colours, keybinds and all) to the defaults?", self, "_st_reset_answer")

func _st_reset_answer(answer: String):
	if answer != "yes":
		return
	var keep := {"patterns": ed.s.patterns, "lastLeftNav": ed.s.lastLeftNav, "lastRightNav": ed.s.lastRightNav}
	var d := SSQESettings.defaults()
	for k in d:
		ed.s[k] = keep[k] if keep.has(k) else d[k]
	ed.settings_changed()
	_st_tab(_st.tab)

func _st_folder():
	var dir := Globals.p("user://editor")
	Directory.new().make_dir_recursive(dir)
	OS.shell_open(ProjectSettings.globalize_path(dir) if dir.begins_with("user://") else dir)
