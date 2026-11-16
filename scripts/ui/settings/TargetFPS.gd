extends SpinBox

# Settings > Video & Audio > Max FPS. In VR the headset paces the frames
# (Rhythia.apply_vr_pacing): the box then shows and changes your desktop
# frame cap (Rhythia._desk_fps), kept for when you play without VR; it used to
# put that cap on the headset (the old menu's box did it every frame while VR
# started, and after a profile switch).

# Phones: 120 Hz takes a limit under 120 off (Rhythia.apply_mobile_tuning), and
# this box then shows that. It used to put its own number straight back, so
# with a Max FPS of 60 the 120 Hz switch did nothing but add delay.
var _cap_rev := 0

func upd():
	if value < 15 and value != 0:
		value = 15
	if Rhythia.vr:
		Rhythia._desk_fps = int(value)
		return
	Engine.target_fps = value
	if Rhythia.dev == "mobile":
		_phone_cap()

# A limit typed in on a phone. Under 120 with 120 Hz on: the limit is what you
# just asked for, so 120 Hz goes off. On an iPhone the screen paces the
# frames: a limit at or above its rate is taken off again (it only delays).
func _phone_cap():
	if value > 0 and value < 120 and Rhythia.mobile_high_hz:
		Rhythia.mobile_high_hz = false
		var root = get_tree().current_scene
		var box = root.find_node("mobile_high_hz", true, false) if root != null else null
		if box is CheckBox:
			box.pressed = false
		Globals.notify(Globals.NOTIFY_INFO, "120 Hz was turned off, because you set Max FPS to %d. Tick 120 Hz again to take the limit off." % int(value), "Max FPS")
	elif OS.has_feature("iOS") or Engine.has_meta("ios_native_fake"):
		var rate: int = int(load("res://scripts/HighHzCheck.gd").ask()[0]) if Rhythia.mobile_high_hz else 60
		if value >= rate:
			Globals.notify(Globals.NOTIFY_INFO, "The screen already holds the game at %d frames a second here, so a Max FPS of %d wasn't needed and is off again (it would only have added delay)." % [rate, int(value)], "Max FPS")
		Rhythia.call_deferred("apply_mobile_tuning")

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if Rhythia.vr: return
	# (Streaming Mode holds the frame limit lower: the box keeps showing yours,
	# and changing it here still sets it, scripts/StreamMode.gd)
	if Rhythia.stream_user_fps >= 0: return
	if _cap_rev != Rhythia.fps_cap_rev:
		_cap_rev = Rhythia.fps_cap_rev
		value = Engine.target_fps
		return
	if value != Engine.target_fps: upd()

func _ready():
	_cap_rev = Rhythia.fps_cap_rev
	value = Rhythia._desk_fps if Rhythia.vr else (Rhythia.stream_user_fps if Rhythia.stream_user_fps >= 0 else Engine.target_fps)
	connect("changed",self,"upd")
