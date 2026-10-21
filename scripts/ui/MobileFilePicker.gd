extends Control

# Phones and tablets: the file browser (open files, save a file, pick a
# folder) made for fingers instead of Godot's FileDialog, whose rows, path box
# and buttons were far too small to tap. Big rows that scroll by dragging,
# a Back button, the folder shown as a path you can read, and big buttons.
# FileSelector.gd opens it and gets the result back through its usual
# files_sel / save_sel / folder_sel / _cancel.

const LILAC := Color(0.764706, 0.65098, 0.8)
const PINK := Color(1.0, 0.757, 0.961)
const TEXT := Color(0.94, 0.95, 1.0)
const DIM := Color(0.66, 0.64, 0.74)
const BG := Color(0.075, 0.065, 0.11, 0.99)
const ROW_A := Color(1, 1, 1, 0.035)
const ROW_SEL := Color(0.764706, 0.65098, 0.8, 0.32)

var sel # the FileSelector
var kind := "open" # "open", "save" or "folder"
var multiselect := false
var exts := [] # allowed extensions (lower case, no dot); empty = every file
var filter_name := ""
var show_all := false
var cur_dir := ""
var root_dir := "" # Back stops here
var entries := [] # [{name, dir, size}]
var selected := {} # file name -> true
var _replace_armed := ""

var u := 1.0 # layout unit (1 at 860 px tall)
var font: DynamicFont
var font_small: DynamicFont
var font_bold: DynamicFont

var top_bar: Control
var back_btn: Button
var path_label: Label
var files_app_btn: Button
var places_btn: Button
var list # FileList
var bottom_bar: Control
var info_label: Label
var name_edit: LineEdit
var all_btn: Button
var cancel_btn: Button
var ok_btn: Button
var places_menu: VBoxContainer

func _init():
	name = "MobileFilePicker"
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	pause_mode = PAUSE_MODE_PROCESS

func _ready():
	theme = load("res://uitheme.tres")
	var jp = load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf")
	font = DynamicFont.new()
	font.font_data = load("res://assets/font/Lato/Lato-Regular.ttf")
	font.add_fallback(jp)
	font.use_filter = true
	font_small = font.duplicate()
	font_bold = DynamicFont.new()
	font_bold.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	font_bold.add_fallback(jp)
	font_bold.use_filter = true
	_build()
	get_viewport().connect("size_changed", self, "_layout")
	_layout()

# --- building ----------------------------------------------------------------

func _button(text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.add_font_override("font", font_bold)
	b.connect("pressed", self, method)
	return b

func _build():
	var bg := ColorRect.new()
	bg.color = BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	top_bar = Control.new()
	top_bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(top_bar)
	back_btn = _button("‹  Back", "_on_back")
	top_bar.add_child(back_btn)
	path_label = Label.new()
	path_label.clip_text = true
	path_label.valign = Label.VALIGN_CENTER
	path_label.add_font_override("font", font_bold)
	path_label.add_color_override("font_color", TEXT)
	top_bar.add_child(path_label)
	places_btn = _button("Places", "_toggle_places")
	places_btn.visible = _places().size() > 1
	top_bar.add_child(places_btn)
	files_app_btn = _button("Files app", "_on_files_app")
	files_app_btn.visible = OS.has_feature("iOS")
	top_bar.add_child(files_app_btn)

	list = FileList.new()
	list.picker = self
	add_child(list)

	bottom_bar = Control.new()
	bottom_bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bottom_bar)
	info_label = Label.new()
	info_label.clip_text = true
	info_label.valign = Label.VALIGN_CENTER
	info_label.add_font_override("font", font_small)
	info_label.add_color_override("font_color", DIM)
	bottom_bar.add_child(info_label)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "File name"
	name_edit.add_font_override("font", font)
	name_edit.connect("text_changed", self, "_on_name_changed")
	name_edit.connect("text_entered", self, "_on_name_entered")
	add_child(name_edit)
	all_btn = _button("Show all files", "_toggle_all")
	bottom_bar.add_child(all_btn)
	cancel_btn = _button("Cancel", "_on_cancel")
	bottom_bar.add_child(cancel_btn)
	ok_btn = _button("Open", "_on_ok")
	bottom_bar.add_child(ok_btn)

	places_menu = VBoxContainer.new()
	places_menu.visible = false
	add_child(places_menu)
	for p in _places():
		var b := _button(p[0], "_go_place")
		b.disconnect("pressed", self, "_go_place")
		b.connect("pressed", self, "_go_place", [p[1]])
		places_menu.add_child(b)

func _layout():
	var vp := get_viewport_rect().size
	if vp.y <= 0:
		return
	u = vp.y / 860.0
	font.size = int(round(32 * u))
	font_small.size = int(round(26 * u))
	font_bold.size = int(round(32 * u))
	# keep clear of the notch and the home bar
	var safe := Rect2(Vector2.ZERO, vp)
	var win := OS.get_window_size()
	var sa := OS.get_window_safe_area()
	if win.x > 0 and win.y > 0 and sa.size.x > 0 and sa.size.y > 0:
		var k := vp / win
		safe = Rect2(sa.position * k, sa.size * k)
	var pad := 18.0 * u
	var left := safe.position.x + pad
	var right := safe.end.x - pad
	var top := safe.position.y + pad * 0.6
	var bottom := safe.end.y - pad * 0.6
	var bar_h := 96.0 * u
	var gap := 16.0 * u

	# top: [Back] path ... [Places] [Files app]
	top_bar.rect_position = Vector2(left, top)
	top_bar.rect_size = Vector2(right - left, bar_h)
	var x := 0.0
	back_btn.rect_position = Vector2(0, 0)
	back_btn.rect_size = Vector2(200 * u, bar_h)
	x = 200 * u + gap
	var rx := right - left
	for b in [files_app_btn, places_btn]:
		if b.visible:
			var w: float = max(200 * u, font_bold.get_string_size(b.text).x + 60 * u)
			rx -= w
			b.rect_position = Vector2(rx, 0)
			b.rect_size = Vector2(w, bar_h)
			rx -= gap
	path_label.rect_position = Vector2(x, 0)
	path_label.rect_size = Vector2(max(10.0, rx - x), bar_h)

	# bottom: info or name box, [Show all files], [Cancel], [Open]
	bottom_bar.rect_position = Vector2(left, bottom - bar_h)
	bottom_bar.rect_size = Vector2(right - left, bar_h)
	var bw := 250.0 * u
	rx = right - left
	ok_btn.rect_position = Vector2(rx - bw, 0)
	ok_btn.rect_size = Vector2(bw, bar_h)
	rx -= bw + gap
	cancel_btn.rect_position = Vector2(rx - bw, 0)
	cancel_btn.rect_size = Vector2(bw, bar_h)
	rx -= bw + gap
	if all_btn.visible:
		var aw: float = font_bold.get_string_size(all_btn.text).x + 60 * u
		all_btn.rect_position = Vector2(rx - aw, 0)
		all_btn.rect_size = Vector2(aw, bar_h)
		rx -= aw + gap
	info_label.rect_position = Vector2(0, 0)
	info_label.rect_size = Vector2(max(10.0, rx), bar_h)

	# saving: the name box sits under the top bar (the keyboard covers the bottom)
	var list_top := top + bar_h + gap
	if name_edit.visible:
		name_edit.rect_position = Vector2(left, list_top)
		name_edit.rect_size = Vector2(right - left, bar_h * 0.85)
		list_top += bar_h * 0.85 + gap
	list.rect_position = Vector2(left, list_top)
	list.rect_size = Vector2(right - left, (bottom - bar_h - gap) - list_top)
	list.row_h = 100.0 * u
	list.clamp_scroll()
	list.update()

	places_menu.rect_position = Vector2(places_btn.rect_global_position.x - rect_global_position.x, top + bar_h + 6 * u)
	for b in places_menu.get_children():
		b.rect_min_size = Vector2(max(places_btn.rect_size.x, 380 * u), bar_h)
	places_menu.rect_size = Vector2.ZERO
	if places_menu.rect_position.x + places_menu.rect_size.x > right:
		places_menu.rect_position.x = right - places_menu.rect_size.x

# --- opening -----------------------------------------------------------------

# filters like ["*.png, *.jpg ; Images", "* ; All Files"]
func open(p_kind: String, p_filters: PoolStringArray, p_multi: bool, start_dir: String):
	kind = p_kind
	multiselect = p_multi and kind == "open"
	exts = []
	var names := []
	var any := p_filters.empty()
	for f in p_filters:
		var parts: Array = f.split(";")
		for pat in parts[0].split(","):
			pat = pat.strip_edges().to_lower()
			if pat == "*" or pat == "*.*":
				any = true
			elif pat.begins_with("*.") and pat.length() > 2:
				if not exts.has(pat.substr(2)):
					exts.append(pat.substr(2))
		if parts.size() > 1 and parts[1].strip_edges() != "" and not parts[1].strip_edges().to_lower().begins_with("all"):
			names.append(parts[1].strip_edges())
	if any and kind != "save":
		exts = []
	filter_name = PoolStringArray(names).join(", ")
	show_all = false
	selected = {}
	_replace_armed = ""
	root_dir = _root_for(start_dir)
	name_edit.text = ""
	name_edit.visible = kind == "save"
	all_btn.visible = kind == "open" and not exts.empty()
	ok_btn.text = {"open": "Open", "save": "Save", "folder": "Use folder"}[kind]
	places_menu.visible = false
	visible = true
	_go(start_dir)
	_layout()

func _root_for(dir: String) -> String:
	var best := ""
	for p in _places():
		var r: String = p[1]
		if (dir + "/").begins_with(r.trim_suffix("/") + "/") and r.length() > best.length():
			best = r
	if best == "":
		best = "/"
	return best.trim_suffix("/") if best != "/" else best

func _places() -> Array:
	var out := [["Chromia", OS.get_user_data_dir()]]
	if OS.has_feature("Android"):
		var base := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP, false)
		if base != "" and base != OS.get_user_data_dir():
			out[0] = ["Chromia", base]
		var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS, false)
		if dl != "":
			out.append(["Downloads", dl])
		out.append(["Phone storage", "/storage/emulated/0"])
	return out

func _go(dir: String):
	dir = dir.replace("\\", "/")
	if dir.length() > 1:
		dir = dir.trim_suffix("/")
	var d := Directory.new()
	if d.open(dir) != OK:
		if cur_dir == "":
			dir = root_dir
			if d.open(dir) != OK:
				entries = []
				cur_dir = dir
				_refresh_labels()
				return
		else:
			Globals.notify(Globals.NOTIFY_WARN, "That folder can't be opened.", "Files")
			return
	cur_dir = dir
	if not (cur_dir + "/").begins_with(root_dir.trim_suffix("/") + "/"):
		root_dir = _root_for(cur_dir)
	var dirs := []
	var files := []
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			dirs.append({"name": n, "dir": true, "size": -1})
		elif kind != "folder":
			if show_all or exts.empty() or exts.has(n.get_extension().to_lower()):
				files.append({"name": n, "dir": false, "size": _size(cur_dir.plus_file(n))})
		n = d.get_next()
	d.list_dir_end()
	dirs.sort_custom(self, "_by_name")
	files.sort_custom(self, "_by_name")
	entries = dirs + files
	selected = {}
	_replace_armed = ""
	list.scroll = 0.0
	list.vel = 0.0
	list.update()
	_refresh_labels()

func _by_name(a, b) -> bool:
	return String(a.name).nocasecmp_to(String(b.name)) < 0

func _size(path: String) -> int:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return -1
	var n := f.get_len()
	f.close()
	return n

static func fmt_size(n: int) -> String:
	if n < 0:
		return ""
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%.0f KB" % (n / 1024.0)
	if n < 1024 * 1024 * 1024:
		return "%.1f MB" % (n / 1048576.0)
	return "%.1f GB" % (n / 1073741824.0)

# "Chromia › maps › pack"
func _pretty_path() -> String:
	var label := cur_dir
	for p in _places():
		var r: String = String(p[1]).trim_suffix("/")
		if cur_dir == r or cur_dir.begins_with(r + "/"):
			label = String(p[0]) + cur_dir.substr(r.length())
			break
	return label.replace("/", "  ›  ")

func _refresh_labels():
	path_label.text = _pretty_path()
	back_btn.disabled = cur_dir == root_dir or cur_dir == "/" or cur_dir == ""
	var n_files := 0
	for e in entries:
		if not e.dir:
			n_files += 1
	match kind:
		"open":
			if selected.size() > 0:
				info_label.text = (PoolStringArray(selected.keys()).join(", ") if selected.size() <= 3 else "%d files selected" % selected.size())
				info_label.add_color_override("font_color", TEXT)
			else:
				var what := filter_name if filter_name != "" and not show_all else "files"
				info_label.text = ("Tap files to select them (%s)" if multiselect else "Tap a file to open it (%s)") % what
				info_label.add_color_override("font_color", DIM)
			ok_btn.disabled = selected.empty()
		"save":
			ok_btn.disabled = name_edit.text.strip_edges() == ""
			if _replace_armed != "":
				info_label.text = "%s already exists" % _replace_armed.get_file()
				info_label.add_color_override("font_color", PINK)
			else:
				var ext_note: String = (" (.%s)" % exts[0]) if not exts.empty() else ""
				info_label.text = "Type a name above%s, or tap a file to reuse its name" % ext_note
				info_label.add_color_override("font_color", DIM)
			ok_btn.text = "Replace it?" if _replace_armed != "" else "Save"
		"folder":
			info_label.text = "Open the folder you want, then tap Use folder"
			ok_btn.disabled = false
	all_btn.text = "Only %s" % (filter_name if filter_name != "" else "matching") if show_all else "Show all files"
	if all_btn.visible:
		_layout_soon()
	list.update()

var _layout_queued := false
func _layout_soon():
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_do_layout")

func _do_layout():
	_layout_queued = false
	_layout()

# --- actions -----------------------------------------------------------------

func tapped(i: int, double: bool):
	if i < 0 or i >= entries.size():
		return
	var e: Dictionary = entries[i]
	if e.dir:
		_go(cur_dir.plus_file(e.name))
		return
	match kind:
		"open":
			if multiselect:
				if selected.has(e.name):
					selected.erase(e.name)
				else:
					selected[e.name] = true
			else:
				var again: bool = selected.has(e.name)
				selected = {e.name: true}
				if again or double:
					_on_ok()
					return
		"save":
			name_edit.text = e.name
			_replace_armed = ""
	_refresh_labels()

func _on_back():
	places_menu.visible = false
	if cur_dir == root_dir or cur_dir == "/":
		return
	var up := cur_dir.get_base_dir()
	if up == "":
		up = "/"
	_go(up)

func _toggle_places():
	places_menu.visible = not places_menu.visible
	_layout()

func _go_place(path: String):
	places_menu.visible = false
	root_dir = path.trim_suffix("/")
	var d := Directory.new()
	if not d.dir_exists(path):
		d.make_dir_recursive(path)
	_go(path)

func _on_files_app():
	sel.open_files_app()

func _toggle_all():
	show_all = not show_all
	_go(cur_dir)

func _on_name_changed(_t):
	_replace_armed = ""
	_refresh_labels()

func _on_name_entered(_t):
	_on_ok()

func _on_cancel():
	visible = false
	sel._cancel()

func _save_name() -> String:
	var n := name_edit.text.strip_edges().replace("/", "_").replace("\\", "_")
	if n == "":
		return ""
	if not exts.empty() and not exts.has(n.get_extension().to_lower()):
		n += "." + String(exts[0])
	return n

func _on_ok():
	match kind:
		"open":
			if selected.empty():
				return
			var out := PoolStringArray()
			for e in entries: # keep the list's order
				if selected.has(e.name):
					out.append(cur_dir.plus_file(e.name))
			visible = false
			sel.files_sel(out)
		"save":
			var n := _save_name()
			if n == "":
				return
			var path := cur_dir.plus_file(n)
			if File.new().file_exists(path) and _replace_armed != path:
				_replace_armed = path
				_refresh_labels()
				return
			visible = false
			sel.save_sel(path)
		"folder":
			visible = false
			sel.folder_sel(cur_dir)

func _unhandled_input(event):
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		_on_cancel()

# --- the list ----------------------------------------------------------------

class FileList extends Control:
	var picker
	var row_h := 100.0
	var scroll := 0.0
	var vel := 0.0
	var _down := false
	var _dragging := false
	var _press := Vector2.ZERO
	var _moved := 0.0
	var _last_tap_ms := 0
	var _last_tap_row := -1
	var _last_move_us := 0

	func _init():
		rect_clip_content = true
		mouse_filter = MOUSE_FILTER_STOP

	func max_scroll() -> float:
		return max(0.0, picker.entries.size() * row_h - rect_size.y)

	func clamp_scroll():
		scroll = clamp(scroll, 0.0, max_scroll())

	func _gui_input(event):
		if event is InputEventMouseButton:
			if event.button_index == BUTTON_WHEEL_UP and event.pressed:
				scroll -= row_h
				clamp_scroll()
				update()
			elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
				scroll += row_h
				clamp_scroll()
				update()
			elif event.button_index == BUTTON_LEFT:
				if event.pressed:
					_down = true
					_dragging = false
					_moved = 0.0
					_press = event.position
					vel = 0.0
					_last_move_us = OS.get_ticks_usec()
				else:
					if _dragging and OS.get_ticks_usec() - _last_move_us > 120000:
						vel = 0.0
					if _down and not _dragging:
						var i := int((event.position.y + scroll) / row_h)
						var now := OS.get_ticks_msec()
						var double := i == _last_tap_row and now - _last_tap_ms < 350
						_last_tap_ms = now
						_last_tap_row = i
						picker.tapped(i, double)
					_down = false
					_dragging = false
		elif event is InputEventMouseMotion and _down:
			_moved += abs(event.relative.y)
			if not _dragging and _moved > row_h * 0.15:
				_dragging = true
			if _dragging:
				scroll -= event.relative.y
				clamp_scroll()
				var now := OS.get_ticks_usec()
				var dt: float = clamp((now - _last_move_us) / 1000000.0, 0.004, 0.1)
				_last_move_us = now
				vel = lerp(vel, -event.relative.y / dt, 0.5)
				update()

	func _process(delta):
		if not _down and abs(vel) > 5.0:
			scroll += vel * delta
			vel *= pow(0.04, delta)
			var before := scroll
			clamp_scroll()
			if scroll != before:
				vel = 0.0
			update()

	func _draw():
		var f: DynamicFont = picker.font
		var fs: DynamicFont = picker.font_small
		var u: float = picker.u
		var w := rect_size.x
		draw_rect(Rect2(Vector2.ZERO, rect_size), Color(0, 0, 0, 0.25))
		var entries: Array = picker.entries
		if entries.empty():
			var msg := "This folder is empty"
			if picker.kind == "open" and not picker.exts.empty() and not picker.show_all:
				msg = "No %s here. Open a folder, or tap Show all files" % (picker.filter_name if picker.filter_name != "" else "matching files")
			elif picker.kind == "folder":
				msg = "No folders inside. Tap Use folder to pick this one"
			var sz := fs.get_string_size(msg)
			draw_string(fs, Vector2((w - sz.x) / 2, rect_size.y / 2), msg, picker.DIM)
			return
		var first := int(scroll / row_h)
		var last: int = min(entries.size() - 1, int((scroll + rect_size.y) / row_h))
		for i in range(first, last + 1):
			var e: Dictionary = entries[i]
			var y := i * row_h - scroll
			var r := Rect2(0, y, w, row_h)
			var is_sel: bool = picker.selected.has(e.name) and not e.dir
			if is_sel:
				draw_rect(r.grow(-2 * u), picker.ROW_SEL)
			elif i % 2 == 0:
				draw_rect(r, picker.ROW_A)
			draw_line(Vector2(0, y + row_h), Vector2(w, y + row_h), Color(1, 1, 1, 0.06), 1.0)
			var ic := Vector2(44 * u, y + row_h / 2)
			if e.dir:
				_folder_icon(ic, u)
			else:
				_file_icon(ic, u)
			var tx := 110 * u
			var right_text := ""
			if e.dir:
				right_text = "›"
			else:
				right_text = picker.fmt_size(e.size)
			var rw := 0.0
			if right_text != "":
				var rf: DynamicFont = f if e.dir else fs
				var rsz := rf.get_string_size(right_text)
				rw = rsz.x + 30 * u
				draw_string(rf, Vector2(w - rsz.x - 24 * u, y + (row_h + rf.get_ascent() - rf.get_descent()) / 2), right_text, picker.DIM)
			if picker.multiselect and not e.dir:
				var cc := Vector2(w - rw - 40 * u, y + row_h / 2)
				draw_arc(cc, 16 * u, 0, TAU, 32, picker.LILAC, 3 * u, true)
				if is_sel:
					draw_circle(cc, 11 * u, picker.PINK)
				rw += 70 * u
			var name_text: String = e.name
			var max_w := w - tx - rw - 20 * u
			if f.get_string_size(name_text).x > max_w:
				while name_text.length() > 4 and f.get_string_size(name_text + "…").x > max_w:
					name_text = name_text.substr(0, name_text.length() - 1)
				name_text += "…"
			draw_string(f, Vector2(tx, y + (row_h + f.get_ascent() - f.get_descent()) / 2), name_text, picker.TEXT)
		# scroll bar
		var ms := max_scroll()
		if ms > 0:
			var h: float = max(40 * u, rect_size.y * rect_size.y / (entries.size() * row_h))
			var by: float = (rect_size.y - h) * scroll / ms
			draw_rect(Rect2(w - 6 * u, by, 5 * u, h), Color(1, 1, 1, 0.25))

	func _folder_icon(c: Vector2, u: float):
		var col: Color = picker.LILAC
		var w := 46 * u
		var h := 34 * u
		var o := c - Vector2(w / 2, h / 2)
		draw_rect(Rect2(o + Vector2(0, -6 * u), Vector2(w * 0.42, 10 * u)), col)
		draw_rect(Rect2(o, Vector2(w, h)), col)

	func _file_icon(c: Vector2, u: float):
		var col: Color = picker.TEXT
		var w := 34 * u
		var h := 44 * u
		var o := c - Vector2(w / 2, h / 2)
		var k := 11 * u
		draw_colored_polygon(PoolVector2Array([o, o + Vector2(w - k, 0), o + Vector2(w, k), o + Vector2(w, h), o + Vector2(0, h)]), Color(col.r, col.g, col.b, 0.85))
		draw_colored_polygon(PoolVector2Array([o + Vector2(w - k, 0), o + Vector2(w, k), o + Vector2(w - k, k)]), Color(0.5, 0.48, 0.58))
