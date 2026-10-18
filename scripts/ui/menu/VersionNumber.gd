extends Label

func _ready():
	text = "Chromia [%s]" % ProjectSettings.get_setting("application/config/version")
	text += " [%s]" % Rhythia.dev
