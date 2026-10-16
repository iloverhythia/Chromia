extends Button

func _pressed():
	if OS.has_feature("HTML5") and OS.has_feature("JavaScript"):
		Globals.open_web_file_picker(self, "_on_map_files_selected", ".sspm,.sspm2")
	else:
		Globals.file_sel.open_file(
			self,
			"_on_map_files_selected",
			PoolStringArray(["*.sspm, *.sspm2 ; Sound Space maps"]),
			true,
			"user://"
		)

func _on_map_files_selected(files: PoolStringArray):
	var imported := 0
	for source_path in files:
		var map := Song.new()
		var load_result = map.load_from_sspm(source_path)
		if load_result is String:
			Globals.notify(Globals.NOTIFY_WARN, load_result, "Map Import Failed")
			continue
		if Rhythia.registry_song.idx_id.has(map.id):
			Globals.notify(Globals.NOTIFY_WARN, "A map with this ID is already in your game.", "Map Not Imported")
			continue

		var map_dir := Directory.new()
		var destination := Globals.p("user://maps/%s.sspm" % map.id)
		if not map_dir.dir_exists(Globals.p("user://maps")):
			map_dir.make_dir_recursive(Globals.p("user://maps"))
		var source := File.new()
		if source.open(source_path, File.READ) != OK:
			Globals.notify(Globals.NOTIFY_WARN, "Could not read the selected map file.", "Map Import Failed")
			continue
		var bytes := source.get_buffer(source.get_len())
		source.close()
		var output := File.new()
		if output.open(destination, File.WRITE) != OK:
			Globals.notify(Globals.NOTIFY_WARN, "Could not save this map.", "Map Import Failed")
			continue
		output.store_buffer(bytes)
		output.close()
		var added = Rhythia.registry_song.add_sspm_map(destination)
		if added:
			imported += 1

	var map_list = get_node_or_null("/root/Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list:
		map_list.refresh_songs()
	if imported > 0:
		Globals.notify(Globals.NOTIFY_SUCCEED, "%d map(s) added." % imported, "Maps Imported")

func _ready():
	visible = Rhythia.device("mobile")
