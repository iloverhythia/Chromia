extends VBoxContainer

# Settings > Skins: Chromia skins (.cskin, scripts/Skin.gd). Export everything
# you have on into one file, import someone's, or put on one you saved. Putting
# one on keeps your look as "Before <skin>" in the list first.

const Skin = preload("res://scripts/Skin.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const GOOD := Color(0.6, 1, 0.7)
const BAD := Color(1, 0.55, 0.55)

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var box: VBoxContainer
var _name_in: LineEdit
var _export_status: Label
var _import_status: Label
var _preview_box: VBoxContainer
var _preview_l: Label
var _list_box: VBoxContainer
var _pending = null # a read skin waiting for "Put it on"

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Skins"):
		return
	var t = load("res://scripts/ui/settings/SkinsTab.gd").new()
	t.name = "Skins"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Fonts")
	if after == null:
		after = tab_container.get_node_or_null("Background Editor")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

# a .cskin dropped on the game window: shown in the Skins tab
static func import_dropped(tree: SceneTree, path: String) -> bool:
	for n in tree.get_nodes_in_group("skins_tab"):
		n.show_skin_file(path)
		var tc = n.get_parent()
		if tc is TabContainer:
			tc.current_tab = n.get_index()
		return true
	return false

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	add_to_group("skins_tab")
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	var m = MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	_label("Chromia skins (.cskin)", f_title, ACCENT)
	_label("A skin is everything you have on in one file: your look settings (notes, cursor, trail, grid, HUD, camera, colours, fonts, panels, avatar, VR hands), what you have equipped (colorset, note mesh, border, hit and miss sounds, space, effects) and your custom files (cursor and trail pictures, sounds, backgrounds and Background Editor layers, HUD font and panel picture). Your device settings (window, sensitivity, volume, offset) and the hit window stay yours.", f_body, DIM, true)

	box.add_child(HSeparator.new())
	_label("Export what you have on", f_title, ACCENT)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	box.add_child(h)
	_name_in = LineEdit.new()
	_name_in.theme = load("res://uitheme.tres")
	_name_in.add_font_override("font", f_bold)
	_name_in.placeholder_text = "Skin name"
	_name_in.text = _default_name()
	_name_in.rect_min_size = Vector2(280, 40)
	h.add_child(_name_in)
	_button(h, "Export skin...", "_export")
	_button(h, "Save to My skins", "_save_mine")
	_export_status = _label("", f_body, TEXT, true)

	box.add_child(HSeparator.new())
	_label("Import a skin", f_title, ACCENT)
	_label("Pick a .cskin file (or drop one on the game window).", f_body, DIM, true)
	var h2 = HBoxContainer.new()
	h2.add_constant_override("separation", 10)
	box.add_child(h2)
	_button(h2, "Import skin...", "_import")
	_import_status = _label("", f_body, TEXT, true)
	_preview_box = VBoxContainer.new()
	_preview_box.add_constant_override("separation", 6)
	_preview_box.visible = false
	box.add_child(_preview_box)
	_preview_l = _label("", f_body, TEXT, true, _preview_box)
	var h3 = HBoxContainer.new()
	h3.add_constant_override("separation", 10)
	_preview_box.add_child(h3)
	_button(h3, "Put it on", "_put_on")
	_button(h3, "Save to My skins", "_keep_pending")
	_button(h3, "Cancel", "_cancel")

	box.add_child(HSeparator.new())
	var h4 = HBoxContainer.new()
	h4.add_constant_override("separation", 10)
	box.add_child(h4)
	var t = _label("My skins", f_title, ACCENT, false, h4)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	_button(h4, "Open folder", "_open_folder")
	_list_box = VBoxContainer.new()
	_list_box.add_constant_override("separation", 4)
	box.add_child(_list_box)
	connect("visibility_changed", self, "_refresh_list")
	_refresh_list()

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l = Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String, binds: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(150, 40)
	b.size_flags_horizontal = 0
	b.connect("pressed", self, method, binds)
	parent.add_child(b)
	return b

func _say(l: Label, text: String, col: Color = TEXT):
	l.text = text
	l.add_color_override("font_color", col)

func _default_name() -> String:
	var n: String = Skin.author_name()
	return ("%s's skin" % n) if n != "" else "My skin"

func _skin_name() -> String:
	var n := _name_in.text.strip_edges()
	return n if n != "" else _default_name()

func _skins_dir() -> String:
	var p: String = Globals.p(Skin.SKINS_DIR)
	Directory.new().make_dir_recursive(p)
	return p

# --- Export -------------------------------------------------------------------
func _export():
	if Globals.file_sel == null:
		_say(_export_status, "The file picker isn't available here: use Save to My skins.", BAD)
		return
	var file_name: String = Skin._clean_name(_skin_name() + "." + Skin.EXT, "skin." + Skin.EXT)
	Globals.file_sel.save_file(self, "_export_picked", PoolStringArray(["*.cskin ; Chromia skin"]), OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).plus_file(file_name))

func _export_picked(path):
	path = String(path)
	if path == "":
		return
	if path.get_extension().to_lower() != Skin.EXT:
		path += "." + Skin.EXT
	_write_skin(path)

func _save_mine():
	_write_skin(_skins_dir().plus_file(Skin._clean_name(_skin_name() + "." + Skin.EXT, "skin." + Skin.EXT)))

func _write_skin(path: String):
	_say(_export_status, "Packing your skin...")
	yield(get_tree(), "idle_frame")
	var r: Dictionary = Skin.save_to(path, _skin_name())
	if r.has("error"):
		_say(_export_status, String(r.error), BAD)
		return
	_say(_export_status, "Saved %s (%s): %s." % [path.get_file(), load("res://scripts/SettingsTransfer.gd").human_size(r.bytes.size()), PoolStringArray(r.parts).join(", ")], GOOD)
	_refresh_list()

# --- Import -------------------------------------------------------------------
func _import():
	if Globals.file_sel == null:
		_say(_import_status, "The file picker isn't available here: drop the .cskin on the game window.", BAD)
		return
	Globals.file_sel.open_file(self, "_import_picked", PoolStringArray(["*.cskin ; Chromia skin"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _import_picked(files):
	var path := ""
	if files is String:
		path = files
	elif (files is PoolStringArray or files is Array) and files.size() > 0:
		path = String(files[0])
	if path != "":
		show_skin_file(path)

func show_skin_file(path: String):
	var r: Dictionary = Skin.read_file(path)
	if r.has("error"):
		_pending = null
		_preview_box.visible = false
		_say(_import_status, String(r.error), BAD)
		return
	_pending = r.data
	_pending["_path"] = path
	_say(_import_status, "")
	var by := (" by " + String(_pending.author)) if String(_pending.author) != "" else ""
	_preview_l.text = "%s%s\nHas: %s.\nPutting it on keeps your look as \"Before %s\" in My skins first, so you can go back." % [_pending.name, by, Skin.describe(_pending), _pending.name]
	_preview_box.visible = true

func _cancel():
	_pending = null
	_preview_box.visible = false

func _keep_pending():
	if _pending == null:
		return
	var src: String = String(_pending.get("_path", ""))
	var dst: String = _skins_dir().plus_file(Skin._clean_name(String(_pending.name) + "." + Skin.EXT, "skin." + Skin.EXT))
	if src.get_base_dir() == dst.get_base_dir():
		_say(_import_status, "It's already in My skins.", GOOD)
	elif Directory.new().copy(src, dst) == OK:
		_say(_import_status, "Saved to My skins.", GOOD)
		_refresh_list()
	else:
		_say(_import_status, "Couldn't save it.", BAD)

func _put_on():
	if _pending == null:
		return
	var d: Dictionary = _pending
	_pending = null
	_preview_box.visible = false
	_say(_import_status, "Putting on %s..." % d.name)
	yield(get_tree(), "idle_frame")
	var r: Dictionary = Skin.apply(d)
	if r.has("error"):
		_say(_import_status, String(r.error), BAD)
		return
	Rhythia.trail("skin: put on %s (%d files)" % [d.name, r.written])
	# like Reload Content: everything is read again from the files, so the
	# skin's colorset, border, sounds... are in the lists (loading the settings
	# here instead let the old menu's boxes write their values back over it)
	var menu = Rhythia.menu_node()
	if menu != null and "black_fade_target" in menu:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	Rhythia.is_init = true
	get_tree().change_scene("res://scenes/init.tscn")

# --- My skins -----------------------------------------------------------------
func _refresh_list():
	if _list_box == null or not is_visible_in_tree():
		return
	for c in _list_box.get_children():
		c.queue_free()
	var names := []
	var d := Directory.new()
	if d.open(_skins_dir()) == OK:
		d.list_dir_begin(true, true)
		var n := d.get_next()
		while n != "":
			if not d.current_is_dir() and n.get_extension().to_lower() == Skin.EXT:
				names.append(n)
			n = d.get_next()
		d.list_dir_end()
	names.sort()
	if names.empty():
		_label("None yet. Skins you save or put on are kept here.", f_body, DIM, true, _list_box)
		return
	for n in names:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 10)
		_list_box.add_child(row)
		_label(String(n).get_basename(), f_body, TEXT, false, row)
		_button(row, "Put on...", "show_skin_file", [_skins_dir().plus_file(n)])
		_button(row, "Delete", "_delete", [_skins_dir().plus_file(n)])

func _delete(path: String):
	Directory.new().remove(path)
	_refresh_list()

func _open_folder():
	OS.shell_open(ProjectSettings.globalize_path(_skins_dir()))
