extends VBoxContainer

# The Hand Creator's editor (Settings > VR > Hands; the hand itself is
# vr/HandCreator.gd). A turning 3D preview, the list of parts, and for the
# picked part its shape, look, colour, place, turn and size; for the whole
# hand an outline, its size and whether the left hand is the mirror image.
# Every change shows at once in the preview, and on your own hands in the
# headset when the created hand is the one you wear.

const HC = preload("res://vr/HandCreator.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)

# [name, what of the part, axis, least, most, step, unit, sign] (place and size in cm; the design keeps mm)
const ROWS := [
	["Place: left / right", "pos", 0, -15.0, 15.0, 0.2, " cm", 1.0],
	["Place: down / up", "pos", 1, -15.0, 15.0, 0.2, " cm", 1.0],
	["Place: back / forward", "pos", 2, -15.0, 15.0, 0.2, " cm", -1.0], # (forward is -Z)
	["Size: wide", "size", 0, 0.2, 20.0, 0.2, " cm", 1.0],
	["Size: tall", "size", 1, 0.2, 20.0, 0.2, " cm", 1.0],
	["Size: long", "size", 2, 0.2, 20.0, 0.2, " cm", 1.0],
	["Turn: tip up / down", "rot", 0, -180.0, 180.0, 5.0, "°", 1.0],
	["Turn: left / right", "rot", 1, -180.0, 180.0, 5.0, "°", 1.0],
	["Turn: roll", "rot", 2, -180.0, 180.0, 5.0, "°", 1.0],
]

var tab = null # the VR settings tab (its fonts, and its Hands list)
var d: Dictionary = {}
var sel: int = 0
var _undo = null # the design before the last big change (a preset loaded, a code pasted, a part deleted)
var _loading := false

var _list: ItemList
var _shape: OptionButton
var _look: OptionButton
var _color: ColorPickerButton
var _add: OptionButton
var _preset: OptionButton
var _sliders := [] # [HSlider, value Label] per ROWS
var _outline: CheckBox
var _outline_color: ColorPickerButton
var _mirror: CheckBox
var _scale: HSlider
var _scale_val: Label
var _spin: CheckBox
var _status: Label
var _del: Button
var _undo_btn: Button
var _pivot: Spatial
var _mesh: MeshInstance
var _mark: MeshInstance
var _apply_at := 0
var _save_at := 0
var _hold = null # [slider, direction, next time]: a - / + button held

func setup(vr_tab):
	tab = vr_tab
	d = HC.parse(Rhythia.vr_hand_design)
	if d.parts.empty():
		d = HC.parse(HC.PRESETS[0][1])
	add_constant_override("separation", 8)
	_build()
	_refresh_all()

# --- small pieces ----------------------------------------------------------------

func _font(kind: String) -> Font:
	return tab.get("f_" + kind) if tab != null else null

func _lbl(text: String, parent: Node, kind: String = "body", col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap = wrap
	if _font(kind) != null:
		l.add_font_override("font", _font(kind))
	l.add_color_override("font_color", col)
	if wrap:
		l.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

func _btn(text: String, parent: Node, method: String, width: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	if _font("bold") != null:
		b.add_font_override("font", _font("bold"))
	b.rect_min_size = Vector2(width, 36)
	b.size_flags_horizontal = 0
	b.focus_mode = FOCUS_NONE
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _opt(parent: Node, items: Array, method: String, width: float = 220.0) -> OptionButton:
	var o := OptionButton.new()
	o.theme = load("res://uitheme.tres")
	if _font("body") != null:
		o.add_font_override("font", _font("body"))
	o.rect_min_size = Vector2(width, 34)
	for it in items:
		o.add_item(it[1])
		o.set_item_metadata(o.get_item_count() - 1, it[0])
	o.connect("item_selected", self, method)
	parent.add_child(o)
	return o

func _row(parent: Node = null) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 10)
	(parent if parent != null else self).add_child(h)
	return h

func _check(text: String, parent: Node, method: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.theme = load("res://uitheme.tres")
	if _font("bold") != null:
		c.add_font_override("font", _font("bold"))
	c.focus_mode = FOCUS_NONE
	c.connect("toggled", self, method)
	parent.add_child(c)
	return c

# a slider with exact - / + buttons beside it (dragging with the VR pointer is fiddly: VRTab.gd)
func _slider(parent: Node, lo: float, hi: float, step: float, method: String, binds: Array = []) -> Array:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.rect_min_size = Vector2(220, 28)
	sl.theme = load("res://uitheme.tres")
	sl.focus_mode = FOCUS_NONE
	sl.set("scrollable", false)
	for dir in [-1, 1]:
		if dir == 1:
			parent.add_child(sl)
		var b := Button.new()
		b.text = "-" if dir < 0 else "+"
		b.theme = load("res://uitheme.tres")
		if _font("title") != null:
			b.add_font_override("font", _font("title"))
		b.rect_min_size = Vector2(40, 34)
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.focus_mode = FOCUS_NONE
		b.connect("button_down", self, "_hold_down", [sl, dir])
		b.connect("button_up", self, "_hold_up")
		b.connect("mouse_exited", self, "_hold_up")
		parent.add_child(b)
	var val := _lbl("", parent)
	val.rect_min_size = Vector2(84, 0)
	sl.connect("value_changed", self, method, binds)
	return [sl, val]

func _hold_down(sl: HSlider, dir: int):
	sl.value = clamp(stepify(sl.value + dir * sl.step, sl.step), sl.min_value, sl.max_value)
	_hold = [sl, dir, OS.get_ticks_msec() + 400]

func _hold_up():
	_hold = null

# --- the page ----------------------------------------------------------------------

func _build():
	_lbl("Build your own hands out of parts. Pick a part in the list, then change its shape, colour, place, turn and size. Everything shows at once in the preview, and on your real hands in the headset while you wear this hand. The hand is the right one, seen with its fingers pointing away from you; the left hand is made from it.", self, "body", DIM, true)

	var top := _row()
	top.add_constant_override("separation", 14)
	top.add_child(_make_preview())
	var side := VBoxContainer.new()
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	side.add_constant_override("separation", 6)
	top.add_child(side)
	_lbl("Parts", side, "bold")
	_list = ItemList.new()
	_list.theme = load("res://uitheme.tres")
	if _font("body") != null:
		_list.add_font_override("font", _font("body"))
	_list.rect_min_size = Vector2(300, 190)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.focus_mode = FOCUS_NONE
	_list.connect("item_selected", self, "_on_pick")
	side.add_child(_list)
	var pb := _row(side)
	_add = _opt(pb, [["", "Add a part..."]] + HC.SHAPES, "_on_add", 170)
	_btn("Copy part", pb, "_on_duplicate", 110)
	_btn("Mirror copy", pb, "_on_mirror_copy", 120)
	_del = _btn("Delete", pb, "_on_delete", 90)
	_spin = _check("Turn the preview", side, "_on_spin")
	_spin.pressed = true

	add_child(HSeparator.new())
	_lbl("The picked part", self, "bold", ACCENT)
	var pr := _row()
	_lbl("Shape", pr, "bold")
	_shape = _opt(pr, HC.SHAPES, "_on_shape", 190)
	_lbl("Look", pr, "bold")
	_look = _opt(pr, HC.LOOKS, "_on_look", 170)
	_lbl("Colour", pr, "bold")
	_color = ColorPickerButton.new()
	_color.rect_min_size = Vector2(110, 34)
	_color.edit_alpha = false
	_color.connect("color_changed", self, "_on_color")
	pr.add_child(_color)
	for i in range(ROWS.size()):
		var r := _row()
		var name_l := _lbl(ROWS[i][0], r, "bold")
		name_l.rect_min_size = Vector2(210, 0)
		_sliders.append(_slider(r, ROWS[i][3], ROWS[i][4], ROWS[i][5], "_on_slider", [i]))

	add_child(HSeparator.new())
	_lbl("The whole hand", self, "bold", ACCENT)
	var wr := _row()
	_outline = _check("Outline", wr, "_on_outline")
	_outline_color = ColorPickerButton.new()
	_outline_color.rect_min_size = Vector2(110, 34)
	_outline_color.edit_alpha = false
	_outline_color.connect("color_changed", self, "_on_outline_color")
	wr.add_child(_outline_color)
	_mirror = _check("The left hand is its mirror image (off: the same shape on both hands)", wr, "_on_mirror")
	var sr := _row()
	var sl_name := _lbl("Hand size", sr, "bold")
	sl_name.rect_min_size = Vector2(210, 0)
	var sc := _slider(sr, HC.SCALE_MIN, HC.SCALE_MAX, 5, "_on_scale")
	_scale = sc[0]
	_scale_val = sc[1]

	add_child(HSeparator.new())
	var st := _row()
	_lbl("Start from", st, "bold")
	var names := []
	for p in HC.PRESETS:
		names.append([p[0], p[0]])
	_preset = _opt(st, names, "_noop", 280)
	_btn("Load it", st, "_on_preset", 100)
	_undo_btn = _btn("Undo", st, "_on_undo", 90)
	var br := _row()
	_btn("Wear this hand", br, "_on_wear", 170)
	_btn("Copy its code", br, "_on_copy", 150)
	_btn("Paste a code", br, "_on_paste", 150)
	_status = _lbl("", self, "body", DIM, true)

func _make_preview() -> Control:
	var vc := ViewportContainer.new()
	vc.rect_min_size = Vector2(360, 300)
	vc.stretch = true
	vc.mouse_filter = MOUSE_FILTER_PASS
	var vp := Viewport.new()
	vp.own_world = true
	vp.size = Vector2(360, 300)
	vp.msaa = Viewport.MSAA_4X
	vp.transparent_bg = false
	vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	vc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.085, 0.12)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera.new()
	cam.fov = 38
	cam.near = 0.01
	cam.far = 5.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.13, 0.24), Vector3(0, 0, -0.012), Vector3.UP)
	cam.current = true
	_pivot = Spatial.new()
	vp.add_child(_pivot)
	_mesh = MeshInstance.new()
	_pivot.add_child(_mesh)
	# the picked part, shown through everything in see-through yellow
	_mark = MeshInstance.new()
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.flags_no_depth_test = true
	m.albedo_color = Color(1.0, 0.9, 0.2, 0.38)
	_mark.material_override = m
	_pivot.add_child(_mark)
	return vc

# --- showing the design --------------------------------------------------------------

func _swatch(c: Color) -> ImageTexture:
	var img := Image.new()
	img.create(18, 18, false, Image.FORMAT_RGB8)
	img.fill(c)
	var t := ImageTexture.new()
	t.create_from_image(img, 0)
	return t

func _select_meta(o: OptionButton, value):
	for i in range(o.get_item_count()):
		if str(o.get_item_metadata(i)) == str(value):
			o.select(i)
			return

func _refresh_all():
	_loading = true
	sel = int(clamp(sel, 0, max(0, d.parts.size() - 1)))
	_list.clear()
	for i in range(d.parts.size()):
		var p: Dictionary = d.parts[i]
		_list.add_item("%d. %s" % [i + 1, HC.shape_name(p.shape)], _swatch(p.color))
	if d.parts.size() > 0:
		_list.select(sel)
	_outline.pressed = bool(d.outline)
	_outline_color.color = d.outline_color
	_mirror.pressed = bool(d.mirror)
	_scale.value = int(d.scale)
	_scale_val.text = "%d %%" % int(d.scale)
	_del.disabled = d.parts.size() <= 1
	_undo_btn.disabled = _undo == null
	_loading = false
	_refresh_part()
	_redraw()

func _refresh_part():
	if d.parts.empty():
		return
	_loading = true
	var p: Dictionary = d.parts[sel]
	_select_meta(_shape, p.shape)
	_select_meta(_look, p.look)
	_color.color = p.color
	for i in range(ROWS.size()):
		var r: Array = ROWS[i]
		var v: float = Vector3(p[r[1]])[r[2]] * float(r[7])
		if r[1] != "rot":
			v /= 10.0 # mm -> cm
		_sliders[i][0].value = v
		_sliders[i][1].text = _fmt(_sliders[i][0].value, r)
	_loading = false

static func _fmt(v: float, r: Array) -> String:
	if r[1] == "rot":
		return "%d%s" % [int(round(v)), r[6]]
	return "%.1f%s" % [v, r[6]]

func _redraw():
	_mesh.mesh = HC.build(d)
	_mark.mesh = HC.build(d, sel) if not d.parts.empty() else null

# the design changed: the preview now, your hands and the settings file a moment later
func _changed(list_too: bool = false):
	Rhythia.vr_hand_design = HC.encode(d)
	if list_too:
		_refresh_all()
	else:
		_redraw()
	var now := OS.get_ticks_msec()
	_apply_at = now + 150
	_save_at = now + 1200

func _process(delta: float):
	if _pivot != null and _spin != null and _spin.pressed and is_visible_in_tree():
		_pivot.rotate_y(delta * 0.7)
	var now := OS.get_ticks_msec()
	if _hold != null and now >= int(_hold[2]):
		var sl: HSlider = _hold[0]
		sl.value = clamp(stepify(sl.value + int(_hold[1]) * sl.step, sl.step), sl.min_value, sl.max_value)
		_hold[2] = now + 70
	if _apply_at > 0 and now >= _apply_at:
		_apply_at = 0
		var vp = Rhythia.vr_player
		if is_instance_valid(vp) and vp.has_method("refresh_built_hand"):
			vp.refresh_built_hand()
	if _save_at > 0 and now >= _save_at:
		_save_at = 0
		Rhythia.save_settings()

func _exit_tree():
	if _save_at > 0:
		_save_at = 0
		Rhythia.save_settings()

func _say(text: String):
	_status.text = text

func _keep_undo():
	_undo = HC.parse(HC.encode(d))

# --- what is pressed -------------------------------------------------------------------

func _noop(_i = 0):
	pass

func _on_pick(i: int):
	if _loading:
		return
	sel = i
	_refresh_part()
	_redraw()

func _on_add(i: int):
	var shape := str(_add.get_item_metadata(i))
	_add.select(0)
	if shape == "":
		return
	if d.parts.size() >= HC.MAX_PARTS:
		_say("A hand can have %d parts at most." % HC.MAX_PARTS)
		return
	var p: Dictionary = HC.part(shape)
	if not d.parts.empty():
		# (in the colour and look of the picked part: most parts of a hand match)
		p.color = d.parts[sel].color
		p.look = d.parts[sel].look
	d.parts.append(p)
	sel = d.parts.size() - 1
	_changed(true)

func _copy_of(p: Dictionary) -> Dictionary:
	return {shape = p.shape, pos = Vector3(p.pos), rot = Vector3(p.rot), size = Vector3(p.size), color = Color(p.color), look = p.look}

func _on_duplicate():
	if d.parts.empty() or d.parts.size() >= HC.MAX_PARTS:
		return
	var p := _copy_of(d.parts[sel])
	p.pos += Vector3(10, 0, 0)
	d.parts.append(p)
	sel = d.parts.size() - 1
	_changed(true)

# the same part on the other side of the hand
func _on_mirror_copy():
	if d.parts.empty() or d.parts.size() >= HC.MAX_PARTS:
		return
	var p := _copy_of(d.parts[sel])
	p.pos.x = -p.pos.x
	p.rot.y = -p.rot.y
	p.rot.z = -p.rot.z
	d.parts.append(p)
	sel = d.parts.size() - 1
	_changed(true)

func _on_delete():
	if d.parts.size() <= 1:
		return
	_keep_undo()
	d.parts.remove(sel)
	_changed(true)

func _on_shape(i: int):
	if _loading or d.parts.empty():
		return
	d.parts[sel].shape = str(_shape.get_item_metadata(i))
	_changed(true)

func _on_look(i: int):
	if _loading or d.parts.empty():
		return
	d.parts[sel].look = str(_look.get_item_metadata(i))
	_changed()

func _on_color(c: Color):
	if _loading or d.parts.empty():
		return
	d.parts[sel].color = Color(c.r, c.g, c.b)
	_list.set_item_icon(sel, _swatch(c))
	_changed()

func _on_slider(v: float, i: int):
	var r: Array = ROWS[i]
	_sliders[i][1].text = _fmt(v, r)
	if _loading or d.parts.empty():
		return
	var vec: Vector3 = d.parts[sel][r[1]]
	vec[r[2]] = v * float(r[7]) * (1.0 if r[1] == "rot" else 10.0)
	d.parts[sel][r[1]] = vec
	_changed()

func _on_outline(on: bool):
	if _loading:
		return
	d.outline = on
	_changed()

func _on_outline_color(c: Color):
	if _loading:
		return
	d.outline_color = Color(c.r, c.g, c.b)
	_changed()

func _on_mirror(on: bool):
	if _loading:
		return
	d.mirror = on
	_changed()

func _on_scale(v: float):
	_scale_val.text = "%d %%" % int(v)
	if _loading:
		return
	d.scale = int(v)
	_changed()

func _on_spin(_on: bool):
	pass

func _on_preset():
	_keep_undo()
	d = HC.parse(HC.PRESETS[_preset.selected][1])
	sel = 0
	_changed(true)
	_say("Loaded \"%s\". Undo brings your hand back." % HC.PRESETS[_preset.selected][0])

func _on_undo():
	if _undo == null:
		return
	d = _undo
	_undo = null
	sel = 0
	_changed(true)
	_say("Back to the hand before.")

func _on_wear():
	Rhythia.vr_hand_design = HC.encode(d)
	Rhythia.vr_hand = "built"
	if tab != null and tab.get("_hand_pick") != null:
		tab._select_meta(tab._hand_pick, "built")
	var vp = Rhythia.vr_player
	if is_instance_valid(vp) and vp.has_method("refresh_built_hand"):
		vp.refresh_built_hand()
	Rhythia.save_settings()
	_say("You are wearing this hand now%s." % ("" if Rhythia.vr else " (you see it on your hands in VR)"))

func _on_copy():
	OS.clipboard = HC.code_of(d)
	_say("The hand's code is copied. Send it to someone: they paste it here with \"Paste a code\".")

func _on_paste():
	var got = HC.from_code(OS.clipboard)
	if got == null:
		_say("There is no hand code copied. Copy a code that starts with %s first." % HC.CODE_PREFIX)
		return
	_keep_undo()
	d = got
	sel = 0
	_changed(true)
	_say("Pasted a hand with %d parts. Undo brings your hand back." % d.parts.size())
