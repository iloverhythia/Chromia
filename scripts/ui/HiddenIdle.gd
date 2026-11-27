extends Node

# VR menu (vrmenu.gd adds it to the menu): the settings boxes and mod buttons
# that check every frame whether their setting changed are paused while their
# page isn't on screen, and run again the moment it shows.
#
# There are about 70 of them (each settings page's boxes, the mod buttons), and
# together they were half of the menu's own script time every frame, shown or
# not: on the Meta Quest's processor a few milliseconds of every frame, with
# the store's review measuring the menu under 60 frames a second
# (VRC.Quest.Performance.1). What they do is copy a box's value to the setting
# (or the other way), which only matters while you can see and use the box.
#
# Left running: the ones that also work while hidden (a transfer, a save
# timer, the menu music, the map lists, the pin button, a login countdown...).

const DIRS := ["res://scripts/ui/settings/", "res://scripts/ui/menu/buttons/", "res://scenes/menu/"]
const ALSO := ["rainbow.gd", "AddSong.gd", "DownloadScreen.gd"]
const KEEP := ["TransferTab.gd", "HandCreatorPanel.gd", "NoteBuilder.gd", "DiscordLoginPanel.gd",
	"PlaySong.gd", "PinnedTab.gd", "SettingsPreview.gd", "FontsTab.gd", "EndInfo.gd",
	"v2MapList.gd", "v3MapList.gd", "menu2.gd"]

var _watched := {} # node -> true

static func pausable(n: Node) -> bool:
	if not (n is CanvasItem) or n.get_script() == null or not n.has_method("_process"):
		return false
	var p: String = String(n.get_script().resource_path)
	var file := p.get_file()
	# (the Sound Space mod panel's tiles: hidden with the panel unless Sound Space menus are on)
	if p == "" and n.get_parent() != null and n.get_parent().get_script() != null and String(n.get_parent().get_script().resource_path).get_file() == "SSModPanel.gd":
		return true
	if file == "" or file in KEEP:
		return false
	if file in ALSO:
		return true
	for d in DIRS:
		if p.begins_with(d):
			return true
	return false

func _ready():
	var top := get_parent()
	if top == null:
		return
	_walk(top)
	get_tree().connect("node_added", self, "_on_node_added")

func _walk(n: Node):
	_watch(n)
	for c in n.get_children():
		_walk(c)

func _on_node_added(n: Node):
	var top := get_parent()
	if top != null and top.is_a_parent_of(n) and pausable(n):
		# (after its _ready: Godot turns processing on itself then)
		call_deferred("_watch", n)

func _watch(n):
	if not is_instance_valid(n) or _watched.has(n) or not pausable(n) or not n.is_inside_tree():
		return
	_watched[n] = true
	n.connect("visibility_changed", self, "_follow", [n])
	n.connect("tree_exiting", self, "_forget", [n])
	_follow(n)

func _follow(n):
	if is_instance_valid(n) and n.is_inside_tree():
		n.set_process(n.is_visible_in_tree())

func _forget(n):
	_watched.erase(n)
	if is_instance_valid(n):
		if n.is_connected("visibility_changed", self, "_follow"):
			n.disconnect("visibility_changed", self, "_follow")
		if n.is_connected("tree_exiting", self, "_forget"):
			n.disconnect("tree_exiting", self, "_forget")

func _exit_tree():
	for n in _watched.keys():
		if is_instance_valid(n):
			n.set_process(true)
			if n.is_connected("visibility_changed", self, "_follow"):
				n.disconnect("visibility_changed", self, "_follow")
			if n.is_connected("tree_exiting", self, "_forget"):
				n.disconnect("tree_exiting", self, "_forget")
	_watched.clear()
