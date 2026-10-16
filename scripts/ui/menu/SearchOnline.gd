extends CheckBox

export(String) var target

func upd():

	pressed = Rhythia.get(target)
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").show_online_maps = pressed

func _pressed():
	if pressed != Rhythia.get(target):
		Rhythia.set(target, pressed)
	if pressed:
		Rhythia.ensure_online_maps_loaded()
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_showonline(
		Rhythia.last_search_incl_online
	)
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").show_online_maps = pressed

func _ready():
	upd()
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_showonline(
		Rhythia.last_search_incl_online
	)
