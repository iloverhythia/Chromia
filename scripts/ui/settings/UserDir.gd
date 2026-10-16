extends Button

func _pressed():
	if not OS.has_feature("Android") and not OS.has_feature("HTML5"):
		OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://")))

func _ready():
	if OS.has_feature("HTML5"):
		disabled = true
		text = "Browser storage (not a folder)"
	elif OS.has_feature("Android"):
		disabled = true
		text = "User folder location: " + Globals.p("user://")
