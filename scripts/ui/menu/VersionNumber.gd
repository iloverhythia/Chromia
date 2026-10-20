extends Label

func _ready():
	text = "Chromia [%s]" % ProjectSettings.get_setting("application/config/version")
	text += " [%s]" % ("web" if OS.has_feature("JavaScript") else Rhythia.dev)
	if Rhythia.device("mobile"):
		visible = false # overlaps the song panel on small screens
