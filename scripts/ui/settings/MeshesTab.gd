extends MarginContainer
# "Meshes" settings tab: every note mesh as a 3D picture in a grid. Click one
# to use it, star favorites, search, import .obj files, and "Build" opens the
# Note Builder (scripts/ui/settings/NoteBuilder.gd) inside this tab.
#
# The pictures are rendered one at a time with a single offscreen viewport and
# saved to user://caches/mesh_thumbs, so after the first time the grid is just
# images (no live 3D views, no FPS cost).

const ObjParse = preload("res://scripts/content/resources/ObjParse.gd")
const FavoriteStar = preload("res://scripts/ui/settings/FavoriteStar.gd")
const NBMesh = preload("res://scripts/ui/settings/NoteBuilderMesh.gd")

const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const DIM = Color(0.62, 0.6, 0.68, 1)
const CARD_BG = Color(0.11, 0.105, 0.14, 1)
const CARD_HOVER = Color(0.15, 0.14, 0.19, 1)
const CARD_SEL = Color(0.17, 0.145, 0.21, 1)

const CARD_W = 176
const CARD_H = 196
const THUMB_PX = 256
const THUMB_VERSION = 2
const THUMB_DIR = "user://caches/mesh_thumbs"
const MEM_KEY = "chromia_mesh_thumbs"

var font_regular: DynamicFont
var font_bold: DynamicFont
var font_title: DynamicFont
var font_small: DynamicFont
var _rename_popup: PopupPanel
var _rename_edit: LineEdit
var _rename_id := ""
var _meshes_dirty := false

var title: Label
var import_btn: Button
var browser: VBoxContainer
var builder_box: MarginContainer
var builder = null
var search: LineEdit
var all_btn: Button
var builder_btn: Button
var status: Label
var grid: GridContainer

var cards := {}          # mesh id -> {panel, tex, name, star, mesh}
var _hover_id := ""

# thumbnail renderer
var _rvp: Viewport
var _rpivot: Spatial
var _rmesh: MeshInstance
var _queue := []         # mesh ids waiting for a picture
var _render_id := ""     # mesh being rendered
var _render_key := ""
var _render_wait := 0    # frames left before reading the picture back

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container):
		return
	if tab_container.has_node("Meshes"):
		return
	var tab = load("res://scripts/ui/settings/MeshesTab.gd").new()
	tab.name = "Meshes"
	tab_container.add_child(tab)
	var notes = tab_container.get_node_or_null("Notes")
	if notes != null:
		tab_container.move_child(tab, notes.get_index() + 1)
		# the old mesh dropdown is replaced by this tab
		var old = notes.get_node_or_null("Notes/Group/H/Mesh")
		if old != null:
			old.visible = false

# ------------------------------------------------------------------ helpers

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _flat(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

func _button(text: String, method: String) -> Button:
	var b = Button.new()
	b.text = text
	b.rect_min_size = Vector2(110, 34)
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", font_bold)
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, method)
	return b

func _thumbs_mem() -> Dictionary:
	var root = Engine.get_main_loop().root
	if not root.has_meta(MEM_KEY):
		root.set_meta(MEM_KEY, {})
	return root.get_meta(MEM_KEY)

# ------------------------------------------------------------------ build

func _ready():
	font_regular = _font("res://assets/font/Lato/Lato-Regular.ttf", 16)
	font_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 16)
	font_title = _font("res://assets/font/Lato/Lato-Black.ttf", 22)
	font_small = _font("res://assets/font/Lato/Lato-Bold.ttf", 13)

	add_constant_override("margin_left", 40)
	add_constant_override("margin_right", 40)
	add_constant_override("margin_top", 14)
	add_constant_override("margin_bottom", 10)

	var root = VBoxContainer.new()
	root.add_constant_override("separation", 10)
	add_child(root)

	var top = HBoxContainer.new()
	top.add_constant_override("separation", 10)
	root.add_child(top)
	title = Label.new()
	title.text = "Meshes"
	title.add_font_override("font", font_title)
	title.add_color_override("font_color", TEXT)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	import_btn = _button("Import", "_on_import")
	import_btn.hint_tooltip = "Add .obj meshes"
	top.add_child(import_btn)

	search = LineEdit.new()
	search.placeholder_text = "Search meshes"
	search.rect_min_size = Vector2(0, 36)
	search.add_font_override("font", font_regular)
	search.add_stylebox_override("normal", _content(_flat(Color(0.13, 0.125, 0.165, 1), 8)))
	search.add_stylebox_override("focus", _content(_flat(Color(0.13, 0.125, 0.165, 1), 8, LILAC, 1)))
	search.add_color_override("font_color", TEXT)
	search.connect("text_changed", self, "_on_search")
	root.add_child(search)

	# tabs: all meshes (favorites first) / the Mesh Builder
	var tabs = HBoxContainer.new()
	tabs.add_constant_override("separation", 8)
	root.add_child(tabs)
	all_btn = _filter_button("_show_builder", false)
	tabs.add_child(all_btn)
	builder_btn = _filter_button("_show_builder", true)
	builder_btn.text = "Mesh Builder"
	builder_btn.hint_tooltip = "Shape your own note"
	tabs.add_child(builder_btn)

	# ---- browser
	browser = VBoxContainer.new()
	browser.size_flags_vertical = SIZE_EXPAND_FILL
	browser.add_constant_override("separation", 10)
	root.add_child(browser)

	status = Label.new()
	status.add_font_override("font", font_regular)
	status.add_color_override("font_color", DIM)
	status.autowrap = true
	status.visible = false
	browser.add_child(status)

	# no scroll box of its own: the settings page scrolls, like the other tabs
	grid = GridContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 12)
	grid.add_constant_override("vseparation", 12)
	browser.add_child(grid)
	browser.connect("resized", self, "_relayout")

	# ---- builder (made when first opened)
	builder_box = MarginContainer.new()
	builder_box.size_flags_vertical = SIZE_EXPAND_FILL
	builder_box.visible = false
	root.add_child(builder_box)

	# the builder writes its note file when it first opens; until then the
	# "Custom (Note Builder)" card had no picture and played as the default note
	if not File.new().file_exists(NBMesh.obj_path()):
		NBMesh.save(NBMesh.load_params())

	_build_renderer()
	_rebuild_cards()
	Rhythia.connect("selected_mesh_changed", self, "_on_mesh_changed")
	connect("visibility_changed", self, "_on_visibility")

func _content(sb: StyleBoxFlat) -> StyleBoxFlat:
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb

func _filter_button(method: String, favs: bool) -> Button:
	var b = Button.new()
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.rect_min_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", font_bold)
	b.add_color_override("font_color", DIM)
	b.add_color_override("font_color_hover", TEXT)
	b.add_color_override("font_color_pressed", TEXT)
	b.add_stylebox_override("normal", _flat(Color(0.1, 0.095, 0.125, 1), 8))
	b.add_stylebox_override("hover", _flat(Color(0.14, 0.13, 0.18, 1), 8))
	b.add_stylebox_override("pressed", _flat(Color(0.2, 0.17, 0.25, 1), 8, LILAC, 1))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.toggle_mode = true
	b.connect("pressed", self, method, [favs])
	return b

func _build_renderer():
	_rvp = Viewport.new()
	_rvp.size = Vector2(THUMB_PX, THUMB_PX)
	_rvp.own_world = true
	_rvp.world = World.new()
	_rvp.transparent_bg = true
	_rvp.hdr = false
	_rvp.msaa = Viewport.MSAA_4X
	_rvp.render_target_v_flip = true
	_rvp.render_target_update_mode = Viewport.UPDATE_DISABLED
	var env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	_rvp.world.environment = env
	add_child(_rvp)

	var cam = Camera.new()
	cam.fov = 40
	cam.translation = Vector3(0, 0, 4.2)
	cam.current = true
	_rvp.add_child(cam)
	var key = DirectionalLight.new()
	key.light_energy = 0.75
	key.rotation_degrees = Vector3(-30, -35, 0)
	_rvp.add_child(key)
	var rim = DirectionalLight.new()
	rim.light_energy = 0.25
	rim.light_color = ACCENT
	rim.rotation_degrees = Vector3(25, 150, 0)
	_rvp.add_child(rim)

	_rpivot = Spatial.new()
	# looking at the note a little from above and the side, like a note flying in
	_rpivot.transform.basis = Basis(Vector3.UP, deg2rad(-24)) * Basis(Vector3.RIGHT, deg2rad(26))
	_rvp.add_child(_rpivot)
	_rmesh = MeshInstance.new()
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(0.95, 0.95, 0.97)
	mat.roughness = 0.55
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_rmesh.material_override = mat
	_rpivot.add_child(_rmesh)

# ------------------------------------------------------------------ cards

func _sorted_meshes() -> Array:
	var arr = []
	if Rhythia.registry_mesh != null:
		for m in Rhythia.registry_mesh.get_items():
			if m != null:
				arr.append(m)
	arr.sort_custom(self, "_by_name")
	return arr

# starred meshes first, then everything else; both by name
func _by_name(a, b) -> bool:
	var fa = Rhythia.favorite_meshes.has(String(a.id))
	var fb = Rhythia.favorite_meshes.has(String(b.id))
	if fa != fb:
		return fa
	return String(a.name).to_lower() < String(b.name).to_lower()

func _reorder():
	var i = 0
	for m in _sorted_meshes():
		if cards.has(m.id) and is_instance_valid(cards[m.id].panel):
			grid.move_child(cards[m.id].panel, i)
			i += 1

func _rebuild_cards():
	for c in grid.get_children():
		c.queue_free()
	cards.clear()
	for m in _sorted_meshes():
		_make_card(m)
	_apply_filter()
	_relayout()
	_update_styles()

func _make_card(m):
	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(CARD_W, CARD_H)
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.hint_tooltip = "%s\nby %s" % [m.name, m.creator]
	panel.connect("gui_input", self, "_on_card_input", [m.id])
	panel.connect("mouse_entered", self, "_on_card_hover", [m.id, true])
	panel.connect("mouse_exited", self, "_on_card_hover", [m.id, false])
	grid.add_child(panel)

	var wrap = Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(wrap)

	var v = VBoxContainer.new()
	v.anchor_right = 1
	v.anchor_bottom = 1
	v.margin_top = 6
	v.margin_bottom = -10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(v)

	var tex = TextureRect.new()
	tex.expand = true
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size_flags_vertical = SIZE_EXPAND_FILL
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tex)

	var name_l = Label.new()
	name_l.text = m.name
	name_l.align = Label.ALIGN_CENTER
	name_l.clip_text = true
	name_l.add_font_override("font", font_bold)
	name_l.add_color_override("font_color", TEXT)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)

	var star = FavoriteStar.new()
	star.rect_min_size = Vector2(24, 24)
	star.anchor_left = 1
	star.anchor_right = 1
	star.margin_left = -30
	star.margin_right = -6
	star.margin_top = 6
	star.margin_bottom = 30
	star.fav = Rhythia.favorite_meshes.has(String(m.id))
	star.connect("pressed", self, "_on_star", [m.id])
	wrap.add_child(star)

	# Edit: builder meshes open in the Mesh Builder, others get renamed
	var edit = Button.new()
	edit.text = "Edit" if NBMesh.slot_of(String(m.id)) != null else "Rename"
	edit.focus_mode = Control.FOCUS_NONE
	edit.flat = true
	edit.add_font_override("font", font_small)
	edit.add_color_override("font_color", DIM)
	edit.add_color_override("font_color_hover", ACCENT)
	edit.margin_left = 6
	edit.margin_top = 4
	edit.hint_tooltip = "Edit this mesh in the Mesh Builder" if edit.text == "Edit" else "Change this mesh's name"
	edit.connect("pressed", self, "_on_edit", [m.id])
	wrap.add_child(edit)

	cards[m.id] = {"panel": panel, "tex": tex, "name": name_l, "star": star, "mesh": m}
	panel.connect("resized", self, "_fit_name", [m.id])
	# "resized" doesn't fire for a card the grid gives exactly its minimum width
	call_deferred("_fit_name", m.id)
	_request_thumb(m)

# Long names end in "..." instead of being cut off on both sides.
func _fit_name(id):
	if not cards.has(id):
		return
	var c = cards[id]
	if not is_instance_valid(c.name):
		return
	var full = String(c.mesh.name)
	var avail = c.panel.rect_size.x - 16
	if avail <= 0 or font_bold.get_string_size(full).x <= avail:
		c.name.text = full
		return
	var lo = 0
	var hi = full.length()
	while lo < hi:
		var mid = (lo + hi + 1) / 2
		if font_bold.get_string_size(full.substr(0, mid).strip_edges() + "…").x <= avail:
			lo = mid
		else:
			hi = mid - 1
	c.name.text = full.substr(0, lo).strip_edges() + "…"

func _update_styles():
	var sel_id = Rhythia.selected_mesh.id if Rhythia.selected_mesh != null else ""
	for id in cards:
		var c = cards[id]
		if not is_instance_valid(c.panel):
			continue
		var sb: StyleBoxFlat
		if id == sel_id:
			sb = _flat(CARD_SEL, 10, LILAC, 2)
		elif id == _hover_id:
			sb = _flat(CARD_HOVER, 10)
		else:
			sb = _flat(CARD_BG, 10)
		c.panel.add_stylebox_override("panel", sb)
		c.name.add_color_override("font_color", ACCENT if id == sel_id else TEXT)

func _apply_filter():
	var q = search.text.strip_edges().to_lower() if search != null else ""
	var total = 0
	for id in cards:
		var c = cards[id]
		total += 1
		c.panel.visible = (q == "" or String(c.mesh.name).to_lower().find(q) != -1)
	all_btn.text = "All (%d)" % total
	all_btn.pressed = not builder_box.visible
	builder_btn.pressed = builder_box.visible

func _relayout():
	if grid == null or browser == null:
		return
	var w = browser.rect_size.x
	grid.columns = int(max(1, floor((w + 12) / (CARD_W + 12))))

# ------------------------------------------------------------------ thumbnails

func _thumb_key(m) -> String:
	var path = String(m.path)
	var extra = ""
	if not path.begins_with("res://"):
		var f = File.new()
		if f.file_exists(path):
			extra = "|%d" % f.get_modified_time(path)
			if f.open(path, File.READ) == OK:
				extra += "|%d" % f.get_len()
				f.close()
	return "%d|%s|%s%s" % [THUMB_VERSION, m.id, path, extra]

func _request_thumb(m):
	var key = _thumb_key(m)
	var mem = _thumbs_mem()
	if mem.has(key):
		_set_thumb(m.id, mem[key])
		return
	if not _queue.has(m.id):
		_queue.append(m.id)

func _set_thumb(id, tex):
	if cards.has(id) and is_instance_valid(cards[id].tex):
		cards[id].tex.texture = tex

func _load_mesh(m) -> Mesh:
	var path = String(m.path)
	if path == "":
		return null
	if path.begins_with("res://"):
		var r = load(path)
		return r if r is Mesh else null
	if not File.new().file_exists(path):
		return null
	return ObjParse.load_obj(path)

func _process(_delta):
	if not is_visible_in_tree():
		return
	if _render_id != "":
		_render_wait -= 1
		if _render_wait <= 0:
			_finish_render()
		return
	# cached pictures from disk: several per frame; a new render: one at a time
	var t0 = OS.get_ticks_usec()
	while not _queue.empty() and OS.get_ticks_usec() - t0 < 4000:
		var id = _queue.pop_front()
		if not cards.has(id):
			continue
		var m = cards[id].mesh
		var key = _thumb_key(m)
		var mem = _thumbs_mem()
		if mem.has(key):
			_set_thumb(id, mem[key])
			continue
		var disk = Globals.p(THUMB_DIR).plus_file(key.md5_text() + ".png")
		if File.new().file_exists(disk):
			var img = Image.new()
			if img.load(disk) == OK:
				var t = ImageTexture.new()
				t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
				mem[key] = t
				_set_thumb(id, t)
				continue
		_start_render(id, m, key)
		return

func _start_render(id, m, key):
	var mesh = _load_mesh(m)
	if mesh == null or mesh.get_surface_count() == 0:
		return # no picture for a broken mesh
	_rmesh.mesh = mesh
	var aabb: AABB = mesh.get_aabb()
	# fit the whole mesh (deep meshes like cubes turn their depth toward the camera)
	var s = min(1.75 / max(max(aabb.size.x, aabb.size.y), 0.001), 2.5 / max(aabb.size.length(), 0.001))
	var center = aabb.position + aabb.size * 0.5
	_rmesh.transform = Transform(Basis().scaled(Vector3(s, s, s)), -center * s)
	_render_id = id
	_render_key = key
	_render_wait = 2
	_rvp.render_target_update_mode = Viewport.UPDATE_ONCE

func _finish_render():
	var id = _render_id
	var key = _render_key
	_render_id = ""
	var img: Image = _rvp.get_texture().get_data()
	_rmesh.mesh = null
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	var d = Directory.new()
	d.make_dir_recursive(Globals.p(THUMB_DIR))
	img.save_png(Globals.p(THUMB_DIR).plus_file(key.md5_text() + ".png"))
	var t = ImageTexture.new()
	t.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	_thumbs_mem()[key] = t
	_set_thumb(id, t)

# ------------------------------------------------------------------ events

func _on_card_input(ev, id):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		var m = Rhythia.registry_mesh.get_item(id)
		if m is NoteMesh: # (the registry returns false, not null, for a missing id)
			Rhythia.select_mesh(m)
			Rhythia.save_settings()

func _on_card_hover(id, inside: bool):
	_hover_id = id if inside else ("" if _hover_id == id else _hover_id)
	_update_styles()

func _on_star(id):
	var sid = String(id)
	if Rhythia.favorite_meshes.has(sid):
		Rhythia.favorite_meshes.erase(sid)
	else:
		Rhythia.favorite_meshes.append(sid)
	if cards.has(id):
		cards[id].star.fav = Rhythia.favorite_meshes.has(sid)
	Rhythia.save_settings()
	_reorder()

func _on_search(_t):
	_apply_filter()


func _on_mesh_changed(_m):
	_update_styles()

func _on_visibility():
	if is_visible_in_tree():
		_relayout()

func _show_builder(on: bool):
	if on == builder_box.visible:
		all_btn.pressed = not on
		builder_btn.pressed = on
		return
	if on:
		_open_builder()
	else:
		_close_builder()
	all_btn.pressed = not on
	builder_btn.pressed = on

func _open_builder():
	if builder == null:
		builder = load("res://scripts/ui/settings/NoteBuilder.gd").new()
		builder.name = "NoteBuilder"
		builder_box.add_child(builder)
		builder.connect("meshes_changed", self, "_on_builder_meshes_changed")
	browser.visible = false
	search.visible = false
	builder_box.visible = true
	import_btn.visible = false

func _close_builder():
	builder_box.visible = false
	browser.visible = true
	search.visible = true
	import_btn.visible = true
	# the builder saves 0.6 s after the last change: save a pending change now,
	# or the picture below is made from the old file
	if builder != null and is_instance_valid(builder) and builder._save_timer > 0.0:
		builder._save_now()
	# meshes may have been added, renamed or deleted: rebuild the grid
	# (pictures of changed meshes are redrawn: they're keyed on the file's time)
	if _meshes_dirty:
		_meshes_dirty = false
		_rebuild_cards()
	else:
		for id in cards:
			if NBMesh.slot_of(String(id)) != null:
				_request_thumb(cards[id].mesh)

func _on_builder_meshes_changed():
	_meshes_dirty = true

func _on_edit(id):
	var sid = String(id)
	var slot = NBMesh.slot_of(sid)
	if slot != null:
		_show_builder(true)
		if builder != null:
			builder.edit_slot(slot)
		return
	var m = Rhythia.registry_mesh.get_item(sid)
	if not (m is NoteMesh):
		return
	if _rename_popup == null:
		_rename_popup = PopupPanel.new()
		_rename_popup.add_stylebox_override("panel", _flat(Color(0.1, 0.095, 0.13, 1), 10, LILAC, 1))
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 8)
		_rename_popup.add_child(h)
		_rename_edit = LineEdit.new()
		_rename_edit.rect_min_size = Vector2(260, 34)
		_rename_edit.add_font_override("font", font_regular)
		_rename_edit.connect("text_entered", self, "_on_rename_done")
		h.add_child(_rename_edit)
		var ok = _button("Save", "_on_rename_done")
		h.add_child(ok)
		add_child(_rename_popup)
	_rename_id = sid
	_rename_edit.text = m.name
	_rename_popup.popup_centered(Vector2(420, 54))
	_rename_edit.grab_focus()
	_rename_edit.select_all()

func _on_rename_done(_t = null):
	var n = _rename_edit.text.strip_edges()
	_rename_popup.hide()
	var m = Rhythia.registry_mesh.get_item(_rename_id)
	if n == "" or not (m is NoteMesh):
		return
	m.name = n
	var names = load_name_overrides()
	names[_rename_id] = n
	var f = File.new()
	if f.open(Globals.p(NAMES_FILE), File.WRITE) == OK:
		f.store_string(to_json(names))
		f.close()
	if cards.has(_rename_id):
		cards[_rename_id].panel.hint_tooltip = "%s\nby %s" % [m.name, m.creator]
		_fit_name(_rename_id)
	_reorder()

# Names you gave meshes (other than builder meshes, which keep their own name).
const NAMES_FILE = "user://mesh_names.json"
static func load_name_overrides() -> Dictionary:
	var f = File.new()
	if f.open(Globals.p(NAMES_FILE), File.READ) == OK:
		var res = JSON.parse(f.get_as_text())
		f.close()
		if res.error == OK and typeof(res.result) == TYPE_DICTIONARY:
			return res.result
	return {}

# Called from Savia.register_meshes().
static func apply_name_overrides(registry) -> void:
	if registry == null:
		return
	var names = load_name_overrides()
	for id in names:
		var m = registry.get_item(String(id))
		if m is NoteMesh and typeof(names[id]) == TYPE_STRING and names[id].strip_edges() != "":
			m.name = names[id]

func _on_import():
	if Globals.file_sel == null:
		_show_status("The file picker isn't available")
		return
	Globals.file_sel.open_file(self, "_on_import_files",
		PoolStringArray(["*.obj ; OBJ meshes"]), true, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _on_import_files(files):
	if not is_inside_tree():
		return
	if typeof(files) == TYPE_STRING:
		files = [files]
	var d = Directory.new()
	d.make_dir_recursive(Rhythia.user_mesh_dir)
	var added = []
	var msgs = []
	for f in files:
		f = String(f)
		if f == "" or f.get_extension().to_lower() != "obj":
			continue
		# lowercase ".obj": the game only loads that extension from the meshes folder
		var dest = Rhythia.user_mesh_dir.plus_file(f.get_file().get_basename() + ".obj")
		# picked from the meshes folder itself: copying a file onto itself empties it
		var same = _same_file(f, dest)
		if not same and d.copy(f, dest) != OK:
			msgs.append("couldn't copy %s" % f.get_file())
			continue
		var mtl = f.get_basename() + ".mtl"
		if not same and File.new().file_exists(mtl):
			d.copy(mtl, dest.get_basename() + ".mtl")
		var test = ObjParse.load_obj(dest)
		if test == null or test.get_surface_count() == 0:
			if not same:
				d.remove(dest)
			msgs.append("%s isn't a mesh the game can read" % f.get_file())
			continue
		var id = "ugc_" + f.get_file().to_lower().replace(" ", "_")
		var item = Rhythia.registry_mesh.get_item(id)
		if not (item is NoteMesh):
			item = NoteMesh.new(id, f.get_file().get_basename() + " (custom)", dest, "You")
			Rhythia.registry_mesh.add_item(item)
		added.append(item)
	if not added.empty():
		_rebuild_cards()
		Rhythia.select_mesh(added[added.size() - 1])
		Rhythia.save_settings()
		msgs.push_front("Imported %d mesh%s" % [added.size(), "" if added.size() == 1 else "es"])
	if not msgs.empty():
		_show_status(PoolStringArray(msgs).join(" · "))

func _same_file(a: String, b: String) -> bool:
	a = ProjectSettings.globalize_path(a).replace("\\", "/").simplify_path()
	b = ProjectSettings.globalize_path(b).replace("\\", "/").simplify_path()
	if OS.has_feature("Windows"):
		return a.to_lower() == b.to_lower()
	return a == b

func _show_status(t: String):
	status.text = t
	status.visible = true
