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

func _open_touch_editor():
	var root := get_tree().root
	if root.has_node("TouchIndicatorEditor"):
		return
	var ed = load("res://scripts/ui/TouchIndicatorEditor.gd").new()
	root.add_child(ed)
