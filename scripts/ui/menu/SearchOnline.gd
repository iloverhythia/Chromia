extends CheckBox

export(String) var target

func upd():

	pressed = Rhythia.get(target)
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).show_online_maps = pressed

func _pressed():
	if pressed != Rhythia.get(target):
		Rhythia.set(target, pressed)
	if pressed:
		Rhythia.ensure_online_maps_loaded()
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_showonline(
		Rhythia.last_search_incl_online
	)
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).show_online_maps = pressed

func _ready():
	upd()
	preload("res://scripts/ui/menu/MapListOf.gd").find(self).update_search_showonline(
		Rhythia.last_search_incl_online
	)
