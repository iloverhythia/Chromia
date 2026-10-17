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

var copy_old_from: String


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
	Globals.file_sel.open_file(self, "sel", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.gif ; Image files"]), false, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))

func _ready():
	$Clear.connect("pressed", self, "reset_to_default")
	if kind == KIND.IMAGE:
		$ImgPreview.visible = true
		load_img()
	else:
		$ImgPreview.visible = false
