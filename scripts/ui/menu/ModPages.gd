extends HBoxContainer

# The map screen's modifier checkboxes on pages: there are more of them than
# fit under the speed row, so they show a few rows at a time with a page bar
# under them ("<  • • •  >": the arrows turn the page, a dot jumps to its
# page; a page with a modifier on has a green dot, so nothing that's on is
# out of sight unnoticed). What was under the checkboxes (HP model, grade
# system, 360 speed) moves up under the bar.
#
# Only the classic layout: Sound Space Mode's tiles (SSModPanel.gd) have
# their own pages, and while they show this bar hides and leaves the
# checkboxes alone. menu2.gd installs it (_add_new_mod_checkboxes), before
# SSModPanel takes its snapshot of the layout.

const ROWS := 3 # rows of two per page
const ROW_H := 30.0
const ON_DOT := Color(0.45, 0.95, 0.5)
const LABEL_YELLOW := Color(0.960784, 1, 0.478431)

# the order (left, right, left, right...): the hardest first, then the
# ones that move or hide the notes, then the rest; any checkbox not named
# here goes at the end. (Long names in the right column: the left one's
# names reach towards the Best column next to it.)
const ORDER := [
	"NoFail", "SuddenDeath",
	"EasyMode", "HardMode",
	"Ghost", "HardModeMod",
	"HardRock", "HarderRockMod",
	"MirrorX", "MirrorY",
	"ReverseMod", "InvertMouse",
	"Earthquake", "VisualMode",
	"Chaos", "Strobe",
	"360", "FlashlightMod",
]

var mods: Control
var boxes := [] # CheckBox, in page order
var page := 0
var pages := 1
var _left_x := 0.0
var _right_dx := 180.0
var _top_y := 0.0
var _dots := []
var _prev: Button
var _next: Button
var _ss = null

static func install(mods_node: Control):
	if mods_node == null or mods_node.has_node("ModPages"):
		return
	var p = load("res://scripts/ui/menu/ModPages.gd").new()
	p.name = "ModPages"
	p.mods = mods_node
	mods_node.add_child(p)
	p._build()

func _build():
	# which checkboxes: the visible ones (Nearsight stays hidden)
	var found := {}
	for c in mods.get_children():
		if c is CheckBox and c.visible:
			found[c.name] = c
	for n in ORDER:
		if found.has(n):
			boxes.append(found[n])
			found.erase(n)
	for n in found:
		boxes.append(found[n])
	if boxes.empty():
		return
	# the two columns and the first row, from where they are now
	var nf = mods.get_node_or_null("NoFail")
	var sd = mods.get_node_or_null("SuddenDeath")
	_left_x = nf.rect_position.x if nf else boxes[0].rect_position.x
	_right_dx = (sd.rect_position.x - _left_x) if (nf and sd) else 180.0
	_top_y = 1e9
	var old_bottom := -1e9
	for b in boxes:
		_top_y = min(_top_y, b.rect_position.y)
		old_bottom = max(old_bottom, b.rect_position.y + b.rect_size.y)
	pages = int(ceil(boxes.size() / float(ROWS * 2)))

	# the page bar
	alignment = BoxContainer.ALIGN_CENTER
	add_constant_override("separation", 6)
	mouse_filter = MOUSE_FILTER_PASS
	var font: Font = nf.get_node("Label").get_font("font") if nf and nf.has_node("Label") else null
	_prev = _arrow("<", font, -1)
	for i in pages:
		var d := Button.new()
		d.flat = true
		d.focus_mode = FOCUS_NONE
		d.rect_min_size = Vector2(16, 22)
		d.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		d.connect("pressed", self, "_go_to", [i])
		d.connect("draw", self, "_draw_dot", [d, i])
		add_child(d)
		_dots.append(d)
	_next = _arrow(">", font, 1)
	var bar_y := _top_y + ROWS * ROW_H + 2
	rect_position = Vector2(_left_x - 60, bar_y)
	rect_size = Vector2(_right_dx + 120, 24)

	# what was under the checkboxes moves up under the bar
	var below := []
	for c in mods.get_children():
		if c is Control and c != self and not (c is CheckBox) and c.rect_position.y >= old_bottom - 1:
			below.append(c)
	var first := 1e9
	for c in below:
		first = min(first, c.rect_position.y)
	var shift: float = (bar_y + 30) - first
	for c in below:
		c.rect_position.y += shift
	var bottom := 0.0
	for c in mods.get_children():
		if c is Control and c.visible:
			bottom = max(bottom, c.rect_position.y + c.rect_size.y)
	mods.rect_min_size.y = bottom + 8

	if not Rhythia.is_connected("mods_changed", self, "_on_mods_changed"):
		Rhythia.connect("mods_changed", self, "_on_mods_changed")
	_show_page()

func _arrow(text: String, font: Font, dir: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.rect_min_size = Vector2(26, 22)
	if font != null:
		b.add_font_override("font", font)
	for k in ["font_color", "font_color_hover", "font_color_pressed"]:
		b.add_color_override(k, LABEL_YELLOW)
	b.connect("pressed", self, "_go", [dir])
	add_child(b)
	return b

func _go(dir: int):
	_go_to((page + dir + pages) % pages)

func _go_to(i: int):
	page = clamp(i, 0, pages - 1)
	_show_page()

# lays the page's checkboxes out in its rows and hides the others
func _show_page():
	if _ss_on():
		return
	for i in boxes.size():
		var b: CheckBox = boxes[i]
		if not is_instance_valid(b):
			continue
		var on_page: int = i / (ROWS * 2)
		var k: int = i % (ROWS * 2)
		b.visible = on_page == page
		b.rect_position.y = _top_y + (k / 2) * ROW_H
		# (the columns: whatever the menu shifted them to since, keep it)
		b.rect_position.x = _col_x(k % 2)
	visible = pages > 1
	for d in _dots:
		d.update()
	_prev.disabled = false
	_next.disabled = false
	var menu = get_tree().current_scene if is_inside_tree() else null
	if menu != null and menu.has_method("_relayout_mods_soon"):
		menu.call_deferred("_relayout_mods_soon")

# the x of a column now (the menu re-centres the checkboxes all together)
func _col_x(col: int) -> float:
	var nf = mods.get_node_or_null("NoFail")
	var base: float = nf.rect_position.x if nf else _left_x
	# (No-Fail is always in the left column)
	return base + (_right_dx if col == 1 else 0.0)

func _page_has_on(i: int) -> bool:
	for j in range(i * ROWS * 2, min(boxes.size(), (i + 1) * ROWS * 2)):
		if is_instance_valid(boxes[j]) and boxes[j].pressed:
			return true
	return false

func _draw_dot(d: Button, i: int):
	var c := d.rect_size / 2.0
	var cur := i == page
	var col: Color = ON_DOT if _page_has_on(i) else LABEL_YELLOW
	if not cur:
		col.a = 0.45
	d.draw_circle(c, 4.5 if cur else 3.5, col)
	if cur:
		d.draw_arc(c, 7.0, 0, TAU, 20, Color(col.r, col.g, col.b, 0.6), 1.5, true)

func _on_mods_changed():
	for d in _dots:
		d.update()

func _ss_on() -> bool:
	return bool(Rhythia.call("ss_menus_on")) if Rhythia.has_method("ss_menus_on") else false

# (Sound Space Mode on / off: SSModPanel puts its saved layout back; once it
# has, show this page again)
func _process(_d):
	var on := _ss_on()
	if on == _ss:
		return
	_ss = on
	# (deferred: SSModPanel puts its saved layout back in its own _process,
	# after this one)
	call_deferred("_after_ss")

func _after_ss():
	if _ss_on():
		visible = false
	else:
		_show_page()

func _input(ev):
	# the mouse wheel over the checkboxes turns the page
	if not is_visible_in_tree() or not (ev is InputEventMouseButton) or not ev.pressed:
		return
	if ev.button_index != BUTTON_WHEEL_UP and ev.button_index != BUTTON_WHEEL_DOWN:
		return
	var area = null
	for b in boxes:
		if is_instance_valid(b) and b.visible:
			var r: Rect2 = b.get_global_rect()
			var lbl = b.get_node_or_null("Label")
			if lbl is Control:
				r = r.merge(lbl.get_global_rect())
			area = r if area == null else area.merge(r)
	if area == null or not area.has_point(get_global_mouse_position()):
		return
	_go(-1 if ev.button_index == BUTTON_WHEEL_UP else 1)
	get_tree().set_input_as_handled()
