extends LineEdit

var _filter_container: Node = null
var _ignore_nodes: Array = []

func _ready():
	_filter_container = get_node_or_null("../../S/VBoxContainer")

	_setup_nodes()

	text = Rhythia.last_search_str
	update_txt()

	connect("text_changed", self, "update_txt")

	if _filter_container:
		_filter_container.connect("reset_filters", self, "_on_reset_filters")
		_filter_container.connect("lock_type", self, "_on_lock_type")

	var run_node = get_node_or_null("../../../Results/Results/RS/H1/Info/Run")
	if run_node:
		run_node.connect("lock_type", self, "_on_lock_type")

func _setup_nodes():
	var root_path = "/root/Menu/Main/Maps/"
	if Rhythia.vr:
		root_path = "/root/VRMenuHolder/PointerScreen/Viewport/Menu/Main/Maps/"

	var paths = [
		root_path + "MapRegistry/T/AuthorSearch",
		root_path + "Results/Results/RS/H2/Mods/SpeedMod/C/CustomSpeed",
		root_path + "Results/Results/RS/H2/Mods/StartOffset/TimeTextBox",
		root_path + "Results/Results/RS/H2/Mods/360Speed/SpeedTextBox"
	]

	for p in paths:
		var node = get_node_or_null(p)
		if node:
			if node.has_method("get_line_edit"):
				_ignore_nodes.append(node.get_line_edit())
			else:
				_ignore_nodes.append(node)

func update_txt(_v = null):
	if _filter_container and _filter_container.has_method("update_search_text"):
		_filter_container.update_search_text(text)

	Rhythia.last_search_str = text

func _on_reset_filters():
	text = ""
	update_txt()

func _on_lock_type():
	set_editable(false)

func _input(event):
	if not is_visible_in_tree() or not editable:
		return

	var current_focus = get_focus_owner()
	if current_focus == self:
		return

	if current_focus != null and (current_focus is LineEdit or current_focus is TextEdit):
		return

	for node in _ignore_nodes:
		if current_focus == node:
			return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.scancode == KEY_SPACE:
			return

		if event.scancode == KEY_BACKSPACE:
			if len(text) > 0:
				clear()
				grab_focus()
			return

		var unicode = event.unicode
		if unicode != 0:
			grab_focus()
