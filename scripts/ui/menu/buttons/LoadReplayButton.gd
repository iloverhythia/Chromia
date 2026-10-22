extends Button
# Phones: "Load Replay" next to "Map Folders" in the map list. On a computer a
# replay is watched by dropping its .sspre file on the window, which phones
# can't do: this picks one with the file picker (your replays folder, or any
# file on the phone) and plays it the same way.

static func install(menu: Node):
	if menu == null or not Rhythia.device("mobile"):
		return
	var bar = menu.get_node_or_null("Main/Maps/MapRegistry/T")
	if bar == null or bar.has_node("LoadReplay"):
		return
	var b = load("res://scripts/ui/menu/buttons/LoadReplayButton.gd").new()
	b.name = "LoadReplay"
	var like = bar.get_node_or_null("Folders")
	if like:
		b.theme = like.theme
		b.rect_min_size = like.rect_min_size
		b.size_flags_horizontal = like.size_flags_horizontal
		b.size_flags_vertical = like.size_flags_vertical
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	b.text = "Load Replay"
	b.hint_tooltip = "Watch a replay (.sspre file)"
	bar.add_child(b)
	if like:
		bar.move_child(b, like.get_index() + 1)

func _pressed():
	Globals.file_sel.open_file(self, "_on_picked", PoolStringArray(["*.sspre ; Replays"]), false, Globals.p("user://replays"))

func _on_picked(path):
	if typeof(path) == TYPE_STRING_ARRAY or typeof(path) == TYPE_ARRAY:
		path = path[0] if path.size() > 0 else ""
	path = String(path)
	if path == "":
		return
	if path.get_extension().to_lower() != "sspre":
		Globals.notify(Globals.NOTIFY_WARN, "That isn't a replay. Replays are .sspre files.", "Load Replay")
		return
	var run = Rhythia.menu_node("Main/Maps/Results/Results/RS/H1/Info/Run")
	if run and run.has_method("files_dropped"):
		run.files_dropped(PoolStringArray([path]), 0)
