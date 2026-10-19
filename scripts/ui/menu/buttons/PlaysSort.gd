extends CheckBox
# "most played" sort in the map list Filters column (made by menu2.gd next to
# the "stars" sort, styled like it). The two sorts turn each other off.

var stars: CheckBox

func _pressed():
	Rhythia.sort_by_plays = pressed
	if pressed and Rhythia.sort_by_stars:
		Rhythia.sort_by_stars = false
		if stars != null and is_instance_valid(stars):
			stars.pressed = false
	Rhythia.save_settings()
	_refresh()

func _ready():
	pressed = Rhythia.sort_by_plays
	hint_tooltip = "sort maps by how often you've played them (the difficulty arrow flips the order)"
	if stars != null:
		stars.connect("pressed", self, "_on_stars_pressed")

func _on_stars_pressed():
	if stars.pressed and pressed:
		pressed = false
		Rhythia.sort_by_plays = false
		Rhythia.save_settings()
		_refresh()

func _refresh():
	var list = get_parent().get_parent().get_node_or_null("MapRegistry/S/VBoxContainer")
	if list != null:
		list.update_search_sort_stars(pressed)
