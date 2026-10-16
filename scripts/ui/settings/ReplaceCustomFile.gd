extends Button

var dir: Directory = Directory.new()

export(String) var target = "cursor"
export(Texture) var default_image

enum KIND {
	IMAGE
	SOUND
}

export(KIND) var kind = KIND.IMAGE

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]
const PICK_TMP := "user://_picked_image"
const WEB_ACCEPT := "image/*,.png,.jpg,.jpeg,.webp,.bmp,.gif"

var copy_old_from: String
var _web_cb


func _asset_path(ext: String) -> String:
	return Globals.p("user://%s.%s" % [target, ext])

func _existing_ext() -> String:
	for ext in IMAGE_EXTS:
		if dir.file_exists(_asset_path(ext)):
			return ext
	return ""

func _remove_existing():
	for ext in IMAGE_EXTS:
		if dir.file_exists(_asset_path(ext)):
			dir.remove(_asset_path(ext))

func _clear_picked_tmp():
	for ext in IMAGE_EXTS:
		var p = "%s.%s" % [PICK_TMP, ext]
		if dir.file_exists(p):
			dir.remove(p)

func _is_web() -> bool:
	return OS.has_feature("HTML5") and OS.has_feature("JavaScript")


func save_sel(file: String):
	dir.copy(copy_old_from, file)

func load_img():
	var tex = Globals.imageLoader.load_if_exists("user://" + target)
	if tex:
		$ImgPreview.texture = tex
		$Clear.disabled = false
	else:
		$ImgPreview.texture = default_image
		$Clear.disabled = true

func rename_old(ext: String):
	copy_old_from = _asset_path(ext)
	if _is_web():

		var f := File.new()
		if f.open(copy_old_from, File.READ) == OK:
			var bytes := f.get_buffer(f.get_len())
			f.close()
			var mime := "image/" + ("jpeg" if ext == "jpg" else ext)
			JavaScript.download_buffer(bytes, "%s.%s" % [target, ext], mime)
		return
	Globals.file_sel.save_file(
		self,
		"save_sel",
		["*.%s ; %s file" % [ext, ext]],
		OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) + "/%s.%s" % [target, ext]
	)

func reset_to_default():
	if kind == KIND.IMAGE:
		Globals.confirm_prompt.open(
			"Are you sure? This can't be undone!",
			"Remove Custom Asset",
			[
				{text = "Cancel"},
				{text = "Save old image"},
				{text = "OK", wait = 0}
			]
		)
		var response: int = yield(Globals.confirm_prompt, "option_selected")
		while response == 1:
			var ext := _existing_ext()
			if ext != "": rename_old(ext)
			response = yield(Globals.confirm_prompt, "option_selected")
		if response == 2:
			_remove_existing()
			load_img()
		else: print("cancelled")
		Globals.confirm_prompt.close()

func sel(files: Array):
	if files.size() != 0 and kind == KIND.IMAGE:
		Globals.confirm_prompt.open(
			"Are you sure? This will overwrite the previous image!",
			"Replace Custom Asset",
			[
				{text = "Cancel"},
				{text = "Save old image"},
				{text = "OK", wait = 0}
			]
		)
		var response: int = yield(Globals.confirm_prompt, "option_selected")
		while response == 1:
			var ext := _existing_ext()
			if ext != "": rename_old(ext)
			response = yield(Globals.confirm_prompt, "option_selected")
		if response == 2:
			_remove_existing()
			dir.copy(files[0], _asset_path(files[0].get_extension().to_lower()))
			load_img()
		else: print("cancelled")
		Globals.confirm_prompt.close()


func _pressed():
	if kind != KIND.IMAGE:
		return
	if _is_web():
		_open_web_picker()
	else:
		Globals.file_sel.open_file(self, "sel", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Image files"]))

func _open_web_picker():
	if _web_cb == null:
		_web_cb = JavaScript.create_callback(self, "_on_web_file_picked")
	var win = JavaScript.get_interface("window")
	win.saviaPickCb = _web_cb
	JavaScript.eval( \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
	 \
		"\n\t(function () {\n\t\tvar input = document.createElement('input');\n\t\tinput.type = 'file';\n\t\tinput.accept = '%s';\n\t\tinput.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;';\n\t\tdocument.body.appendChild(input);\n\t\tinput.addEventListener('change', function () {\n\t\t\tvar f = input.files && input.files[0];\n\t\t\tif (!f) { input.remove(); return; }\n\t\t\tvar reader = new FileReader();\n\t\t\treader.onload = function () {\n\t\t\t\tvar bytes = new Uint8Array(reader.result);\n\t\t\t\tvar bin = '';\n\t\t\t\tfor (var i = 0; i < bytes.length; i += 0x8000) {\n\t\t\t\t\tbin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));\n\t\t\t\t}\n\t\t\t\twindow.saviaPickCb(f.name, f.type, btoa(bin));\n\t\t\t\tinput.remove();\n\t\t\t};\n\t\t\treader.readAsArrayBuffer(f);\n\t\t});\n\t\tinput.click();\n\t})();\n\t" % WEB_ACCEPT, true)

func _ext_for(file_name: String, mime: String) -> String:
	var ext := file_name.get_extension().to_lower()
	if ext in IMAGE_EXTS:
		return ext

	match mime:
		"image/png": return "png"
		"image/jpeg": return "jpg"
		"image/webp": return "webp"
		"image/bmp": return "bmp"
		"image/gif": return "gif"
	return ""

func _on_web_file_picked(args):
	if args.size() < 3:
		return
	var ext := _ext_for(str(args[0]), str(args[1]))
	if ext == "":
		Globals.notify(Globals.NOTIFY_ERROR, "That file type isn't supported. Use PNG, JPG, WEBP, BMP or GIF.", "Unsupported Image")
		return
	var raw := Marshalls.base64_to_raw(str(args[2]))
	if raw.size() == 0:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not read that file.", "Upload Failed")
		return
	_clear_picked_tmp()
	var path := "%s.%s" % [PICK_TMP, ext]
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_ERROR, "Could not store the picked image.", "Upload Failed")
		return
	f.store_buffer(raw)
	f.close()
	sel([path])

func _ready():
	$Clear.connect("pressed", self, "reset_to_default")
	if kind == KIND.IMAGE:
		$ImgPreview.visible = true
		load_img()
	else:
		$ImgPreview.visible = false
