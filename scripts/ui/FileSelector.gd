extends ColorRect
class_name FileSelector2D

var use_native: bool = false

var target_object: Object
var target_method: String
var cancel_method: String

func save_sel(file: String):
	if target_object and target_object != self:
		target_object.call(target_method, file)
		target_object = self
		visible = false

func files_single(file: String):
	if target_object and target_object != self:
		target_object.call(target_method, PoolStringArray([file]))
		target_object = self
		visible = false

func files_sel(files: PoolStringArray):
	if target_object and target_object != self:
		target_object.call(target_method, files)
		target_object = self
		visible = false

func folder_sel(folder: String):
	if target_object and target_object != self:
		target_object.call(target_method, folder)
		target_object = self
		visible = false


func _ready():
	visible = false
	if not ProjectSettings.get_setting("application/config/disable_native_file_dialogs"):
		$OpenFile.set_script(load("res://addons/native_dialogs/bin/native_dialog_open_file.gdns"))
		$SaveFile.set_script(load("res://addons/native_dialogs/bin/native_dialog_save_file.gdns"))
		$Folder.set_script(load("res://addons/native_dialogs/bin/native_dialog_select_folder.gdns"))
	if (
		not ProjectSettings.get_setting("application/config/disable_native_file_dialogs") and
		$OpenFile.has_signal("files_selected") and
		$SaveFile.has_signal("file_selected") and
		$Folder.has_signal("folder_selected")
	):
		use_native = true
		$OpenFile.connect("files_selected", self, "files_sel")
		$SaveFile.connect("file_selected", self, "save_sel")
		$Folder.connect("folder_selected", self, "folder_sel")

		$Spinner.visible = true
		$Label.visible = true
		$Label.text = "Waiting for file dialog...\n(click to cancel)"
		$Label.margin_bottom = 100
	else:
		$C/SaveFile.connect("file_selected", self, "save_sel")
		$C/OpenFile.connect("file_selected", self, "files_single")
		$C/OpenFile.connect("files_selected", self, "files_sel")
		$C/Folder.connect("dir_selected", self, "folder_sel")

		$C/OpenFile.connect("hide", self, "files_sel", [PoolStringArray()])
		$C/SaveFile.connect("hide", self, "save_sel", [""])
		$C/Folder.connect("hide", self, "folder_sel", [""])

		$Spinner.visible = false
		$Label.visible = false


# While a native dialog is open the game only shows "waiting for file dialog".
# If that dialog never reports back (e.g. it opened behind a fullscreen window
# or was closed without a result), clicking the overlay cancels.
func _gui_input(event):
	if use_native and visible and event is InputEventMouseButton and event.pressed:
		_cancel()

var _pending_kind: String = "open"

func _cancel():
	if target_object and target_object != self:
		var obj = target_object
		target_object = self
		visible = false
		obj.call(target_method, PoolStringArray() if _pending_kind == "open" else "")
	else:
		visible = false

func open_file(
	obj: Object,
	method: String,
	filters: PoolStringArray = PoolStringArray(["* ; All Files"]),
	multiselect: bool = false,
	initial_path: String = "user://"
):
	target_object = obj
	target_method = method
	_pending_kind = "open"

	$C/OpenFile.rect_pivot_offset = get_viewport_rect().size / 2

	if use_native:
		$OpenFile.filters = filters
		$OpenFile.multiselect = multiselect
		$OpenFile.initial_path = Globals.p(initial_path)
		if multiselect:
			$OpenFile.title = "Select files..."
		else:
			$OpenFile.title = "Select file..."
		$OpenFile.show()

	else:
		$C/OpenFile.filters = filters
		if multiselect:
			$C/OpenFile.mode = $C/OpenFile.MODE_OPEN_FILES
			$C/OpenFile.window_title = "Select files..."
		else:
			$C/OpenFile.mode = $C/OpenFile.MODE_OPEN_FILE
			$C/OpenFile.window_title = "Select file..."
		$C/OpenFile.show()
		$C/OpenFile.call_deferred("set_current_dir", ProjectSettings.globalize_path(Globals.p(initial_path)))
	visible = true
	raise()

func save_file(
	obj: Object,
	method: String,
	filters: PoolStringArray = PoolStringArray(["* ; All Files"]),
	initial_path: String = "user://"
):
	target_object = obj
	target_method = method
	_pending_kind = "save"

	$C/OpenFile.rect_pivot_offset = get_viewport_rect().size / 2

	if use_native:
		$SaveFile.filters = filters
		$SaveFile.initial_path = Globals.p(initial_path)
		$SaveFile.show()

	else:
		$C/SaveFile.filters = filters
		$C/SaveFile.show()
		$C/SaveFile.call_deferred("set_current_dir", ProjectSettings.globalize_path(Globals.p(initial_path)))
	visible = true
	raise()

func open_folder(
	obj: Object,
	method: String,
	initial_path: String = "user://"
):
	target_object = obj
	target_method = method
	_pending_kind = "folder"

	if use_native:
		$Folder.initial_path = Globals.p(initial_path)
		$Folder.show()

	else:
		$C/Folder.show()
		$C/Folder.call_deferred("set_current_dir", ProjectSettings.globalize_path(Globals.p(initial_path)))
	visible = true
	raise()
