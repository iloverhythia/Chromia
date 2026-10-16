extends CheckBox

func _pressed():
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_xponly(pressed)
	Rhythia.last_search_xp_only = pressed

func _ready():
	pressed = Rhythia.last_search_xp_only
	get_parent().get_parent().get_node("MapRegistry/S/VBoxContainer").update_search_xponly(pressed)
