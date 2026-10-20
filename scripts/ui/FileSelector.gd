extends ColorRect
class_name FileSelector2D

var use_native: bool = false

var _win_dialog = null
var _win_request: Array = []

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
		# preview pane (images, GIFs, videos, audio) next to the file list
		load("res://scripts/ui/FilePreview.gd").attach($C/OpenFile)

		$Spinner.visible = false
		$Label.visible = false


# While a native dialog is open the game only shows "waiting for file dialog".
# If that dialog never reports back (e.g. it opened behind a fullscreen window
# or was closed without a result), clicking the overlay cancels.
func _gui_input(event):
	if (use_native or _win_dialog != null) and visible and event is InputEventMouseButton and event.pressed:
		_win_dialog = null
		_set_waiting(false)
		_cancel()

func _set_waiting(on: bool):
	$Spinner.visible = on or use_native
	$Label.visible = on or use_native
	if on:
		$Label.text = "Waiting for file dialog...\n(click to cancel)"
		$Label.margin_bottom = 100

# The Windows file picker used to be opened through a hidden PowerShell, which
# antivirus (Bitdefender) flags as a threat. The in-game browser is used now.
func _try_windows_dialog(_mode: String, _filters: PoolStringArray, _multiselect: bool, _initial_path: String, _title: String) -> bool:
	return false

func _on_win_dialog_done(ok: bool, paths: Array, d):
	if d != _win_dialog:
		return # cancelled from the overlay meanwhile
	_win_dialog = null
	_set_waiting(false)
	if not ok:
		# PowerShell couldn't show it; use the in-game browser instead.
		var r = _win_request
		match r[0]:
			"open": _open_ingame(r[1], r[2], r[3])
			"save": _save_ingame(r[1], r[3])
			"folder": _folder_ingame(r[3])
		return
	match _win_request[0]:
		"open": files_sel(PoolStringArray(paths))
		"save": save_sel(paths[0] if paths.size() > 0 else "")
		"folder": folder_sel(paths[0] if paths.size() > 0 else "")

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
	if _web():
		_web_open(filters, multiselect)
		return
	if _try_windows_dialog("open", filters, multiselect, initial_path, "Select files..." if multiselect else "Select file..."):
		return
	_open_ingame(filters, multiselect, initial_path)

func _open_ingame(filters: PoolStringArray, multiselect: bool, initial_path: String):
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
	if _web():
		_web_save(filters)
		return
	if _try_windows_dialog("save", filters, false, initial_path, "Save file..."):
		return
	_save_ingame(filters, initial_path)

func _save_ingame(filters: PoolStringArray, initial_path: String):
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
	if _web():
		Globals.notify(Globals.NOTIFY_WARN, "Picking folders isn't possible in the browser version. Pick the files instead.", "Not available")
		folder_sel("")
		return
	if _try_windows_dialog("folder", PoolStringArray(), false, initial_path, "Select folder..."):
		return
	_folder_ingame(initial_path)

func _folder_ingame(initial_path: String):

	if use_native:
		$Folder.initial_path = Globals.p(initial_path)
		$Folder.show()

	else:
		$C/Folder.show()
		$C/Folder.call_deferred("set_current_dir", ProjectSettings.globalize_path(Globals.p(initial_path)))
	visible = true
	raise()


# ---- Browser (web) version -----------------------------------------------
# The in-game browser can only see the game's own storage there, so files come
# from the browser's file chooser (copied into the game's file system) and
# saving a file downloads it.

func _web() -> bool:
	return OS.has_feature("JavaScript")

# "*.png, *.jpg ; Images" -> ".png,.jpg"
static func _web_accept(filters: PoolStringArray) -> String:
	var exts := []
	for f in filters:
		for pat in f.split(";")[0].split(","):
			pat = pat.strip_edges()
			if pat.begins_with("*.") and pat.length() > 2:
				exts.append(pat.substr(1))
	return PoolStringArray(exts).join(",")

func _web_open(filters: PoolStringArray, multiselect: bool):
	var js := """(function () {
		window.chromiaPicked = null;
		var i = document.createElement('input');
		i.type = 'file'; i.accept = %s; i.multiple = %s; i.style.display = 'none';
		document.body.appendChild(i);
		var done = function (v) { if (window.chromiaPicked === null) window.chromiaPicked = v; i.remove(); };
		i.addEventListener('cancel', function () { done(''); });
		i.addEventListener('change', async function () {
			var out = [];
			for (var k = 0; k < i.files.length; k++) {
				var f = i.files[k];
				var p = '/chromia_upload/' + Date.now() + '_' + k + '/' + f.name;
				engine.copyToFS(p, await f.arrayBuffer());
				out.push(p);
			}
			done(out.join('\\n'));
		});
		i.click();
	})();""" % [to_json(_web_accept(filters)), "true" if multiselect else "false"]
	Engine.get_singleton("JavaScript").eval(js, true)
	var picked = null
	var waited := 0.0
	while picked == null and waited < 600.0:
		yield(get_tree().create_timer(0.25), "timeout")
		waited += 0.25
		picked = Engine.get_singleton("JavaScript").eval("window.chromiaPicked", true)
	var files := PoolStringArray()
	if picked is String and picked != "":
		files = PoolStringArray(picked.split("\n", false))
	if target_object and target_object != self:
		files_sel(files)

func _web_save(filters: PoolStringArray):
	var acc: String = _web_accept(filters)
	var ext: String = acc.split(",")[0] if acc != "" else ""
	var d = Directory.new()
	d.make_dir_recursive("/chromia_export")
	var path := "/chromia_export/chromia_export" + ext
	if d.file_exists(path):
		d.remove(path)
	save_sel(path)
	# the caller writes the file now; then hand it to the browser as a download
	for i in range(3):
		yield(get_tree(), "idle_frame")
	var f = File.new()
	if f.open(path, File.READ) == OK:
		var buf = f.get_buffer(f.get_len())
		f.close()
		Engine.get_singleton("JavaScript").download_buffer(buf, path.get_file(), "application/octet-stream")
