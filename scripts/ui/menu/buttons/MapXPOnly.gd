extends CheckBox

func _pressed():
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_xponly(pressed)
	Rhythia.last_search_xp_only = pressed

func _ready():
	pressed = Rhythia.last_search_xp_only
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_xponly(pressed)
