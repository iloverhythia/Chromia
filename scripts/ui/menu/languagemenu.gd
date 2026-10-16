extends ColorRect

onready var languageselect = $ChangeLanguage/SelectLanguageWindow/languageselector







func _ready():

	add_items()
	languageselect.selected = Rhythia.language

func add_items():
	languageselect.add_item("ENGLISH")
	languageselect.add_item("JAPANESE")
	languageselect.add_item("FRENCH")
	languageselect.add_item("SPANISH")
	languageselect.add_item("Dude Your Voice")

func _on_languageselector_item_selected(index):
	Rhythia.language = index
	Globals.apply_language_locale(index)
	var sidebar = get_node_or_null("../../../Sidebar")
	if sidebar != null:
		sidebar.refresh_language_labels()
