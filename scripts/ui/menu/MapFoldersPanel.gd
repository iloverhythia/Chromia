extends PopupPanel
# "Map Folders" popup: create / rename / recolor / delete folders, add the
# selected map to them, and pick which folder the map list shows.

const MapFolders = preload("res://scripts/MapFolders.gd")
const UI_THEME = preload("res://uitheme.tres")
const FONT_REGULAR = preload("res://assets/font/Lato/Lato-Regular.ttf")
const FONT_BLACK = preload("res://assets/font/Lato/Lato-Black.ttf")
const FONT_JP = preload("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf")

var store
var rows: VBoxContainer
var scroll: ScrollContainer
var all_btn: Button
var new_name: LineEdit
var sel_label: Label
var empty_label: Label
var _delete_armed: int = -1
var _rebuilding: bool = false

func _font(data, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = data
	f.size = size
	f.use_filter = true
	f.add_fallback(FONT_JP)
	return f

func _ready():
	store = MapFolders.get_store()
	theme = UI_THEME
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.11, 1)
	sb.border_color = Color(0.913725, 0.74902, 0.94902, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	add_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.name = "V"
	v.add_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "Map Folders"
	title.add_font_override("font", _font(FONT_BLACK, 26))
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.rect_min_size = Vector2(70, 30)
	close.connect("pressed", self, "hide")
	head.add_child(close)

	sel_label = Label.new()
	sel_label.add_font_override("font", _font(FONT_REGULAR, 15))
	sel_label.modulate = Color(1, 1, 1, 0.7)
	sel_label.clip_text = true
	v.add_child(sel_label)

	all_btn = Button.new()
	all_btn.toggle_mode = true
	all_btn.rect_min_size = Vector2(0, 32)
	all_btn.hint_tooltip = "Show every map in the list"
	all_btn.connect("pressed", self, "_on_show_all")
	v.add_child(all_btn)

	var sep := HSeparator.new()
	v.add_child(sep)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	v.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_constant_override("separation", 6)
	scroll.add_child(rows)

	empty_label = Label.new()
	empty_label.text = "No folders yet. Name one below and press Create."
	empty_label.add_font_override("font", _font(FONT_REGULAR, 16))
	empty_label.modulate = Color(1, 1, 1, 0.6)
	empty_label.align = Label.ALIGN_CENTER
	empty_label.autowrap = true
	v.add_child(empty_label)

	var create_row := HBoxContainer.new()
	create_row.add_constant_override("separation", 8)
	v.add_child(create_row)
	new_name = LineEdit.new()
	new_name.placeholder_text = "New folder name"
	new_name.size_flags_horizontal = SIZE_EXPAND_FILL
	new_name.connect("text_entered", self, "_on_create")
	create_row.add_child(new_name)
	var create := Button.new()
	create.text = "Create folder"
	create.rect_min_size = Vector2(120, 30)
	create.connect("pressed", self, "_on_create")
	create_row.add_child(create)

	store.connect("changed", self, "_on_store_changed")
	Rhythia.connect("selected_song_changed", self, "_on_selected_changed")
	rebuild()

func open():
	_delete_armed = -1
	rebuild()
	popup()
	_fit()
	# freshly built rows only report their real minimum size a frame later
	call_deferred("_fit")

func _fit():
	# grow with the number of folders, scroll past ~8 of them
	var vp: Vector2 = get_viewport_rect().size
	scroll.rect_min_size.y = clamp(store.folders.size() * 38, 0, min(304, vp.y - 260))
	get_node("V").rect_min_size.x = min(600, vp.x - 72)
	if visible:
		rect_size = Vector2.ZERO # shrink to fit the content
		rect_position = ((vp - get_combined_minimum_size()) / 2).floor()

func _on_store_changed():
	if not _rebuilding and visible: rebuild()

func _on_selected_changed(_s = null):
	if visible: rebuild()

func _selected_id():
	if Rhythia.single_map_mode or Rhythia.selected_song == null: return null
	return Rhythia.selected_song.id

func rebuild():
	_rebuilding = true
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var sel = _selected_id()
	if sel != null:
		sel_label.text = "Selected map: " + Rhythia.selected_song.name
	else:
		sel_label.text = "Select a map to add it to folders."
	all_btn.text = "All maps  (%d)" % Rhythia.registry_song.get_items().size()
	all_btn.pressed = store.active == -1
	empty_label.visible = store.folders.empty()

	for i in store.folders.size():
		var fd: Dictionary = store.folders[i]
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 6)
		rows.add_child(row)

		var cp := ColorPickerButton.new()
		cp.color = fd.color
		cp.edit_alpha = false
		cp.rect_min_size = Vector2(34, 32)
		cp.hint_tooltip = "Folder color"
		cp.connect("color_changed", self, "_on_color_changed", [i])
		cp.connect("popup_closed", self, "_on_color_closed", [i])
		row.add_child(cp)

		var name_edit := LineEdit.new()
		name_edit.text = fd.name
		name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		name_edit.hint_tooltip = "Folder name (press Enter to rename)"
		name_edit.connect("text_entered", self, "_on_rename", [i])
		name_edit.connect("focus_exited", self, "_on_rename_focus", [i, name_edit])
		row.add_child(name_edit)

		var count := Label.new()
		count.text = "%d maps" % fd.maps.size()
		count.rect_min_size = Vector2(66, 0)
		count.align = Label.ALIGN_RIGHT
		count.add_font_override("font", _font(FONT_REGULAR, 15))
		row.add_child(count)

		var view := Button.new()
		view.toggle_mode = true
		view.pressed = store.active == i
		view.text = "Showing" if store.active == i else "Show"
		view.rect_min_size = Vector2(76, 32)
		view.hint_tooltip = "Only show this folder's maps in the map list"
		view.connect("pressed", self, "_on_show", [i])
		row.add_child(view)

		var add := Button.new()
		add.rect_min_size = Vector2(86, 32)
		if sel == null:
			add.text = "+ Map"
			add.disabled = true
		elif fd.maps.has(sel):
			add.text = "- Map"
			add.hint_tooltip = "Remove the selected map from this folder"
		else:
			add.text = "+ Map"
			add.hint_tooltip = "Add the selected map to this folder"
		add.connect("pressed", self, "_on_toggle_map", [i])
		row.add_child(add)

		var del := Button.new()
		del.text = "Sure?" if _delete_armed == i else "Delete"
		del.rect_min_size = Vector2(64, 32)
		del.hint_tooltip = "Delete this folder (maps are not deleted)"
		if _delete_armed == i:
			del.add_color_override("font_color", Color(0.8, 0, 0))
			del.add_color_override("font_color_hover", Color(0.8, 0, 0))
		del.connect("pressed", self, "_on_delete", [i])
		row.add_child(del)
	_fit()
	call_deferred("_fit")
	_rebuilding = false

func _on_create(_t = null):
	store.create_folder(new_name.text)
	new_name.text = ""
	rebuild()

func _on_show_all():
	store.set_active(-1)
	rebuild()

func _on_show(i: int):
	store.set_active(-1 if store.active == i else i)
	rebuild()

func _on_toggle_map(i: int):
	var sel = _selected_id()
	if sel == null: return
	store.toggle_map(i, sel)
	rebuild()

func _on_delete(i: int):
	if _delete_armed != i:
		_delete_armed = i
		rebuild()
		return
	_delete_armed = -1
	store.delete_folder(i)
	rebuild()

func _on_rename(txt: String, i: int):
	store.rename_folder(i, txt)

func _on_rename_focus(i: int, edit: LineEdit):
	if not _rebuilding and is_instance_valid(edit): store.rename_folder(i, edit.text)

func _on_color_changed(c: Color, i: int):
	# live preview without hitting the disk on every drag step
	_rebuilding = true
	store.set_color(i, c, false)
	_rebuilding = false

func _on_color_closed(i: int):
	if store.valid(i): store.set_color(i, store.folders[i].color, true)
	call_deferred("rebuild")
