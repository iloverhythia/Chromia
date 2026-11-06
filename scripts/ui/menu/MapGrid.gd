extends Control

# Grid map list (Settings > Grid Map List, or Filters > View: grid): the maps
# as square tiles like Sound Space Plus's grid menu (v2MapList.gd there): a
# difficulty-coloured frame, the cover (or the name when a map has none), a
# heart for favourites and a cloud for online maps. Click a tile to pick the
# map, click it again quickly to play it.
#
# Made for big libraries: SSP's grid built a button for every map on the page
# again on each page turn. This one only has the tiles you can see (a fixed
# pool of a few dozen) and gives them new maps as you scroll, so 10 maps or
# 50,000 cost the same. Covers come from the square cover cache (CoverSq.gd),
# made on a background thread.
#
# The map list (v3MapList.gd) still does the searching, filters and sorting;
# this only shows its `disp` list. It is made and removed while the game runs
# (Rhythia.map_grid), no restart needed.

const CoverSq = preload("res://scripts/ui/modern/CoverSq.gd")

const CELL := 128.0
const GAP := 4.0
const PAD := 6.0
const DRAG_START := 10.0
const MOTD_YELLOW := Color(1, 0.9, 0.05) # (like the list's Map of the Day button)

var list # v3MapList.gd
var covers
var _pool := [] # tiles
var _off := 0.0 # scroll, in pixels
var _target := 0.0
var _cols := 1
var _dirty := true
var _templates := {}
var _diff_colors := {}
var _press_at := Vector2()
var _press_off := 0.0
var _pressing := false
var _dragging := false
var _no_click := false
var _vel := 0.0
var _last_y := 0.0
var _hold := 0 # -1 / 1 while UP / DOWN is held

func _init(map_list):
	list = map_list
	name = "MapGrid"
	anchor_right = 1
	anchor_bottom = 1
	rect_clip_content = true
	mouse_filter = MOUSE_FILTER_PASS
	covers = CoverSq.get_cache()
	for d in ["EASY", "MEDIUM", "HARD", "LOGIC", "AMOGUS", "NODIF"]:
		var n = list.get_node_or_null(d)
		if n != null:
			_templates[d] = n
			_diff_colors[d] = n.self_modulate

func _ready():
	covers.connect("ready", self, "_on_cover_ready")
	Rhythia.connect("selected_song_changed", self, "_on_selected")
	connect("resized", self, "_relayout")

func _exit_tree():
	if covers.is_connected("ready", self, "_on_cover_ready"):
		covers.disconnect("ready", self, "_on_cover_ready")

# ---- what the map list calls

func refresh(show_current := false):
	for t in _pool:
		t.set_meta("idx", -1)
	_dirty = true
	if show_current:
		show_index(list.cur_map, true)
	_clamp_target()

func show_index(i: int, jump := false):
	if i < 0 or i >= list.disp.size():
		return
	if int(max(1, floor((rect_size.x - PAD * 2 + GAP) / (CELL + GAP)))) != _cols:
		_relayout()
	var rh := CELL + GAP
	var y := float(i / _cols) * rh
	var h := rect_size.y
	# only move when it isn't fully on screen; then put it in the middle
	if y < _target or y + rh > _target + h - PAD * 2:
		_target = y - (h - rh) / 2.0
	_clamp_target()
	if jump:
		_off = _target
		_dirty = true

func to_top():
	_target = 0
	_vel = 0

func scroll_rows(n: float):
	_target += n * (CELL + GAP)
	_clamp_target()

func hold_scroll(dir: int):
	_hold = dir

func refresh_tiles():
	refresh()

# ---- layout

func _max_off() -> float:
	var rows := int(ceil(float(list.disp.size()) / float(_cols)))
	return max(0.0, rows * (CELL + GAP) - GAP + PAD * 2 - rect_size.y)

func _clamp_target():
	_target = clamp(_target, 0.0, _max_off())

func _relayout():
	var c := int(max(1, floor((rect_size.x - PAD * 2 + GAP) / (CELL + GAP))))
	if c != _cols:
		# keep the same maps in view
		var first := int(_off / (CELL + GAP)) * _cols
		_cols = c
		_off = float(first / _cols) * (CELL + GAP)
		_target = _off
		for t in _pool:
			t.set_meta("idx", -1)
	_clamp_target()
	_off = min(_off, _max_off())
	_dirty = true

func _process(delta):
	if not is_visible_in_tree():
		return
	if _hold != 0:
		_target += _hold * 900.0 * delta
		_clamp_target()
	if not _pressing and abs(_vel) > 1.0:
		_target += _vel * delta
		_vel = lerp(_vel, 0.0, min(1.0, delta * 5.0))
		_clamp_target()
	if abs(_target - _off) > 0.5:
		_off = lerp(_off, _target, min(1.0, delta * 16.0))
		_dirty = true
	elif _off != _target:
		_off = _target
		_dirty = true
	if _dirty:
		_dirty = false
		_place()

func _place():
	if int(max(1, floor((rect_size.x - PAD * 2 + GAP) / (CELL + GAP)))) != _cols:
		_relayout()
	var disp: Array = list.disp
	var rh := CELL + GAP
	var first_row := int(floor(_off / rh))
	var rows := int(ceil(rect_size.y / rh)) + 1
	var need := rows * _cols
	while _pool.size() < need:
		_pool.append(_make_tile())
	var left := floor((rect_size.x - (_cols * rh - GAP)) / 2.0)
	var used := 0
	for r in rows:
		var row: int = first_row + r
		for c in _cols:
			var i: int = row * _cols + c
			if i >= disp.size():
				break
			var t: Panel = _pool[used]
			used += 1
			if int(t.get_meta("idx")) != i:
				_fill(t, i, disp[i])
			t.rect_position = Vector2(left + c * rh, PAD + row * rh - _off)
			t.visible = true
	for k in range(used, _pool.size()):
		_pool[k].visible = false
		_pool[k].set_meta("idx", -1)

# ---- tiles

func _make_tile() -> Panel:
	var src: Panel = _templates.get("NODIF", _templates.values()[0] if not _templates.empty() else null)
	var t: Panel
	if src != null:
		t = src.duplicate()
		for extra in ["Label"]:
			if t.has_node(extra):
				t.get_node(extra).visible = false
	else:
		t = Panel.new()
	t.set_script(null)
	t.rect_min_size = Vector2(CELL, CELL)
	t.rect_size = Vector2(CELL, CELL)
	t.size_flags_horizontal = 0
	t.mouse_filter = MOUSE_FILTER_PASS
	t.set_meta("idx", -1)
	var cover: TextureRect = t.get_node_or_null("Cover")
	if cover != null:
		cover.modulate = Color(1, 1, 1)
		cover.self_modulate = Color(1, 1, 1)
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var nm: Label = t.get_node_or_null("Name")
	if nm != null:
		nm.margin_left = 10
		nm.margin_right = -10
		nm.margin_top = 6
		nm.margin_bottom = -6
		nm.align = Label.ALIGN_CENTER
		nm.valign = Label.VALIGN_CENTER
		nm.autowrap = true
		nm.clip_text = true
	var sel: Button = t.get_node_or_null("Select")
	if sel != null:
		sel.group = null
		sel.disabled = false
		sel.toggle_mode = true
		sel.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		sel.focus_mode = FOCUS_NONE
		sel.mouse_filter = MOUSE_FILTER_PASS
		sel.connect("pressed", self, "_on_tile_pressed", [t])
	var strip := ColorRect.new()
	strip.name = "Folder"
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	strip.anchor_top = 1
	strip.anchor_right = 1
	strip.anchor_bottom = 1
	strip.margin_left = 6
	strip.margin_right = -6
	strip.margin_top = -12
	strip.margin_bottom = -6
	strip.visible = false
	t.add_child(strip)
	add_child(t)
	return t

func _diff_key(d) -> String:
	match d:
		Globals.DIFF_EASY: return "EASY"
		Globals.DIFF_MEDIUM: return "MEDIUM"
		Globals.DIFF_HARD: return "HARD"
		Globals.DIFF_LOGIC: return "LOGIC"
		Globals.DIFF_AMOGUS: return "AMOGUS"
	return "NODIF"

func _fill(t: Panel, i: int, map: Song):
	t.set_meta("idx", i)
	var col: Color = _diff_colors.get(_diff_key(map.difficulty), Color(1, 1, 1))
	var motd: bool = map == list.get("_motd_song")
	t.self_modulate = MOTD_YELLOW if motd else col
	var bg = t.get_node_or_null("TextureRect")
	if bg != null:
		bg.self_modulate = col
	var tex: Texture = covers.tex_for(map) if map.has_cover else null
	var cover = t.get_node_or_null("Cover")
	if cover != null:
		cover.texture = tex
		cover.visible = tex != null
	var nm = t.get_node_or_null("Name")
	if nm != null:
		nm.visible = tex == null
		nm.text = map.name
		if map.is_broken:
			nm.modulate = Color(1, 0.4, 0.4)
		elif map.warning != "":
			nm.modulate = Color(1, 1, 0.2)
		else:
			nm.modulate = Color(1, 1, 1)
	var f = t.get_node_or_null("F")
	if f != null:
		f.visible = list.is_fav(map)
	var cloud = t.get_node_or_null("Cloud")
	if cloud != null:
		cloud.visible = map.is_online
	var strip: ColorRect = t.get_node("Folder")
	var fcol = list.folders.color_for(map.id)
	strip.visible = fcol != null
	if fcol != null:
		strip.color = fcol
	var sel = t.get_node_or_null("Select")
	if sel != null:
		sel.set_pressed_no_signal(map == Rhythia.selected_song)
		sel.hint_tooltip = map.name + (("\n" + map.creator) if String(map.creator) != "" else "") + ("\nMap of the Day" if motd else "")

func _on_cover_ready(song):
	for t in _pool:
		var i := int(t.get_meta("idx"))
		if i >= 0 and i < list.disp.size() and list.disp[i] == song:
			_fill(t, i, song)

func _on_selected(_s = null):
	for t in _pool:
		var i := int(t.get_meta("idx"))
		var sel = t.get_node_or_null("Select")
		if sel != null and i >= 0 and i < list.disp.size():
			sel.set_pressed_no_signal(list.disp[i] == Rhythia.selected_song)

func _on_tile_pressed(t: Panel):
	var i := int(t.get_meta("idx"))
	if _no_click or i < 0 or i >= list.disp.size():
		_on_selected()
		return
	list.grid_pressed(i)
	_on_selected()

# ---- scrolling: the wheel, dragging (touch / mouse) with a little fling,
# and the UP / DOWN buttons beside the list

func _input(ev):
	if not is_visible_in_tree():
		return
	var inside := get_global_rect().has_point(Rhythia.menu_mouse(self))
	if ev is InputEventMouseButton:
		if ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN:
			if ev.pressed and inside and not Rhythia.alt_held(ev):
				_vel = 0
				scroll_rows((-1.0 if ev.button_index == BUTTON_WHEEL_UP else 1.0) * 1.0)
			return
		if ev.button_index != BUTTON_LEFT:
			return
		if ev.pressed:
			_no_click = false
			if inside:
				_pressing = true
				_dragging = false
				_press_at = Rhythia.menu_mouse(self)
				_press_off = _target
				_last_y = _press_at.y
				_vel = 0
		elif _pressing:
			_pressing = false
			if _dragging:
				_dragging = false
				_no_click = true # (this release doesn't pick the tile under it)
	elif ev is InputEventMouseMotion and _pressing:
		var p := Rhythia.menu_mouse(self)
		if not _dragging and abs(p.y - _press_at.y) > DRAG_START:
			_dragging = true
		if _dragging:
			_target = _press_off - (p.y - _press_at.y)
			_clamp_target()
			_off = _target
			_dirty = true
			var dt: float = max(get_process_delta_time(), 0.001)
			_vel = lerp(_vel, -(p.y - _last_y) / dt, 0.4)
			_last_y = p.y
