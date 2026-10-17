extends Reference
# User-made map folders (name + color + set of song ids), saved to
# user://map_folders.json. There is one shared store per game run:
#   const MapFolders = preload("res://scripts/MapFolders.gd")
#   var store = MapFolders.get_store()

signal changed

const SAVE_PATH = "user://map_folders.json"
const META_KEY = "furria_map_folders_store"
const DEFAULT_COLORS = [
	Color("#ff6b9d"), Color("#6bc5ff"), Color("#8cff6b"), Color("#ffd36b"),
	Color("#c46bff"), Color("#ff8f5c"), Color("#5cffd9"), Color("#ff5c5c"),
]

# Each folder: {"name": String, "color": Color, "maps": Dictionary(song id -> true)}
var folders: Array = []
# Index of the folder the map list is filtered to, or -1 for all maps.
var active: int = -1
# song id -> Color of the first folder containing it (for list markers)
var _color_of: Dictionary = {}

static func get_store():
	# Kept as metadata on the root viewport (not Engine) so it is freed with
	# the scene tree, before the script language shuts down.
	var root: Viewport = Engine.get_main_loop().root
	if root.has_meta(META_KEY):
		return root.get_meta(META_KEY)
	var s = load("res://scripts/MapFolders.gd").new()
	s.load_data()
	root.set_meta(META_KEY, s)
	return s

func load_data():
	folders = []
	active = -1
	var f := File.new()
	var path: String = Globals.p(SAVE_PATH)
	if f.file_exists(path) and f.open(path, File.READ) == OK:
		var res := JSON.parse(f.get_as_text())
		f.close()
		if res.error == OK and typeof(res.result) == TYPE_DICTIONARY:
			var data: Dictionary = res.result
			for fd in data.get("folders", []):
				if typeof(fd) != TYPE_DICTIONARY: continue
				var maps := {}
				for id in fd.get("maps", []):
					maps[str(id)] = true
				var col = Color(DEFAULT_COLORS[folders.size() % DEFAULT_COLORS.size()])
				var cs = str(fd.get("color", ""))
				if cs.is_valid_html_color(): col = Color(cs)
				folders.append({"name": str(fd.get("name", "Folder")), "color": col, "maps": maps})
			active = int(data.get("active", -1))
			if active < -1 or active >= folders.size(): active = -1
		else:
			print("map_folders.json could not be parsed")
	_rebuild_colors()

func save():
	var out := []
	for fd in folders:
		out.append({"name": fd.name, "color": "#" + fd.color.to_html(false), "maps": fd.maps.keys()})
	var f := File.new()
	if f.open(Globals.p(SAVE_PATH), File.WRITE) == OK:
		f.store_string(JSON.print({"folders": out, "active": active}, "\t"))
		f.close()
	else:
		print("could not save map_folders.json")

func _rebuild_colors():
	_color_of = {}
	for fd in folders:
		for id in fd.maps:
			if not _color_of.has(id): _color_of[id] = fd.color

func _commit(persist: bool = true):
	_rebuild_colors()
	if persist: save()
	emit_signal("changed")

func valid(i: int) -> bool:
	return i >= 0 and i < folders.size()

func create_folder(name: String = "", color = null) -> int:
	if name.strip_edges() == "": name = "Folder %d" % (folders.size() + 1)
	if color == null: color = DEFAULT_COLORS[folders.size() % DEFAULT_COLORS.size()]
	folders.append({"name": name.strip_edges(), "color": color, "maps": {}})
	_commit()
	return folders.size() - 1

func delete_folder(i: int):
	if not valid(i): return
	folders.remove(i)
	if active == i: active = -1
	elif active > i: active -= 1
	_commit()

func rename_folder(i: int, name: String):
	if not valid(i) or name.strip_edges() == "": return
	if folders[i].name == name.strip_edges(): return
	folders[i].name = name.strip_edges()
	_commit()

func set_color(i: int, color: Color, persist: bool = true):
	if not valid(i): return
	folders[i].color = color
	_commit(persist)

func add_map(i: int, id: String):
	if not valid(i) or folders[i].maps.has(id): return
	folders[i].maps[id] = true
	_commit()

func remove_map(i: int, id: String):
	if not valid(i) or not folders[i].maps.has(id): return
	folders[i].maps.erase(id)
	_commit()

func toggle_map(i: int, id: String):
	if not valid(i): return
	if folders[i].maps.has(id): remove_map(i, id)
	else: add_map(i, id)

func has_map(i: int, id: String) -> bool:
	return valid(i) and folders[i].maps.has(id)

func folders_with(id: String) -> Array:
	var out := []
	for i in folders.size():
		if folders[i].maps.has(id): out.append(i)
	return out

func set_active(i: int):
	if not valid(i): i = -1
	if active == i: return
	active = i
	_commit()

# Dictionary (song id -> true) of the active folder, or null when showing all maps.
func active_set():
	if valid(active): return folders[active].maps
	return null

func active_folder():
	if valid(active): return folders[active]
	return null

# Color of the first folder containing this map, or null.
func color_for(id: String):
	return _color_of.get(id)
