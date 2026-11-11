extends Button

func _pressed():
	if not OS.has_feature("Android"):
		OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://")))

func _add_move_button():
	load("res://scripts/StorageMoveUI.gd").add_next_to(self)

func _ready():
	# (computers: Move maps & replays next to it, StorageMoveUI.gd)
	call_deferred("_add_move_button")
	if OS.has_feature("Android"):
		disabled = true
		text = "User folder location: " + Globals.p("user://")
