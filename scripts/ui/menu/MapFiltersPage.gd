extends Node

# The map list's column is "Difficulties" now: it keeps the difficulty
# buttons, and a Filters button under the heading opens a side page with
# everything else: what to show (broken, online, ranked), how to sort (the
# old stars / most played sorts and the new ones in v3MapList._sorted_by_mode),
# the order switches and the map folders. The checkboxes are the same nodes as
# before, moved into the page (they find the map list with MapListOf.gd).

const SORTS := [
	["", "difficulty"], ["stars", "stars"], ["plays", "most played"],
	["length_short", "shortest"], ["length_long", "longest"],
	["sp_high", "highest SP"], ["sp_low", "lowest SP"],
	["played", "played"], ["unplayed", "unplayed"],
	["recent_ranked", "recently ranked"], ["recent_played", "recently played"],
	["notes_high", "most notes"], ["notes_low", "fewest notes"],
]
const W := 250.0
const BG := Color(0.07, 0.065, 0.09, 0.97)
const EDGE := Color(0.45, 0.4, 0.55, 0.9)
const HEAD := Color(1, 0.756863, 0.960784)

var filters: Control
var button: Button
var page: PanelContainer
var dim: ColorRect
var _radios := {} # sort key -> CheckBox
var _group := ButtonGroup.new()
var _box: VBoxContainer

static func attach(menu) -> void:
	var f = menu.get_node_or_null("Main/Maps/Filters")
	if f == null or f.has_node("MapFiltersPage"):
		return
	var p = load("res://scripts/ui/menu/MapFiltersPage.gd").new()
	p.name = "MapFiltersPage"
	p.filters = f
	f.add_child(p)

func _ready():
	call_deferred("_build")

func _current_key() -> String:
	if String(Rhythia.map_sort) != "":
		return String(Rhythia.map_sort)
	if Rhythia.sort_by_stars:
		return "stars"
	if Rhythia.sort_by_plays:
		return "plays"
	return ""

func _build():
	var title: Label = filters.get_node_or_null("Label")
	var tmpl: CheckBox = filters.get_node_or_null("StarSort")
	if title == null or tmpl == null:
		return
	if not title.text.begins_with("Difficulties"):
		title.text = "Difficulties"
	var bump = filters.get_node_or_null("bump")
	# the button under the heading
	button = Button.new()
	button.name = "FiltersButton"
	button.text = "Filters"
	button.hint_tooltip = "What to show and how to sort the maps"
	button.theme = bump.theme if bump != null and bump.theme != null else tmpl.theme
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.connect("pressed", self, "_toggle")
	filters.add_child(button)
	filters.move_child(button, title.get_index() + 1)

	# a see-through layer behind the page: a click outside closes it
	dim = ColorRect.new()
	dim.name = "FiltersDim"
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_as_toplevel(true)
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.connect("gui_input", self, "_on_dim_input")
	filters.add_child(dim)

	page = PanelContainer.new()
	page.name = "FiltersPage"
	page.set_as_toplevel(true)
	page.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	page.add_stylebox_override("panel", sb)
	filters.add_child(page)
	var outer := VBoxContainer.new()
	page.add_child(outer)
	var top := HBoxContainer.new()
	outer.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_constant_override("separation", 5)
	scroll.add_child(box)
	_box = box
	var head := _heading("Filters", title)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.connect("pressed", self, "_close")
	close.add_color_override("font_color", Color(0.85, 0.82, 0.9))
	close.add_color_override("font_color_hover", HEAD)
	if title.get_font("font") != null:
		close.add_font_override("font", title.get_font("font"))
	top.add_child(close)

	box.add_child(_heading("Show", title, true))
	for n in ["Broken", "Online", "XPOnly"]:
		_move(n, box)
	box.add_child(_heading("Sort by", title, true))
	var cur := _current_key()
	for s in SORTS:
		var cb: CheckBox = tmpl.duplicate(0)
		cb.name = "Sort_" + (s[0] if s[0] != "" else "difficulty")
		cb.text = s[1]
		cb.group = _group
		cb.pressed = s[0] == cur
		cb.hint_tooltip = "sort the maps by %s" % s[1]
		cb.connect("pressed", self, "_on_sort", [s[0]])
		box.add_child(cb)
		_radios[s[0]] = cb
	box.add_child(_heading("Order", title, true))
	var flip = _move("DiffSort", box)
	if flip != null:
		flip.text = "reversed"
		flip.hint_tooltip = "the other way round (hard to easy, Z-A, most to fewest...)"
	var names = _move("NameSort", box)
	if names != null:
		names.text = "names Z-A"
		names.hint_tooltip = "names from Z to A within each difficulty"
	# the old sort checkboxes stay (hidden) so they keep working with the sorts
	for n in ["StarSort", "PlaysSort"]:
		var c = _move(n, box)
		if c != null:
			c.visible = false
	var ff = filters.get_node_or_null("FolderFilters")
	if ff != null:
		var fh := _heading("Folders", title, true)
		box.add_child(fh)
		_move("FolderFilters", box)
		fh.visible = ff.visible
		ff.connect("visibility_changed", self, "_folders_seen", [ff, fh])
	_update_button()

func _folders_seen(ff: Control, fh: Control):
	fh.visible = ff.visible

func _heading(text: String, like: Label, small := false) -> Label:
	var l := Label.new()
	l.text = text
	var f = like.get_font("font")
	if f != null:
		l.add_font_override("font", f)
	l.add_color_override("font_color", HEAD if not small else Color(0.75, 0.72, 0.82))
	if small:
		l.rect_min_size = Vector2(0, 22)
		l.valign = Label.VALIGN_BOTTOM
	return l

func _move(n: String, to: Control) -> Control:
	var c = filters.get_node_or_null(n)
	if c == null:
		return null
	filters.remove_child(c)
	to.add_child(c)
	if c is CheckBox:
		c.clip_text = false
	return c

func _on_sort(key: String):
	match key:
		"":
			Rhythia.map_sort = ""
			Rhythia.sort_by_stars = false
			Rhythia.sort_by_plays = false
		"stars":
			Rhythia.map_sort = ""
			Rhythia.sort_by_stars = true
			Rhythia.sort_by_plays = false
		"plays":
			Rhythia.map_sort = ""
			Rhythia.sort_by_stars = false
			Rhythia.sort_by_plays = true
		_:
			Rhythia.map_sort = key
			Rhythia.sort_by_stars = false
			Rhythia.sort_by_plays = false
	# the hidden old checkboxes follow
	var box = _box
	var st = box.get_node_or_null("StarSort")
	if st != null:
		st.pressed = Rhythia.sort_by_stars
	var pl = box.get_node_or_null("PlaysSort")
	if pl != null:
		pl.pressed = Rhythia.sort_by_plays
	if key in ["sp_high", "sp_low", "recent_ranked"]:
		var lm = get_node_or_null("/root/LobbyManager")
		if lm != null and lm.has_method("list_ranked_maps"):
			lm.list_ranked_maps() # (each map's SP and rank date)
	Rhythia.save_settings()
	var list = preload("res://scripts/ui/menu/MapListOf.gd").find(filters.get_node("Label"))
	if list != null and list.has_method("update_search_sort_mode"):
		list.update_search_sort_mode()
	_update_button()

func _update_button():
	if button == null:
		return
	var key := _current_key()
	var label := "difficulty"
	for s in SORTS:
		if s[0] == key:
			label = s[1]
	button.hint_tooltip = "What to show and how to sort the maps (sorted by %s)" % label

func _toggle():
	if page.visible:
		_close()
	else:
		_open()

func _open():
	var cur := _current_key()
	if _radios.has(cur):
		_radios[cur].pressed = true
	var vp := filters.get_viewport_rect().size
	dim.rect_global_position = Vector2()
	dim.rect_size = vp
	var col := filters.get_global_rect()
	var h: float = clamp(col.size.y, 300.0, vp.y - 16.0)
	page.rect_size = Vector2(W, h)
	var x: float = col.position.x - W - 8.0
	if x < 8.0:
		x = col.end.x + 8.0
	page.rect_global_position = Vector2(x, clamp(col.position.y, 8.0, vp.y - h - 8.0))
	dim.visible = true
	page.visible = true

func _close():
	page.visible = false
	dim.visible = false

func _on_dim_input(ev):
	if ev is InputEventMouseButton and ev.pressed:
		_close()

func _unhandled_input(ev):
	if page != null and page.visible and ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		_close()
		get_tree().set_input_as_handled()
