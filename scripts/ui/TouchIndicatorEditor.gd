extends Control

# Settings > Gameplay > "Customize Touch Indicator": every option of the touch
# indicator (scripts/ui/TouchIndicator.gd) with a live preview. Changes apply
# right away and are kept in Rhythia.touch_style (only the keys that differ
# from TouchIndicator.DEFAULTS), saved when the panel closes.

const TI = preload("res://scripts/ui/TouchIndicator.gd")
const PICTURE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]

var _font: DynamicFont
var _small: DynamicFont
var _controls := {}       # key -> control showing it
var _value_labels := {}   # key -> label next to a slider
var _loading := false
var _preview: Control
var _picture: Texture = null
var _time := 0.0
var _trail := []          # preview finger trail [[pos, t]]
var _pic_status: Label

func _ready():
	name = "TouchIndicatorEditor"
	pause_mode = PAUSE_MODE_PROCESS
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	var th: Theme = load("res://uitheme.tres").duplicate()
	_font = DynamicFont.new()
	_font.font_data = load("res://assets/font/Lato/Lato-Regular.ttf")
	_font.size = 22
	_small = DynamicFont.new()
	_small.font_data = _font.font_data
	_small.size = 17
	th.default_font = _font
	theme = th
	_picture = _load_picture()
	_build()
	_refresh()

# --- UI ---------------------------------------------------------------------

func _build():
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	add_child(panel)
	_fit_panel(panel)
	get_viewport().connect("size_changed", self, "_fit_panel", [panel])

	var col := VBoxContainer.new()
	col.add_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Touch Indicator"
	var big := DynamicFont.new()
	big.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	big.size = 30
	title.add_font_override("font", big)
	title.align = Label.ALIGN_CENTER
	col.add_child(title)

	_preview = Control.new()
	_preview.rect_min_size = Vector2(0, 170)
	_preview.rect_clip_content = true
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	_preview.connect("draw", self, "_draw_preview")
	col.add_child(_preview)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_constant_override("separation", 6)
	scroll.add_child(rows)

	_section(rows, "Presets")
	var presets := OptionButton.new()
	presets.add_item("Pick a preset...")
	for n in TI.PRESETS:
		presets.add_item(n)
	presets.connect("item_selected", self, "_on_preset", [presets])
	_row(rows, "Preset", presets)

	_section(rows, "Look")
	var shape := OptionButton.new()
	for n in TI.SHAPE_NAMES:
		shape.add_item(n)
	shape.connect("item_selected", self, "_on_shape")
	_controls["shape"] = shape
	_row(rows, "Shape", shape)
	_slider(rows, "size", "Size", 8, 200, 1, "%d px")
	_slider(rows, "thickness", "Outline width", 0.5, 20, 0.5, "%.1f px")
	_color(rows, "color", "Outline colour")
	_color(rows, "fill", "Fill colour")
	_slider(rows, "opacity", "Opacity", 0.05, 1, 0.05, "%d%%", 100)

	_section(rows, "Animation")
	_slider(rows, "fade", "Fade out time", 0, 2, 0.01, "%.2f s")
	_check(rows, "grow", "Grow while fading out")
	_check(rows, "pop", "Pop in when touching")
	_check(rows, "ripple", "Ripple on every tap")
	_slider(rows, "ripple_size", "Ripple size", 1.1, 5, 0.1, "%.1fx")
	_check(rows, "trail", "Trail behind moving fingers")
	_slider(rows, "trail_time", "Trail length", 0.05, 1.5, 0.05, "%.2f s")
	_slider(rows, "trail_width", "Trail width", 0.05, 1.5, 0.05, "%d%%", 100)
	_check(rows, "rainbow", "Rainbow colours")
	_slider(rows, "rainbow_speed", "Rainbow speed", 0.05, 4, 0.05, "%.2fx")

	_section(rows, "Where")
	_check(rows, "in_menus", "Show in menus")
	_check(rows, "in_songs", "Show while playing songs")

	_section(rows, "Custom picture")
	var pics := HBoxContainer.new()
	pics.add_constant_override("separation", 10)
	var pick := Button.new()
	pick.text = "Pick picture..."
	pick.size_flags_horizontal = SIZE_EXPAND_FILL
	pick.rect_min_size.y = 50
	pick.connect("pressed", self, "_on_pick_picture")
	pics.add_child(pick)
	var clear := Button.new()
	clear.text = "Remove picture"
	clear.size_flags_horizontal = SIZE_EXPAND_FILL
	clear.rect_min_size.y = 50
	clear.connect("pressed", self, "_on_remove_picture")
	pics.add_child(clear)
	rows.add_child(pics)
	_pic_status = Label.new()
	_pic_status.add_font_override("font", _small)
	_pic_status.autowrap = true
	_pic_status.add_color_override("font_color", Color(0.75, 0.75, 0.8))
	rows.add_child(_pic_status)

	var bottom := HBoxContainer.new()
	bottom.add_constant_override("separation", 12)
	var reset := Button.new()
	reset.text = "Reset to default"
	reset.size_flags_horizontal = SIZE_EXPAND_FILL
	reset.rect_min_size.y = 50
	reset.connect("pressed", self, "_on_reset")
	bottom.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.size_flags_horizontal = SIZE_EXPAND_FILL
	done.rect_min_size.y = 50
	done.connect("pressed", self, "close")
	bottom.add_child(done)
	col.add_child(bottom)

func _fit_panel(panel: Control):
	var vp := get_viewport_rect().size
	var size := Vector2(min(vp.x - 24, 760), min(vp.y - 24, 900))
	panel.margin_left = -size.x / 2
	panel.margin_right = size.x / 2
	panel.margin_top = -size.y / 2
	panel.margin_bottom = size.y / 2

func _section(rows: Control, text: String):
	var l := Label.new()
	l.text = text
	l.add_color_override("font_color", Color(0.8, 0.66, 1.0))
	if rows.get_child_count() > 0:
		l.rect_min_size.y = 40
		l.valign = Label.VALIGN_BOTTOM
	rows.add_child(l)

func _row(rows: Control, text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	var l := Label.new()
	l.text = text
	l.rect_min_size.x = 210
	l.valign = Label.VALIGN_CENTER
	l.size_flags_vertical = SIZE_FILL
	h.add_child(l)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	control.rect_min_size.y = 44
	h.add_child(control)
	rows.add_child(h)
	return h

func _slider(rows: Control, key: String, text: String, lo: float, hi: float, step: float, fmt: String, mult: float = 1.0):
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.connect("value_changed", self, "_on_value", [key])
	var h := _row(rows, text, s)
	var v := Label.new()
	v.rect_min_size.x = 84
	v.align = Label.ALIGN_RIGHT
	v.valign = Label.VALIGN_CENTER
	v.size_flags_vertical = SIZE_FILL
	v.set_meta("fmt", fmt)
	v.set_meta("mult", mult)
	h.add_child(v)
	_controls[key] = s
	_value_labels[key] = v

func _color(rows: Control, key: String, text: String):
	var c := ColorPickerButton.new()
	c.edit_alpha = true
	c.connect("color_changed", self, "_on_color", [key])
	c.get_popup().connect("about_to_show", self, "_keep_on_screen", [c])
	_row(rows, text, c)
	_controls[key] = c

func _check(rows: Control, key: String, text: String):
	var c := CheckBox.new()
	c.text = text
	c.flat = true
	c.rect_min_size.y = 44
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
		c.add_color_override(k, Color(0.9, 0.95, 1.0))
	c.connect("toggled", self, "_on_check", [key])
	rows.add_child(c)
	_controls[key] = c

# Colour pickers open at the button, which can be partly off the screen.
func _keep_on_screen(c: ColorPickerButton):
	yield(get_tree(), "idle_frame")
	var pop: Control = c.get_popup()
	if not is_instance_valid(pop):
		return
	var vp := get_viewport_rect().size
	var r := pop.get_global_rect()
	var p := r.position
	p.x = clamp(p.x, 8, max(8, vp.x - r.size.x - 8))
	p.y = clamp(p.y, 8, max(8, vp.y - r.size.y - 8))
	pop.rect_global_position = p

func _refresh():
	_loading = true
	var st: Dictionary = TI.style()
	for key in _controls:
		var c = _controls[key]
		if key == "shape":
			c.select(max(0, TI.SHAPES.find(String(st.shape))))
		elif c is ColorPickerButton:
			c.color = TI.color_of(st[key], Color(TI.DEFAULTS[key]))
		elif c is CheckBox:
			c.pressed = bool(st[key])
		elif c is HSlider:
			c.value = float(st[key])
			_show_value(key, float(st[key]))
	_loading = false
	_update_enabled(st)
	_update_picture_status(st)

func _show_value(key: String, v: float):
	var l: Label = _value_labels.get(key)
	if l == null:
		return
	var fmt: String = l.get_meta("fmt")
	var mult: float = l.get_meta("mult")
	l.text = fmt % (v * mult)

# Options that only matter when another one is on are greyed out.
func _update_enabled(st: Dictionary):
	var deps := {"ripple_size": "ripple", "trail_time": "trail", "trail_width": "trail", "rainbow_speed": "rainbow"}
	for key in deps:
		var on := bool(st[deps[key]])
		_controls[key].editable = on
		_controls[key].modulate.a = 1.0 if on else 0.45
		_value_labels[key].modulate.a = 1.0 if on else 0.45

func _update_picture_status(st: Dictionary):
	if _picture == null:
		_pic_status.text = "No picture yet. Pick one (a PNG with a see-through background looks best) and the shape switches to \"Custom picture\"."
	elif String(st.shape) != "image":
		_pic_status.text = "A picture is saved. Set the shape to \"Custom picture\" to use it."
	else:
		_pic_status.text = "Using your picture (%dx%d)." % [_picture.get_width(), _picture.get_height()]

# --- Changes ----------------------------------------------------------------

func _put(key: String, value):
	if _loading:
		return
	var user: Dictionary = Rhythia.touch_style.duplicate()
	if typeof(value) == typeof(TI.DEFAULTS[key]) and value == TI.DEFAULTS[key]:
		user.erase(key)
	else:
		user[key] = value
	Rhythia.touch_style = user
	var st: Dictionary = TI.style()
	_update_enabled(st)
	_update_picture_status(st)

func _on_value(v: float, key: String):
	_show_value(key, v)
	_put(key, v)

func _on_check(on: bool, key: String):
	_put(key, on)

func _on_color(c: Color, key: String):
	_put(key, c.to_html(true))

func _on_shape(i: int):
	_put("shape", TI.SHAPES[i])

func _on_preset(i: int, ob: OptionButton):
	if i <= 0:
		return
	var preset: Dictionary = TI.PRESETS[ob.get_item_text(i)]
	var keep := {}
	for k in ["in_menus", "in_songs"]:
		if Rhythia.touch_style.has(k):
			keep[k] = Rhythia.touch_style[k]
	var user := preset.duplicate()
	for k in keep:
		user[k] = keep[k]
	Rhythia.touch_style = user
	_refresh()
	ob.select(0)

func _on_reset():
	Rhythia.touch_style = {}
	_refresh()

# --- Custom picture ---------------------------------------------------------

func _load_picture() -> Texture:
	var tex = Globals.imageLoader.load_if_exists("user://touch")
	if tex == null or tex == Globals.imageLoader.error_texture or tex == Globals.imageLoader.invalid_texture:
		return null
	return tex

func _remove_pictures():
	var d := Directory.new()
	for ext in PICTURE_EXTS:
		var p: String = Globals.p("user://touch.%s" % ext)
		if d.file_exists(p):
			d.remove(p)

func _on_pick_picture():
	if Globals.file_sel.get_parent() != null:
		Globals.file_sel.raise() # above this panel
	Globals.file_sel.open_file(self, "_on_picture_picked", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Images"]), false, OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) if OS.has_feature("pc") else "user://")

func _on_picture_picked(files):
	if files == null or files.size() == 0:
		return
	var src := String(files[0])
	var ext := src.get_extension().to_lower()
	if not ext in PICTURE_EXTS:
		Globals.notify(Globals.NOTIFY_ERROR, "Pick a png, jpg, webp, bmp or gif picture.", "Touch Indicator")
		return
	_remove_pictures()
	if Directory.new().copy(src, Globals.p("user://touch.%s" % ext)) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't copy that picture.", "Touch Indicator")
		return
	_picture_changed()
	if _picture == null:
		_remove_pictures()
		Globals.notify(Globals.NOTIFY_ERROR, "That picture couldn't be opened.", "Touch Indicator")
		_picture_changed()
		return
	_put("shape", "image")
	_refresh()

func _on_remove_picture():
	_remove_pictures()
	_picture_changed()
	if String(TI.style().shape) == "image":
		_put("shape", TI.DEFAULTS.shape)
	_refresh()

func _picture_changed():
	_picture = _load_picture()
	var ind = Rhythia.get_node_or_null("TouchIndicator")
	if ind and ind.has_method("reload_picture"):
		ind.reload_picture()

# --- Preview ----------------------------------------------------------------

func _process(delta):
	_time += delta
	if is_instance_valid(_preview):
		_preview.update()

func _draw_preview():
	var st: Dictionary = TI.style()
	var size := _preview.rect_size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.05)
	bg.set_corner_radius_all(10)
	_preview.draw_style_box(bg, Rect2(Vector2(), size))
	_preview.draw_string(_small, Vector2(12, size.y - 12), "Tap", Color(1, 1, 1, 0.35))
	_preview.draw_string(_small, Vector2(size.x * 0.36, size.y - 12), "Drag", Color(1, 1, 1, 0.35))

	# a finger tapping on the left: held 0.45 s, then lifted
	var cycle := 0.45 + max(float(st.fade), 0.05) + 0.35
	var t := fmod(_time, cycle)
	var tap_pos := Vector2(size.x * 0.17, size.y * 0.5)
	if st.ripple and t < 0.5:
		TI.draw_ripple(_preview, tap_pos, t / 0.5, st, _hue(0, st))
	var a := 1.0
	if t > 0.45:
		a = 1.0 - (t - 0.45) / max(float(st.fade), 0.01)
	if a > 0.0:
		TI.draw_marker(_preview, tap_pos, clamp(a, 0, 1), st, TI.marker_scale(st, t, clamp(a, 0, 1)), _hue(0, st), _picture)

	# a finger moving in a loop on the right
	var c := Vector2(size.x * 0.66, size.y * 0.5)
	var p := c + Vector2(cos(_time * 1.7) * size.x * 0.25, sin(_time * 3.4) * size.y * 0.28)
	_trail.append([p, _time])
	while _trail.size() > 0 and _time - _trail[0][1] > float(st.trail_time):
		_trail.pop_front()
	if st.trail and _trail.size() > 1:
		TI.draw_trail(_preview, _trail, _time, st, 1.0, _hue(1, st))
	TI.draw_marker(_preview, p, 1.0, st, TI.marker_scale(st, 1.0, 1.0), _hue(1, st), _picture)

func _hue(i: int, st: Dictionary) -> float:
	return fmod(_time * float(st.rainbow_speed) + i * 0.17, 1.0)

# --- Closing ----------------------------------------------------------------

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		close()

func close():
	Rhythia.save_settings()
	queue_free()
