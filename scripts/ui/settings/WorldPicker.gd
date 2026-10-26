extends CanvasLayer
# Background picker: every background as a tile (thumbnail + name) in a grid
# that fits the screen and scrolls, so the whole list is reachable on phones
# (the old dropdown ran off the bottom of the screen). Opened by WorldSel.gd.

signal picked(world)

const TILE_W := 150.0
const TILE_GAP := 10.0
const DRAG_START := 12.0

var worlds: Array = []
var selected = null

var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _grid_box: VBoxContainer
var _font: DynamicFont
var _small: DynamicFont
var _big: DynamicFont
var _press_pos = null
var _dragging := false
var _last_drag_ms := -1000
var _tiles := []

func _ready():
	layer = 110
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Regular.ttf")
	_font.size = 17
	_small = DynamicFont.new()
	_small.font_data = _font.font_data
	_small.size = 15
	_big = DynamicFont.new()
	_big.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	_big.size = 26
	_build()
	get_viewport().connect("size_changed", self, "_layout")
	_layout()
	call_deferred("_scroll_to_selected")

func _build():
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.connect("gui_input", self, "_on_dim_input")
	_root.add_child(dim)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_constant_override("separation", 8)
	_panel.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	var title := Label.new()
	title.text = "Background"
	title.add_font_override("font", _big)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.add_font_override("font", _font)
	close.rect_min_size = Vector2(96, 44)
	close.connect("pressed", self, "close")
	top.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.scroll_horizontal_enabled = false
	col.add_child(_scroll)
	_grid_box = VBoxContainer.new()
	_grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_box.add_constant_override("separation", 8)
	_scroll.add_child(_grid_box)

# Sections in list order: Chromia's own backgrounds, Rhythia's, Roblox Rhythia's
static func _section_of(w) -> String:
	var c: String = w.creator
	if c.begins_with("Rhythia (Roblox)"):
		return "Rhythia (Roblox)"
	if c.begins_with("Rhythia"):
		return "Rhythia"
	return "Chromia"

func _layout():
	if _panel == null:
		return
	var vp: Vector2 = _root.get_viewport_rect().size
	var size = Vector2(min(vp.x - 20, 1100), vp.y - 20)
	_panel.margin_left = -size.x / 2
	_panel.margin_right = size.x / 2
	_panel.margin_top = -size.y / 2
	_panel.margin_bottom = size.y / 2
	var inner: float = size.x - 32 - 14 # panel margins + scroll bar
	var cols: int = int(max(2, floor((inner + TILE_GAP) / (TILE_W + TILE_GAP))))
	var tile_w: float = floor((inner - TILE_GAP * (cols - 1)) / cols)
	_fill(cols, tile_w)

func _fill(cols: int, tile_w: float):
	for c in _grid_box.get_children():
		_grid_box.remove_child(c)
		c.queue_free()
	_tiles = []
	var sections := []
	var by_section := {}
	for w in worlds:
		var s := _section_of(w)
		if not by_section.has(s):
			by_section[s] = []
			sections.append(s)
		by_section[s].append(w)
	for s in sections:
		var head := Label.new()
		head.text = s
		head.add_font_override("font", _font)
		head.add_color_override("font_color", Color(0.8, 0.66, 1.0))
		_grid_box.add_child(head)
		var grid := GridContainer.new()
		grid.columns = cols
		grid.add_constant_override("hseparation", int(TILE_GAP))
		grid.add_constant_override("vseparation", int(TILE_GAP))
		_grid_box.add_child(grid)
		for w in by_section[s]:
			grid.add_child(_tile(w, tile_w))

func _tile(w, tile_w: float) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.pressed = w == selected
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(tile_w, tile_w * 0.75 + 40)
	b.clip_text = true
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.05)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = Color(1, 1, 1, 0.08)
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.1)
	var on := normal.duplicate()
	on.bg_color = Color(0.78, 0.62, 1.0, 0.22)
	on.border_color = Color(0.85, 0.72, 1.0, 0.95)
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", on)
	b.add_stylebox_override("hover_pressed", on)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.connect("gui_input", self, "_on_tile_input")
	b.connect("pressed", self, "_on_tile_pressed", [w])

	var pic := TextureRect.new()
	pic.expand = true
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = w.cover if w.has_cover else null
	pic.rect_position = Vector2(6, 6)
	pic.rect_size = Vector2(tile_w - 12, tile_w * 0.75 - 6)
	b.add_child(pic)

	var lbl := Label.new()
	lbl.text = w.name
	lbl.add_font_override("font", _small)
	lbl.align = Label.ALIGN_CENTER
	lbl.valign = Label.VALIGN_CENTER
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.rect_position = Vector2(4, tile_w * 0.75 + 2)
	lbl.rect_size = Vector2(tile_w - 8, 34)
	b.add_child(lbl)
	_tiles.append([b, w])
	return b

func _scroll_to_selected():
	for t in _tiles:
		if t[1] == selected and is_instance_valid(t[0]):
			yield(get_tree(), "idle_frame")
			var y: float = t[0].rect_global_position.y - _scroll.rect_global_position.y + _scroll.scroll_vertical
			_scroll.scroll_vertical = int(max(0, y - _scroll.rect_size.y / 2 + t[0].rect_size.y / 2))
			return

# Drag anywhere on the tiles to scroll (fingers and mouse); a drag never picks.
func _on_tile_input(e: InputEvent):
	if e is InputEventMouseButton and e.button_index == BUTTON_LEFT:
		if e.pressed:
			_press_pos = e.global_position
			_dragging = false
		else:
			_press_pos = null
	elif e is InputEventMouseMotion and _press_pos != null and (e.button_mask & BUTTON_MASK_LEFT):
		if not _dragging and e.global_position.distance_to(_press_pos) > DRAG_START:
			_dragging = true
		if _dragging:
			_scroll.scroll_vertical -= int(e.relative.y)
			_last_drag_ms = OS.get_ticks_msec()
	elif e is InputEventScreenDrag and not ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"):
		# (with mouse emulation on, the same drag also arrives as mouse motion)
		_dragging = true
		_scroll.scroll_vertical -= int(e.relative.y)
		_last_drag_ms = OS.get_ticks_msec()

func _on_tile_pressed(w):
	if _dragging or OS.get_ticks_msec() - _last_drag_ms < 150:
		# the finger moved: that was a scroll, keep the old choice highlighted
		for t in _tiles:
			t[0].pressed = t[1] == selected
		return
	selected = w
	for t in _tiles:
		t[0].pressed = t[1] == w
	emit_signal("picked", w)
	close()

func _on_dim_input(e: InputEvent):
	if e is InputEventMouseButton and e.pressed:
		close()

func _unhandled_input(e: InputEvent):
	if e.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		close()

func close():
	queue_free()
