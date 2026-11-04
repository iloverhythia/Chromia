extends CheckBox

# In VR vsync stays off (the headset paces the frames): the box is your
# desktop choice then, kept for when you play without VR.

func _pressed():
	if Rhythia.vr:
		Rhythia._desk_vsync = pressed
		return
	if pressed != OS.vsync_enabled:
		OS.vsync_enabled = pressed

func _ready():
	pressed = Rhythia._desk_vsync if Rhythia.vr else OS.vsync_enabled
