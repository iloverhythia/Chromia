extends SpinBox

# Settings > Video & Audio > Max FPS. In VR the headset paces the frames
# (Rhythia.apply_vr_pacing): the box then shows and changes your desktop
# frame cap (Rhythia._desk_fps), kept for when you play without VR; it used to
# put that cap on the headset (the old menu's box did it every frame while VR
# started, and after a profile switch).

func upd():
	if value < 15 and value != 0:
		value = 15
	if Rhythia.vr:
		Rhythia._desk_fps = int(value)
		return
	Engine.target_fps = value

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if Rhythia.vr: return
	if value != Engine.target_fps: upd()

func _ready():
	value = Rhythia._desk_fps if Rhythia.vr else Engine.target_fps
	connect("changed",self,"upd")
