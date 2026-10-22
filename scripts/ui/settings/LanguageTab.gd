extends MarginContainer
# "Language" settings tab (it used to be its own sidebar page).

const LANGUAGES := ["English", "Japanese", "French", "Spanish", "Dude Your Voice"]

func _ready():
	var ui_theme = load("res://uitheme.tres")
	add_constant_override("margin_left", 16)
	add_constant_override("margin_right", 16)
	add_constant_override("margin_top", 12)
	add_constant_override("margin_bottom", 12)

	var list := VBoxContainer.new()
	list.add_constant_override("separation", 8)
	add_child(list)

	var row := HBoxContainer.new()
	row.add_constant_override("separation", 10)
	list.add_child(row)

	var label := Label.new()
	label.text = "Language"
	label.theme = ui_theme
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var pick := OptionButton.new()
	pick.theme = ui_theme
	pick.rect_min_size = Vector2(220, 32)
	for l in LANGUAGES:
		pick.add_item(l)
	pick.selected = int(clamp(int(Rhythia.language), 0, LANGUAGES.size() - 1))
	pick.connect("item_selected", self, "_on_selected")
	row.add_child(pick)

	var hint := Label.new()
	hint.text = "Some text only changes after reopening the menu."
	hint.theme = ui_theme
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.autowrap = true
	list.add_child(hint)

func _on_selected(index: int):
	Rhythia.language = index
	Globals.apply_language_locale(index)
	Rhythia.save_settings()
	var sidebar = Rhythia.menu_node("Sidebar")
	if sidebar != null and sidebar.has_method("refresh_language_labels"):
		sidebar.refresh_language_labels()
