extends Label

func _ready():
	text = "Chromia [%s]" % ProjectSettings.get_setting("application/config/version")
	text += " [%s]" % ("web" if OS.has_feature("JavaScript") else Rhythia.dev)
