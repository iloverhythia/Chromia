extends CheckBox

# Sorts the map list by star rating (easy to hard; the difficulty arrow flips it).
func _pressed():
	Rhythia.sort_by_stars = pressed
	Rhythia.save_settings()
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_sort_stars(pressed)

func _ready():
	pressed = Rhythia.sort_by_stars
	Rhythia.connect("star_ratings_updated", self, "_on_ratings_updated")
	hint_tooltip = "sort maps by star rating (the difficulty arrow flips the order)"

# Re-sort once background rating finishes.
func _on_ratings_updated():
	if pressed:
		get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_sort_stars(true)
