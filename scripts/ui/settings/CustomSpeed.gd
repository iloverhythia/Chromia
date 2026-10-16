extends SpinBox

func upd():
	Rhythia.custom_speed = value / 100

func _process(_d):
	if not is_equal_approx(value, Rhythia.custom_speed * 100): upd()


func _ready():
	value = Rhythia.custom_speed * 100
	connect("changed", self, "upd")
	get_line_edit().connect("text_entered", self, "_on_line_edit_text_entered")

func _on_line_edit_text_entered(_new_text):
	get_line_edit().release_focus()
