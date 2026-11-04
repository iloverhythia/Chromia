extends CheckBox

func _pressed():
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_flip_name(
		!preload("res://scripts/ui/menu/MapListOf.gd").find(self).flip_name
	)
	Rhythia.last_search_flip_name_sort = pressed

func _ready():
	pressed = Rhythia.last_search_flip_name_sort
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_flip_name(
		Rhythia.last_search_flip_name_sort
	)
