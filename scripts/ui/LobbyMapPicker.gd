extends PanelContainer

# Online > your lobby > Pick map: the host chooses the lobby's map in its own
# window instead of going to the Maps page and back. A search box, the
# difficulty buttons, and every map in one list (cover, name, mapper, length,
# stars). Click a map to pick it, then "Use this map" (or double-click).
#
# Fast with big libraries: only the rows you can see exist (a small pool
# reused while scrolling), and the search runs on names made lower case once.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const CoverSq = preload("res://scripts/ui/modern/CoverSq.gd")

const ROW := 58.0
const GAP := 4.0
const DIFFS := [
	["All", -2], ["N", -1], ["E", Globals.DIFF_EASY], ["M", Globals.DIFF_MEDIUM],
	["H", Globals.DIFF_HARD], ["L", Globals.DIFF_LOGIC], ["助", Globals.DIFF_AMOGUS],
]

var S
var lm
var covers
var _search: LineEdit
var _view: Control
var _bar: VScrollBar
var _use: Button
var _picked_label: Label
var _diff := -2
var _all := [] # [song, lower name + mapper]
var _shown := [] # songs
var _pool := []
var _off := 0.0
var _picked = null
var _last_click := 0
var _diff_buttons := []

static func open_on(parent: Node):
	var tree = parent.get_tree()
	var old = tree.root.get_node_or_null("LobbyMapPickerLayer")
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "LobbyMapPickerLayer"
	tree.root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var m = load("res://scripts/ui/LobbyMapPicker.gd").new()
	m.name = "LobbyMapPicker"
	layer.add_child(m)
	dim.connect("gui_input", m, "_on_dim")
	return m

func _init():
	S = OnlineStyle.new()
	covers = CoverSq.get_cache()
	add_stylebox_override("panel", OnlineStyle.flat(S.WINDOW_BG, 6, Color(1, 1, 1, 0.1), 1, 20, 16))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t: Label = S.heading("Pick the lobby's map")
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(t)
	var x := Button.new()
	x.text = "Close"
	S.button(x, false, true)
	x.connect("pressed", self, "close")
	head.add_child(x)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 6)
	v.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search maps or mappers"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = SIZE_EXPAND_FILL
	S.field(_search)
	_search.connect("text_changed", self, "_filter")
	row.add_child(_search)
	for d in DIFFS:
		var b := Button.new()
		b.text = d[0]
		b.toggle_mode = true
		b.pressed = d[1] == _diff
		S.button(b, false, true)
		b.rect_min_size.x = 34 if d[0] != "All" else 44
		# (the chosen one stands out)
		b.add_stylebox_override("pressed", OnlineStyle.flat(S.ACCENT, 4, Color(0, 0, 0, 0), 0, 8, 4))
		b.add_color_override("font_color_pressed", Color(0.08, 0.06, 0.1))
		b.connect("pressed", self, "_set_diff", [d[1]])
		row.add_child(b)
		_diff_buttons.append([b, d[1]])
	var area := HBoxContainer.new()
	area.size_flags_vertical = SIZE_EXPAND_FILL
	area.add_constant_override("separation", 4)
	v.add_child(area)
	_view = Control.new()
	_view.rect_clip_content = true
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	_view.size_flags_vertical = SIZE_EXPAND_FILL
	_view.mouse_filter = MOUSE_FILTER_PASS
	_view.connect("resized", self, "_place")
	_view.connect("gui_input", self, "_on_view_input")
	area.add_child(_view)
	_bar = VScrollBar.new()
	_bar.size_flags_vertical = SIZE_EXPAND_FILL
	_bar.connect("value_changed", self, "_on_bar")
	area.add_child(_bar)
	var foot := HBoxContainer.new()
	foot.add_constant_override("separation", 10)
	v.add_child(foot)
	_picked_label = S.label("Pick a map", S.f_small, S.DIM)
	_picked_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_picked_label.clip_text = true
	foot.add_child(_picked_label)
	_use = Button.new()
	_use.text = "Use this map"
	S.button(_use, true)
	_use.disabled = true
	_use.connect("pressed", self, "_use_map")
	foot.add_child(_use)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	covers.connect("ready", self, "_on_cover_ready")
	for s in Rhythia.registry_song.get_items():
		if s != null and not s.is_broken:
			_all.append([s, (String(s.name) + " " + String(s.creator)).to_lower()])
	_all.sort_custom(self, "_by_name")
	if Rhythia.selected_song != null:
		_picked = Rhythia.selected_song
	_filter()
	get_viewport().connect("size_changed", self, "_layout")
	call_deferred("_layout")
	_search.call_deferred("grab_focus")
	if _picked != null:
		call_deferred("_show_picked")

func _exit_tree():
	if covers.is_connected("ready", self, "_on_cover_ready"):
		covers.disconnect("ready", self, "_on_cover_ready")

static func _by_name(a, b) -> bool:
	return a[1] < b[1]

func _layout():
	var vp := get_viewport_rect().size
	rect_size = Vector2(min(720.0, vp.x - 40.0), min(620.0, vp.y - 40.0))
	rect_position = ((vp - rect_size) / 2.0).floor()

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func close():
	var layer = get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()

# ---- the list

func _set_diff(d: int):
	_diff = d
	for bd in _diff_buttons:
		bd[0].set_pressed_no_signal(bd[1] == d)
	_filter()

func _filter(_t = null):
	var q := _search.text.strip_edges().to_lower()
	_shown = []
	for e in _all:
		var s = e[0]
		if _diff != -2 and int(s.difficulty) != _diff:
			continue
		if q != "" and String(e[1]).find(q) == -1:
			continue
		_shown.append(s)
	_off = 0.0
	_update_bar()
	_place(true)

func _max_off() -> float:
	return max(0.0, _shown.size() * (ROW + GAP) - GAP - _view.rect_size.y)

func _update_bar():
	_bar.max_value = _shown.size() * (ROW + GAP)
	_bar.page = _view.rect_size.y
	_bar.set_block_signals(true)
	_bar.value = _off
	_bar.set_block_signals(false)

func _on_bar(v: float):
	_off = clamp(v, 0.0, _max_off())
	_place()

func _scroll(px: float):
	_off = clamp(_off + px, 0.0, _max_off())
	_update_bar()
	_place()

func _show_picked():
	var i := _shown.find(_picked)
	if i >= 0:
		_off = clamp(i * (ROW + GAP) - (_view.rect_size.y - ROW) / 2.0, 0.0, _max_off())
		_update_bar()
	_place(true)
	_update_footer()

func _on_view_input(ev):
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == BUTTON_WHEEL_UP:
			_scroll(-(ROW + GAP) * 2)
		elif ev.button_index == BUTTON_WHEEL_DOWN:
			_scroll((ROW + GAP) * 2)
	elif ev is InputEventPanGesture:
		_scroll(ev.delta.y * 20)
	elif ev is InputEventScreenDrag:
		_scroll(-ev.relative.y)

func _place(force := false):
	if _view == null:
		return
	_update_bar_page()
	var first := int(floor(_off / (ROW + GAP)))
	var count := int(ceil(_view.rect_size.y / (ROW + GAP))) + 1
	while _pool.size() < count:
		_pool.append(_make_row())
	var used := 0
	for k in count:
		var i: int = first + k
		if i >= _shown.size():
			break
		var r: Button = _pool[used]
		used += 1
		if force or int(r.get_meta("idx")) != i:
			_fill(r, i)
		r.rect_position = Vector2(0, i * (ROW + GAP) - _off)
		r.rect_size = Vector2(_view.rect_size.x, ROW)
		r.visible = true
	for k in range(used, _pool.size()):
		_pool[k].visible = false
		_pool[k].set_meta("idx", -1)

func _update_bar_page():
	_bar.page = _view.rect_size.y
	_bar.visible = _shown.size() * (ROW + GAP) > _view.rect_size.y

func _make_row() -> Button:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.set_meta("idx", -1)
	b.mouse_filter = MOUSE_FILTER_PASS
	b.connect("pressed", self, "_on_row", [b])
	var bar := ColorRect.new()
	bar.name = "Diff"
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.anchor_bottom = 1
	bar.margin_right = 4
	b.add_child(bar)
	var pic := TextureRect.new()
	pic.name = "Cover"
	pic.expand = true
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	pic.rect_position = Vector2(12, 7)
	pic.rect_size = Vector2(44, 44)
	b.add_child(pic)
	var nm: Label = S.label("", S.f_bold, S.TEXT)
	nm.name = "Name"
	nm.clip_text = true
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	nm.anchor_right = 1
	nm.margin_left = 68
	nm.margin_right = -90
	nm.margin_top = 9
	b.add_child(nm)
	var sub: Label = S.label("", S.f_small, S.DIM)
	sub.name = "Sub"
	sub.clip_text = true
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	sub.anchor_right = 1
	sub.margin_left = 68
	sub.margin_right = -90
	sub.margin_top = 30
	b.add_child(sub)
	var st: Label = S.label("", S.f_bold, S.TEXT)
	st.name = "Stars"
	st.align = Label.ALIGN_RIGHT
	st.mouse_filter = MOUSE_FILTER_IGNORE
	st.anchor_left = 1
	st.anchor_right = 1
	st.margin_left = -86
	st.margin_right = -12
	st.margin_top = 19
	b.add_child(st)
	_view.add_child(b)
	return b

func _style(b: Button, picked: bool):
	for stn in ["normal", "hover", "pressed", "focus"]:
		var bg: Color = S.CARD_BG
		if stn == "hover":
			bg = bg.lightened(0.05)
		b.add_stylebox_override(stn, OnlineStyle.flat(bg, 4, S.ACCENT if picked else Color(1, 1, 1, 0.04), 2 if picked else 1))

func _fill(b: Button, i: int):
	var s = _shown[i]
	b.set_meta("idx", i)
	_style(b, s == _picked)
	b.get_node("Diff").color = Globals.difficulty_colors.get(int(s.difficulty), Color(0.5, 0.5, 0.55))
	b.get_node("Cover").texture = covers.tex_for(s) if s.has_cover else null
	b.get_node("Name").text = String(s.name)
	var secs := int(s.last_ms / 1000.0)
	var sub := "%d:%02d" % [secs / 60, secs % 60]
	if String(s.creator) != "":
		sub = String(s.creator) + "  ·  " + sub
	if s.is_online:
		sub += "  ·  online"
	b.get_node("Sub").text = sub
	var stars := float(s.star_rating_shown()) if s.has_method("star_rating_shown") else 0.0
	b.get_node("Stars").text = ("%.2f ★" % stars) if stars > 0 else ""

func _on_cover_ready(song):
	for b in _pool:
		var i := int(b.get_meta("idx"))
		if i >= 0 and i < _shown.size() and _shown[i] == song:
			b.get_node("Cover").texture = covers.tex_for(song)

func _on_row(b: Button):
	var i := int(b.get_meta("idx"))
	if i < 0 or i >= _shown.size():
		return
	var s = _shown[i]
	var now := OS.get_ticks_msec()
	var again: bool = s == _picked and now - _last_click < 400
	_last_click = now
	_picked = s
	_place(true)
	_update_footer()
	if again:
		_use_map()

func _update_footer():
	_use.disabled = _picked == null
	_picked_label.text = ("Picked: " + String(_picked.name)) if _picked != null else "Pick a map"

func _use_map():
	if _picked == null or lm == null:
		return
	var s = _picked
	close()
	if Rhythia.selected_song != s:
		Rhythia.select_song(s) # (an online map downloads first)
	if Rhythia.selected_song == s:
		_set_lobby_song(s)
	else:
		Rhythia.connect("selected_song_changed", lm, "_lobby_song_from_picker", [s], CONNECT_ONESHOT)

func _set_lobby_song(s):
	if lm.lobby_active and lm.is_host:
		lm.set_lobby_song(s)
		lm.push_current_mods()
