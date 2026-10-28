extends VBoxContainer

# Settings > Background Editor: place images/videos around the screen. The
# layers are shown during gameplay by scripts/game/BgLayersGame.gd.
# Data: user://bg_layers.json, media files copied into user://bg_layers/.

const BG = preload("res://scripts/BgLayers.gd")
const Preview = preload("res://scripts/ui/settings/BgEditorPreview.gd")

const LILAC = Color(0.764706, 0.65098, 0.8)
const PINK = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.75, 0.75, 0.82, 1)
const LEFT_W = 300.0

enum { M_FRONT, M_BACK, M_FLIP, M_FULL, M_REMOVE, M_FIT_COVER = 10, M_FIT_STRETCH, M_FIT_CONTAIN }

var data: Dictionary
var layers: Array
var visuals: Array = [] # build_visual() results, same order as layers

var preview: Preview
var list: ItemList
var ctx: PopupMenu
var fit_menu: PopupMenu
var tint_btn: ColorPickerButton
var opacity_slider: HSlider
var opacity_label: Label
var fit_option: OptionButton
var flip_box: CheckBox
var props_box: VBoxContainer
var enabled_box: CheckBox
var placement_option: OptionButton
var status: Label
var save_timer: Timer
var error_tex: Texture

var font_reg: DynamicFont
var font_bold: DynamicFont
var font_small: DynamicFont
var _updating_ui := false

# Called once from menu2.gd: adds the "Background Editor" tab after
# "World & Cursor" in the settings TabContainer.
static func install(menu: Node):
	if menu == null:
		return
	var tc = menu.get_node_or_null("Main/Settings/S/F/TabContainer")
	if tc == null or tc.has_node("Background Editor"):
		return
	var tab = load("res://scripts/ui/settings/BgEditor.gd").new()
	tab.name = "Background Editor"
	tc.add_child(tab)
	var after = tc.get_node_or_null("World & Cursor")
	if after != null:
		tc.move_child(tab, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _label(text: String, font: Font = null, color: Color = TEXT) -> Label:
	var l = Label.new()
	l.text = text
	l.valign = Label.VALIGN_CENTER
	l.add_font_override("font", font if font else font_reg)
	l.add_color_override("font_color", color)
	return l

func _button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.rect_min_size = Vector2(0, 32)
	b.connect("pressed", self, method, args)
	return b

func _row(label_text: String) -> HBoxContainer:
	var r = HBoxContainer.new()
	r.add_constant_override("separation", 8)
	var l = _label(label_text)
	l.rect_min_size = Vector2(76, 0)
	r.add_child(l)
	return r

func _panel_style(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	if border.a > 0:
		s.set_border_width_all(1)
		s.border_color = border
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _ready():
	name = "Background Editor"
	add_constant_override("separation", 0)
	font_reg = _font("res://assets/font/Lato/Lato-Regular.ttf", 16)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 16)
	font_small = _font("res://assets/font/Lato/Lato-Regular.ttf", 13)
	error_tex = Globals.imageLoader.error_texture

	data = BG.load_data()
	layers = data.layers

	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, 10)
	add_child(spacer)

	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 66)
	margin.add_constant_override("margin_right", 66)
	margin.add_constant_override("margin_top", 12)
	margin.add_constant_override("margin_bottom", 12)
	add_child(margin)

	var main = VBoxContainer.new()
	main.add_constant_override("separation", 8)
	margin.add_child(main)

	var title = _label("Background Editor", _font("res://assets/font/Lato/Lato-Bold.ttf", 20))
	main.add_child(title)
	var hint = _label("Drag to move, corners to resize, top handle to rotate. Right-click for more.", font_small, DIM)
	hint.autowrap = true
	main.add_child(hint)

	var body = HBoxContainer.new()
	body.add_constant_override("separation", 16)
	main.add_child(body)

	# --- left column -----------------------------------------------------
	var left = VBoxContainer.new()
	left.rect_min_size = Vector2(LEFT_W, 0)
	left.add_constant_override("separation", 6)
	body.add_child(left)

	left.add_child(_label("Layers", font_bold, PINK))
	list = ItemList.new()
	list.rect_min_size = Vector2(LEFT_W, 190)
	list.fixed_icon_size = Vector2(48, 27)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.allow_rmb_select = true
	list.add_font_override("font", font_reg)
	list.add_stylebox_override("bg", _panel_style(Color(0.08, 0.075, 0.1), Color(1, 1, 1, 0.1)))
	list.add_stylebox_override("bg_focus", _panel_style(Color(0.08, 0.075, 0.1), Color(1, 1, 1, 0.1)))
	list.add_stylebox_override("selected", _panel_style(Color(LILAC.r, LILAC.g, LILAC.b, 0.35)))
	list.add_stylebox_override("selected_focus", _panel_style(Color(LILAC.r, LILAC.g, LILAC.b, 0.45)))
	list.connect("item_selected", self, "_on_list_selected")
	list.connect("item_rmb_selected", self, "_on_list_rmb")
	left.add_child(list)

	var btns = HBoxContainer.new()
	btns.add_constant_override("separation", 6)
	var imp = _button("Import media", "_on_import_pressed")
	imp.size_flags_horizontal = SIZE_EXPAND_FILL
	btns.add_child(imp)
	btns.add_child(_button("Remove", "_remove_selected"))
	btns.add_child(_button("Open folder", "_open_folder"))
	left.add_child(btns)
	var formats = _label("Images, or .webm / .ogv videos.", font_small, DIM)
	formats.autowrap = true
	formats.rect_min_size = Vector2(LEFT_W, 0)
	left.add_child(formats)

	left.add_child(HSeparator.new())

	props_box = VBoxContainer.new()
	props_box.add_constant_override("separation", 6)
	left.add_child(props_box)

	var tr = _row("Tint")
	tint_btn = ColorPickerButton.new()
	tint_btn.edit_alpha = false
	tint_btn.rect_min_size = Vector2(110, 30)
	tint_btn.connect("color_changed", self, "_on_tint_changed")
	tr.add_child(tint_btn)
	tr.add_child(_button("Reset", "_reset_tint"))
	props_box.add_child(tr)

	var orow = _row("Opacity")
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0
	opacity_slider.max_value = 100
	opacity_slider.step = 1
	opacity_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	opacity_slider.size_flags_vertical = SIZE_SHRINK_CENTER
	opacity_slider.connect("value_changed", self, "_on_opacity_changed")
	orow.add_child(opacity_slider)
	opacity_label = _label("100%")
	opacity_label.rect_min_size = Vector2(44, 0)
	orow.add_child(opacity_label)
	props_box.add_child(orow)

	var frow = _row("Fit")
	fit_option = OptionButton.new()
	fit_option.add_item("Stretch", 0)
	fit_option.add_item("Cover", 1)
	fit_option.add_item("Contain", 2)
	fit_option.size_flags_horizontal = SIZE_EXPAND_FILL
	fit_option.connect("item_selected", self, "_on_fit_option")
	frow.add_child(fit_option)
	flip_box = CheckBox.new()
	flip_box.text = "Flip"
	flip_box.add_font_override("font", font_reg)
	flip_box.connect("toggled", self, "_on_flip_toggled")
	frow.add_child(flip_box)
	props_box.add_child(frow)

	left.add_child(HSeparator.new())

	enabled_box = CheckBox.new()
	enabled_box.text = "Show in game"
	enabled_box.add_font_override("font", font_reg)
	enabled_box.pressed = data.enabled
	enabled_box.connect("toggled", self, "_on_enabled_toggled")
	left.add_child(enabled_box)

	var prow = _row("Draw")
	placement_option = OptionButton.new()
	placement_option.add_item("In front of the world", 0)
	placement_option.add_item("Behind the world", 1)
	placement_option.hint_tooltip = "Behind: the grid and notes draw over your layers (worlds with a sky always use In front)"
	placement_option.select(1 if data.placement == BG.PLACE_BEHIND else 0)
	placement_option.size_flags_horizontal = SIZE_EXPAND_FILL
	placement_option.connect("item_selected", self, "_on_placement")
	prow.add_child(placement_option)
	left.add_child(prow)

	# --- preview -----------------------------------------------------------
	var right = VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_label("Preview", font_bold, PINK))
	preview = Preview.new()
	var vp_size = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var aspect = vp_size.x / max(vp_size.y, 1.0)
	aspect = clamp(aspect, 1.0, 2.6)
	var pw = 800.0
	preview.rect_min_size = Vector2(pw, round(pw / aspect))
	preview.size_flags_horizontal = 0
	preview.layers = layers
	preview.connect("layer_selected", self, "_on_preview_selected")
	preview.connect("layer_changed", self, "_on_preview_changed")
	preview.connect("context_requested", self, "_on_context_requested")
	preview.connect("delete_requested", self, "_on_delete_requested")
	right.add_child(preview)
	status = _label("", font_small, PINK)
	right.add_child(status)

	# --- context menu ------------------------------------------------------
	ctx = PopupMenu.new()
	ctx.name = "LayerMenu"
	ctx.add_font_override("font", font_reg)
	fit_menu = PopupMenu.new()
	fit_menu.name = "FitMenu"
	fit_menu.add_font_override("font", font_reg)
	fit_menu.add_radio_check_item("Cover", M_FIT_COVER)
	fit_menu.add_radio_check_item("Stretch", M_FIT_STRETCH)
	fit_menu.add_radio_check_item("Contain", M_FIT_CONTAIN)
	fit_menu.connect("id_pressed", self, "_on_ctx_id")
	ctx.add_child(fit_menu)
	ctx.add_item("Move to Front", M_FRONT)
	ctx.add_item("Move to Back", M_BACK)
	ctx.add_check_item("Flip Horizontal", M_FLIP)
	ctx.add_item("Make Fullscreen", M_FULL)
	ctx.add_submenu_item("Fit", "FitMenu")
	ctx.add_separator()
	ctx.add_item("Remove", M_REMOVE)
	ctx.connect("id_pressed", self, "_on_ctx_id")
	add_child(ctx)

	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = 0.35
	save_timer.connect("timeout", self, "_save_now")
	add_child(save_timer)

	connect("visibility_changed", self, "_update_video_pause")

	_rebuild_visuals()
	_refresh_list()
	_select(layers.size() - 1 if layers.size() > 0 else -1)
	_update_video_pause()

# --- visuals / list -----------------------------------------------------------

func _rebuild_visuals():
	for v in visuals:
		if is_instance_valid(v.rect):
			v.rect.queue_free()
	visuals.clear()
	var rects = []
	for l in layers:
		var v = BG.build_visual(l, preview.layer_root(), error_tex, is_visible_in_tree())
		visuals.append(v)
		rects.append(v.rect)
	preview.rects = rects
	preview.relayout()

func _layer_title(i: int) -> String:
	var l = layers[i]
	var n = str(l.get("name", l.file))
	if n.length() > 28:
		n = n.substr(0, 26) + "…"
	if not visuals[i].ok:
		n = "(missing) " + n
	if BG.is_video_file(l.file):
		n += "  [video]"
	return n

func _refresh_list():
	list.clear()
	# Top-most layer first, like most editors.
	for i in range(layers.size() - 1, -1, -1):
		list.add_item(_layer_title(i), visuals[i].rect.texture)
	if layers.empty():
		list.add_item("No layers yet", null, false)
		list.set_item_disabled(0, true)

func _list_to_layer(li: int) -> int:
	return layers.size() - 1 - li

func _select(i: int):
	if i >= layers.size():
		i = layers.size() - 1
	preview.set_selected(i)
	if i >= 0:
		list.select(layers.size() - 1 - i)
	else:
		list.unselect_all()
	_update_props()

func _sel() -> int:
	return preview.selected if preview.selected >= 0 and preview.selected < layers.size() else -1

func _update_props():
	var i = _sel()
	_updating_ui = true
	for c in [tint_btn, fit_option, flip_box]:
		c.disabled = i < 0
	opacity_slider.editable = i >= 0
	if i >= 0:
		var l = layers[i]
		tint_btn.color = Color(l.tint)
		opacity_slider.value = round(l.opacity * 100.0)
		opacity_label.text = "%d%%" % int(round(l.opacity * 100.0))
		fit_option.select({BG.FIT_STRETCH: 0, BG.FIT_COVER: 1, BG.FIT_CONTAIN: 2}.get(l.fit, 0))
		flip_box.pressed = l.flip_h
	props_box.modulate.a = 1.0 if i >= 0 else 0.5
	_updating_ui = false

func _update_video_pause():
	var show = is_visible_in_tree()
	for v in visuals:
		if v.video != null and is_instance_valid(v.video):
			if show and not v.video.is_playing():
				v.video.play()
			v.video.paused = not show

func _queue_save():
	if save_timer and save_timer.is_inside_tree():
		save_timer.start()
	else:
		_save_now()

func _save_now():
	if not BG.save_data(data):
		status.text = "Couldn't save the background layers"

func _exit_tree():
	if save_timer and not save_timer.is_stopped():
		save_timer.stop()
		_save_now()

# --- signals --------------------------------------------------------------

func _on_list_selected(li: int):
	if layers.empty():
		return
	_select(_list_to_layer(li))

func _on_list_rmb(li: int, at: Vector2):
	if layers.empty():
		return
	_select(_list_to_layer(li))
	_open_ctx(list.rect_global_position + at)

func _on_preview_selected(i: int):
	_select(i)

func _on_preview_changed(_i: int):
	_queue_save()

func _on_context_requested(i: int, pos: Vector2):
	_select(i)
	_open_ctx(pos)

func _on_delete_requested(i: int):
	_remove_layer(i)

func _open_ctx(pos: Vector2):
	var i = _sel()
	if i < 0:
		return
	var l = layers[i]
	ctx.set_item_checked(ctx.get_item_index(M_FLIP), l.flip_h)
	fit_menu.set_item_checked(fit_menu.get_item_index(M_FIT_COVER), l.fit == BG.FIT_COVER)
	fit_menu.set_item_checked(fit_menu.get_item_index(M_FIT_STRETCH), l.fit == BG.FIT_STRETCH)
	fit_menu.set_item_checked(fit_menu.get_item_index(M_FIT_CONTAIN), l.fit == BG.FIT_CONTAIN)
	ctx.rect_size = Vector2()
	ctx.popup(Rect2(pos, Vector2(1, 1)))

func _on_ctx_id(id: int):
	var i = _sel()
	if i < 0:
		return
	var l = layers[i]
	match id:
		M_FRONT: _move_layer(i, layers.size() - 1)
		M_BACK: _move_layer(i, 0)
		M_FLIP: _set_prop(i, "flip_h", not l.flip_h)
		M_FULL:
			l.x = 0.5
			l.y = 0.5
			l.w = 1.0
			l.h = 1.0
			l.rot = 0.0
			_changed(i)
		M_FIT_COVER: _set_prop(i, "fit", BG.FIT_COVER)
		M_FIT_STRETCH: _set_prop(i, "fit", BG.FIT_STRETCH)
		M_FIT_CONTAIN: _set_prop(i, "fit", BG.FIT_CONTAIN)
		M_REMOVE: _remove_layer(i)

func _set_prop(i: int, key: String, value):
	layers[i][key] = value
	_changed(i)

func _changed(i: int):
	preview.refresh_layer(i)
	_update_props()
	_queue_save()

func _on_tint_changed(c: Color):
	if _updating_ui or _sel() < 0:
		return
	layers[_sel()].tint = c.to_html(false)
	preview.refresh_layer(_sel())
	_queue_save()

func _reset_tint():
	if _sel() < 0:
		return
	_set_prop(_sel(), "tint", "ffffff")

func _on_opacity_changed(v: float):
	opacity_label.text = "%d%%" % int(v)
	if _updating_ui or _sel() < 0:
		return
	layers[_sel()].opacity = clamp(v / 100.0, 0.0, 1.0)
	preview.refresh_layer(_sel())
	_queue_save()

func _on_fit_option(idx: int):
	if _updating_ui or _sel() < 0:
		return
	_set_prop(_sel(), "fit", [BG.FIT_STRETCH, BG.FIT_COVER, BG.FIT_CONTAIN][clamp(idx, 0, 2)])

func _on_flip_toggled(on: bool):
	if _updating_ui or _sel() < 0:
		return
	_set_prop(_sel(), "flip_h", on)

func _on_enabled_toggled(on: bool):
	data.enabled = on
	_queue_save()

func _on_placement(idx: int):
	data.placement = BG.PLACE_BEHIND if idx == 1 else BG.PLACE_FRONT
	_queue_save()

# --- layer operations -----------------------------------------------------------

func _move_layer(from: int, to: int):
	if from == to or from < 0 or from >= layers.size():
		return
	var l = layers[from]
	var v = visuals[from]
	layers.remove(from)
	visuals.remove(from)
	layers.insert(to, l)
	visuals.insert(to, v)
	for k in visuals.size():
		preview.layer_root().move_child(visuals[k].rect, k)
	var rects = []
	for vv in visuals:
		rects.append(vv.rect)
	preview.rects = rects
	_refresh_list()
	_select(to)
	_queue_save()

func _remove_selected():
	_remove_layer(_sel())

func _remove_layer(i: int):
	if i < 0 or i >= layers.size():
		return
	var file_name = layers[i].file
	var v = visuals[i]
	if v.video != null and is_instance_valid(v.video):
		v.video.stop()
	if is_instance_valid(v.rect):
		v.rect.queue_free()
	layers.remove(i)
	visuals.remove(i)
	preview.rects.remove(i)
	var still_used = false
	for l in layers:
		if l.file == file_name:
			still_used = true
	if not still_used:
		BG.delete_file(file_name)
	_refresh_list()
	_select(min(i, layers.size() - 1))
	preview.relayout()
	_save_now()
	status.text = "Removed layer"

func _open_folder():
	var dir = Directory.new()
	if not dir.dir_exists(BG.media_path("")):
		dir.make_dir_recursive(BG.media_path(""))
	OS.shell_open(ProjectSettings.globalize_path(BG.media_path("")))

func _on_import_pressed():
	if layers.size() >= BG.MAX_LAYERS:
		status.text = "You can have up to %d layers" % BG.MAX_LAYERS
		return
	if Globals.file_sel == null:
		status.text = "File picker isn't available"
		return
	Globals.file_sel.open_file(self, "_on_files_picked",
		PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif, *.webm, *.ogv ; Images and videos"]),
		true, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _on_files_picked(files):
	if not is_inside_tree():
		return
	var added = 0
	var msgs = []
	for path in files:
		path = str(path)
		if path == "":
			continue
		if layers.size() >= BG.MAX_LAYERS:
			msgs.append("layer limit reached")
			break
		if not BG.is_supported_file(path):
			var ext = path.get_extension().to_lower()
			if ["mp4", "mov", "mkv", "avi", "m4v"].has(ext):
				msgs.append("%s: .%s isn't supported, use .webm" % [path.get_file(), ext])
			else:
				msgs.append("%s isn't a supported file" % path.get_file())
			continue
		if add_layer_from_file(path):
			added += 1
		else:
			msgs.append("couldn't load " + path.get_file())
	if added > 0:
		msgs.push_front("Added %d layer%s" % [added, "" if added == 1 else "s"])
	status.text = PoolStringArray(msgs).join(" · ")

# Imports one file as a new top layer. Returns false if it can't be shown.
func add_layer_from_file(path: String) -> bool:
	var file_name = BG.import_file(path)
	if file_name == "":
		return false
	var l = BG.new_layer(file_name, 16.0 / 9.0)
	l.name = path.get_file()
	var v = BG.build_visual(l, preview.layer_root(), null, is_visible_in_tree())
	if not v.ok:
		if is_instance_valid(v.rect):
			v.rect.queue_free()
		BG.delete_file(file_name)
		return false
	var tex: Texture = v.rect.texture
	if tex != null and tex.get_height() > 0:
		var screen = preview.rect_size if preview.rect_size.y > 0 else Vector2(16, 9)
		var sized = BG.new_layer(file_name, float(tex.get_width()) / float(tex.get_height()))
		# new_layer assumes 16:9; correct for the real screen shape
		var screen_aspect = screen.x / screen.y
		l.w = sized.w * (16.0 / 9.0) / screen_aspect
		l.h = sized.h
	var offset = 0.03 * (layers.size() % 6)
	l.x = 0.5 + offset
	l.y = 0.5 + offset
	layers.append(l)
	visuals.append(v)
	preview.rects.append(v.rect)
	preview.relayout()
	_refresh_list()
	_select(layers.size() - 1)
	_save_now()
	return true
