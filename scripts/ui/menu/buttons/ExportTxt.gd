extends Button

var debounce = false

func _ready():
	$SaveFile.set_script(load("res://addons/native_dialogs/bin/native_dialog_save_file.gdns"))

func _pressed():
	if debounce or not Rhythia.selected_song: return
	debounce = true
	text = "Saving"
	$SaveFile.set_initial_path("~/Downloads/%s.txt" % Rhythia.selected_song.id)
	$SaveFile.show()
	var path = yield($SaveFile, "file_selected")
	disabled = true
	Rhythia.selected_song.export_text(path)
	text = "Export map data"
	disabled = false
	debounce = false
