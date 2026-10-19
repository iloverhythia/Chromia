extends Node
# Click the "Filters" heading to collapse / expand the Filters column; the map
# list grows into the freed space. The choice is remembered.

const PREFS = "user://ui_prefs.cfg"

var filters: Control
var title: Label
var collapsed := false
var _hidden := []   # nodes this script hid (restored on expand)

static func attach(menu) -> void:
	var f = menu.get_node_or_null("Main/Maps/Filters")
	if f == null or f.has_node("FiltersCollapse"):
		return
	var c = load("res://scripts/ui/menu/FiltersCollapse.gd").new()
	c.name = "FiltersCollapse"
	c.filters = f
	f.add_child(c)

func _ready():
	title = filters.get_node_or_null("Label")
	if title == null:
		return
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title.hint_tooltip = "Click to hide / show the filters"
	title.connect("gui_input", self, "_on_title_input")
	var cfg = ConfigFile.new()
	if cfg.load(PREFS) == OK and bool(cfg.get_value("maps", "filters_collapsed", false)):
		call_deferred("_set_collapsed", true)
	else:
		_update_title()

func _on_title_input(ev):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		_set_collapsed(not collapsed)
		var cfg = ConfigFile.new()
		cfg.load(PREFS)
		cfg.set_value("maps", "filters_collapsed", collapsed)
		cfg.save(PREFS)

func _set_collapsed(on: bool):
	collapsed = on
	if on:
		_hidden.clear()
		for c in filters.get_children():
			if c is Control and c != title and c.name != "bump" and c.visible:
				c.visible = false
				_hidden.append(c)
	else:
		for c in _hidden:
			if is_instance_valid(c):
				c.visible = true
		_hidden.clear()
		# folder filters decide their own visibility (only when folders exist)
		var ff = filters.get_node_or_null("FolderFilters")
		if ff != null and ff.has_method("_rebuild"):
			ff._rebuild()
	_update_title()

func _update_title():
	title.text = "Filters  +" if collapsed else "Filters  −"
