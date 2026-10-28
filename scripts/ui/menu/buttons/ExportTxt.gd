extends Button

var debounce = false

# The save dialog is the native_dialogs plugin, which only exists for Windows,
# Linux and macOS. Elsewhere (iPhone, Android, the web) loading it failed with
# "does not have a library for the current platform" every time the menu
# loaded, and pressing the button would call into a script that isn't there.
static func _native() -> bool:
	return OS.has_feature("Windows") or OS.has_feature("X11") or OS.has_feature("OSX")

func _ready():
	if _native():
		$SaveFile.set_script(load("res://addons/native_dialogs/bin/native_dialog_save_file.gdns"))
	else:
		visible = false

func _pressed():
	if debounce or not Rhythia.selected_song or not _native(): return
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
