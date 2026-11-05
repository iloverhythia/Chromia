extends CheckBox

func _pressed():
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_showbroken(
		!preload("res://scripts/ui/menu/MapListOf.gd").find(self).show_broken_maps
	)
	Rhythia.last_search_incl_broken = pressed

func _ready():
	pressed = Rhythia.last_search_incl_broken
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_showbroken(
		Rhythia.last_search_incl_broken
	)
