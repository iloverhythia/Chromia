extends Label

func _ready():
	text = "Savia [%s]" % ProjectSettings.get_setting("application/config/version")
	text += " [%s]" % Rhythia.dev
