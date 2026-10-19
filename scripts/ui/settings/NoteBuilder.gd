extends MarginContainer

# "Note Builder" settings tab: build a custom 3D note mesh with sliders and a
# live preview, then use it as the gameplay note. Built in code; added to the
# settings TabContainer by add_tab() (called from menu2.gd _ready()).

const NBMesh = preload("res://scripts/ui/settings/NoteBuilderMesh.gd")

const LILAC = Color(0.764706, 0.65098, 0.8)
const LILAC_HOVER = Color(0.913725, 0.74902, 0.94902)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)

# key, label, min, max, step, percent display
const SLIDERS = [
	["Shape"],
	["corners", "Corners", 3, 14, 1, false],
	["rounding", "Corner Rounding", 0, 1, 0.01, true],
	["fill", "Border Fill", 0, 1, 0.01, true],
	["Volume"],
	["depth", "Depth", 0.02, 1, 0.01, false],
	["bevel", "Bevel", 0, 1, 0.01, true],
	["bulge", "Bulge", 0, 1, 0.01, true],
]

const PRESETS = [
	["Rounded", {"corners": 4, "rounding": 0.35, "fill": 1.0, "depth": 0.2, "bevel": 0.0, "bulge": 0.0}],
	["Circle", {"corners": 4, "rounding": 1.0, "fill": 1.0, "depth": 0.2, "bevel": 0.0, "bulge": 0.0}],
	["Hex Ring", {"corners": 6, "rounding": 0.15, "fill": 0.3, "depth": 0.25, "bevel": 0.5, "bulge": 0.0}],
	["Pillow", {"corners": 4, "rounding": 0.5, "fill": 1.0, "depth": 0.3, "bevel": 0.8, "bulge": 0.6}],
	["Donut", {"corners": 14, "rounding": 1.0, "fill": 0.45, "depth": 0.45, "bevel": 1.0, "bulge": 0.3}],
]

var params: Dictionary = {}
var sliders: Dictionary = {}
var value_labels: Dictionary = {}

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont

var vp: Viewport
var pivot: Spatial
var mesh_inst: MeshInstance
var wire_inst: MeshInstance
var surface_mat: SpatialMaterial
var wire_mat: SpatialMaterial
var wire_check: CheckBox
var status: Label
var stats_label: Label
var use_btn: Button

var _dirty := true
var _save_timer := -1.0
var _setting_ui := false
var _dragging := false
var _idle_t := 0.0
var _yaw := 0.6
var _pitch := 0.35

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container):
		return
	if tab_container.has_node("Note Builder"):
		return
	var tab = load("res://scripts/ui/settings/NoteBuilder.gd").new()
	tab.name = "Note Builder"
	tab_container.add_child(tab)
	var notes = tab_container.get_node_or_null("Notes")
	if notes != null:
		tab_container.move_child(tab, notes.get_index() + 1)

# ------------------------------------------------------------------- UI helpers

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
	l.add_font_override("font", font if font else font_regular)
	l.add_color_override("font_color", color)
	return l

func _flat(bg: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

func _button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.rect_min_size = Vector2(0, 32)
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", font_regular)
	b.connect("pressed", self, method, args)
	return b

func _grabber_tex(col: Color) -> ImageTexture:
	var sz := 16
	var img = Image.new()
	img.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.lock()
	var c := Vector2(sz / 2.0 - 0.5, sz / 2.0 - 0.5)
	for y in range(sz):
		for x in range(sz):
			var d = Vector2(x, y).distance_to(c)
			var a = clamp(7.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.unlock()
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER)
	return t

func _style_slider(s: HSlider) -> void:
	var track = _flat(Color(0.16, 0.15, 0.2, 1), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill = _flat(LILAC, 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_h = _flat(LILAC_HOVER, 3)
	fill_h.content_margin_top = 3
	fill_h.content_margin_bottom = 3
	s.add_stylebox_override("slider", track)
	s.add_stylebox_override("grabber_area", fill)
	s.add_stylebox_override("grabber_area_highlight", fill_h)
	s.add_icon_override("grabber", _grabber_tex(LILAC))
	s.add_icon_override("grabber_highlight", _grabber_tex(LILAC_HOVER))
	s.add_icon_override("grabber_disabled", _grabber_tex(DIM))

# ---------------------------------------------------------------------- build

func _ready():
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 18)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 22)
	params = NBMesh.load_params()

	add_constant_override("margin_left", 60)
	add_constant_override("margin_right", 60)
	add_constant_override("margin_top", 16)
	add_constant_override("margin_bottom", 12)

	var hb = HBoxContainer.new()
	hb.add_constant_override("separation", 28)
	add_child(hb)

	# ---- left column: sliders
	var left = VBoxContainer.new()
	left.rect_min_size = Vector2(430, 0)
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_constant_override("separation", 8)
	hb.add_child(left)

	left.add_child(_label("Note Builder", font_title, TEXT))
	var hint = _label("Shape your own note. It is saved automatically; press \"Use this note\" to play with it.", font_regular, DIM)
	hint.autowrap = true
	left.add_child(hint)

	for spec in SLIDERS:
		if spec.size() == 1:
			var sec = _label(spec[0], font_bold, ACCENT)
			sec.rect_min_size = Vector2(0, 30)
			sec.valign = Label.VALIGN_BOTTOM
			left.add_child(sec)
			var sep = HSeparator.new()
			left.add_child(sep)
			continue
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 12)
		var l = _label(spec[1])
		l.rect_min_size = Vector2(150, 28)
		row.add_child(l)
		var s = HSlider.new()
		s.min_value = spec[2]
		s.max_value = spec[3]
		s.step = spec[4]
		s.size_flags_horizontal = SIZE_EXPAND_FILL
		s.size_flags_vertical = SIZE_SHRINK_CENTER
		s.rect_min_size = Vector2(160, 20)
		s.focus_mode = FOCUS_NONE
		_style_slider(s)
		s.connect("value_changed", self, "_on_slider", [spec[0]])
		row.add_child(s)
		var v = _label("", font_bold, TEXT)
		v.rect_min_size = Vector2(56, 0)
		v.align = Label.ALIGN_RIGHT
		row.add_child(v)
		left.add_child(row)
		sliders[spec[0]] = s
		value_labels[spec[0]] = [v, spec[5]]

	left.add_child(_label("Presets", font_bold, ACCENT))
	var prow = HBoxContainer.new()
	prow.add_constant_override("separation", 6)
	for pr in PRESETS:
		prow.add_child(_button(pr[0], "_apply_preset", [pr[1]]))
	left.add_child(prow)

	var brow = HBoxContainer.new()
	brow.add_constant_override("separation", 8)
	use_btn = _button("Use this note", "_use_note")
	use_btn.rect_min_size = Vector2(150, 34)
	brow.add_child(use_btn)
	brow.add_child(_button("Reset", "_apply_preset", [NBMesh.DEFAULTS]))
	brow.add_child(_button("Open folder", "_open_folder"))
	left.add_child(brow)
	status = _label("", font_regular, ACCENT)
	status.autowrap = true
	left.add_child(status)

	# ---- right column: preview
	var right = VBoxContainer.new()
	right.add_constant_override("separation", 6)
	hb.add_child(right)
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", _flat(Color(0.07, 0.065, 0.09, 1), 10, Color(0.764706, 0.65098, 0.8, 0.35), 2))
	panel.rect_min_size = Vector2(440, 380)
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(panel)
	var vpc = ViewportContainer.new()
	vpc.stretch = true
	vpc.rect_min_size = Vector2(430, 370)
	vpc.mouse_filter = MOUSE_FILTER_STOP
	vpc.connect("gui_input", self, "_on_preview_input")
	panel.add_child(vpc)
	_build_preview(vpc)

	var under = HBoxContainer.new()
	wire_check = CheckBox.new()
	wire_check.text = "Wireframe"
	wire_check.pressed = true
	wire_check.add_font_override("font", font_regular)
	wire_check.connect("toggled", self, "_on_wire_toggled")
	under.add_child(wire_check)
	var spacer = Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	under.add_child(spacer)
	stats_label = _label("", font_regular, DIM)
	under.add_child(stats_label)
	right.add_child(under)
	right.add_child(_label("Drag the preview to rotate it", font_regular, DIM))

	_apply_params_to_ui()
	if Rhythia.has_signal("selected_mesh_changed"):
		Rhythia.connect("selected_mesh_changed", self, "_on_mesh_changed")
	if Rhythia.has_signal("selected_colorset_changed"):
		Rhythia.connect("selected_colorset_changed", self, "_on_colorset_changed")
	_rebuild()
	# make sure the registered mesh file exists so selecting it always works
	var f = File.new()
	if not f.file_exists(NBMesh.obj_path()):
		NBMesh.save(params)
	_update_status()

func _build_preview(vpc: ViewportContainer) -> void:
	vp = Viewport.new()
	vp.size = Vector2(430, 370)
	vp.own_world = true
	vp.transparent_bg = true
	vp.msaa = Viewport.MSAA_4X
	vp.render_target_update_mode = Viewport.UPDATE_WHEN_VISIBLE
	vp.world = World.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.62)
	env.ambient_light_energy = 0.25
	vp.world.environment = env
	vpc.add_child(vp)

	var cam = Camera.new()
	cam.fov = 35
	cam.translation = Vector3(0, 0, 5.4)
	cam.current = true
	vp.add_child(cam)

	var key = DirectionalLight.new()
	key.light_energy = 0.75
	key.rotation_degrees = Vector3(-35, -40, 0)
	vp.add_child(key)
	var fill = DirectionalLight.new()
	fill.light_energy = 0.3
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.rotation_degrees = Vector3(20, 150, 0)
	vp.add_child(fill)
	var rim = OmniLight.new()
	rim.translation = Vector3(-2.5, 2.0, 2.5)
	rim.omni_range = 8
	rim.light_energy = 0.4
	rim.light_color = ACCENT
	vp.add_child(rim)

	pivot = Spatial.new()
	vp.add_child(pivot)
	surface_mat = SpatialMaterial.new()
	surface_mat.roughness = 0.4
	surface_mat.metallic_specular = 0.6
	mesh_inst = MeshInstance.new()
	pivot.add_child(mesh_inst)

	wire_mat = SpatialMaterial.new()
	wire_mat.flags_unshaded = true
	wire_mat.flags_transparent = true
	wire_inst = MeshInstance.new()
	wire_inst.scale = Vector3.ONE * 1.003
	pivot.add_child(wire_inst)
	_on_colorset_changed(null)
	_apply_rotation()

func _apply_rotation() -> void:
	if pivot:
		pivot.transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

# --------------------------------------------------------------------- events

func _apply_params_to_ui() -> void:
	_setting_ui = true
	for k in sliders.keys():
		sliders[k].value = params.get(k, NBMesh.DEFAULTS[k])
		_update_value_label(k)
	_setting_ui = false

func _update_value_label(k: String) -> void:
	var v = value_labels[k]
	var val = params.get(k, 0)
	if k == "corners":
		v[0].text = str(int(val))
	elif v[1]:
		v[0].text = "%d%%" % int(round(val * 100.0))
	else:
		v[0].text = "%.2f" % val

func _on_slider(value: float, key: String) -> void:
	if _setting_ui:
		return
	params[key] = int(value) if key == "corners" else value
	_update_value_label(key)
	_changed()

func _apply_preset(p: Dictionary) -> void:
	params = NBMesh.sanitize(p)
	_apply_params_to_ui()
	_changed()

func _changed() -> void:
	_dirty = true
	_save_timer = 0.6
	if status:
		status.text = "Saving..."

func _process(delta):
	if _dirty:
		_dirty = false
		_rebuild()
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_now()
	if pivot and not _dragging and is_visible_in_tree():
		_idle_t += delta
		if _idle_t > 1.5:
			_yaw += delta * 0.45
			_apply_rotation()

func _on_preview_input(ev) -> void:
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		_dragging = ev.pressed
		_idle_t = 0.0
	elif ev is InputEventMouseMotion and _dragging:
		_yaw += ev.relative.x * 0.01
		_pitch = clamp(_pitch + ev.relative.y * 0.01, -1.4, 1.4)
		_idle_t = 0.0
		_apply_rotation()

func _on_wire_toggled(on: bool) -> void:
	if wire_inst:
		wire_inst.visible = on

func _on_colorset_changed(_c) -> void:
	if surface_mat == null:
		return
	var col = Color(1, 1, 1)
	var cs = Rhythia.selected_colorset
	if cs != null and "real_colors" in cs and cs.real_colors.size() > 0 and cs.real_colors[0] is Color:
		col = cs.real_colors[0]
	surface_mat.albedo_color = col
	if wire_mat:
		var lum = col.r * 0.3 + col.g * 0.59 + col.b * 0.11
		wire_mat.albedo_color = Color(0.05, 0.04, 0.1, 0.55) if lum > 0.45 else Color(1, 1, 1, 0.45)

func _on_mesh_changed(_m) -> void:
	_update_status()

func _rebuild() -> void:
	if mesh_inst == null:
		return
	var data = NBMesh.build(params)
	var m = NBMesh.to_array_mesh(data)
	if m.get_surface_count() > 0:
		m.surface_set_material(0, surface_mat)
	mesh_inst.mesh = m
	var w = NBMesh.to_wire_mesh(data)
	if w.get_surface_count() > 0:
		w.surface_set_material(0, wire_mat)
	wire_inst.mesh = w
	if stats_label:
		stats_label.text = "%d verts, %d tris" % [data.verts.size(), data.tris.size() / 3]

func _save_now() -> bool:
	_save_timer = -1.0
	var err = NBMesh.save(params)
	if err != OK:
		if status: status.text = "Couldn't save the note (error %d)" % err
		return false
	_update_status()
	return true

func _is_selected() -> bool:
	return Rhythia.selected_mesh != null and Rhythia.selected_mesh.id == NBMesh.MESH_ID

func _update_status() -> void:
	if status == null:
		return
	if _save_timer > 0.0:
		return
	if _is_selected():
		status.text = "Saved. This note is in use."
	else:
		status.text = "Saved. Press \"Use this note\" to play with it."
	if use_btn:
		use_btn.disabled = _is_selected()

func _use_note() -> void:
	if not _save_now():
		return
	var item = Rhythia.registry_mesh.get_item(NBMesh.MESH_ID)
	if item == null:
		NBMesh.register(Rhythia.registry_mesh)
		item = Rhythia.registry_mesh.get_item(NBMesh.MESH_ID)
	if item == null:
		status.text = "Couldn't register the note"
		return
	Rhythia.select_mesh(item)
	Rhythia.save_settings()
	_update_status()

func _open_folder() -> void:
	var d = Directory.new()
	if not d.dir_exists(NBMesh.dir_path()):
		d.make_dir_recursive(NBMesh.dir_path())
	OS.shell_open(ProjectSettings.globalize_path(NBMesh.dir_path()))

func _exit_tree():
	# don't lose the last change if the menu closes before the debounce fires
	if _save_timer > 0.0:
		NBMesh.save(params)
		_save_timer = -1.0
