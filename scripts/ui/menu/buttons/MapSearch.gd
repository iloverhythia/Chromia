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
	var menu = Rhythia.menu_node()
	if menu:
		root_path = String(menu.get_path()) + "/Main/Maps/"

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

# Speed keys: Ctrl+S, then A / D (or the arrows) move through the speeds,
# slowest to fastest, instead of typing into the search. Ctrl+S again, Esc or
# Enter stops (as does any other key, which then types as usual).
const SPEED_ORDER := [Globals.SPEED_MMMM, Globals.SPEED_MMM, Globals.SPEED_MM, Globals.SPEED_M, Globals.SPEED_NORMAL,
	Globals.SPEED_P, Globals.SPEED_PP, Globals.SPEED_PPP, Globals.SPEED_PPPP]
const SPEED_NAMES := {Globals.SPEED_MMMM: "----", Globals.SPEED_MMM: "---", Globals.SPEED_MM: "--", Globals.SPEED_M: "-",
	Globals.SPEED_NORMAL: "Normal", Globals.SPEED_P: "+", Globals.SPEED_PP: "++", Globals.SPEED_PPP: "+++", Globals.SPEED_PPPP: "++++"}
var _speed_keys := false
var _speed_label: Label = null

func _show_speed_keys(on: bool):
	_speed_keys = on
	if _speed_label == null:
		_speed_label = Label.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.8)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		_speed_label.add_stylebox_override("normal", sb)
		_speed_label.add_color_override("font_color", Color(1, 1, 1))
		_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_speed_label.set_as_toplevel(true) # (over the map list)
		add_child(_speed_label)
	_speed_label.rect_position = rect_global_position + Vector2(0, rect_size.y + 4)
	_speed_label.visible = on
	if on:
		var lvl: int = Rhythia.mod_speed_level
		var speed := "Custom" if lvl == Globals.SPEED_CUSTOM else String(SPEED_NAMES.get(lvl, "?"))
		_speed_label.text = "Speed: %s (%.2fx)   A / D to change, Esc when done" % [speed, float(Globals.speed_multi[lvl])]

func _step_speed(dir: int):
	var i: int = SPEED_ORDER.find(Rhythia.mod_speed_level)
	if i < 0:
		i = SPEED_ORDER.find(Globals.SPEED_NORMAL) # (from a custom speed: next to normal)
	i = int(clamp(i + dir, 0, SPEED_ORDER.size() - 1))
	Rhythia.mod_speed_level = SPEED_ORDER[i]
	_show_speed_keys(true)

func _speed_key_input(event) -> bool:
	if not (event is InputEventKey) or not event.pressed:
		return false
	var sc: int = event.scancode
	if sc == KEY_S and event.control and not event.alt:
		if not event.echo:
			_show_speed_keys(not _speed_keys)
		return true
	if not _speed_keys:
		return false
	if sc == KEY_A or sc == KEY_LEFT:
		_step_speed(-1)
		return true
	if sc == KEY_D or sc == KEY_RIGHT:
		_step_speed(1)
		return true
	if event.echo:
		return false
	_show_speed_keys(false)
	return sc == KEY_ESCAPE or sc == KEY_ENTER or sc == KEY_KP_ENTER

func _input(event):
	if not is_visible_in_tree() or not editable:
		if _speed_keys:
			_show_speed_keys(false)
		return

	# (other text boxes keep their keys)
	var f = get_focus_owner()
	if not (f != null and f != self and (f is LineEdit or f is TextEdit)) and _speed_key_input(event):
		get_tree().set_input_as_handled()
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

		# the retry keybind (` by default, or a letter) isn't typing: it doesn't
		# jump into the search box
		if InputMap.has_action("retry") and event.is_action("retry"):
			return

		if event.scancode == KEY_BACKSPACE:
			if len(text) > 0:
				clear()
				grab_focus()
			return

		var unicode = event.unicode
		if unicode != 0:
			grab_focus()
