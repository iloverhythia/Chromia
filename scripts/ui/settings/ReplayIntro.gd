extends Node

func _on_Play_pressed():
	# (no intro in VR: Intro.gd would go straight back to loading everything)
	if Rhythia.vr or OS.has_feature("quest"):
		Globals.notify(Globals.NOTIFY_INFO, "The intro doesn't play in VR.", "Intro")
		return
	get_tree().change_scene("res://scenes/Intro.tscn")
