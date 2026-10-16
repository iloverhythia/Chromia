extends Button

var debounce = false

func _ready():
	if not OS.has_feature("HTML5"):
		$SaveFile.set_script(load("res://addons/native_dialogs/bin/native_dialog_save_file.gdns"))

func _pressed():
	if debounce or not Rhythia.selected_song: return
	debounce = true
	if OS.has_feature("HTML5"):
		var map_data = Rhythia.selected_song.id + ","
		var notes = Rhythia.selected_song.read_notes()
		if notes.empty():
			debounce = false
			return
		for note in notes:
			map_data += "%s|%s|%s," % [2 - note[0], 2 - note[1], note[2]]
		JavaScript.download_buffer(map_data.trim_suffix(",").to_utf8(), "%s.txt" % Rhythia.selected_song.id, "text/plain")
		debounce = false
		return
	text = "Saving"
	$SaveFile.set_initial_path("~/Downloads/%s.txt" % Rhythia.selected_song.id)
	$SaveFile.show()
	var path = yield($SaveFile, "file_selected")
	disabled = true
	Rhythia.selected_song.export_text(path)
	text = "Export map data"
	disabled = false
	debounce = false
