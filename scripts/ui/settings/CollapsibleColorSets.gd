extends VBoxContainer

var collapsed: bool = false

func _load_collapsed() -> bool:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return false
	return bool(config.get_value("ui", "colorsets_collapsed", false))

func _save_collapsed(value: bool):
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("ui", "colorsets_collapsed", value)
	config.save("user://settings.cfg")

func _apply_collapsed():
	$MarginContainer.visible = not collapsed
	$ColorSet.visible = not collapsed
	$Label.text = ("▸ Note Colors (click to expand)" if collapsed else "▾ Note Colors (click to collapse)")

func _on_label_gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		collapsed = not collapsed
		_apply_collapsed()
		_save_collapsed(collapsed)

func _ready():
	$Label.mouse_filter = Control.MOUSE_FILTER_STOP
	$Label.connect("gui_input", self, "_on_label_gui_input")
	collapsed = _load_collapsed()
	_apply_collapsed()
