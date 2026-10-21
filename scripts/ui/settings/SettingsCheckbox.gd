extends CheckBox

export(String) var target

func upd():
#	print('scb "%s"' % name)
	pressed = Rhythia.get(target)
	
func _pressed():
	# var a = OS.get_ticks_usec()
#	print('scb "%s" press' % name)
	if pressed != Rhythia.get(target):
		Rhythia.set(target,pressed)
#	print('scb "%s" press done, took %s usec' % [name,Globals.comma_sep(OS.get_ticks_usec() - a)])

func _ready():
	upd()
	if target == "absolute_mode" and Rhythia.device("mobile"):
		call_deferred("_add_touch_toggle")

# Phones: "Touch Indicator" (rings under the fingers) goes under this one.
func _add_touch_toggle():
	var parent = get_parent()
	if parent == null or parent.has_node("TouchIndicator"):
		return
	var cb = duplicate()
	cb.name = "TouchIndicator"
	cb.target = "show_touch_indicator"
	cb.text = "Touch Indicator"
	cb.hint_tooltip = "Shows a ring where your fingers touch the screen."
	parent.add_child(cb)
	parent.move_child(cb, get_index() + 1)
	var b := Button.new()
	b.name = "CustomizeTouchIndicator"
	b.text = "Customize Touch Indicator..."
	b.theme = theme
	b.add_font_override("font", get_font("font"))
	b.rect_min_size = Vector2(rect_size.x, 40)
	b.hint_tooltip = "Shape, colours, size, trail, ripple, rainbow and more."
	b.connect("pressed", self, "_open_touch_editor")
	parent.add_child(b)
	parent.move_child(b, cb.get_index() + 1)
	var after: Node = b
	for opt in [
		["mobile_no_delay", "No Touch Delay", "The cursor reacts to your finger right away: every movement is used as it comes, and on iPhone the short hold Chromia's engine puts on each new touch is removed."],
		["mobile_high_hz", "120 Hz", "Draws at your screen's highest refresh rate (120 Hz on ProMotion iPhones and iPads) for smoother movement and less delay. Uses more battery."],
	]:
		if parent.has_node(opt[0]):
			continue
		var t = duplicate()
		t.name = opt[0]
		t.target = opt[0]
		t.text = opt[1]
		t.hint_tooltip = opt[2]
		parent.add_child(t)
		parent.move_child(t, after.get_index() + 1)
		t.connect("pressed", self, "_mobile_tuning_pressed", [t, opt[0]])
		after = t

# iPhone: say when the app needs reinstalling for these
func _mobile_tuning_pressed(box: CheckBox, key: String):
	if not box.pressed or not OS.has_feature("iOS"):
		return
	yield(get_tree().create_timer(0.3), "timeout")
	if Rhythia.mobile_tuning_status == "":
		Globals.notify(Globals.NOTIFY_WARN, "This needs the latest chromia-ios.ipa installed once (in-app updates can't add it). Until then only part of it works.", "Reinstall needed")
	elif key == "mobile_high_hz" and Rhythia.mobile_tuning_status.find("max 60") != -1:
		Globals.notify(Globals.NOTIFY_INFO, "This screen goes up to 60 Hz.", "120 Hz")

func _open_touch_editor():
	var root := get_tree().root
	if root.has_node("TouchIndicatorEditor"):
		return
	var ed = load("res://scripts/ui/TouchIndicatorEditor.gd").new()
	root.add_child(ed)
