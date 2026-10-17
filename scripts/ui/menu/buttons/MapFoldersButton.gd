extends Button
# "Map Folders" button next to "Select random from search". Opens the folder
# panel and shows which folder (if any) the map list is filtered to.

const MapFolders = preload("res://scripts/MapFolders.gd")
const MapFoldersPanel = preload("res://scripts/ui/menu/MapFoldersPanel.gd")

var store
var panel
var strip: ColorRect

func _ready():
	store = MapFolders.get_store()
	strip = ColorRect.new()
	strip.mouse_filter = MOUSE_FILTER_IGNORE
	strip.anchor_top = 1
	strip.anchor_right = 1
	strip.anchor_bottom = 1
	strip.margin_left = 4
	strip.margin_right = -4
	strip.margin_top = -5
	strip.margin_bottom = -2
	add_child(strip)
	store.connect("changed", self, "upd")
	upd()

func _pressed():
	open_panel()

func open_panel():
	if panel == null:
		panel = MapFoldersPanel.new()
		panel.name = "MapFoldersPanel"
		# keep the popup outside the containers so it isn't laid out by them
		var menu = get_tree().current_scene if get_tree().current_scene else get_parent()
		menu.add_child(panel)
	panel.open()

func upd():
	var fd = store.active_folder()
	if fd == null:
		text = "Map Folders"
		hint_tooltip = "Create folders, add maps to them and filter the list by folder"
		strip.visible = false
	else:
		var nm: String = fd.name
		if nm.length() > 16: nm = nm.substr(0, 15) + "..."
		text = nm
		hint_tooltip = "Showing only maps in \"%s\" (%d). Click to change." % [fd.name, fd.maps.size()]
		strip.visible = true
		strip.color = fd.color
