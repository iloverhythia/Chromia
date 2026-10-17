extends Label

func _ready():
	text = "Furria [%s]" % ProjectSettings.get_setting("application/config/version")
	text += " [%s]" % Rhythia.dev
