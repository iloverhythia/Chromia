extends VBoxContainer

# Colorset maker: pick colors, name the set, save it. Saved sets are plain text
# files in user://colorsets (one color per line, "m" = mirror), the same format
# the game already loads custom colorsets from.

const COLORS_PER_ROW = 16 # no limit on colors; they wrap into rows

var font: Font
var name_edit: LineEdit
var colors_box: GridContainer
var mirror_box: CheckBox
var status: Label
var pickers: Array = []

func _label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	l.valign = Label.VALIGN_CENTER
	if font: l.add_font_override("font", font)
	l.add_color_override("font_color", Color(0.898039, 0.94902, 1, 1))
	return l

func _button(text: String, method: String, args: Array = []) -> Button:
	var b = Button.new()
	b.text = text
	b.rect_min_size = Vector2(40 if text.length() <= 1 else 0, 32)
	b.connect("pressed", self, method, args)
	return b

func _ready():
	font = $Title.get("custom_fonts/font")
	$Title.text = "Colorset Maker"

	var row1 = HBoxContainer.new()
	row1.add_child(_label("Name"))
	name_edit = LineEdit.new()
	name_edit.rect_min_size = Vector2(260, 32)
	name_edit.placeholder_text = "My Colorset"
	row1.add_child(name_edit)
	mirror_box = CheckBox.new()
	mirror_box.text = "Mirror (play colors back and forth)"
	if font: mirror_box.add_font_override("font", font)
	row1.add_child(mirror_box)
	add_child(row1)

	var row2 = HBoxContainer.new()
	row2.add_child(_label("Colors"))
	colors_box = GridContainer.new()
	colors_box.columns = COLORS_PER_ROW
	row2.add_child(colors_box)
	row2.add_child(_button("+", "_add_color", [Color(1, 1, 1)]))
	row2.add_child(_button("-", "_remove_color"))
	add_child(row2)

	var row3 = HBoxContainer.new()
	row3.add_child(_button("Copy selected colorset", "_copy_selected"))
	row3.add_child(_button("Save colorset", "_save"))
	row3.add_child(_button("Open colorsets folder", "_open_folder"))
	status = _label("")
	row3.add_child(status)
	add_child(row3)

	_copy_selected()
	name_edit.text = ""

func _add_color(c: Color = Color(1, 1, 1)):
	var p = ColorPickerButton.new()
	p.color = c
	p.edit_alpha = false
	p.rect_min_size = Vector2(48, 32)
	colors_box.add_child(p)
	pickers.append(p)

func _remove_color():
	if pickers.size() <= 1:
		return
	var p = pickers.pop_back()
	p.queue_free()

func _set_colors(cols: Array):
	for p in pickers:
		p.queue_free()
	pickers.clear()
	for c in cols:
		_add_color(c)
	if pickers.empty():
		_add_color()

func _copy_selected():
	var set = Rhythia.selected_colorset
	if set == null: return
	_set_colors(set.real_colors)
	mirror_box.pressed = set.mirror
	name_edit.text = set.name + " (copy)"

func _safe_name(n: String) -> String:
	var out := ""
	for i in n.length():
		var ch := n[i]
		if "\\/:*?\"<>|".find(ch) == -1:
			out += ch
	return out.strip_edges()

func _save():
	var n := _safe_name(name_edit.text)
	if n == "":
		status.text = "Give it a name first"
		return
	var dir = Directory.new()
	if not dir.dir_exists(Rhythia.user_colorset_dir):
		dir.make_dir_recursive(Rhythia.user_colorset_dir)
	var path: String = Rhythia.user_colorset_dir.plus_file(n + ".txt")
	var f = File.new()
	if f.open(path, File.WRITE) != OK:
		status.text = "Couldn't save the file"
		return
	for p in pickers:
		f.store_line("#" + p.color.to_html(false))
	if mirror_box.pressed:
		f.store_line("m")
	f.close()

	# Same id scheme the game uses when it loads the colorsets folder.
	var id: String = "custom_" + path.get_file().to_lower().md5_text()
	var existed: bool = Rhythia.registry_colorset.idx_id.has(id)
	Rhythia.load_color_txt(path, id)
	var set = Rhythia.registry_colorset.get_item(id)
	var grid = get_node_or_null("../ColorSet2/ColorSet")
	if grid and not existed and grid.has_method("add_set"):
		grid.add_set(set)
	elif grid and grid.has_method("refresh_set"):
		grid.refresh_set(set)
	Rhythia.select_colorset(set)
	status.text = ("Updated \"%s\"" if existed else "Saved \"%s\" and selected it") % n

func _open_folder():
	var dir = Directory.new()
	if not dir.dir_exists(Rhythia.user_colorset_dir):
		dir.make_dir_recursive(Rhythia.user_colorset_dir)
	OS.shell_open(ProjectSettings.globalize_path(Rhythia.user_colorset_dir))
