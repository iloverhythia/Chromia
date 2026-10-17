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
	set_process(true)

# Re-sort once background rating finishes.
func _on_ratings_updated():
	if pressed:
		get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_sort_stars(true)

func _process(_d):
	if not Rhythia._star_done and Rhythia._star_total > 0:
		text = "stars (rating %d/%d)" % [Rhythia._star_progress, Rhythia._star_total]
	elif text != "stars":
		text = "stars"
