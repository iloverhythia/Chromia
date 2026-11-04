extends SpinBox

func upd():
	Rhythia.note_opacity = clamp(value / 100,0,1)

func _process(_d):
	if Rhythia.has_meta("spec_backup"): return # (watching with their settings: the box would put yours back)
	if (value / 100) != Rhythia.note_opacity: upd()

func _ready():
	value = Rhythia.note_opacity * 100
	connect("changed",self,"upd")
	call_deferred("_add_brightness")

# Note Brightness, a row like this one under it
func _add_brightness():
	var row = get_parent()
	var box = row.get_parent()
	if box == null or box.has_node("NoteBrightness"):
		return
	var nb = row.duplicate()
	nb.name = "NoteBrightness"
	nb.hint_tooltip = "[def. 100%] how bright the notes are: less is darker, more goes towards white"
	var spin = nb.get_node("NoteOpacity")
	spin.set_script(load("res://scripts/ui/settings/NoteBrightness.gd"))
	spin.name = "NoteBrightness"
	spin.hint_tooltip = nb.hint_tooltip
	nb.get_node("Label").text = "Note Brightness"
	box.add_child(nb)
	box.move_child(nb, row.get_index() + 1)
