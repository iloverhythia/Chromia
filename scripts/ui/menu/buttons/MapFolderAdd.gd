extends MenuButton
# "Folders" dropdown next to the Favorite button in the song info panel:
# toggle the selected map in/out of each folder, or make a new folder for it.

const MapFolders = preload("res://scripts/MapFolders.gd")

const ID_NEW = 100000
const ID_MANAGE = 100001

var store

func _ready():
	store = MapFolders.get_store()
	get_popup().theme = preload("res://uitheme.tres")
	get_popup().connect("id_pressed", self, "_on_id")
	connect("about_to_show", self, "_build")
	store.connect("changed", self, "upd")
	Rhythia.connect("selected_song_changed", self, "upd")
	upd()

func _sel():
	if Rhythia.single_map_mode or Rhythia.selected_song == null: return null
	return Rhythia.selected_song.id

func upd(_s = null):
	var sel = _sel()
	disabled = sel == null
	if sel == null:
		text = "Folders"
		return
	var inn: Array = store.folders_with(sel)
	if inn.empty():
		text = "Add to folder"
		hint_tooltip = "Add this map to one of your map folders"
	elif inn.size() == 1:
		text = "In: " + store.folders[inn[0]].name
		hint_tooltip = "Click to add/remove this map from folders"
	else:
		text = "In %d folders" % inn.size()
		hint_tooltip = "Click to add/remove this map from folders"
	var col = store.color_for(sel)
	if col != null:
		add_color_override("font_color", col.darkened(0.45))
		add_color_override("font_color_hover", col.darkened(0.45))
	else:
		# no remove_color_override in 3.x; go back to the theme's black
		add_color_override("font_color", Color(0, 0, 0))
		add_color_override("font_color_hover", Color(0, 0, 0))

func _swatch(c: Color) -> ImageTexture:
	var img := Image.new()
	img.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	var t := ImageTexture.new()
	t.create_from_image(img, 0)
	return t

func _build():
	var p: PopupMenu = get_popup()
	p.clear()
	var sel = _sel()
	for i in store.folders.size():
		var fd = store.folders[i]
		# uitheme has no check icons, so spell the action out instead
		if sel != null and fd.maps.has(sel):
			p.add_icon_item(_swatch(fd.color), "Remove from \"%s\"" % fd.name, i)
		else:
			p.add_icon_item(_swatch(fd.color), "Add to \"%s\"" % fd.name, i)
	if not store.folders.empty(): p.add_separator()
	p.add_item("New folder with this map", ID_NEW)
	p.add_item("Manage folders...", ID_MANAGE)

func _on_id(id: int):
	var sel = _sel()
	if id == ID_MANAGE:
		var btn = get_tree().current_scene.get_node_or_null("Main/Maps/MapRegistry/T/Folders") if get_tree().current_scene else null
		if btn: btn.open_panel()
		return
	if sel == null: return
	if id == ID_NEW:
		var i = store.create_folder()
		store.add_map(i, sel)
		return
	store.toggle_map(id, sel)
