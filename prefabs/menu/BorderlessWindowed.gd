extends CheckBox

func _pressed():
	if pressed != OS.window_borderless:
		Rhythia.set_borderless_windowed(pressed)

func _ready():
	visible = Rhythia.device("pc")
	pressed = OS.window_borderless
