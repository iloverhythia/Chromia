extends CheckBox

# Sorts the map list by star rating (easy to hard; the difficulty arrow flips it).
func _pressed():
	Rhythia.sort_by_stars = pressed
	Rhythia.save_settings()
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_sort_stars(pressed)

func _ready():
	pressed = Rhythia.sort_by_stars
