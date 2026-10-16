extends Button

var _pending_name := ""

func _pressed():
	Globals.string_prompt.open(
		"Name this border",
		"New Border",
		"My Border",
		[{text = "OK"}, {text = "Cancel", wait = 0}]
	)
	var response = yield(Globals.string_prompt, "option_selected")
	Globals.string_prompt.close()
	if response != 0:
		return
	var new_name = Globals.string_prompt.input.get_text().strip_edges()
	if new_name == "":
		return
	_pending_name = new_name
	Globals.file_sel.open_file(self, "_on_file_selected", PoolStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Image files"]), false)

func _on_file_selected(files: PoolStringArray):
	if files.size() == 0:
		return
	Rhythia.create_border_from_file(_pending_name, files[0])
