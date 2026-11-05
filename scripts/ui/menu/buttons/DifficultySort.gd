extends CheckBox

func _pressed():
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_flipped(
		!preload("res://scripts/ui/menu/MapListOf.gd").find(self).flip_display
	)
	Rhythia.last_search_flip_sort = pressed

func _ready():
	pressed = Rhythia.last_search_flip_sort
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_flipped(
		Rhythia.last_search_flip_sort
	)
