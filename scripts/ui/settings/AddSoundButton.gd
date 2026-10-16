extends Button

export(String) var kind = "hit"

var _pending_name := ""

func _pressed():
	Globals.string_prompt.open(
		"Name this %s sound" % kind,
		"New %s Sound" % ("Hit" if kind == "hit" else "Miss"),
		"My Sound",
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
	Globals.file_sel.open_file(self, "_on_file_selected", PoolStringArray(["*.ogg, *.mp3, *.wav ; Audio files"]), false)

func _on_file_selected(files: PoolStringArray):
	if files.size() == 0:
		return
	Rhythia.create_named_sound_from_file(kind, _pending_name, files[0])
